# Sourced by the release scripts. Bash 3.2, as macOS ships it.
#
# Nothing here, or in a script that sources it, runs under `set -x`: some steps
# hold a secret in a variable, and a trace would print it.

# The names below are for the scripts that source this file.
# shellcheck disable=SC2034
set -euo pipefail
set +x

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RELEASE_DIR="$ROOT/build/release"
REQUIREMENT_FILE="$ROOT/Tools/release/designated-requirement.txt"
IDENTITY_NAME="Livepaper Release"
APP_ID="app.livepaper.Livepaper"
EXTENSION_ID="app.livepaper.Livepaper.WallpaperExtension"
REPO_SLUG="oTerminal/Livepaper"
FEED_URL="https://oterminal.github.io/Livepaper/appcast.xml"

say() { printf 'release: %s\n' "$*"; }
die() {
	printf 'release: refused: %s\n' "$*" >&2
	exit 1
}

# The refusal sign.sh makes for `--deep`, whoever passes it.
refuse_deep() {
	local argument
	for argument in "$@"; do
		[ "$argument" != "--deep" ] || die "never --deep: sign.sh signs each piece of code itself, innermost first"
	done
}

# release-kit, built once by the first script of a run and handed to the scripts it
# runs through the environment.
if [ -z "${RELEASE_KIT:-}" ]; then
	swift build --package-path "$ROOT/Tools/release" -c release --product release-kit --quiet >&2
	RELEASE_KIT="$(swift build --package-path "$ROOT/Tools/release" -c release --show-bin-path)/release-kit"
	export RELEASE_KIT
fi
kit() { "$RELEASE_KIT" "$@"; }

# Sparkle's tools from the archive sparkle.env pins; prints the folder holding bin/.
sparkle_tools() {
	# shellcheck source=Tools/release/sparkle.env
	. "$ROOT/Tools/release/sparkle.env"
	grep -q "exactVersion: $SPARKLE_VERSION\$" "$ROOT/project.yml" \
		|| die "project.yml does not pin Sparkle $SPARKLE_VERSION, the version sparkle.env names"
	local dest="$RELEASE_DIR/sparkle-$SPARKLE_VERSION"
	if [ -x "$dest/bin/generate_appcast" ] && [ "$(cat "$dest/.sha256" 2>/dev/null)" = "$SPARKLE_SHA256" ]; then
		printf '%s\n' "$dest"
		return
	fi
	rm -rf "${dest:?}"
	mkdir -p "$dest"
	curl -fsSL --retry 3 -o "$dest/archive.tar.xz" "$SPARKLE_URL"
	local actual
	actual="$(shasum -a 256 "$dest/archive.tar.xz" | cut -d' ' -f1)"
	[ "$actual" = "$SPARKLE_SHA256" ] || die "Sparkle's archive has sha256 $actual, not the pinned $SPARKLE_SHA256"
	tar -xJf "$dest/archive.tar.xz" -C "$dest" ./bin ./LICENSE
	rm "$dest/archive.tar.xz"
	printf '%s\n' "$SPARKLE_SHA256" >"$dest/.sha256"
	printf '%s\n' "$dest"
}

# The app's version and build, from its Info.plist.
bundle_version() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist"; }
bundle_build() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist"; }

# The recorded requirement line for one identifier, after "designated => ".
recorded_requirement() {
	grep "^designated => identifier \"$1\" " "$REQUIREMENT_FILE" | sed 's/^designated => //'
}
