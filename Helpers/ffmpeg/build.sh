#!/bin/bash
# Builds the ffmpeg helper Livepaper bundles: a minimal, static, LGPL-only
# ffmpeg for macOS arm64.
#
#   Helpers/ffmpeg/build.sh      or      make ffmpeg
#
# Output, in Helpers/ffmpeg/out/ (ignored by git, published by CI):
#   ffmpeg                  the binary
#   ffmpeg-<version>.tar.xz the exact source it was built from
#   BUILD-INFO.txt          version, sha256, configure line, what the binary reports
#   build.sh, licenses/     this script and the licence texts
#
# To move to another release: change FFMPEG_VERSION and FFMPEG_SHA256, check the
# sha256 against a second source (the .asc signature on ffmpeg.org, or Homebrew's
# formula), run the script, and copy the licence texts again if it asks.

set -euo pipefail

FFMPEG_VERSION="9.0.2"
# sha256 of ffmpeg-9.0.2.tar.xz. Checked two ways on 2026-09-21: it is the hash
# Homebrew's ffmpeg formula pins for the same URL, and the archive carries a
# good signature from the FFmpeg release key
# FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8.
FFMPEG_SHA256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"

# The app's deployment target. An older SDK cannot target it; see below.
WANTED_DEPLOYMENT_TARGET="26.0"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$HERE/src"
OUT_DIR="$HERE/out"
LICENSES_DIR="$HERE/licenses"
ARCHIVE_NAME="ffmpeg-$FFMPEG_VERSION.tar.xz"
ARCHIVE="$SRC_DIR/$ARCHIVE_NAME"
SOURCE_URL="https://ffmpeg.org/releases/$ARCHIVE_NAME"
TREE="$SRC_DIR/ffmpeg-$FFMPEG_VERSION"
BUILD_DIR="$SRC_DIR/build"
BUILD_INFO="$OUT_DIR/BUILD-INFO.txt"
LICENSE_FILES=(COPYING.LGPLv2.1 LICENSE.md)

# Only the system toolchain. Nothing from Homebrew can be found, so nothing from
# Homebrew can be linked in.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_LIBDIR="/var/empty"
export LC_ALL=C

say() { printf 'ffmpeg helper: %s\n' "$*"; }
die() { printf 'ffmpeg helper: error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] \
	|| die "this builds and then runs an arm64 macOS binary; run it on an Apple silicon Mac"

# --- Deployment target -------------------------------------------------------

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
DEPLOYMENT_TARGET="$WANTED_DEPLOYMENT_TARGET"
if (( ${SDK_VERSION%%.*} < ${WANTED_DEPLOYMENT_TARGET%%.*} )); then
	DEPLOYMENT_TARGET="${SDK_VERSION%%.*}.0"
	say "warning: the macOS $SDK_VERSION SDK cannot target $WANTED_DEPLOYMENT_TARGET;" \
		"building for $DEPLOYMENT_TARGET. Do not ship this binary."
fi
export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"

# --- Configure flags ---------------------------------------------------------
# No --enable-gpl, no --enable-nonfree, no --enable-version3: LGPL 2.1 or later.
# No paths in here: ffmpeg embeds this line in the binary, and the quick exit
# below compares it with BUILD-INFO.txt.

PROTOCOLS=(file pipe)
# matroska covers WebM and MKV; asf covers WMV; mov is for round trips in tests.
DEMUXERS=(matroska avi asf gif mov)
MUXERS=(mov mp4)
# No av1: the native decoder only drives hardware decoders, and the software
# ones (dav1d, libaom) are external libraries.
VIDEO_DECODERS=(vp8 vp9 h264 hevc mpeg4 msmpeg4v1 msmpeg4v2 msmpeg4v3 mjpeg
	wmv1 wmv2 wmv3 vc1 gif theora)
AUDIO_DECODERS=(vorbis opus aac mp3float ac3 flac wmav1 wmav2 wmapro
	pcm_s16le pcm_s24le pcm_f32le pcm_u8)
ENCODERS=(hevc_videotoolbox aac)
# gif is not optional: the GIF demuxer hands over raw bytes and the parser finds the frames.
PARSERS=(h264 hevc vp8 vp9 vp3 mpeg4video vc1 mjpeg gif aac opus vorbis mpegaudio
	ac3 flac)
BSFS=(h264_mp4toannexb hevc_mp4toannexb extract_extradata vp9_superframe
	vp9_superframe_split aac_adtstoasc)
# What the fixed command line and ffmpeg's automatic conversions need. ffmpeg
# itself adds trim, atrim, crop, rotate, transpose, hflip and vflip.
FILTERS=(scale format fps null setsar setpts aresample aformat anull)

join() { local IFS=,; printf '%s' "$*"; }

CONFIGURE_FLAGS=(
	--disable-everything
	--disable-autodetect
	--disable-network
	--disable-doc
	--disable-debug
	--disable-ffplay
	--disable-ffprobe
	--disable-avdevice
	--disable-iamf
	--enable-static
	--disable-shared
	--enable-pic
	--enable-swscale
	--enable-swresample
	--arch=arm64
	--target-os=darwin
	--cc=clang
	"--extra-cflags=-arch arm64 -mmacosx-version-min=$DEPLOYMENT_TARGET -fstack-protector-strong"
	"--extra-ldflags=-arch arm64 -mmacosx-version-min=$DEPLOYMENT_TARGET"
	# Only for hevc_videotoolbox. AudioToolbox is not needed: the AAC encoder is ffmpeg's own.
	--enable-videotoolbox
	"--enable-protocol=$(join "${PROTOCOLS[@]}")"
	"--enable-demuxer=$(join "${DEMUXERS[@]}")"
	"--enable-muxer=$(join "${MUXERS[@]}")"
	"--enable-decoder=$(join "${VIDEO_DECODERS[@]}" "${AUDIO_DECODERS[@]}")"
	"--enable-encoder=$(join "${ENCODERS[@]}")"
	"--enable-parser=$(join "${PARSERS[@]}")"
	"--enable-bsf=$(join "${BSFS[@]}")"
	"--enable-filter=$(join "${FILTERS[@]}")"
)

# One line, quoted so that it can be pasted into a shell.
CONFIGURE_LINE="./configure"
for flag in "${CONFIGURE_FLAGS[@]}"; do
	case "$flag" in
		*" "*) CONFIGURE_LINE+=" '$flag'" ;;
		*) CONFIGURE_LINE+=" $flag" ;;
	esac
done

# --- Checks on a built binary ------------------------------------------------

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

verify_binary() {
	local binary="$1" banner licence protocols wanted_protocols libraries foreign encoders name

	[[ -x "$binary" ]] || die "$binary is missing or not executable"
	[[ "$(lipo -archs "$binary")" == "arm64" ]] || die "$binary is not an arm64-only binary"

	banner="$("$binary" -hide_banner -version)"
	grep -q "^ffmpeg version $FFMPEG_VERSION " <<<"$banner" \
		|| die "the binary does not report version $FFMPEG_VERSION"
	for name in --enable-gpl --enable-nonfree --enable-version3; do
		if grep -q -- "$name" <<<"$banner"; then
			die "the binary was configured with $name"
		fi
	done

	licence="$("$binary" -hide_banner -L)"
	grep -q "GNU Lesser General Public" <<<"$licence" \
		|| die "ffmpeg -L does not report the LGPL: $licence"
	grep -q "version 2.1 of the License" <<<"$licence" \
		|| die "ffmpeg -L does not report LGPL version 2.1 or later: $licence"
	if grep -q -e "GNU General Public" -e "nonfree" -e "unredistributable" <<<"$licence"; then
		die "ffmpeg -L reports a licence other than the LGPL: $licence"
	fi

	protocols="$("$binary" -hide_banner -protocols | sed -n 's/^  *//p' | sort -u | tr '\n' ' ')"
	wanted_protocols="$(printf '%s\n' "${PROTOCOLS[@]}" | sort -u | tr '\n' ' ')"
	[[ "$protocols" == "$wanted_protocols" ]] \
		|| die "protocols are '$protocols', expected '$wanted_protocols'"

	libraries="$(otool -L "$binary" | tail -n +2 | awk '{print $1}')"
	foreign="$(grep -v -e '^/usr/lib/' -e '^/System/Library/' <<<"$libraries" || true)"
	[[ -z "$foreign" ]] || die "the binary links outside the system: $foreign"

	encoders="$("$binary" -hide_banner -encoders)"
	for name in "${ENCODERS[@]}"; do
		grep -q " $name " <<<"$encoders" || die "encoder $name is missing from the binary"
	done
}

# --- Quick exit when out/ is already this build --------------------------------

if [[ -x "$OUT_DIR/ffmpeg" && -f "$BUILD_INFO" && -f "$OUT_DIR/$ARCHIVE_NAME" ]] \
	&& grep -Fxq "version: $FFMPEG_VERSION" "$BUILD_INFO" \
	&& grep -Fxq "sha256: $FFMPEG_SHA256" "$BUILD_INFO" \
	&& grep -Fxq "configure: $CONFIGURE_LINE" "$BUILD_INFO" \
	&& [[ "$(sha256_of "$OUT_DIR/$ARCHIVE_NAME")" == "$FFMPEG_SHA256" ]]; then
	verify_binary "$OUT_DIR/ffmpeg"
	cp "$HERE/build.sh" "$OUT_DIR/build.sh"
	say "out/ffmpeg is already $FFMPEG_VERSION with these flags; nothing to do"
	exit 0
fi

# --- Source ------------------------------------------------------------------

mkdir -p "$SRC_DIR"
if [[ -f "$ARCHIVE" && "$(sha256_of "$ARCHIVE")" != "$FFMPEG_SHA256" ]]; then
	say "the archive in src/ has the wrong sha256; downloading it again"
	rm -f "$ARCHIVE"
fi
if [[ ! -f "$ARCHIVE" ]]; then
	say "downloading $SOURCE_URL"
	curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
		--retry 3 --output "$ARCHIVE.part" "$SOURCE_URL"
	mv "$ARCHIVE.part" "$ARCHIVE"
fi
ACTUAL_SHA256="$(sha256_of "$ARCHIVE")"
[[ "$ACTUAL_SHA256" == "$FFMPEG_SHA256" ]] \
	|| die "sha256 of $ARCHIVE_NAME is $ACTUAL_SHA256, expected $FFMPEG_SHA256; not building"

say "unpacking $ARCHIVE_NAME"
rm -rf "$TREE" "$BUILD_DIR"
tar -xf "$ARCHIVE" -C "$SRC_DIR"

# The licence texts in the repository must be the ones this release ships.
for name in "${LICENSE_FILES[@]}"; do
	cmp -s "$TREE/$name" "$LICENSES_DIR/$name" \
		|| die "licenses/$name differs from the one in ffmpeg $FFMPEG_VERSION;" \
			"copy it from src/ffmpeg-$FFMPEG_VERSION/$name, read the change, and commit it"
done

# --- Build, out of tree ---------------------------------------------------------

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
say "configuring (deployment target $DEPLOYMENT_TARGET, SDK $SDK_VERSION)"
"$TREE/configure" "${CONFIGURE_FLAGS[@]}" >configure.log \
	|| { tail -n 20 configure.log ffbuild/config.log >&2 || true; die "configure failed"; }
grep -E '^License:' configure.log
grep -q '^#define FFMPEG_LICENSE "LGPL version 2.1 or later"$' config.h \
	|| die "configure chose a licence other than LGPL 2.1 or later"

say "building"
make -j"$(sysctl -n hw.ncpu)" ffmpeg >make.log 2>&1 \
	|| { tail -n 40 make.log >&2; die "make failed; the full log is $BUILD_DIR/make.log"; }

verify_binary "$BUILD_DIR/ffmpeg"

# --- Install -----------------------------------------------------------------

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/licenses"
install -m 755 "$BUILD_DIR/ffmpeg" "$OUT_DIR/ffmpeg"
cp "$ARCHIVE" "$OUT_DIR/$ARCHIVE_NAME"
cp "$HERE/build.sh" "$OUT_DIR/build.sh"
for name in "${LICENSE_FILES[@]}"; do
	cp "$LICENSES_DIR/$name" "$OUT_DIR/licenses/$name"
done

{
	echo "ffmpeg helper for Livepaper, built by Helpers/ffmpeg/build.sh"
	echo "version: $FFMPEG_VERSION"
	echo "source: $SOURCE_URL"
	echo "sha256: $FFMPEG_SHA256"
	echo "configure: $CONFIGURE_LINE"
	echo "deployment-target: $DEPLOYMENT_TARGET"
	echo "sdk: $SDK_VERSION"
	echo "compiler: $(clang --version | head -n 1)"
	echo "binary-sha256: $(sha256_of "$OUT_DIR/ffmpeg")"
	echo
	echo "--- ffmpeg -version"
	"$OUT_DIR/ffmpeg" -hide_banner -version
	echo
	echo "--- ffmpeg -L"
	"$OUT_DIR/ffmpeg" -hide_banner -L
	echo
	echo "--- ffmpeg -protocols"
	"$OUT_DIR/ffmpeg" -hide_banner -protocols
	echo
	echo "--- otool -L ffmpeg"
	otool -L "$OUT_DIR/ffmpeg" | tail -n +2
} >"$BUILD_INFO"

verify_binary "$OUT_DIR/ffmpeg"

# src/ keeps the archive only; the unpacked tree and the objects are rebuilt from it.
cd "$HERE"
rm -rf "$TREE" "$BUILD_DIR"

say "built out/ffmpeg ($(du -h "$OUT_DIR/ffmpeg" | cut -f1 | tr -d ' '), $(stat -f %z "$OUT_DIR/ffmpeg") bytes)"
