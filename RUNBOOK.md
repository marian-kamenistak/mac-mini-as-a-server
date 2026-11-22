# Mac mini setup runbook

Takes a new or wiped Mac mini to an always-on runner for scheduled jobs. Every step is a command plus a check. Re-running any script is safe. When a step needs a fix, add a row to [PITFALLS.md](PITFALLS.md).

Placeholders used below: user `youruser` (in a shell: `$USER`), mini hostname `my-mini` (ssh alias `mini`), Tailscale IP `100.x.y.z`, home folder `$HOME`.

**Assumed machine:** Mac mini on Apple silicon, macOS 26 or newer, FileVault on, Ethernet. If the mini ships with a newer major macOS than your laptop, check launchd, background items and Tailscale behaviour before moving jobs, and keep both on the same major version.

**Laptop ssh alias:** in `~/.ssh/config`:

```
Host mini
  HostName 100.x.y.z
  User youruser
  IdentityFile ~/.ssh/id_ed25519_mini
```

Use the `.local` name until Tailscale is up, then switch `HostName` to the Tailscale IP.

## Hard rules

1. **Never use Migration Assistant.** It copies every live LaunchAgent, and every job then runs on both Macs.
2. **Same account name on both Macs** (`youruser`). Every plist and script hard-codes `/Users/youruser`.
3. **One job, one machine.** Move jobs only with `scripts/move-job.sh`.
4. **No `ANTHROPIC_API_KEY` on the mini.** With it set, `claude -p` silently bills the API.

## Phase A: at the mini (15 minutes, monitor and keyboard attached)

| # | Step | Check |
|---|---|---|
| A1 | Connect Ethernet. In Setup Assistant create the account `youruser` with a strong password (save it in your password manager). Sign in to your Apple ID. Turn FileVault ON with a recovery key, not iCloud, and store the key in your password manager | You can log in |
| A2 | Software Update to the latest release | `sw_vers` |
| A3 | System Settings > General > Sharing: set Local hostname to `my-mini`. Remote Login ON for your user only, with "Allow full disk access for remote users" ticked. Screen Sharing ON | `nc -z my-mini.local 22` from the laptop succeeds |
| A3b | Sharing > Remote Management (the i button): "Always show status in menu bar" ON. "Anyone may request permission" OFF. "VNC viewers may control screen with password" OFF. Allow access for "Only these users": your user. Options: tick Observe and Control | From the laptop, `open vnc://100.x.y.z` signs in with your mini account |
| A4 | In Terminal: `echo "$USER ALL=(ALL) NOPASSWD: ALL" \| sudo tee /etc/sudoers.d/automation && sudo chmod 440 /etc/sudoers.d/automation && sudo visudo -c` | "parsed OK" |
| A5 | iCloud: turn OFF Desktop and Documents, Photos and Messages. Focus: Do Not Disturb always on | n/a |

A4 lets scripts run `sudo` without a password so setup can run over SSH. It is a real trade-off. Delete `/etc/sudoers.d/automation` when setup is done if you do not want it.

## Phase B: from the laptop

| # | Command (laptop unless noted) | Check |
|---|---|---|
| B1 | `ssh-copy-id -i ~/.ssh/id_ed25519_mini.pub mini` (you type the mini password once) | `ssh -o BatchMode=yes mini true` |
| B2 | `bash scripts/50-secrets.sh`. It copies this kit to `~/mini-setup` on the mini, then the files listed in `secrets.list` (default: `~/.env`), minus `ANTHROPIC_API_KEY` | ALL PASS |
| B3 | `ssh mini 'bash ~/mini-setup/scripts/10-root.sh'`: hostname, energy, updates, firewall, key-only SSH, Spotlight off | ALL PASS, `pmset -g` shows sleep 0 |
| B4 | `ssh mini 'bash ~/mini-setup/scripts/20-toolchain.sh'`: Command Line Tools, Homebrew, formulas, Node, Python, npm packages, bun | ALL PASS |
| B5 | `ssh -t mini 'bash ~/mini-setup/scripts/30-tailscale.sh'`. Sign the browser in to the Tailscale account (tailnet) that you own, THEN open the printed URL. Fallback: an auth key from admin console > Settings > Keys. Then in the admin console: your mini > Disable key expiry | `tailscale ip -4` gives a 100.x.y.z IP. Put it in `~/.ssh/config` |
| B6 | `ssh -t mini 'gh auth login -h github.com -p https -w'`. You enter the device code | `gh auth status` |
| B7 | Copy `manifest/repos.tsv.example` to `manifest/repos.tsv`, edit it, re-run B2 so the kit on the mini has it, then `ssh mini 'bash ~/mini-setup/scripts/40-repos.sh'`. It clones every repo to the same path as on the laptop | ALL PASS |
| B8 | Screen Sharing (`vnc://100.x.y.z`) > Terminal on the mini: `bash ~/mini-setup/scripts/60-claude.sh`, then `claude` > `/login`, then run the script again. Open a new Terminal window first if `claude` is not found: windows opened before the PATH edit do not see it | "launchd job got a Claude answer" |
| B8b | Remote Control (optional), in the mini's GUI Terminal: `cd ~/code/my-project && claude` > trust the folder: Yes > `/exit` (trust is saved on exit). Then `claude remote-control` > y > Ctrl+C. Then from the laptop, edit `launchagents/local.claude-remote.plist` (user, paths, name) and: `scp launchagents/local.claude-remote.plist mini:Library/LaunchAgents/ && ssh mini 'launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.claude-remote.plist'` | `tail ~/logs/claude-remote.log` on the mini shows "Connected" |
| B9 | Claude config parity. Your `~/.claude` (settings, hooks, skills) comes over if it is a git repo in `repos.tsv`. Not in git: (a) plugins install at the first GUI start, compare `~/.claude/plugins/installed_plugins.json` on both Macs. (b) User MCP servers: copy the `mcpServers` block of `~/.claude.json`. (c) MCP servers that use OAuth keep their tokens in the Keychain per Mac: run `claude` > `/mcp` > Authenticate each, in the mini's GUI Terminal | `claude mcp list` on the mini shows every server Connected |
| B10 | If Screen Sharing shows a tiny resolution without a monitor, plug in an HDMI dummy plug | Resolution is normal |
| B11 | Remote test over a phone hotspot, not home Wi-Fi: `ssh mini`, Screen Sharing, and (if used) a Claude Remote Control session from your phone | All work |

## Phase C: move jobs (one per day at first)

For each job:

```bash
bash scripts/move-job.sh <launchd-label> --state <path-relative-to-HOME> [--state ...]
```

Before you move a job, run its dry run on the mini, with the environment its wrapper loads (`set -a; . ~/.env; set +a`). A bare hand-run does not load `~/.env` and looks broken when it is not. After every move, check `launchctl list` on both Macs.

State that a fresh clone does not have: anything gitignored. That includes "already sent" keys, ledgers, queues and `*.state.json` files. Without them a sender can contact the same people twice.

**Rollback** of one job:

1. On the mini: `launchctl bootout gui/$(id -u)/<label>`.
2. On the laptop: `mv ~/Library/LaunchAgents/<label>.plist.moved-to-mini ~/Library/LaunchAgents/<label>.plist && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<label>.plist`.
3. Copy the state back the same way it went over.

## Interactive Claude sessions on the mini

A plain `ssh mini claude` answers "Not logged in", because SSH cannot open the login Keychain. Two fixes, pick by what you need.

**Fix 1, the model only: a token for SSH shells.** Enough for a quick question or a script. It does not bring connectors, OAuth tool servers or Artifacts.

| # | Step | Check |
|---|---|---|
| S1 | From the laptop: `ssh -t mini 'claude setup-token'`. Open the link, approve, paste the one-time code back into the terminal | It prints a token that starts with `sk-ant-oat01-` |
| S2 | Copy only the token line, then: `pbpaste \| ssh mini 'umask 077; cat > ~/.claude/ssh-oauth-token'` | `ssh mini 'wc -c ~/.claude/ssh-oauth-token'` shows about 110 bytes, not the length of the command |
| S3 | In `~/.zshenv` on the mini: `if [[ -n $SSH_CONNECTION && -r ~/.claude/ssh-oauth-token ]]; then export CLAUDE_CODE_OAUTH_TOKEN="$(<~/.claude/ssh-oauth-token)"; fi` | Desktop sessions and launchd jobs keep using the Keychain |
| S4 | `ssh mini 'claude -p "Reply with exactly: ok"'` | Prints ok, exit code 0 |
| S5 | Keep a copy in your password manager. The token ends after one year: set an alert before that date | The alert exists |

**Fix 2, the full login: a tmux server that starts with the desktop login.** Sessions opened inside it inherit the desktop login, so the Keychain opens. They also survive a dropped SSH connection.

| # | Step | Check |
|---|---|---|
| T1 | On the mini: `brew install tmux`, copy `launchagents/local.tmux-gui.plist` to `~/Library/LaunchAgents/`, replace `youruser`, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.tmux-gui.plist` | `ssh mini /opt/homebrew/bin/tmux -L claude ls` shows `keep` |
| T2 | Link `scripts/claude-mini-remote` into `~/.local/bin` on the mini and `scripts/claude-mini` into `~/.local/bin` on the laptop | `which claude-mini` on the laptop |
| T3 | In a project folder on the laptop: `claude-mini` | Claude opens on the mini in the same folder; `/mcp` lists your connectors |
| T4 | Close the terminal tab, run `claude-mini` in the same folder again | It prints "reattaching" and the conversation is still there |

`claude-mini` warns about uncommitted or unpushed changes on the laptop, because the mini cannot see them. On the mini it pulls only when the folder there is clean. The mini must be logged in at the desktop (see Reboots).

## Reboots (FileVault ON)

- **Planned:** `ssh mini 'sudo fdesetup authrestart'`. It comes back logged in. Test this once while you are at home.
- **Unplanned** (a power cut longer than the UPS, a kernel panic): the mini waits at the FileVault screen. Unlock it at home, or from the home LAN with `ssh youruser@<LAN-IP>` (pre-boot SSH, needs Ethernet). Set up an alert on missing job runs so you notice.

After any restart, log in on the mini (Screen Sharing over Tailscale, or a keyboard), then check that your LaunchAgents are loaded (`ssh mini 'launchctl list | grep -c <your-label-prefix>'`) and that Remote Control logs "Connected". Automatic login is not possible while FileVault is ON.
