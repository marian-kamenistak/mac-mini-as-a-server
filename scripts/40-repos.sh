#!/bin/bash
# 40-repos.sh: clone every repo to the same path it has on the laptop.
# List: manifest/repos.tsv, one line per repo: path<TAB>remote<TAB>branch (path relative to $HOME).
# See manifest/repos.tsv.example. Needs "gh auth login" first. Safe to re-run:
# existing clones are fetched, never reset. Run ON THE MINI.
source "$(dirname "$0")/lib.sh"
on_mini || { echo "not on the mini, refusing"; exit 2; }
eval "$(/opt/homebrew/bin/brew shellenv)"
MANIFEST="$KIT/manifest/repos.tsv"
[ -f "$MANIFEST" ] || { echo "no $MANIFEST (copy manifest/repos.tsv.example and edit it)"; exit 2; }
check "gh authenticated" gh auth status
gh auth setup-git
while IFS=$'\t' read -r rel remote branch; do
  [ -n "$rel" ] || continue; dst="$HOME/$rel"
  if [ -d "$dst/.git" ]; then
    if git -C "$dst" fetch -q; then pass "fetched $rel"; else fail "fetch $rel"; fi
    continue
  fi
  if [ -d "$dst" ] && [ -n "$(ls -A "$dst" 2>/dev/null)" ]; then
    # the folder exists with content (an app created it, or it holds nested clones): adopt it in place
    git -C "$dst" init -q; git -C "$dst" remote add origin "$remote" 2>/dev/null || true
    if git -C "$dst" fetch -q origin "$branch" && git -C "$dst" checkout -q -B "$branch" "origin/$branch" 2>/dev/null \
       && git -C "$dst" branch -q -u "origin/$branch"; then pass "adopted $rel"; else fail "adopt $rel (files in the way? check by hand)"; fi
  else
    mkdir -p "$(dirname "$dst")"
    if git clone -q -b "$branch" "$remote" "$dst"; then pass "cloned $rel"; else fail "clone $rel"; fi
  fi
done < "$MANIFEST"
say "npm ci where a lockfile exists"
# sudo npm -g leaves root-owned cache files
[ -d ~/.npm ] && sudo chown -R "$(id -u):$(id -g)" ~/.npm || true
while IFS=$'\t' read -r rel remote branch; do
  [ -n "$rel" ] || continue; d="$HOME/$rel"
  [ -f "$d/package-lock.json" ] || continue
  # a plain loop, no subshell: fail() must update FAILS in this shell
  if npm ci --prefix "$d" --silent >/dev/null 2>&1; then pass "npm ci $rel"; else fail "npm ci $rel"; fi
done < "$MANIFEST"
done_summary
