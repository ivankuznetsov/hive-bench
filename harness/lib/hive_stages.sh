#!/usr/bin/env bash
# Runs INSIDE hive-bench-runner: drives REAL hive plan->execute->open-pr->review
# for one seeded task and captures the candidate diffs. Invoked by
# HiveBench::HiveDriver. /work is the seeded target clone — a .hive-state git
# repo with the task at 2-brainstorm, a config.yml, and NO origin remote (so the
# execute worktree branches off the task's local main = base_commit).
#
#   hive_stages.sh <slug> <base_commit>
#   HB_REVIEW=0 skips open-pr + review (plan+execute only).
#
# Markers on stdout (parsed by the driver): `HB_STAGE <name> rc=<n>`,
# `HB_NOTE <x>`, `HB_DIFF <label> lines=<n> files=<n>`, `HB_DONE`.
set -uo pipefail

SLUG="$1"
BASE="$2"
export HOME=/home/asterio
git config --global --add safe.directory '*' 2>/dev/null
mkdir -p /work/.hb
cd /work || exit 3

stage() { echo "HB_STAGE $1 rc=$2"; }

# Capture the task worktree's diff vs base into $1: committed + uncommitted +
# untracked (agents often leave work uncommitted), minus vendored/build trees.
# Pathspecs mirror GitRestore::VENDORED_EXCLUDES — keep them in sync.
capture() {
  local out="$1" label="$2"
  local wt p b
  wt="$(find /work/.hive-state/stages -name worktree.yml 2>/dev/null | head -1)"
  [ -n "$wt" ] || return 1
  p="$(ruby -ryaml -e 'puts(YAML.load_file(ARGV[0])["path"].to_s)' "$wt" 2>/dev/null)"
  b="$(ruby -ryaml -e 'puts(YAML.load_file(ARGV[0])["execute_base_head"].to_s)' "$wt" 2>/dev/null)"
  [ -z "$b" ] && b="$BASE"
  if [ -n "$p" ] && git -C "$p" rev-parse >/dev/null 2>&1; then
    git -C "$p" add -A >/dev/null 2>&1
    git -C "$p" diff --cached "$b" -- . \
      ':(exclude,glob).gems/**' ':(exclude).gems' \
      ':(exclude,glob)**/node_modules/**' \
      ':(exclude,glob)vendor/bundle/**' ':(exclude,glob)vendor/gems/**' \
      ':(exclude,glob)vendor/cache/**' ':(exclude,glob).bundle/**' \
      ':(exclude).hive-bench-prompt.md' ':(exclude).hive_probe_tmp' \
      >"$out" 2>/dev/null
    echo "HB_DIFF $label lines=$(wc -l <"$out") files=$(grep -c '^diff --git' "$out")"
  fi
}

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

# Post-execute capture: the raw first-pass diff, kept for review-lift analysis.
capture /work/candidate-execute.patch execute

# 3-4. OPEN-PR + REVIEW — the rest of the real hive cycle (HB_REVIEW=0 skips).
# The container has no GitHub: pushes land on a bench-local bare origin, and a
# minimal gh shim answers the PR calls the stages make. github_publish is
# disabled in the bench config, so review never needs the real API.
# hive moves the task folder across stage dirs as stages complete — always
# re-resolve by slug instead of assuming which stage dir it landed in.
task_dir() { find /work/.hive-state/stages -maxdepth 2 -type d -name "$SLUG" 2>/dev/null | head -1; }

if [ "${HB_REVIEW:-1}" = "1" ] && [ -n "$PLAN_TASK" ] && [ "$PLAN_TASK" != "." ]; then
  git init -q --bare /work/.hb/origin.git 2>/dev/null
  git -C /work remote add origin /work/.hb/origin.git 2>/dev/null
  git -C /work push -q origin main 2>/dev/null

  mkdir -p /work/.hb/bin
  cat >/work/.hb/bin/gh <<'GH'
#!/usr/bin/env bash
# bench gh shim: enough of gh for hive's open-pr/review in an offline container.
case "$1 ${2:-}" in
  "pr create"*) echo "https://github.com/bench/target/pull/1" ;;
  "pr view"*)   echo '{"state":"OPEN","number":1,"url":"https://github.com/bench/target/pull/1","statusCheckRollup":[]}' ;;
  "pr checks"*) echo "no checks reported" ;;
  "auth status"*) echo "Logged in (bench shim)" ;;
  *) echo "{}" ;;
esac
exit 0
GH
  chmod +x /work/.hb/bin/gh
  export PATH="/work/.hb/bin:$PATH"

  hive open-pr "$(task_dir)" --json >/work/.hb/open_pr.json 2>>/work/.hb/stage.err
  stage open-pr $?
  hive review "$(task_dir)" --json >/work/.hb/review.json 2>>/work/.hb/stage.err
  stage review $?

  ST="$(find /work/.hive-state/stages -name status.md -path "*$SLUG*" 2>/dev/null | head -1)"
  for m in REVIEW_COMPLETE REVIEW_WAITING REVIEW_STALE; do
    if [ -n "$ST" ] && grep -q "$m" "$ST"; then echo "HB_NOTE review_status=$m"; break; fi
  done
fi

# Final capture: post-review when review ran (fix commits land in the worktree),
# else identical to the execute diff.
capture /work/candidate.patch final
[ -s /work/candidate.patch ] || { [ -s /work/candidate-execute.patch ] && cp /work/candidate-execute.patch /work/candidate.patch; }
echo "HB_DONE"
