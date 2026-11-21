#!/bin/bash
# 30-tailscale.sh: open-source tailscaled as a system daemon. It starts before login,
# so a reboot never cuts remote access. Run ON THE MINI.
# The first run prints a login URL: open it in a browser that is signed in to the tailnet YOU own.
source "$(dirname "$0")/lib.sh"
on_mini || { echo "not on the mini, refusing"; exit 2; }
eval "$(/opt/homebrew/bin/brew shellenv)"
TS_HOSTNAME="${TS_HOSTNAME:-$(echo "$MINI_HOST_NAME" | tr 'A-Z' 'a-z')}"
command -v tailscale >/dev/null || brew install tailscale
say "system daemon"
if [ ! -f /Library/LaunchDaemons/com.tailscale.tailscaled.plist ]; then
  sudo "$(brew --prefix)/bin/tailscaled" install-system-daemon
fi
sleep 3
say "bring up (node name $TS_HOSTNAME). If a URL prints, approve it in the browser."
# --accept-dns=false: do not depend on MagicDNS (see PITFALLS.md). Use the 100.x IP for ssh and vnc.
sudo tailscale up --hostname="$TS_HOSTNAME" --accept-dns=false || true
tailscale status | head -5
IP="$(tailscale ip -4 2>/dev/null || true)"
if [ -n "$IP" ]; then pass "tailnet IP $IP"; echo "$IP" > "$KIT/logs/tailscale-ip.txt"; else fail "no tailnet IP yet (approve the login URL, then re-run)"; fi
echo "  NEXT (once): Tailscale admin console > Machines > $TS_HOSTNAME > Disable key expiry."
done_summary
