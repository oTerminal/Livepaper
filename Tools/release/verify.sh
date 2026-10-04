#!/bin/bash
# Checks a packaged release before anything is published: mounts the disk image
# and refuses it unless every check passes.
#
#   verify.sh <dmg> <zip> [--dry-run] [--install]
#
# - The app's signature is valid, strict and deep, and its designated requirement
#   and the extension's are the ones designated-requirement.txt records (with
#   --dry-run: ad-hoc, as the dry run signs).
# - The extension's entitlements are the sandbox and the library's read-only
#   exception and no more (WallpaperExtension.entitlements); the app has none.
# - The ffmpeg helper and each shader tool are the binaries their BUILD-INFO.txt
#   describes: the built binary has the recorded sha256, and the shipped copy, its
#   signature stripped, is byte for byte that binary signed and stripped alike.
# - The samples are there with PROVENANCE.md's sha256, the About panel's
#   Credits.rtf is the committed one, and Licenses/ holds the notices and texts.
# - The zip holds the same app: the same cdhash for the app and the extension.
# - With --install (CI's runner, never a Mac whose Livepaper is in use): the app
#   copied to /Applications is listed by `pluginkit -m -v -p com.apple.wallpaper`.
. "$(dirname "$0")/lib.sh"

DMG="" ZIP="" DRY_RUN=0 INSTALL=0
while [ $# -gt 0 ]; do
	case "$1" in
	--dry-run) DRY_RUN=1 ;;
	--install) INSTALL=1 ;;
	-*) die "unknown option $1" ;;
	*) if [ -z "$DMG" ]; then DMG="$1"; else ZIP="$1"; fi ;;
	esac
	shift
done
[ -f "$DMG" ] && [ -f "$ZIP" ] || die "usage: verify.sh <dmg> <zip> [--dry-run] [--install]"

WORK="$(mktemp -d)"
MOUNT="$WORK/mount"
cleanup() {
	hdiutil detach -quiet "$MOUNT" 2>/dev/null || true
	rm -rf "${WORK:?}"
}
trap cleanup EXIT
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" "$DMG"
APP="$MOUNT/Livepaper.app"
APPEX="$APP/Contents/Extensions/WallpaperExtension.appex"
pass() { say "verify: $*"; }

# What the image holds.
[ -d "$APP" ] || die "the image holds no Livepaper.app"
[ "$(readlink "$MOUNT/Applications")" = "/Applications" ] || die "the image's Applications is not a symlink to /Applications"
for licence in NOTICES.txt "Livepaper LICENSE.txt" "Livepaper NOTICE.txt" "Sparkle LICENSE.txt" \
	ffmpeg/COPYING.LGPLv2.1 ffmpeg/LICENSE.md "glslang and SPIRV-Cross/glslang-LICENSE.txt" \
	"glslang and SPIRV-Cross/SPIRV-Cross-LICENSE" "Samples PROVENANCE.md"; do
	[ -s "$MOUNT/Licenses/$licence" ] || die "Licenses/$licence is missing from the image"
done
kit notices --root "$ROOT" --out "$WORK" >/dev/null
cmp -s "$WORK/NOTICES.txt" "$MOUNT/Licenses/NOTICES.txt" || die "Licenses/NOTICES.txt is not the notices that ship"
cmp -s "$ROOT/Resources/Credits.rtf" "$APP/Contents/Resources/Credits.rtf" || die "the app's Credits.rtf is not the committed one"
pass "the app, Applications, and Licenses/ with the notices and $(find "$MOUNT/Licenses" -type f | wc -l | tr -d ' ') files"

# The signature.
codesign --verify --deep --strict "$APP" || die "the app's signature does not verify"
for code in "$APP" "$APPEX"; do
	REQUIREMENT="$(codesign -d -r- "$code" 2>&1)"
	if [ "$DRY_RUN" = 1 ]; then
		kit requirement adhoc <<<"$REQUIREMENT" >/dev/null
	else
		kit requirement check --recorded "$REQUIREMENT_FILE" <<<"$REQUIREMENT" >/dev/null
		codesign -dvv "$code" 2>&1 | grep -qx "Authority=$IDENTITY_NAME" || die "$(basename "$code") is not signed by $IDENTITY_NAME"
	fi
done
if [ "$DRY_RUN" = 1 ]; then pass "signature valid, ad-hoc (the dry run's)"; else pass "signature valid; both requirements are the recorded ones"; fi

# The entitlements.
codesign -d --entitlements - --xml "$APPEX" >"$WORK/extension.plist" 2>/dev/null
plutil -convert xml1 -o "$WORK/shipped.plist" "$WORK/extension.plist"
plutil -convert xml1 -o "$WORK/expected.plist" "$ROOT/WallpaperExtension/WallpaperExtension.entitlements"
cmp -s "$WORK/shipped.plist" "$WORK/expected.plist" || die "the extension's entitlements are not WallpaperExtension.entitlements"
[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.app-sandbox" "$WORK/shipped.plist")" = "true" ] || die "the extension is not sandboxed"
[ "$(plutil -convert json -o - "$WORK/shipped.plist" | tr ',' '\n' | grep -c '"com\.apple\.')" = 2 ] \
	|| die "the extension's entitlements are not exactly two keys"
APP_ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
[ -z "$APP_ENTITLEMENTS" ] || [ "$(printf '%s' "$APP_ENTITLEMENTS" | plutil -convert json -o - -)" = "{}" ] \
	|| die "the app has entitlements; it is signed with none"
pass "the extension's entitlements are the sandbox and the read-only exception alone; the app has none"

# The helpers: each the binary its BUILD-INFO.txt records.
strip_signed() {
	cp "$1" "$2"
	codesign --force --sign - --timestamp=none "$2" 2>/dev/null
	codesign --remove-signature "$2"
	shasum -a 256 "$2" | cut -d' ' -f1
}
helper() {
	local name="$1" built="$2" info="$3" key="$4" recorded
	recorded="$(awk -v key="$key:" '$1 == key { print $2; exit }' "$info")"
	[ -n "$recorded" ] || die "$info records no $key"
	[ "$(shasum -a 256 "$built" | cut -d' ' -f1)" = "$recorded" ] || die "$built is not the binary $info records"
	[ "$(strip_signed "$built" "$WORK/$name.built")" = "$(strip_signed "$APP/Contents/MacOS/$name" "$WORK/$name.shipped")" ] \
		|| die "the shipped $name is not the built one ($key $recorded)"
	pass "$name is the binary BUILD-INFO.txt records ($recorded)"
}
helper ffmpeg "$ROOT/Helpers/ffmpeg/out/ffmpeg" "$ROOT/Helpers/ffmpeg/out/BUILD-INFO.txt" binary-sha256
helper glslang "$ROOT/Helpers/shader-tools/out/glslang" "$ROOT/Helpers/shader-tools/out/BUILD-INFO.txt" glslang-binary-sha256
helper spirv-cross "$ROOT/Helpers/shader-tools/out/spirv-cross" "$ROOT/Helpers/shader-tools/out/BUILD-INFO.txt" spirv-cross-binary-sha256

# The samples, as PROVENANCE.md records them.
SAMPLES=0
# shellcheck disable=SC2016 # the backticks are PROVENANCE.md's Markdown
while IFS= read -r line; do
	file="$(sed -E 's/^- \*\*SHA-256 of `([^`]+)`:\*\* `([0-9a-f]+)`.*/\1/' <<<"$line")"
	sha="$(sed -E 's/^- \*\*SHA-256 of `([^`]+)`:\*\* `([0-9a-f]+)`.*/\2/' <<<"$line")"
	[ -f "$APP/Contents/Resources/Samples/$file" ] || die "the sample $file is missing"
	[ "$(shasum -a 256 "$APP/Contents/Resources/Samples/$file" | cut -d' ' -f1)" = "$sha" ] || die "the sample $file is not the one PROVENANCE.md records"
	SAMPLES=$((SAMPLES + 1))
done < <(grep -E '^- \*\*SHA-256 of `' "$ROOT/Resources/Samples/PROVENANCE.md")
[ "$SAMPLES" -gt 0 ] || die "PROVENANCE.md records no sample"
[ -f "$APP/Contents/Resources/Samples/PROVENANCE.md" ] || die "the app's samples have no PROVENANCE.md"
pass "$SAMPLES samples, each with the sha256 PROVENANCE.md records"

# The zip: the same app.
ditto -x -k "$ZIP" "$WORK/zip"
cdhash() { codesign -dvvv "$1" 2>&1 | awk -F= '/^CDHash=/ { print $2; exit }'; }
[ "$(cdhash "$WORK/zip/Livepaper.app")" = "$(cdhash "$APP")" ] || die "the zip's app is not the disk image's"
[ "$(cdhash "$WORK/zip/Livepaper.app/Contents/Extensions/WallpaperExtension.appex")" = "$(cdhash "$APPEX")" ] \
	|| die "the zip's extension is not the disk image's"
pass "the zip holds the same app, cdhash $(cdhash "$APP")"

# A local install, on a Mac that may have one.
if [ "$INSTALL" = 1 ]; then
	[ ! -e /Applications/Livepaper.app ] || die "/Applications/Livepaper.app exists already: --install is for a clean Mac"
	ditto "$APP" /Applications/Livepaper.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Livepaper.app
	pluginkit -a /Applications/Livepaper.app/Contents/Extensions/WallpaperExtension.appex
	LISTED=""
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		LISTED="$(pluginkit -m -v -p com.apple.wallpaper 2>/dev/null | grep "$EXTENSION_ID" | grep /Applications/Livepaper.app || true)"
		[ -z "$LISTED" ] || break
		sleep 1
	done
	[ -n "$LISTED" ] || die "pluginkit does not list the extension under /Applications after a local install"
	pass "pluginkit lists it: $(tr -s '\t ' ' ' <<<"$LISTED")"
fi
say "verify: passed"
