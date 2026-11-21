# lib.sh: shared helpers for the setup scripts. Source it, do not run it.
# Every script logs to <kit>/logs/<date>_<script>.log (gitignored) and prints PASS / FAIL lines.
set -euo pipefail
# ssh sessions start with a PATH of /usr/bin:/bin only, so export a full one (see PITFALLS.md)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$KIT/logs"
LOG="$KIT/logs/$(date +%F)_$(basename "$0" .sh).log"
exec > >(tee -a "$LOG") 2>&1
say()  { printf '\n== %s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAILS=$((${FAILS:-0}+1)); }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }
done_summary() { [ "${FAILS:-0}" = 0 ] && echo "ALL PASS ($(basename "$0"))" || { echo "$FAILS FAIL(s) ($(basename "$0")), see $LOG"; exit 1; }; }
# The macOS "Local hostname" you set in System Settings > General > Sharing on the mini.
MINI_HOST_NAME="${MINI_HOST_NAME:-my-mini}"
on_mini() { [ "$(scutil --get LocalHostName 2>/dev/null)" = "$MINI_HOST_NAME" ]; }
