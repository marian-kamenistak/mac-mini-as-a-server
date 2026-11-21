#!/bin/bash
# 60-claude.sh: Claude Code on the mini (native installer).
# Run ON THE MINI. The login itself is manual and must happen in the GUI session
# (Screen Sharing > Terminal > `claude` > /login), so the credential lands in the login Keychain,
# which LaunchAgents can read. A login done over SSH falls back to a file.
source "$(dirname "$0")/lib.sh"
on_mini || { echo "not on the mini, refusing"; exit 2; }
[ -x ~/.local/bin/claude ] || curl -fsSL https://claude.ai/install.sh | bash
check "claude installed" ~/.local/bin/claude --version
check "no ANTHROPIC_API_KEY in ~/.env" sh -c "! grep -qE '^(export )?ANTHROPIC_API_KEY=' ~/.env 2>/dev/null"
say "auth (informational)"
if ~/.local/bin/claude auth status >/dev/null 2>&1; then pass "logged in (this shell)"
elif [ -n "${SSH_CONNECTION:-}" ]; then
  echo "  over SSH the login Keychain is locked, so 'not logged in' here is expected. The LaunchAgent test below decides."
else
  echo "  not logged in yet: Terminal on the mini > claude > /login, then re-run"
fi
say "LaunchAgent smoke test: can a launchd job (not this shell) reach Claude?"
mkdir -p ~/Library/LaunchAgents   # a fresh Mac has no such folder
LABEL=local.zz-claude-smoke; PL=~/Library/LaunchAgents/$LABEL.plist; OUT=/tmp/zz-claude-smoke.out; rm -f "$OUT"
cat > "$PL" <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>-c</string><string>env | grep -c ANTHROPIC_API_KEY; $HOME/.local/bin/claude -p 'reply with the single word ok' --model haiku</string></array>
<key>StandardOutPath</key><string>$OUT</string><key>StandardErrorPath</key><string>$OUT</string><key>RunAtLoad</key><true/></dict></plist>
EOF
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "$PL"
for i in $(seq 1 45); do grep -qi ok "$OUT" 2>/dev/null && break; sleep 2; done
sed 's/^/  /' "$OUT" 2>/dev/null || true
check "launchd job got a Claude answer" grep -qi '^ok' "$OUT"
launchctl bootout gui/$(id -u)/$LABEL 2>/dev/null || true; rm -f "$PL"
done_summary
