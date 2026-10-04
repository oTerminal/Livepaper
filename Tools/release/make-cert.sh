#!/bin/bash
# Makes the release certificate, once, by hand, never in CI: a
# self-signed code-signing certificate named "Livepaper Release", for ten years.
# Its leaf hash is every release's identity, so the private key is kept in the
# owner's password manager and as the GitHub `release` environment's secrets
# LIVEPAPER_SIGNING_P12 (the .p12, base64) and LIVEPAPER_SIGNING_P12_PASSWORD, and
# nowhere else: not in the repo, not in a keychain on this Mac.
#
#   Tools/release/make-cert.sh [--dry-run]
#
# Writes Tools/release/designated-requirement.txt and the README's copy of it,
# which are committed, last: once the .p12 is in the password manager and GitHub.
# Refuses to run again once the file exists: a second certificate would make every
# later release a different app to macOS. --dry-run makes a throwaway certificate
# and proves it signs, and writes, saves and sets nothing.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/wizard.sh"

DRY_RUN=0
case "${1:-}" in
--dry-run) DRY_RUN=1 ;;
"") ;;
*) die "usage: make-cert.sh [--dry-run]" ;;
esac
[ ! -f "$REQUIREMENT_FILE" ] || die "designated-requirement.txt exists: the certificate is made. Making another changes the app's identity for every user."
[ "$DRY_RUN" = 1 ] || command -v gh >/dev/null 2>&1 || die "this needs gh, signed in to GitHub with access to $REPO_SLUG"

# The private key lives in this folder, which only you can read and which is not
# synced anywhere, until the script ends, however it ends. rm -P overwrites first.
WORK="$(mktemp -d)"
chmod 700 "${WORK:?}"
forget() {
	rm -P "${WORK:?}"/* 2>/dev/null || true
	rm -rf "${WORK:?}"
	security delete-keychain "${WORK:?}.keychain-db" 2>/dev/null || true
}
trap forget EXIT

TOTAL_STAGES=6
TITLE="The Livepaper Release certificate"
[ "$DRY_RUN" = 0 ] || TITLE="$TITLE (dry run)"
banner "$TITLE"

stage "GitHub's release environment"
say "The release workflow reads the certificate from the 'release' environment's secrets."
if [ "$DRY_RUN" = 1 ]; then
	note "dry run: not touching GitHub"
elif gh api -X PUT "repos/$REPO_SLUG/environments/release" >/dev/null; then
	ok "the release environment exists"
	note "Optional: in Settings → Environments → release, limit it to tags matching v*."
else
	TODO+=("make the 'release' environment: github.com/$REPO_SLUG/settings/environments")
	warn "could not make it; make it on GitHub afterwards"
fi
pause

stage "A password for the .p12"
say "Make a new password in your password manager for 'Livepaper Release .p12', and paste it here."
note "It protects the .p12 file; CI reads it as LIVEPAPER_SIGNING_P12_PASSWORD."
P12_PASSWORD="" AGAIN=""
while :; do
	ask_secret P12_PASSWORD "Password:"
	ask_secret AGAIN "Again:"
	[ "${#P12_PASSWORD}" -ge 12 ] || {
		warn "at least 12 characters"
		continue
	}
	[ "$P12_PASSWORD" = "$AGAIN" ] && break
	warn "the two differ; again"
done
export P12_PASSWORD

stage "The certificate"
P12="$WORK/Livepaper Release.p12"
(
	umask 077
	/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
		-subj "/CN=$IDENTITY_NAME" -addext "basicConstraints=critical,CA:false" \
		-addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
	/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$IDENTITY_NAME" \
		-out "$P12" -passout env:P12_PASSWORD
)
rm -P "$WORK/key.pem"
SHA1="$(/usr/bin/openssl x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g' | tr 'A-F' 'a-f')"
ok "made \"$IDENTITY_NAME\", valid ten years, leaf $SHA1"

# Prove it signs with the requirement it will record: a throwaway keychain and binary.
KEYCHAIN="$WORK.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
cp /usr/bin/true "$WORK/probe"
codesign --force --timestamp=none --sign "$IDENTITY_NAME" --keychain "$KEYCHAIN" --identifier "$APP_ID" "$WORK/probe"
kit requirement record --sha1 "$SHA1" --identifier "$APP_ID" --identifier "$EXTENSION_ID" >"$WORK/requirement.txt"
kit requirement check --recorded "$WORK/requirement.txt" <<<"$(codesign -d -r- "$WORK/probe" 2>&1)" >/dev/null
security delete-keychain "$KEYCHAIN"
ok "a test signature has the requirement it will record"
pause

stage "Your password manager"
if [ "$DRY_RUN" = 1 ]; then
	note "dry run: this certificate is thrown away; nothing to save"
else
	open -R "$P12"
	say "The Finder shows the .p12 in a private temporary folder."
	step "Attach it to the 'Livepaper Release .p12' entry in your password manager, beside its password."
	note "Do not copy it anywhere else: the folder is deleted when this script ends."
	pause "Press Enter once it is saved there"
fi

stage "GitHub's secrets"
if [ "$DRY_RUN" = 1 ]; then
	note "dry run: setting no secret"
else
	base64 -i "$P12" | tr -d '\n' | set_environment_secret LIVEPAPER_SIGNING_P12
	printf '%s' "$P12_PASSWORD" | set_environment_secret LIVEPAPER_SIGNING_P12_PASSWORD
fi
unset P12_PASSWORD AGAIN
pause

stage "The requirement, recorded"
if [ "$DRY_RUN" = 1 ]; then
	note "dry run: it would record"
	sed 's/^/    /' "$WORK/requirement.txt"
else
	mv "$WORK/requirement.txt" "$REQUIREMENT_FILE"
	ok "wrote designated-requirement.txt"
	if kit notices --root "$ROOT" --write >/dev/null; then
		ok "wrote README.md's copy of it"
	else
		TODO+=("make notices, to copy the requirement into README.md")
		warn "could not write README.md's copy; run make notices"
	fi
	say "Commit Tools/release/designated-requirement.txt and README.md."
fi
pause

finish
