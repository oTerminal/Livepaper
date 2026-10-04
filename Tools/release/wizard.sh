# Sourced by make-cert.sh and sparkle-keys.sh: the owner's one-time steps, one
# stage at a time. Nothing is written to a .env file, and secrets go to the GitHub
# `release` environment, never the repository's.

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
	BOLD=$(tput bold) DIM=$(tput dim) RESET=$(tput sgr0)
	BLUE=$(tput setaf 4) GREEN=$(tput setaf 2) YELLOW=$(tput setaf 3)
else
	BOLD="" DIM="" RESET="" BLUE="" GREEN="" YELLOW=""
fi

TOTAL_STAGES=0
_STAGE_INDEX=0
DONE=()
TODO=()

_clear() {
	[[ -t 1 ]] || return 0
	tput clear 2>/dev/null || printf '\033[2J\033[3J\033[H'
}

banner() {
	_clear
	printf '\n%s%s  %s%s\n' "$BOLD" "$BLUE" "$1" "$RESET"
	printf '%s  %s stages. Stop any time with Ctrl-C.%s\n\n' "$DIM" "$TOTAL_STAGES" "$RESET"
	pause "Ready to start?"
}

stage() {
	_clear
	_STAGE_INDEX=$((_STAGE_INDEX + 1))
	printf '\n%s%s▸ Stage %s/%s · %s%s\n' "$BOLD" "$BLUE" "$_STAGE_INDEX" "$TOTAL_STAGES" "$1" "$RESET"
}

say() { printf '  %s\n' "$1"; }
step() { printf '  %s•%s %s\n' "$BLUE" "$RESET" "$1"; }
note() { printf '  %s%s%s\n' "$DIM" "$1" "$RESET"; }
warn() { printf '  %s⚠ %s%s\n' "$YELLOW" "$1" "$RESET"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$1"; }

open_url() {
	printf '  %s↗ opening%s %s\n' "$GREEN" "$RESET" "$1"
	open "$1" >/dev/null 2>&1 || warn "couldn't open a browser; visit it yourself: $1"
}

pause() {
	printf '  %s%s%s ' "$DIM" "${1:-Press Enter to continue}" "$RESET"
	read -r _ || true
}

confirm() {
	local reply=""
	printf '  %s? %s [y/N]%s ' "$YELLOW" "$1" "$RESET"
	read -r reply || true
	[[ "$reply" =~ ^[Yy] ]]
}

# ask_secret NAME "Prompt": hidden entry into $NAME.
ask_secret() {
	local input=""
	printf '  %s%s%s ' "$BOLD" "$2" "$RESET"
	read -rs input || true
	printf '\n'
	printf -v "$1" '%s' "$input"
}

gh_ready() { command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }

# set_environment_secret NAME < value: a secret of the repository's `release`
# environment, read from standard input so that it is never in an argument.
set_environment_secret() {
	if gh_ready && gh secret set "$1" --env release --repo "$REPO_SLUG" >/dev/null 2>&1; then
		DONE+=("the release environment's secret $1")
		ok "set the release environment's secret $1"
	else
		cat >/dev/null
		TODO+=("set the release environment's secret $1: gh secret set $1 --env release --repo $REPO_SLUG")
		warn "could not set $1; set it yourself afterwards"
	fi
}

finish() {
	_clear
	printf '\n%s%s  ✓ Done%s\n' "$BOLD" "$GREEN" "$RESET"
	local item
	for item in ${DONE[@]+"${DONE[@]}"}; do note "  - $item"; done
	if ((${#TODO[@]})); then
		printf '\n'
		warn "still to do by hand:"
		for item in "${TODO[@]}"; do note "  - $item"; done
	fi
	printf '\n'
}
