#!/bin/bash
# 50-secrets.sh: copy machine-local secret files laptop -> mini over SSH
# (encrypted, direct, no third copy anywhere). Run ON THE LAPTOP.
# Your password manager stays the source of truth: these are the working copies the jobs read.
#
# WHAT GETS COPIED: the paths listed in secrets.list (one path per line, relative to $HOME, files only).
# No list yet? Only ~/.env is copied. Copy secrets.list.example to secrets.list and edit it.
#
# ANTHROPIC_API_KEY is stripped from every file on the way. With that key set,
# `claude -p` bills the API instead of your subscription, silently.
source "$(dirname "$0")/lib.sh"
on_mini && { echo "run this on the laptop, not the mini"; exit 2; }
H="${MINI_HOST:-mini}"          # the ssh alias of the mini
LIST="${SECRETS_LIST:-$KIT/secrets.list}"
check "ssh to $H" ssh -o BatchMode=yes "$H" true

say "0. the kit itself (so the mini can run 10-40 before anything else exists there)"
if ssh "$H" 'mkdir -p ~/mini-setup' && rsync -a --exclude logs --exclude secrets.list "$KIT/" "$H:mini-setup/"; then pass "kit copied to ~/mini-setup"; else fail "kit copy"; fi

say "1. secret files (ANTHROPIC_API_KEY removed)"
FILES=".env"
[ -f "$LIST" ] && FILES="$(grep -vE '^[[:space:]]*(#|$)' "$LIST")"
for f in $FILES; do
  [ -f "$HOME/$f" ] || { echo "  skip $f (not on this machine)"; continue; }
  if { grep -a -v -E '^(export )?ANTHROPIC_API_KEY=' "$HOME/$f" || true; } \
     | ssh "$H" "umask 077; mkdir -p \"\$(dirname ~/$f)\"; cat > ~/$f; chmod 600 ~/$f"; then pass "$f"; else fail "$f"; fi
done
check "mini ~/.env has no ANTHROPIC_API_KEY" ssh "$H" "! grep -qE '^(export )?ANTHROPIC_API_KEY=' ~/.env 2>/dev/null"

echo "  NOT copied on purpose: browser profiles (cookies are bound to each Mac's Keychain: log in again on the mini),"
echo "  cloud CLI logins (re-auth on the mini), Claude credentials (Keychain: run /login on the mini)."
done_summary
