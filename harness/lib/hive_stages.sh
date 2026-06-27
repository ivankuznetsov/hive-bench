#!/usr/bin/env bash
# Runs INSIDE hive-bench-runner: drives REAL hive plan->execute for one seeded
# task and captures the candidate diff. Invoked by HiveBench::HiveDriver. /work is
# the seeded target clone — a .hive-state git repo with the task at 2-brainstorm,
# a config.yml, and NO origin remote (so the execute worktree branches off the
# task's local main = base_commit). (Review is a later phase; v2 ships plan+execute.)
#
#   hive_stages.sh <slug> <base_commit>
#
# Markers on stdout (parsed by the driver): `HB_STAGE <name> rc=<n>`,
# `HB_NOTE <x>`, `HB_DIFF lines=<n> files=<n>`, `HB_DONE`.
set -uo pipefail

SLUG="$1"
BASE="$2"
export HOME=/home/asterio
git config --global --add safe.directory '*' 2>/dev/null
mkdir -p /work/.hb
cd /work || exit 3

stage() { echo "HB_STAGE $1 rc=$2"; }

# 1. PLAN — real /ce-plan.
hive plan "/work/.hive-state/stages/2-brainstorm/$SLUG" --json >/work/.hb/plan.json 2>>/work/.hb/stage.err
stage plan $?

# /ce-plan ends WAITING when it raised open questions. With no human in the loop,
# accept the plan as-is: the plan document is the deliverable; the Q&A refinement
# loop is out of scope for the benchmark. Flip the marker so execute can proceed.
PLAN_MD="$(find /work/.hive-state/stages/3-plan -name plan.md 2>/dev/null | head -1)"
if [ -n "$PLAN_MD" ] && grep -q '<!-- WAITING -->' "$PLAN_MD"; then
  sed -i 's/<!-- WAITING -->/<!-- COMPLETE -->/' "$PLAN_MD"
  git -C /work/.hive-state add -A 2>/dev/null
  git -C /work/.hive-state -c user.email=bench@hive-bench -c user.name=hive-bench \
    commit -qm 'bench: force plan complete (no human Q&A)' 2>/dev/null
  echo "HB_NOTE plan_forced_complete"
fi
PLAN_TASK="$(dirname "$PLAN_MD" 2>/dev/null)"

# 2. EXECUTE — real develop -> worktree off base_commit.
if [ -n "$PLAN_TASK" ] && [ "$PLAN_TASK" != "." ]; then
  hive develop "$PLAN_TASK" --json >/work/.hb/develop.json 2>>/work/.hb/stage.err
  stage develop $?
fi

# 3. CAPTURE the working-tree diff vs base: committed + uncommitted + untracked
# (the execute agent often leaves work uncommitted), minus vendored/build trees.
# Pathspecs mirror GitRestore::VENDORED_EXCLUDES — keep them in sync.
WT="$(find /work/.hive-state/stages -name worktree.yml 2>/dev/null | head -1)"
if [ -n "$WT" ]; then
  P="$(ruby -ryaml -e 'puts(YAML.load_file(ARGV[0])["path"].to_s)' "$WT" 2>/dev/null)"
  B="$(ruby -ryaml -e 'puts(YAML.load_file(ARGV[0])["execute_base_head"].to_s)' "$WT" 2>/dev/null)"
  [ -z "$B" ] && B="$BASE"
  if [ -n "$P" ] && git -C "$P" rev-parse >/dev/null 2>&1; then
    git -C "$P" add -A >/dev/null 2>&1
    git -C "$P" diff --cached "$B" -- . \
      ':(exclude,glob).gems/**' ':(exclude).gems' \
      ':(exclude,glob)**/node_modules/**' \
      ':(exclude,glob)vendor/bundle/**' ':(exclude,glob)vendor/gems/**' \
      ':(exclude,glob)vendor/cache/**' ':(exclude,glob).bundle/**' \
      ':(exclude).hive-bench-prompt.md' ':(exclude).hive_probe_tmp' \
      >/work/candidate.patch 2>/dev/null
    echo "HB_DIFF lines=$(wc -l </work/candidate.patch) files=$(grep -c '^diff --git' /work/candidate.patch)"
  fi
fi
echo "HB_DONE"
