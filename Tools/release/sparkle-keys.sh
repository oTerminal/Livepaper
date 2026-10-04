#!/bin/bash
# Makes Sparkle's EdDSA key pair, once, by hand, never in CI, and puts the feed
# on GitHub Pages. The public key goes into project.yml as SUPublicEDKey, which is
# committed; the private key into the owner's password manager and the GitHub
# `release` environment's secret SPARKLE_ED_PRIVATE_KEY, and nowhere else: it is
# taken out of the login keychain that generate_keys makes it in.
#
#   Tools/release/sparkle-keys.sh [--dry-run]
#
# The public key is written into project.yml, and the private key taken out of the
# keychain, last: once the private key is in the password manager and GitHub.
# Refuses to run again once project.yml has a key: a second key would make every
# installed copy refuse every later update. --dry-run makes a throwaway pair outside
# the keychain, and writes, saves, sets and pushes nothing.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/wizard.sh"

DRY_RUN=0
case "${1:-}" in
--dry-run) DRY_RUN=1 ;;
"") ;;
*) die "usage: sparkle-keys.sh [--dry-run]" ;;
esac
! grep -q 'SUPublicEDKey:' "$ROOT/project.yml" \
	|| die "project.yml has SUPublicEDKey: the key is made. Another would make installed copies refuse every update."
[ "$DRY_RUN" = 1 ] || command -v gh >/dev/null 2>&1 || die "this needs gh, signed in to GitHub with access to $REPO_SLUG"

ACCOUNT="livepaper-release"
KEY_LABEL="Private key for signing Sparkle updates"
# The private key lives in this folder, which only you can read and which is not
# synced anywhere, until the script ends, however it ends. rm -P overwrites first.
WORK="$(mktemp -d)"
chmod 700 "${WORK:?}"
forget() {
	rm -P "${WORK:?}"/* 2>/dev/null || true
	rm -rf "${WORK:?}"
}
trap forget EXIT
KEY_FILE="$WORK/Livepaper Sparkle EdDSA key.txt"

TOTAL_STAGES=5
TITLE="Sparkle's update key, and the feed"
[ "$DRY_RUN" = 0 ] || TITLE="$TITLE (dry run)"
banner "$TITLE"

stage "The key pair"
TOOLS="$(sparkle_tools)"
if [ "$DRY_RUN" = 1 ]; then
	PUBLIC_KEY="$(kit throwaway-key "$WORK")"
	mv "$WORK/throwaway-ed25519.txt" "$KEY_FILE"
	note "dry run: a throwaway pair, made outside the keychain"
else
	say "generate_keys makes the pair in your login keychain; macOS may ask to allow it."
	"$TOOLS/bin/generate_keys" --account "$ACCOUNT" >/dev/null
	PUBLIC_KEY="$("$TOOLS/bin/generate_keys" --account "$ACCOUNT" -p)"
	(umask 077 && "$TOOLS/bin/generate_keys" --account "$ACCOUNT" -x "$KEY_FILE" >/dev/null)
fi
[ -s "$KEY_FILE" ] && [ -n "$PUBLIC_KEY" ] || die "no key pair was made"
ok "made the pair; its public key is $PUBLIC_KEY"
pause

stage "Your password manager"
if [ "$DRY_RUN" = 1 ]; then
	note "dry run: this key is thrown away; nothing to save"
else
	open -R "$KEY_FILE"
	say "The Finder shows the private key's file in a private temporary folder."
	step "Save its one line in your password manager as 'Livepaper Sparkle EdDSA key'."
	note "Do not copy it anywhere else: the folder is deleted when this script ends."
	pause "Press Enter once it is saved there"
fi

stage "GitHub's secret"
if [ "$DRY_RUN" = 1 ]; then
	note "dry run: setting no secret"
else
	gh api -X PUT "repos/$REPO_SLUG/environments/release" >/dev/null 2>&1 || true
	set_environment_secret SPARKLE_ED_PRIVATE_KEY <"$KEY_FILE"
fi
pause

stage "The public key, recorded"
if [ "$DRY_RUN" = 1 ]; then
	note "dry run: it would write SUPublicEDKey: $PUBLIC_KEY into project.yml"
else
	if security delete-generic-password -a "$ACCOUNT" -l "$KEY_LABEL" >/dev/null 2>&1; then
		ok "took the private key out of the login keychain"
	else
		TODO+=("delete the keychain item \"$KEY_LABEL\" (account $ACCOUNT) in Keychain Access")
		warn "could not take it out of the login keychain; delete it in Keychain Access afterwards"
	fi
	awk -v key="$PUBLIC_KEY" '{ print } /^        SUFeedURL: / { print "        SUPublicEDKey: " key }' \
		"$ROOT/project.yml" >"$WORK/project.yml" && mv "$WORK/project.yml" "$ROOT/project.yml"
	grep -q "SUPublicEDKey: $PUBLIC_KEY" "$ROOT/project.yml" || die "could not write SUPublicEDKey into project.yml"
	ok "wrote SUPublicEDKey into project.yml; commit it"
fi
pause

stage "The feed on GitHub Pages"
say "Every copy of Livepaper reads $FEED_URL for its life."
if [ "$DRY_RUN" = 1 ]; then
	"$ROOT/Tools/release/appcast.sh" init --dry-run
	note "dry run: not turning Pages on"
else
	"$ROOT/Tools/release/appcast.sh" init
	if gh api -X POST "repos/$REPO_SLUG/pages" -f "source[branch]=appcast" -f "source[path]=/" >/dev/null 2>&1 \
		|| gh api "repos/$REPO_SLUG/pages" --jq '.source.branch' 2>/dev/null | grep -qx appcast; then
		ok "GitHub Pages serves the appcast branch"
	else
		TODO+=("serve the appcast branch with GitHub Pages: github.com/$REPO_SLUG/settings/pages, branch appcast, folder /")
		warn "could not turn Pages on; do it in the repository's settings"
		open_url "https://github.com/$REPO_SLUG/settings/pages"
	fi
	note "Pages takes a minute or two the first time. Then, with no GitHub account: curl -fsS $FEED_URL"
fi
pause

finish
