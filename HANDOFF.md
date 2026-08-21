# hive-bench v2 — handoff & status

_Last updated: 2026-06-27. Branch: `feat/bench-run-dual-judge`._

## TL;DR

**v2 drives REAL hive** (`/ce-plan` → execute), not the v1 imitation. It is proven
end-to-end for the `all-opus-4.8` candidate and committed. v2 ships **plan+execute**;
the **review** stage (open-pr gh-stub + CI + reviewers) is the next phase.

Why the rebuild: v1 imitated hive with a toy `frame_plan_prompt`/`frame_prompt`. The
results proved that was the wrong thing to measure — real `/ce-plan` plans were worth
~2 judge points the toy planner couldn't reach. So v2 runs actual hive with different
model settings and judges the diff hive produces **against the merged reference PR**.

## Current results (all-opus-4.8, real hive, judged vs the gold PR)

| task | opus-4.8 | gpt-5.5-pro | notes |
|---|---|---|---|
| add-i-key | **7.5–8.0** | 4.0 | representative (full-panel) run; 1300-line/18–20-file diff vs 1465-line reference |
| add-i-key | 1.0 | 1.0 | the 1/3 "minimal fork" outlier (see Variance) |
| figure-out-install | **7.0** | 2.0 | full run, ~$33 notional / 45 min |

Live artifacts (diffs, telemetry, plan.md) are under `runs/` (gitignored — they do
NOT transfer via git; regenerate on the new machine). `runs/v2/results.json` holds the
canonical scored cells from the last `hive_run.rb` pass.

## How to run on a fresh machine

**Prereqs:**
- Docker, Ruby 3.4, `bundle install` in this repo.
- The **hive repo** checked out (default `~/Dev/hive`) — it's both the tool (baked into
  the image) and the target repo the tasks run against.
- Agent auth in `~/.claude` (claude OAuth `~/.claude/.credentials.json`, `settings.json`
  with `compound-engineering@every-marketplace` enabled, and `~/.claude/plugins/` with the
  **compound-engineering** plugin — that's where `/ce-plan` lives). For codex/pi later:
  `~/.codex/auth.json`, `~/.pi/agent/auth.json`.
- `OPENROUTER_API_KEY` (for the gpt-5.5-pro judge). **As of handoff the balance is ~$4 —
  needs a top-up before the gpt-judge half can run** (each judge call reserves ~$6).

**Build the runner image (bakes the pinned hive tool):**
```
HIVE_SRC=~/Dev/hive harness/build_runner.sh
```
The builder applies both `hive-bench-runner:latest` (Pi/default) and
`hive-bench-runner:opencode` to the same pinned image. Override them with
`IMAGE_TAG` and `OPENCODE_IMAGE_TAG` when a campaign needs private tags.

**Run a candidate over the corpus (real hive, judged vs the reference PR):**
```
OPENROUTER_API_KEY=… ruby harness/hive_run.rb --source ~/Dev/hive --candidate all-opus-4.8 --out runs/v2
# omit --candidate to run all candidates; --[no-]openrouter-judge toggles the gpt judge
```
Each cell is ~20–45 min and writes `runs/v2/results.json`.

## Container recipe — every piece is load-bearing (debugged the hard way)

These live in `harness/lib/hive_driver.rb` (comments) + `harness/lib/hive_stages.sh`:
- hive baked into the image via **`gem install`** (not a mounted bundle — keeps hive's
  deps off the target repo's CI). Needs `build-essential libsqlite3-dev pkg-config`.
- **Non-root** (claude refuses `--dangerously-skip-permissions` as root). Host uid 1000 ==
  image `runner` uid → no git-ownership friction.
- `HOME=/home/asterio` **and** `/home/asterio/.claude` BOTH on a writable tmpfs
  (`--tmpfs …:exec,mode=1777`). The `.claude` tmpfs is **critical**: claude's Bash tool
  `mkdir`s `~/.claude/session-env`; a plain bind-mount parent is root-owned/ro → Bash dies
  → the agent gives up mid-execute (this was the 78-line-vs-1323-line bug). Bind the claude
  creds/settings/**plugins** ro at that SAME absolute path so the plugin installPaths
  resolve and `/ce-plan` works.
- Target repo: clone, `checkout -B main <base_commit>`, **remove `origin`** (so hive's
  execute worktree branches off local `main`=base, not origin/HEAD). `.hive-state` is its
  OWN git repo — `git init` it. Resolve the task by **path** (not bare slug — avoids hive's
  project registry). `claude.model` must be the CLI id **`claude-opus-4-8`** (hive's short
  `opus-4.8` is rejected). `git config --global --add safe.directory '*'`.
- Capture the **working-tree** diff (`git add --intent-to-add` then `diff <base>`, with one
  shared generated-tree exclusion list) — the execute agent often leaves work uncommitted,
  while build output must not be staged into review. Failed review restores the execute patch
  exactly. Telemetry: parse hive's
  `.hive-state/logs/<slug>/<stage>-*.log` (`[stream] <ts> {json}` lines) for tokens + cost.

## Variance finding (resolved — no hack needed)

Without a human answering the plan's open questions, `/ce-plan` is non-deterministic on
scope-ambiguous tasks. add-i-key: **2/3 of runs honor the brainstorm's full scope** (~1300
lines, ~7.5–8.0), **1/3 fork to a minimal "Path A"** (110 lines, 1.0). Maintainer guidance:
*"plan usually not ends with open questions if brainstorm is correct"* — confirmed (2/3).
The brainstorm is the scope authority; the minimal fork is the exception (plausibly nudged
by the screenshot, which shows the legend bar, not a panel). Do NOT bolt on a variance hack.

## What's left (next session)

1. **Top up OpenRouter**, then finish the gpt-5.5-pro judging of the v2 cells.
2. **codex + open-model candidates** (`all-codex`, `opus-plan→codex-exec`, glm/kimi).
   Container-posture work needed: codex wanted root in v1 (test whether it now runs non-root
   in this image; if not, it conflicts with claude's non-root requirement for mixed
   candidates); pi/open models need model pinning (hive has no `--model` flag for pi —
   configure `~/.pi/agent` or add an `agents.pi.args` passthrough).
3. **v2 leaderboard + article** — new `RESULTS.md` framed as "real hive, judged vs the
   merged PR"; retire the v1 toy-workflow `RESULTS.md` (rename to `RESULTS-v1-deprecated.md`).
4. **Review stage** — the deferred phase: `plan → execute → open-pr → review`. `open-pr`
   needs gh (use hive's babysitter dry-run stubs: `bin/hive-babysitter-stub-gh`); review
   needs `review.ci.command` + reviewer hashes (v2 currently emits empty `reviewers: []`).
   Terminal `REVIEW_*` markers should map to `run_status`.

## Key files

- `harness/lib/hive_driver.rb` — orchestrator (clone→seed→config→container→capture→cell)
- `harness/lib/hive_stages.sh` — in-container plan→execute→capture recipe
- `harness/lib/hive_config.rb` — candidate → hive `config.yml`
- `harness/profiles/candidates.rb` — the v2 slate (model-per-stage configs)
- `harness/hive_run.rb` — the v2 CLI (corpus × candidates via RunAll, judged vs gold)
- `Dockerfile.runner` + `harness/build_runner.sh` — image with hive baked in
- Reused from v1: `harness/judge.rb` (+ `judge-prompt.md`, already supports
  `{{REFERENCE_SECTION}}`), `lib/claude_judge.rb`, `lib/openrouter_judge.rb`,
  `score.rb`, `run_all.rb`, `merge_results.rb`, `lib/corpus.rb`, `lib/git_restore.rb`
- Plan of record: `~/.claude/plans/purring-pondering-pony.md` (the approved v2 plan)

The v1 deprecated path (`harness/lib/pipeline.rb`, `pipeline_run.rb`, the planner/executor
seams in `lib/isolation_exec.rb`, the v1 `RESULTS.md`) is still present and should be
retired in Stage E.
