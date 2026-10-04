#!/bin/bash
# Signs a Release build of Livepaper.app inside-out: Sparkle's helpers
# and XPC services, its framework, the ffmpeg helper, the shader tools, the
# `livepaper` tool, the extension with its entitlements file, then the app. The
# order is ReleaseKit's (`release-kit signing-order`), which refuses a Mach-O it does
# not place. Never --deep, no hardened runtime, --force --timestamp=none.
#
#   sign.sh <app> --identity <"Livepaper Release" | -> [--keychain <keychain>]
#   sign.sh <app> --dry-run          the same as --identity -
#
# With the certificate, it refuses one whose SHA-1 is not the leaf
# designated-requirement.txt records, and ends by checking the app and the extension
# against their recorded requirements. With `-` (the dry run) it signs ad-hoc and
# checks the identifiers alone.
. "$(dirname "$0")/lib.sh"
refuse_deep "$@"

APP="" IDENTITY="" KEYCHAIN=""
while [ $# -gt 0 ]; do
	case "$1" in
	--identity) IDENTITY="${2:?--identity needs a name or -}" && shift ;;
	--keychain) KEYCHAIN="${2:?--keychain needs a file}" && shift ;;
	--dry-run) IDENTITY="-" ;;
	-*) die "unknown option $1" ;;
	*) APP="$1" ;;
	esac
	shift
done
[ -d "$APP" ] || die "usage: sign.sh <app> --identity <name|-> [--keychain <keychain>]"
[ -n "$IDENTITY" ] || die "--identity is required: \"$IDENTITY_NAME\", or - for ad-hoc"
APP="$(cd "$APP" && pwd)"

KEYCHAIN_ARGS=()
[ -z "$KEYCHAIN" ] || KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")

if [ "$IDENTITY" != "-" ]; then
	[ "$IDENTITY" = "$IDENTITY_NAME" ] || die "the release identity is \"$IDENTITY_NAME\", not \"$IDENTITY\""
	[ -f "$REQUIREMENT_FILE" ] || die "no designated-requirement.txt: run Tools/release/make-cert.sh once"
	SHA1="$(security find-certificate -c "$IDENTITY" -Z ${KEYCHAIN:+"$KEYCHAIN"} 2>/dev/null | awk '/^SHA-1 hash:/ { print $3; exit }')"
	[ -n "$SHA1" ] || die "no certificate named \"$IDENTITY\" in ${KEYCHAIN:-the keychain search list}"
	kit requirement certificate --recorded "$REQUIREMENT_FILE" --sha1 "$SHA1"
fi

STEPS="$(kit signing-order "$APP")"
COUNT=0
while IFS="$(printf '\t')" read -r path identifier entitlements; do
	ARGS=(--force --timestamp=none --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"})
	[ "$identifier" = "-" ] || ARGS+=(--identifier "$identifier")
	[ "$entitlements" = "-" ] || ARGS+=(--entitlements "$ROOT/$entitlements")
	TARGET="$APP"
	[ "$path" = "." ] || TARGET="$APP/$path"
	if ! OUTPUT="$(codesign "${ARGS[@]}" "$TARGET" 2>&1)"; then
		printf '%s\n' "$OUTPUT" >&2
		die "codesign failed on $path"
	fi
	if [ "$entitlements" = "-" ]; then say "signed $path"; else say "signed $path with $entitlements"; fi
	COUNT=$((COUNT + 1))
done <<<"$STEPS"

# Every Mach-O in the bundle now carries this signature: one the order missed would not.
while IFS= read -r file; do
	DETAILS="$(codesign -dvv "$APP/$file" 2>&1)" || die "$file is not signed"
	if [ "$IDENTITY" = "-" ]; then
		grep -q '^Signature=adhoc$' <<<"$DETAILS" || die "$file is not signed ad-hoc"
	else
		grep -qx "Authority=$IDENTITY" <<<"$DETAILS" || die "$file is not signed by $IDENTITY: sign.sh missed it"
	fi
done < <(kit machos "$APP")

# --verify --deep checks every nested signature; signing is never --deep.
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | sed 's/^/release: verify: /'
if [ "$IDENTITY" = "-" ]; then
	codesign --verify --test-requirement="=identifier \"$APP_ID\"" "$APP"
	codesign --verify --test-requirement="=identifier \"$EXTENSION_ID\"" "$APP/Contents/Extensions/WallpaperExtension.appex"
else
	codesign --verify --test-requirement="=$(recorded_requirement "$APP_ID")" "$APP"
	codesign --verify --test-requirement="=$(recorded_requirement "$EXTENSION_ID")" "$APP/Contents/Extensions/WallpaperExtension.appex"
fi
LABEL="$IDENTITY"
[ "$IDENTITY" != "-" ] || LABEL="ad-hoc"
say "signed $COUNT pieces of code, $LABEL; the app and the extension satisfy their requirements"
