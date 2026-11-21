#!/bin/bash
# move-job.sh <launchd-label> [--state <path-relative-to-$HOME>]...
# Move ONE launchd job laptop -> mini, never both running. Run ON THE LAPTOP.
# The order is the safety:
#   1. stop it on the laptop   2. copy its gitignored state   3. install and load it on the mini
# Example:
#   move-job.sh com.example.nightly-report --state projects/report/.state.json
# For jobs that send or post anything, also pass the folder that holds their "already sent" keys.
# Rollback: see RUNBOOK.md, "Rollback".
source "$(dirname "$0")/lib.sh"
on_mini && { echo "run this on the laptop"; exit 2; }
L="${1:?label}"; shift; STATE=()
while [ $# -gt 0 ]; do case "$1" in --state) STATE+=("$2"); shift 2;; *) echo "unknown arg $1"; exit 2;; esac; done
H="${MINI_HOST:-mini}"; LA=~/Library/LaunchAgents; P="$LA/$L.plist"
[ -f "$P" ] || { echo "no $P on the laptop"; exit 2; }
say "1. laptop: stop and mark moved"
launchctl bootout gui/$(id -u)/"$L" 2>/dev/null || true
cp -p "$P" "$KIT/logs/$L.plist" && mv "$P" "$P.moved-to-mini"
check "not loaded on laptop" sh -c "! launchctl list | grep -q '$L\$'"
say "2. copy state"
# ${ARR[@]+"${ARR[@]}"} is the empty-array-safe form on macOS bash 3.2 with set -u
for s in ${STATE[@]+"${STATE[@]}"}; do
  [ -e "$HOME/$s" ] || { fail "state $s missing on laptop"; continue; }
  if ssh "$H" "mkdir -p \"\$(dirname ~/$s)\"" && rsync -a "$HOME/$s" "$H:$(dirname "$s")/"; then pass "state $s"; else fail "state $s"; fi
done
say "3. mini: install and load"
scp -q -p "$KIT/logs/$L.plist" "$H:Library/LaunchAgents/$L.plist"
ssh "$H" "launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/$L.plist" || true
check "loaded on mini" ssh "$H" "launchctl list | grep -q '$L\$'"
echo "$(date '+%F %T') moved $L state=[${STATE[*]+"${STATE[*]}"}]" >> "$KIT/MOVED.log"
done_summary
