# mac-mini-as-a-server

A runbook and a set of scripts that turn a Mac mini into an always-on home runner for your scheduled jobs, your Claude Code jobs and your logged-in browser jobs.

The laptop sleeps, travels and freezes. The jobs that live on it fail with it. The mini sits at home, stays awake and keeps the same IP, the same browser sessions and the same Claude login.

Full story: [Mac mini as a server: 53 lessons learned moving my AI jobs](https://www.marian.coach/blog/mac-mini-as-a-server/)

## Where each job runs

Put a job on the mini only if nothing else can run it.

| Where | What runs there | Why |
|---|---|---|
| **MacBook** | Only what is bound to where you work: your own session files, the microphone, screenshots | The data is created there |
| **Mac mini** | Only what the cloud cannot run: logged-in browsers, `claude -p` on local files and skills, and the pollers that start them | It needs a home IP, a signed-in browser profile or the subscription CLI |
| **Cloudflare Workers** | APIs, sending, frequent crons | Always on, no machine to look after |
| **GitHub Actions** | Repo batch work that commits | Runs next to the repo, with both Macs off |
| **Claude routines** | LLM judgment that has to run with both Macs off | Needs no machine of yours at all |

The mini is not a reason to stop moving jobs to the cloud. If a job can run in the cloud, move it there.

## The 4 hard rules

1. **Skip Migration Assistant.** It copies your LaunchAgents, and then each job runs on both Macs. Set the mini up fresh and move jobs one by one.
2. **Same username on both Macs.** Plists and scripts hard-code `/Users/<name>`. With the same name you edit no paths.
3. **One job, one machine.** Move a job only with `scripts/move-job.sh`. It stops the job on the laptop, copies its state, then starts it on the mini.
4. **No `ANTHROPIC_API_KEY` on the mini.** With the key set, `claude -p` bills the API instead of your subscription, and it does so silently.

## Quick start

1. Do phase A of [RUNBOOK.md](RUNBOOK.md) at the mini with a monitor and keyboard (15 minutes).
2. From the laptop, copy your ssh key to the mini and name it `mini` in `~/.ssh/config`.
3. Copy `secrets.list.example` to `secrets.list` and edit it. Copy `manifest/repos.tsv.example` to `manifest/repos.tsv` and edit it.
4. Run the scripts in order. Each one prints PASS or FAIL for every check and ends with ALL PASS or a count of failures. Re-running is safe.

```bash
bash scripts/50-secrets.sh                              # laptop: copies the kit and your secret files
ssh mini 'bash ~/mini-setup/scripts/10-root.sh'         # hostname, energy, updates, firewall, ssh
ssh mini 'bash ~/mini-setup/scripts/20-toolchain.sh'    # Homebrew, Node, Python, npm packages
ssh -t mini 'bash ~/mini-setup/scripts/30-tailscale.sh' # remote access without a static IP
ssh -t mini 'gh auth login -h github.com -p https -w'   # once, by hand
ssh mini 'bash ~/mini-setup/scripts/40-repos.sh'        # clone your repos to the same paths
# at the mini, in the GUI Terminal: bash ~/mini-setup/scripts/60-claude.sh, then claude, then /login, then run it again
```

5. Move jobs one at a time:

```bash
bash scripts/move-job.sh com.example.my-job --state code/my-jobs/.state/my-job.json
```

Set `MINI_HOST_NAME` (default `my-mini`) to the Local hostname you gave the mini. Other settings are variables at the top of each script.

## Files

- [RUNBOOK.md](RUNBOOK.md): every step as a command plus a check, phase A (at the mini), phase B (from the laptop), moving jobs, rollback, reboots
- [PITFALLS.md](PITFALLS.md): what I assumed, what was true, and the fix, for the mistakes along the way
- `scripts/lib.sh`: shared helpers and the full PATH export
- `scripts/10-root.sh` to `scripts/60-claude.sh`: the setup steps
- `scripts/move-job.sh`: move one launchd job to the mini
- `launchagents/`: example plists for a job wrapper and for Claude Remote Control
- `manifest/repos.tsv.example`, `secrets.list.example`: the two lists you edit
- `LICENSE`: MIT

No secrets live here. `50-secrets.sh` copies them from your laptop to the mini over SSH when you run it, and removes `ANTHROPIC_API_KEY` on the way.
