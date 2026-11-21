#!/bin/bash
# 10-root.sh: system settings on the mini. Needs sudo (the NOPASSWD rule from RUNBOOK step A4).
# Safe to re-run. Run ON THE MINI: bash ~/mini-setup/scripts/10-root.sh
# Set REQUIRE_FILEVAULT=0 if you chose to run with FileVault off.
source "$(dirname "$0")/lib.sh"
on_mini || { echo "not on the mini (LocalHostName != $MINI_HOST_NAME), refusing"; exit 2; }

say "machine role (a job wrapper can read this to refuse to run on the wrong machine)"
echo "mini  # always-on home runner" > "$HOME/.machine-role"
check "role mini" grep -q "^mini" "$HOME/.machine-role"

say "hostname"
# Without HostName, `hostname` falls back to the router's DHCP name
sudo scutil --set HostName "$MINI_HOST_NAME"
check "LocalHostName=$MINI_HOST_NAME" test "$(scutil --get LocalHostName)" = "$MINI_HOST_NAME"

say "energy: never sleep, restart after power loss, wake on LAN"
sudo pmset -a sleep 0 disksleep 0 displaysleep 10 powernap 0 womp 1 autorestart 1 tcpkeepalive 1
sudo systemsetup -setrestartfreeze on >/dev/null 2>&1 || true
pmset -g | sed 's/^/  /'
check "pmset sleep 0" sh -c "pmset -g | grep -Eq '^ *sleep +0'"
check "pmset autorestart 1" sh -c "pmset -g | grep -Eq 'autorestart +1'"

say "software updates: check and download, never auto-install"
# With FileVault on, an unattended restart waits at the unlock screen and every job stops.
P=/Library/Preferences/com.apple.SoftwareUpdate
sudo defaults write $P AutomaticCheckEnabled -bool true
sudo defaults write $P AutomaticDownload -bool true
sudo defaults write $P AutomaticallyInstallMacOSUpdates -bool false
sudo defaults write $P CriticalUpdateInstall -bool false
sudo defaults write $P ConfigDataInstall -bool false
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false
check "no auto macOS install" test "$(defaults read $P AutomaticallyInstallMacOSUpdates)" = 0
echo "  NOTE: also confirm in System Settings > General > Software Update > Automatic Updates (the i button): 'Install Security Responses and system files' is OFF."

say "firewall on + stealth (not block-all: that kills SSH)"
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
sudo $FW --setglobalstate on >/dev/null; sudo $FW --setstealthmode on >/dev/null
check "firewall on" sh -c "$FW --getglobalstate | grep -q enabled"

say "SSH: key-only (only if a key is already authorized, so we never lock ourselves out)"
if [ -s "$HOME/.ssh/authorized_keys" ]; then
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\nAllowUsers %s\n' "$(id -un)" | sudo tee /etc/ssh/sshd_config.d/100-no-passwords.conf >/dev/null
  sudo launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true
  check "sshd config valid" sudo /usr/sbin/sshd -t
else
  fail "no ~/.ssh/authorized_keys yet: run ssh-copy-id from the laptop first (password login left ON)"
fi

say "FileVault"
fdesetup status | sed 's/^/  /'
if [ "${REQUIRE_FILEVAULT:-1}" = 1 ]; then
  check "FileVault on" sh -c "fdesetup status | grep -q 'FileVault is On'"
fi

say "no Spotlight indexing of job churn and browser profiles"
if sudo mdutil -i off /System/Volumes/Data >/dev/null 2>&1; then pass "Spotlight off on data volume"; else fail "mdutil"; fi

done_summary
