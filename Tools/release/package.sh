#!/bin/bash
# Packages a signed Livepaper.app: Livepaper-<version>.dmg, compressed, volume
# "Livepaper", holding the app, an Applications symlink and Licenses/, with no
# background picture; and Livepaper-<version>.zip of the same app, for Sparkle.
#
#   package.sh <signed app> --out <dir> [--dry-run]
#
# Packaging publishes nothing, so --dry-run changes nothing here; it is taken so
# that every release script takes it.
#
# The disk image is made with `diskutil image create from` where this Mac has it
# (`hdiutil create` is deprecated on macOS 27), else `hdiutil create`.
# It refuses an image over the 50 MB budget.
. "$(dirname "$0")/lib.sh"

APP="" OUT=""
while [ $# -gt 0 ]; do
	case "$1" in
	--out) OUT="${2:?--out needs a folder}" && shift ;;
	--dry-run) ;;
	-*) die "unknown option $1" ;;
	*) APP="$1" ;;
	esac
	shift
done
[ -d "$APP" ] && [ -n "$OUT" ] || die "usage: package.sh <signed app> --out <dir>"
BUDGET=$((50 * 1000 * 1000))
VERSION="$(bundle_version "$APP")"
DMG="$OUT/Livepaper-$VERSION.dmg"
ZIP="$OUT/Livepaper-$VERSION.zip"
mkdir -p "$OUT"
rm -f "$DMG" "$ZIP"

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE:?}"' EXIT
ditto "$APP" "$STAGE/Livepaper.app"
ln -s /Applications "$STAGE/Applications"

# Licenses/: the notices and every licence text they name (Notices.swift).
LICENSES="$STAGE/Licenses"
mkdir -p "$LICENSES/ffmpeg" "$LICENSES/glslang and SPIRV-Cross"
kit notices --root "$ROOT" --out "$LICENSES" >/dev/null
cp "$ROOT/LICENSE" "$LICENSES/Livepaper LICENSE.txt"
cp "$ROOT/NOTICE" "$LICENSES/Livepaper NOTICE.txt"
cp "$(sparkle_tools)/LICENSE" "$LICENSES/Sparkle LICENSE.txt"
cp "$ROOT/Helpers/ffmpeg/out/licenses/"* "$LICENSES/ffmpeg/"
cp "$ROOT/Helpers/shader-tools/out/licenses/"* "$LICENSES/glslang and SPIRV-Cross/"
cp "$ROOT/Resources/Samples/PROVENANCE.md" "$LICENSES/Samples PROVENANCE.md"

if diskutil image create from -h >/dev/null 2>&1; then
	IMAGE=(diskutil image create from --format ULFO --volumeName Livepaper "$STAGE" "$DMG")
else
	IMAGE=(hdiutil create -volname Livepaper -srcfolder "$STAGE" -format ULFO -ov "$DMG")
fi
say "image: ${IMAGE[*]}"
if ! LOG="$("${IMAGE[@]}" 2>&1)"; then
	printf '%s\n' "$LOG" >&2
	die "the disk image was not made"
fi

ditto -c -k --keepParent "$STAGE/Livepaper.app" "$ZIP"

SIZE="$(stat -f %z "$DMG")"
say "wrote $DMG ($SIZE bytes) and $ZIP ($(stat -f %z "$ZIP") bytes)"
[ "$SIZE" -le "$BUDGET" ] || die "the disk image is $SIZE bytes, over the $BUDGET-byte budget"
