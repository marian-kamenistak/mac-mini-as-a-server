#!/bin/bash
# 20-toolchain.sh: developer toolchain on the mini. Safe to re-run. Run ON THE MINI.
# Versions and package lists are variables at the top: override them from the environment.
# Optional list files (one item per line): manifest/brew-leaves.txt, manifest/npm-global.txt,
# manifest/python-requirements.txt. Missing files are skipped.
source "$(dirname "$0")/lib.sh"
on_mini || { echo "not on the mini, refusing"; exit 2; }
NODE_VER="${NODE_VER:-24.18.0}"        # pin to what your laptop runs
PY_A="${PY_A:-3.14.6}"                 # the python3 that /usr/local/bin/python3 must point to
PY_B="${PY_B:-3.12.10}"                # optional second python.org version ("" to skip)
FORMULAE="${FORMULAE:-coreutils git gh jq tmux tailscale}"
CASKS="${CASKS:-google-chrome}"
TMP="$(mktemp -d)"

say "Xcode Command Line Tools"
if ! xcode-select -p >/dev/null 2>&1; then
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  label="$(softwareupdate -l 2>/dev/null | grep -Eo 'Label: Command Line Tools.*' | sed 's/Label: //' | tail -1)"
  sudo softwareupdate -i "$label" --verbose; rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
fi
check "CLT installed" xcode-select -p

say "Homebrew (native arm64, /opt/homebrew)"
[ -x /opt/homebrew/bin/brew ] || NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"
grep -q 'brew shellenv' ~/.zprofile 2>/dev/null || echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
grep -q 'brew shellenv' ~/.bash_profile 2>/dev/null || echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.bash_profile
check "brew works" brew --version

say "brew formulas and casks"
printf '%s\n' $FORMULAE > "$TMP/f.txt"
[ -f "$KIT/manifest/brew-leaves.txt" ] && cat "$KIT/manifest/brew-leaves.txt" >> "$TMP/f.txt"
brew install $(sort -u "$TMP/f.txt") || fail "some brew formulas failed (see log)"
[ -z "$CASKS" ] || brew install --cask $CASKS || fail "some casks failed"
# brew pulls python@3.x in as a dependency and links /opt/homebrew/bin/python3. That comes before
# /usr/local/bin in a typical job PATH, so jobs would run on brew's Python without your packages.
# Unlink it (formulas keep using their own keg).
for f in $(brew list --formula | grep -E '^python@' || true); do brew unlink "$f" >/dev/null 2>&1 || true; done

say "Node $NODE_VER (nodejs.org pkg -> /usr/local/bin/node)"
if [ "$(/usr/local/bin/node -v 2>/dev/null)" != "v$NODE_VER" ]; then
  curl -fsSL -o "$TMP/node.pkg" "https://nodejs.org/dist/v$NODE_VER/node-v$NODE_VER.pkg" && sudo installer -pkg "$TMP/node.pkg" -target /
fi
check "node v$NODE_VER" test "$(/usr/local/bin/node -v)" = "v$NODE_VER"

say "Python $PY_A ${PY_B:+and $PY_B }(python.org) + certificates"
for v in $PY_A $PY_B; do
  mm="${v%.*}"
  if [ ! -x "/Library/Frameworks/Python.framework/Versions/$mm/bin/python3" ]; then
    curl -fsSL -o "$TMP/py.pkg" "https://www.python.org/ftp/python/$v/python-$v-macos11.pkg" && sudo installer -pkg "$TMP/py.pkg" -target /
  fi
  if [ -f "/Applications/Python $mm/Install Certificates.command" ]; then
    sudo "/Applications/Python $mm/Install Certificates.command" >/dev/null 2>&1 || true
  fi
  if [ -f "$KIT/manifest/python-requirements.txt" ]; then
    "/Library/Frameworks/Python.framework/Versions/$mm/bin/python3" -m pip install -q -r "$KIT/manifest/python-requirements.txt" || fail "pip $mm"
  fi
  check "python $mm TLS ok" "/Library/Frameworks/Python.framework/Versions/$mm/bin/python3" -c "import urllib.request;urllib.request.urlopen('https://www.cloudflare.com/cdn-cgi/trace',timeout=10)"
done
# Each python.org pkg re-points /usr/local/bin/python3 to itself, so the last one installed wins.
# Link the one you want explicitly, after all installs.
sudo ln -sf "/Library/Frameworks/Python.framework/Versions/${PY_A%.*}/bin/python3" /usr/local/bin/python3
check "/usr/local/bin/python3 is $PY_A" sh -c "/usr/local/bin/python3 -V | grep -q $PY_A"

say "global npm packages"
if [ -s "$KIT/manifest/npm-global.txt" ]; then
  grep -vxE 'npm|corepack|n' "$KIT/manifest/npm-global.txt" | xargs sudo /usr/local/bin/npm install -g --silent || fail "npm -g"
fi
# sudo npm leaves a root-owned ~/.npm that breaks every later npm ci as your user
[ -d ~/.npm ] && sudo chown -R "$(id -u):$(id -g)" ~/.npm || true

say "bun"
[ -x ~/.bun/bin/bun ] || curl -fsSL https://bun.sh/install | bash
check "bun" test -x ~/.bun/bin/bun

say "hard-coded /usr/local/bin paths in your job scripts (set JOB_SCRIPT_DIRS to scan them)"
# An Intel Mac keeps brew tools in /usr/local/bin. On Apple silicon they are in /opt/homebrew/bin.
# Link what is missing so scripts written on the laptop still find their tools.
if [ -n "${JOB_SCRIPT_DIRS:-}" ]; then
  for b in $(grep -rhoE '/usr/local/bin/[a-z0-9._-]+' $JOB_SCRIPT_DIRS 2>/dev/null | sort -u); do
    [ -e "$b" ] && continue; n="$(basename "$b")"
    if [ -x "/opt/homebrew/bin/$n" ]; then sudo ln -sf "/opt/homebrew/bin/$n" "$b"; echo "  linked $b -> /opt/homebrew/bin/$n"; else fail "missing $b"; fi
  done
fi

rm -rf "$TMP"; done_summary
