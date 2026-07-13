# Architecture (v2)

How v2 drives **real hive** for one `(task × candidate)` and scores the diff. See [[findings]]
for results, [[decisions]] for the methodology choices, `HANDOFF.md` for run commands.

## Flow

```
for each corpus task T, for each candidate C:
  1. clone target repo, `checkout -B main T.base_commit`, remove origin
  2. seed .hive-state/stages/2-brainstorm/<slug>/ with the FROZEN brainstorm + idea + assets
  3. write .hive-state/config.yml from C (agent-per-stage, claude.model, …); git init .hive-state
  4. container: hive plan (/ce-plan) -> force-complete if WAITING -> hive develop (execute)
  5. capture working-tree diff (base..worktree, vendored-excluded) -> candidate.patch
  6. parse token telemetry from .hive-state/logs/<slug>/*.log
  7. dual-judge (fable-5 + gpt-5.5-pro; was opus-4.8 in early passes) vs reference.patch (reference-PROVIDED)
```

## Components (all under `harness/`)

- **`lib/hive_driver.rb`** — host orchestrator (steps 1–3, 5–6 + the docker run); returns a
  `Run::Cell`-shaped result so it flows into the existing `RunAll`/`Score`.
- **`lib/hive_stages.sh`** — runs INSIDE the container (step 4 + capture): plan, force-complete
  a WAITING plan (no human Q&A), develop, capture the working-tree diff.
- **`lib/hive_config.rb`** — candidate → hive `config.yml`.
- **`profiles/candidates.rb`** — the v2 slate. A *candidate* is a model-per-stage config:
  `all-opus-4.8`, `all-codex`, `opus-plan→codex-exec`. `claude_model` is the CLI id
  (`claude-opus-4-8`); codex/pi take no model flag.
- **`hive_run.rb`** — the CLI: corpus × candidates via `RunAll`, judged vs the gold
  (`withhold_reference: false`), no-op gate (the corpus is mostly uncurated).
  `--seeds N` controls judge samples per judge (default 1; ≥3 for published cells —
  one seed collapses the tie interval).
- **`lib/model_family.rb` / `lib/pricing.rb`** — family mapping for the
  `same_family` judge flag + cross-family aggregate, and the versioned usual-tier
  price table (canonical `cost_usd` = tokens × table; the CLI's self-reported
  figure is kept as `cost_usd_reported`).

## Full cycle (2026-07-01)

v2 now runs the COMPLETE hive pipeline per cell: plan → execute → **open-pr →
review** → capture (HB_REVIEW=0 falls back to plan+execute). The review section
of the generated config mirrors PROD hive defaults (triage courageous, fix
agent, ci.max_attempts 3, max_passes 2) with the candidate's agent substituted
everywhere; `github_publish` is disabled and open-pr lands on a bench-local
bare origin with a minimal `gh` shim on PATH (`hive_stages.sh` writes both).
The pr-review-toolkit reviewer runs only for claude candidates (claude plugin).
TWO diffs are captured: `candidate-execute.patch` (post-execute) and
`candidate.patch` (final, post-review — the scored one; falls back to the
execute diff when review fails). Telemetry gains `open_pr_ok`, `review_ok`,
`review_status` (REVIEW_COMPLETE/WAITING/STALE) and `review_changed_diff`
(the review-lift signal).

## Driver hardening (2026-07-01)

- The gen container is **resource-capped** (`HB_CPUS`/`HB_MEMORY`/`HB_PIDS`,
  default 4 / 8g / 4096) and can attach an egress-allowlisted docker network via
  `HB_GEN_NETWORK` (generation can't run `--network none` — the agent needs its
  model API).
- The stage command appends `HB_EXIT rc=$?`: rc=124 classifies as **`timed_out`**
  (a slow candidate), no longer misread as `plan_failed`.
- `HB_NOTE plan_forced_complete` is surfaced into cell telemetry
  (`plan_forced_complete: true`) — the covariate of the `/ce-plan` scope-fork
  variance.
- Every cell is scanned for **answer-key access** (repo-qualified reference-PR
  URL or `gh pr view/diff/checkout <n>` in the agent stream logs); a hit lands in
  telemetry as `answer_key_access_suspect` and warns loudly.
- **`Dockerfile.runner`** + **`build_runner.sh`** — image with the hive tool baked in as a
  gem (`build_runner.sh` pins it from `git archive HEAD`).

## Reused from v1 (unchanged)

`judge.rb` (+ `judge-prompt.md`, already has `{{REFERENCE_SECTION}}`), `lib/claude_judge.rb`,
`lib/openrouter_judge.rb`, `score.rb`, `run_all.rb`, `merge_results.rb`, `lib/corpus.rb`,
`lib/git_restore.rb`.

## Container recipe — load-bearing details

Every one of these was needed to make real hive run headlessly with `/ce-plan`:

- hive baked via **`gem install`** (not a mounted bundle — keeps hive's deps off the target
  repo's CI). Build deps: `build-essential libsqlite3-dev pkg-config`.
- **non-root** (`runner`, uid 1000 == host uid → no git-ownership friction); claude refuses
  `--dangerously-skip-permissions` as root.
- `HOME=/home/asterio` **and** `/home/asterio/.claude` on a **writable tmpfs**
  (`--tmpfs …:exec,mode=1777`). The `.claude` tmpfs is what keeps claude's Bash tool alive
  (it `mkdir`s `session-env` there). Bind the claude creds/settings/**plugins** ro at that
  absolute path so `/ce-plan` plugin installPaths resolve.
- Grok gets a fresh `~/.grok` tmpfs per cell. A separately authenticated
  credential directory at `~/.local/state/hive-bench/grok-auth` is the only
  persistent state mounted read-write, with `GROK_AUTH_PATH` pointing into it.
  Parallel cells therefore share Grok's `auth.json.lock` and atomic token
  rotation without sharing sessions, config, leader sockets, or the operator's
  real `~/.grok` refresh-token chain. The in-container stage shim links
  `~/.grok/auth.json` to that canonical path inside the tmpfs solely for Hive
  0.3.6's hard-coded agent preflight; Grok itself still uses `GROK_AUTH_PATH`.
- target clone: **drop `origin`** so the execute worktree branches off local `main`=base_commit.
  `.hive-state` is **its own git repo** (`git init`). Resolve the task by **path** (not slug).
- capture the **working-tree** diff (the execute agent often leaves work uncommitted).

These are mirrored in the code comments and [[findings]] (the Bash-tool bug). The fully
worked-out recipe also lives in the project memory `hive-bench-v2-real-hive.md`.
