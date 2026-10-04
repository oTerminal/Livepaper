#!/bin/bash
# Makes a release of Livepaper from a v<X.Y.Z> tag: what .github/workflows/
# release.yml runs on the tag, in the `release` environment.
#
#   release.sh              the tag's release, published
#   release.sh --dry-run    every step but publishing, ad-hoc signed and with a
#                           throwaway EdDSA key, into build/release/ (make release-dry-run)
#
# In order: the refusals that need nothing built; the helpers; gen; a Release build;
# the certificate into a run-scoped keychain, deleted on any exit; sign.sh;
# package.sh; verify.sh; generate_appcast and the merged feed; then the GitHub
# release (the disk image, the zip, ffmpeg-helper-arm64.zip and ffmpeg's source
# archive, the changelog's section its notes) and the appcast branch, in that order
# so that the feed never names a file that is not there yet.
#
# Secrets come from the environment and are never printed: LIVEPAPER_SIGNING_P12
# (the certificate's .p12, base64), LIVEPAPER_SIGNING_P12_PASSWORD, and
# SPARKLE_ED_PRIVATE_KEY (generate_keys -x's file). They are taken out of the
# environment at once, so that no program this runs inherits them, and nothing here
# runs under set -x.
export -n LIVEPAPER_SIGNING_P12 LIVEPAPER_SIGNING_P12_PASSWORD SPARKLE_ED_PRIVATE_KEY 2>/dev/null || true
. "$(dirname "$0")/lib.sh"

DRY_RUN=0 INSTALL=0
for argument in "$@"; do
	case "$argument" in
	--dry-run) DRY_RUN=1 ;;
	--install) INSTALL=1 ;; # verify.sh's local install: CI's runner only
	*) die "usage: release.sh [--dry-run] [--install]" ;;
	esac
done

OUT="$RELEASE_DIR"
SECRETS="$(mktemp -d)"
chmod 700 "$SECRETS"
KEYCHAIN=""
SEARCH_LIST=()
cleanup() {
	if [ -n "$KEYCHAIN" ]; then
		[ ${#SEARCH_LIST[@]} = 0 ] || security list-keychains -d user -s "${SEARCH_LIST[@]}" || true
		security delete-keychain "$KEYCHAIN" 2>/dev/null || true
		say "deleted the run's keychain"
	fi
	rm -rf "${SECRETS:?}"
}
trap cleanup EXIT

cd "$ROOT" || exit 1
read -r VERSION BUILD <<<"$(kit version)"
TAG="v$VERSION"
say "Livepaper $VERSION, build $BUILD$([ "$DRY_RUN" = 0 ] || printf ', dry run')"

# --- Refusals before anything is built -------------------------------------------
if [ "$DRY_RUN" = 0 ]; then
	for secret in LIVEPAPER_SIGNING_P12 LIVEPAPER_SIGNING_P12_PASSWORD SPARKLE_ED_PRIVATE_KEY; do
		[ -n "${!secret:-}" ] || die "the secret $secret is missing: it is the release environment's"
	done
	REF="${GITHUB_REF:-}"
	[ -n "$REF" ] || die "no tag: a release starts from a pushed v<X.Y.Z> tag alone"
	kit version --tag "$REF" >/dev/null
	[ -f "$REQUIREMENT_FILE" ] || die "no designated-requirement.txt: run Tools/release/make-cert.sh once"
	grep -q 'SUPublicEDKey:' project.yml || die "project.yml has no SUPublicEDKey: run Tools/release/sparkle-keys.sh once"
	if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then die "the release $TAG exists already"; fi
fi
mkdir -p "$OUT"
rm -rf "${OUT:?}/stage" "$OUT"/Livepaper-*.dmg "$OUT"/Livepaper-*.zip "$OUT"/appcast*.xml "$OUT"/notes.md "$OUT"/ffmpeg-helper-arm64.zip
"$ROOT/Tools/release/appcast.sh" fetch "$OUT/appcast-published.xml"
if ! kit version --appcast "$OUT/appcast-published.xml" >/dev/null; then
	[ "$DRY_RUN" = 1 ] || exit 1
	# Between releases the build is the last one's: the dry run goes on with an
	# empty feed, and the release itself will refuse until the build is raised.
	say "dry run: the next release must raise CURRENT_PROJECT_VERSION; going on with an empty feed"
	rm -f "$OUT/appcast-published.xml"
fi
kit changelog "$VERSION" >"$OUT/notes.md"
kit notices --root "$ROOT" --check
for helper in Helpers/ffmpeg/out/ffmpeg Helpers/shader-tools/out/glslang Helpers/shader-tools/out/spirv-cross; do
	[ -x "$helper" ] || die "$helper is missing: make ffmpeg shader-tools, or CI's artefacts"
done

# --- Build --------------------------------------------------------------------------
xcodegen generate --quiet
xcodebuild -project Livepaper.xcodeproj -scheme Livepaper -configuration Release \
	-destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -quiet build
mkdir -p "$OUT/stage"
ditto build/DerivedData/Build/Products/Release/Livepaper.app "$OUT/stage/Livepaper.app"
APP="$OUT/stage/Livepaper.app"
[ "$(bundle_version "$APP")" = "$VERSION" ] && [ "$(bundle_build "$APP")" = "$BUILD" ] \
	|| die "the built app is $(bundle_version "$APP") ($(bundle_build "$APP")), not project.yml's $VERSION ($BUILD)"

KEY_FILE="$SECRETS/ed25519.txt"
if [ "$DRY_RUN" = 1 ]; then
	# A throwaway key pair, its public half in the staged app, so that the dry run
	# signs the zip and Sparkle's check of it can be tried. It is not a secret.
	PUBLIC_KEY="$(kit throwaway-key "$SECRETS")"
	plutil -replace SUPublicEDKey -string "$PUBLIC_KEY" "$APP/Contents/Info.plist"
	say "dry run: a throwaway EdDSA key, its public half in the staged app"
else
	[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null)" ] \
		|| die "the built app has no SUPublicEDKey"
fi

# --- Sign -----------------------------------------------------------------------------
if [ "$DRY_RUN" = 1 ]; then
	"$ROOT/Tools/release/sign.sh" "$APP" --identity -
else
	KEYCHAIN="${RUNNER_TEMP:-$SECRETS}/livepaper-release.keychain-db"
	KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
	while IFS= read -r listed; do
		listed="${listed#"${listed%%[![:space:]]*}"}"
		SEARCH_LIST+=("$(tr -d '"' <<<"$listed")")
	done < <(security list-keychains -d user)
	security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
	security set-keychain-settings -lut 3600 "$KEYCHAIN"
	security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
	(umask 077 && printf '%s' "$LIVEPAPER_SIGNING_P12" | base64 -D >"$SECRETS/release.p12")
	# `security import` takes the password only as an argument; the runner is the
	# run's alone, and the log never shows it.
	security import "$SECRETS/release.p12" -k "$KEYCHAIN" -P "$LIVEPAPER_SIGNING_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
	rm -f "$SECRETS/release.p12"
	security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
	security list-keychains -d user -s "$KEYCHAIN" ${SEARCH_LIST[@]+"${SEARCH_LIST[@]}"}
	say "the certificate is in the run's keychain"
	"$ROOT/Tools/release/sign.sh" "$APP" --identity "$IDENTITY_NAME" --keychain "$KEYCHAIN"
fi

# --- Package, verify, appcast -----------------------------------------------------------
"$ROOT/Tools/release/package.sh" "$APP" --out "$OUT"
DMG="$OUT/Livepaper-$VERSION.dmg"
ZIP="$OUT/Livepaper-$VERSION.zip"
VERIFY=("$DMG" "$ZIP")
[ "$DRY_RUN" = 0 ] || VERIFY+=(--dry-run)
[ "$INSTALL" = 0 ] || VERIFY+=(--install)
"$ROOT/Tools/release/verify.sh" "${VERIFY[@]}"
# The EdDSA key is in a file for this step alone.
if [ "$DRY_RUN" = 1 ]; then
	mv "$SECRETS/throwaway-ed25519.txt" "$KEY_FILE"
else
	(umask 077 && printf '%s' "$SPARKLE_ED_PRIVATE_KEY" >"$KEY_FILE")
fi
"$ROOT/Tools/release/appcast.sh" make "$ZIP" --key-file "$KEY_FILE" --feed "$OUT/appcast-published.xml" --out "$OUT/appcast.xml"
SIGNATURE="$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$OUT/appcast.xml" | head -n 1)"
"$(sparkle_tools)/bin/sign_update" --verify --ed-key-file "$KEY_FILE" "$ZIP" "$SIGNATURE" >/dev/null \
	|| die "the zip's EdDSA signature in the appcast does not verify"
rm -f "$KEY_FILE"
say "the appcast's EdDSA signature verifies the zip; generate_appcast signed only because the key is the app's"
ditto -c -k --keepParent Helpers/ffmpeg/out "$OUT/ffmpeg-helper-arm64.zip"
SOURCES=(Helpers/ffmpeg/out/ffmpeg-*.tar.xz)
[ ${#SOURCES[@]} = 1 ] && [ -f "${SOURCES[0]}" ] || die "Helpers/ffmpeg/out holds ${#SOURCES[@]} source archives, not one"
SOURCE="${SOURCES[0]}"

ASSETS=("$DMG" "$ZIP" "$OUT/ffmpeg-helper-arm64.zip" "$SOURCE")
if [ "$DRY_RUN" = 1 ]; then
	say "dry run: would release $TAG with these files and notes, then push the appcast; publishing nothing"
	for asset in "${ASSETS[@]}"; do say "  $(basename "$asset") ($(stat -f %z "$asset") bytes)"; done
	say "  notes: $OUT/notes.md"
	say "  appcast: $OUT/appcast.xml"
	exit 0
fi

# --- Publish --------------------------------------------------------------------------
gh release create "$TAG" --repo "$REPO_SLUG" --verify-tag --title "Livepaper $VERSION" --notes-file "$OUT/notes.md" "${ASSETS[@]}"
"$ROOT/Tools/release/appcast.sh" publish "$OUT/appcast.xml"
say "released $TAG: https://github.com/$REPO_SLUG/releases/tag/$TAG"
