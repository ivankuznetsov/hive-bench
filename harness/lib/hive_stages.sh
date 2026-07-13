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
mkdir -p /work/.hb/bin
export PATH="/work/.hb/bin:$PATH"
cd /work || exit 3

stage() { echo "HB_STAGE $1 rc=$2"; }

# Open-model candidates: hive has no pi model config, so a pi shim injects
# `--model $HB_PI_MODEL` — set per hive verb below from HB_PI_MODEL_<STAGE>,
# which is how a mixed pair (glm plans, kimi implements) works. hive's pi
# preflight also insists on a non-empty ~/.pi/agent/auth.json; pi itself
# authenticates via the OPENROUTER_API_KEY env, so a marker file satisfies it.
if [ -n "${HB_PI_MODEL_PLAN:-}${HB_PI_MODEL_EXECUTE:-}${HB_PI_MODEL_REVIEW:-}" ]; then
  PI_REAL="$(command -v pi)"
  cat >/work/.hb/bin/pi <<PI
#!/usr/bin/env bash
exec "$PI_REAL" \${HB_PI_MODEL:+--model "\$HB_PI_MODEL"} "\$@"
PI
  chmod +x /work/.hb/bin/pi
  mkdir -p "$HOME/.pi/agent"
  [ -s "$HOME/.pi/agent/auth.json" ] || \
    echo '{"openrouter":{"type":"api-key","via":"OPENROUTER_API_KEY env"}}' >"$HOME/.pi/agent/auth.json"
  echo "HB_NOTE pi_models plan=${HB_PI_MODEL_PLAN:-} execute=${HB_PI_MODEL_EXECUTE:-} review=${HB_PI_MODEL_REVIEW:-}"
fi

# Grok candidates: hive's grok profile passes no model/effort flags, so a shim
# injects `-m $HB_GROK_MODEL --reasoning-effort $HB_GROK_EFFORT` (same pattern
# as the pi shim; grok's default model would drift with CLI releases, and the
# effort pin is the candidate definition).
if [ -n "${HB_GROK_MODEL:-}${HB_GROK_EFFORT:-}" ]; then
  GROK_REAL="$(command -v grok)"
  cat >/work/.hb/bin/grok <<GROK
#!/usr/bin/env bash
exec "$GROK_REAL" \${HB_GROK_MODEL:+-m "\$HB_GROK_MODEL"} \${HB_GROK_EFFORT:+--reasoning-effort "\$HB_GROK_EFFORT"} "\$@"
GROK
  chmod +x /work/.hb/bin/grok
  echo "HB_NOTE grok_pin model=${HB_GROK_MODEL:-} effort=${HB_GROK_EFFORT:-}"
fi

# BEGIN grok-auth-preflight
# Hive 0.3.6 checks only ~/.grok/auth.json before launching the agent and does
# not honor GROK_AUTH_PATH. The home is a per-cell tmpfs, so expose a symlink
# for Hive's read-only preflight while Grok keeps using the canonical shared
# path (and its adjacent refresh lock) through GROK_AUTH_PATH.
if [ -n "${GROK_AUTH_PATH:-}" ]; then
  if [ ! -f "$GROK_AUTH_PATH" ]; then
    echo "HB_ERROR grok_auth_preflight missing credential: $GROK_AUTH_PATH" >&2
    exit 4
  fi
  mkdir -p "$HOME/.grok" || {
    echo "HB_ERROR grok_auth_preflight cannot create $HOME/.grok" >&2
    exit 4
  }
  ln -sfn "$GROK_AUTH_PATH" "$HOME/.grok/auth.json" || {
    echo "HB_ERROR grok_auth_preflight cannot link $HOME/.grok/auth.json" >&2
    exit 4
  }
fi
# END grok-auth-preflight

# Native CE skills (prod parity): the driver mounts each CLI's skill tree ro at
# a neutral /opt/hb path; link it into the CLI's discovery path here, inside
# the writable tmpfs (a direct bind under the tmpfs would leave root-owned
# parent dirs that kill the CLIs — the .claude/.codex lesson).
if [ -d /opt/hb/codex-plugins-cache ]; then
  mkdir -p "$HOME/.codex/plugins"
  [ -e "$HOME/.codex/plugins/cache" ] || ln -s /opt/hb/codex-plugins-cache "$HOME/.codex/plugins/cache"
  echo "HB_NOTE codex_skills linked: $(ls /opt/hb/codex-plugins-cache | tr '\n' ' ')"
fi
if [ -d /opt/hb/pi-ce-skills ]; then
  mkdir -p "$HOME/.pi/agent/skills"
  for s in /opt/hb/pi-ce-skills/*/; do
    n="$(basename "$s")"
    [ -e "$HOME/.pi/agent/skills/$n" ] || ln -s "${s%/}" "$HOME/.pi/agent/skills/$n"
  done
  echo "HB_NOTE pi_skills linked: $(ls /opt/hb/pi-ce-skills | wc -l) skills"
fi

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
HB_PI_MODEL="${HB_PI_MODEL_PLAN:-}" \
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
  HB_PI_MODEL="${HB_PI_MODEL_EXECUTE:-}" \
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

  cat >/work/.hb/bin/gh <<'GH'
#!/usr/bin/env bash
# bench gh shim: enough of gh for hive's open-pr/review in an offline container.
# Contract (lib/hive/gh.rb): `pr list --head <branch> --state all --json
# url,number,state,isDraft,headRefName,headRefOid` must return an ARRAY of PRs
# whose headRefOid hive may compare against the pushed branch.
branch=""; prev=""
for a in "$@"; do [ "$prev" = "--head" ] && branch="$a"; prev="$a"; done
URL="https://github.com/bench/target/pull/1"
case "$1 ${2:-}" in
  "pr create"*) echo "$URL" ;;
  "pr list"*)
    oid="$(git rev-parse "$branch" 2>/dev/null || echo "")"
    printf '[{"url":"%s","number":1,"state":"OPEN","isDraft":false,"headRefName":"%s","headRefOid":"%s"}]\n' \
      "$URL" "$branch" "$oid" ;;
  "pr view"*)   echo "{\"state\":\"OPEN\",\"number\":1,\"url\":\"$URL\",\"statusCheckRollup\":[]}" ;;
  "pr checks"*) echo "no checks reported" ;;
  "auth status"*) echo "Logged in (bench shim)" ;;
  *" list"*|"pr list") echo "[]" ;;
  *) echo "{}" ;;
esac
exit 0
GH
  chmod +x /work/.hb/bin/gh

  HB_PI_MODEL="${HB_PI_MODEL_REVIEW:-}" \
    hive open-pr "$(task_dir)" --json >/work/.hb/open_pr.json 2>>/work/.hb/stage.err
  stage open-pr $?
  HB_PI_MODEL="${HB_PI_MODEL_REVIEW:-}" \
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
