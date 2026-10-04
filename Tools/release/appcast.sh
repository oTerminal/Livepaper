#!/bin/bash
# The appcast: one appcast.xml for the app's life, on the orphan `appcast`
# branch that GitHub Pages serves at https://oterminal.github.io/Livepaper/appcast.xml.
#
#   appcast.sh fetch <file>
#       Writes the published feed to <file>, from the public repo's appcast branch;
#       writes nothing when it has no such branch yet (the first release).
#       Any other failure to read it stops the release.
#   appcast.sh make <zip> --key-file <file> --feed <published appcast.xml> --out <file>
#       Signs the zip with generate_appcast and the EdDSA private key in <file>, and
#       writes the published feed with the release added, its notes the changelog's
#       section. Refuses a build already in the feed or not above its last, an
#       unsigned entry (the key is not the app's SUPublicEDKey) and a missing section.
#   appcast.sh publish <file> [--dry-run]
#       Commits <file> as the appcast branch's appcast.xml and pushes it; with
#       --dry-run, makes the commit and says what it would push.
#   appcast.sh init [--dry-run]
#       Makes the appcast branch with a feed of no releases, when the repo has none,
#       so that GitHub Pages can serve it before the first release.
. "$(dirname "$0")/lib.sh"

BRANCH=appcast
# The public repo, named outright: a checkout's origin may be another one.
FEED_REPO="https://github.com/$REPO_SLUG.git"
FEED_REF="refs/remotes/feed/$BRANCH"
# Where gh is signed in, it answers for git too.
PUSH_AUTH=()
if command -v gh >/dev/null 2>&1; then
	PUSH_AUTH=(-c credential.helper= -c 'credential.helper=!gh auth git-credential')
fi
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT

fetch() {
	local out="${1:?appcast.sh fetch <file>}"
	rm -f "$out"
	local status=0
	git -C "$ROOT" ls-remote --exit-code --heads "$FEED_REPO" "$BRANCH" >/dev/null || status=$?
	case "$status" in
	0)
		git -C "$ROOT" fetch --quiet "$FEED_REPO" "+refs/heads/$BRANCH:$FEED_REF"
		git -C "$ROOT" show "$FEED_REF:appcast.xml" >"$out"
		say "appcast: the published feed's last build is $(kit appcast last --appcast "$out")"
		;;
	2) say "appcast: $REPO_SLUG has no $BRANCH branch yet: this is the first release" ;;
	*) die "could not read $REPO_SLUG's $BRANCH branch (git ls-remote said $status)" ;;
	esac
}

make_feed() {
	local zip="" key="" feed="" out=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--key-file) key="${2:?}" && shift ;;
		--feed) feed="${2:?}" && shift ;;
		--out) out="${2:?}" && shift ;;
		--dry-run) ;; # making the feed publishes nothing
		-*) die "unknown option $1" ;;
		*) zip="$1" ;;
		esac
		shift
	done
	[ -f "$zip" ] && [ -f "$key" ] && [ -n "$out" ] || die "usage: appcast.sh make <zip> --key-file <file> --feed <file> --out <file>"
	local version tools
	version="$(basename "$zip" .zip)"
	version="${version#Livepaper-}"
	tools="$(sparkle_tools)"
	# generate_appcast reads a folder: one holding this release's zip alone.
	cp "$zip" "$WORK/"
	"$tools/bin/generate_appcast" --ed-key-file "$key" \
		--download-url-prefix "https://github.com/$REPO_SLUG/releases/download/v$version/" \
		--maximum-versions 0 --maximum-deltas 0 "$WORK" >/dev/null
	kit appcast merge --generated "$WORK/appcast.xml" --appcast "$feed" --changelog "$ROOT/CHANGELOG.md" \
		--url "https://github.com/$REPO_SLUG/releases/download/v$version/$(basename "$zip")" \
		--feed-url "$FEED_URL" >"$out"
	say "appcast: $out lists $(grep -c "<item>" "$out") release(s), $version the newest"
}

publish() {
	local file="${1:?appcast.sh publish <file> [--dry-run]}" dry_run="${2:-}" parent="" blob nojekyll tree commit last message
	if git -C "$ROOT" rev-parse --verify --quiet "$FEED_REF" >/dev/null; then
		parent="$(git -C "$ROOT" rev-parse "$FEED_REF")"
	fi
	blob="$(git -C "$ROOT" hash-object -w "$file")"
	nojekyll="$(git -C "$ROOT" hash-object -w --stdin </dev/null)"
	tree="$(printf '100644 blob %s\t.nojekyll\n100644 blob %s\tappcast.xml\n' "$nojekyll" "$blob" | git -C "$ROOT" mktree)"
	last="$(kit appcast last --appcast "$file")"
	message="Appcast: no releases yet"
	[ -z "$last" ] || message="Appcast: build $last"
	commit="$(git -C "$ROOT" commit-tree "$tree" ${parent:+-p "$parent"} -m "$message")"
	if [ "$dry_run" = "--dry-run" ]; then
		say "appcast: dry run: would push $commit ($message) to $BRANCH"
		return
	fi
	git -C "$ROOT" ${PUSH_AUTH[@]+"${PUSH_AUTH[@]}"} push --quiet "$FEED_REPO" "${commit}:refs/heads/$BRANCH"
	say "appcast: pushed $commit to $BRANCH"
}

init() {
	local dry_run="${1:-}" feed
	feed="$WORK/feed.xml"
	fetch "$feed"
	if [ -s "$feed" ]; then
		say "appcast: $REPO_SLUG has the $BRANCH branch already"
	else
		kit appcast empty --feed-url "$FEED_URL" >"$feed"
		publish "$feed" "$dry_run"
	fi
}

case "${1:-}" in
init) shift && init "$@" ;;
fetch) shift && fetch "$@" ;;
make) shift && make_feed "$@" ;;
publish) shift && publish "$@" ;;
*) die "usage: appcast.sh fetch | make | publish" ;;
esac
