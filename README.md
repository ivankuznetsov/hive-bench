# hive-bench

**Which AI model runs the [hive](https://github.com/ivankuznetsov/hive) pipeline best?**

Hive is an autonomous development pipeline: idea → brainstorm → plan →
implement → PR → review, driven by LLM agents. `hive-bench` answers which model
configuration should drive it — by replaying real, completed hive tasks through
the **actual pipeline** with each candidate's models and grading the final diff
against the pull request a human really merged.

Results: **[/bench on the hive site](https://ivankuznetsov.github.io/hive-site/bench/)** ·
[`RESULTS.md`](RESULTS.md) (full board + findings) ·
sibling project: [`agent-reviewer-eval`](https://github.com/ivankuznetsov/agent-reviewer-eval)
(benchmarks *reviewers*; this benchmarks *implementers*).

## How it works

Each cell is `(corpus task × candidate)`:

1. **A candidate is a model configuration for hive's stages** — `all-opus-4.8`,
   `all-codex`, `all-glm-5.2`, `all-kimi-k2.7-code`, or mixed pairs like
   `opus-plan→codex-exec` (see `harness/profiles/candidates.rb`).
2. The target repo is **rewound to the task's base commit** and seeded with the
   frozen idea + brainstorm. The candidate never sees the reference solution.
3. **Real hive runs the full cycle** in an isolated container: `/ce-plan` →
   execute → open-pr (against a bench-local origin + `gh` shim) → review with
   hive's production review config (reviewers, triage, fix loop).
4. The final post-review diff is graded **against the merged reference PR** by
   two blind judges — `gpt-5.5-pro` and `fable-5` — on an absolute 0–10 rubric
   (the reference is a *signal*, not "closest wins"; verbosity is not rewarded).

## The corpus (v2)

Six real, completed hive tasks — each judged against the PR a human merged:

| task | type | what it asked | merged reference |
|---|---|---|---|
| add-i-key | feature | `i` key + legend opening a task-info panel in the TUI | [hive#103](https://github.com/ivankuznetsov/hive/pull/103) |
| web-install | feature | local (non-Docker) install & run mode for the web UI | [hive#622](https://github.com/ivankuznetsov/hive/pull/622) |
| install | feature | package hive for simple macOS/Linux installation | [hive#127](https://github.com/ivankuznetsov/hive/pull/127) |
| fix-tmux | bugfix | launcher scripts + Claude ready-prompt detection in tmux mode | [hive#623](https://github.com/ivankuznetsov/hive/pull/623) |
| fix-review | bugfix | review-stage stop-hook failures leaving passes in REVIEW_ERROR | [hive#625](https://github.com/ivankuznetsov/hive/pull/625) |
| daemon | feature | auto-retry recoverable terminal error markers | [hive#624](https://github.com/ivankuznetsov/hive/pull/624) |

Corpus entries are validated on entry (`validator/`): answer-key leak checks on
the candidate-visible spec, secret/PII scan, and reference reproducibility.
Curation details: `corpus/MANIFEST.md`.

## The scoped claim (read this first)

The corpus is **six Ruby/CLI tasks from one maintainer's repo**, judge-scored
(no curated test gates yet), mostly single judge seed. The honest headline is
**"who runs the full hive workflow best on this corpus"** — not "best coding
agent" in general. Every hole in the board is labeled with its cause
(subscription limit windows, budget caps, or named maintainer exclusions) —
never silently dropped.

## Integrity model

- **Family-disjoint headline**: both judge families also compete, so a judge
  never counts toward a same-family candidate's headline
  (`mean_quality_cross_family`; every score carries a `same_family` flag).
- **Model claims verified**: `harness/verify_models.rb` cross-checks every
  cell's agent stream logs against the candidate's claimed models (CLI utility
  models allowlisted). Campaign result: 101 substantive stage logs, 0 violations.
- **Judge deliberation** (diagnostic): after independent scoring, judges
  exchange anonymized verdicts and must fact-check each other against the diff
  (`harness/deliberate.rb`). Across 15 discussed verdicts, gpt-5.5-pro revised
  0.00; fable-5 conceded only on diff-verified facts. The leaderboard keeps
  independent scores.
- **Limits are never failures**: provider walls (subscription windows, drained
  credit, key caps) park cells `pending` for re-run; a wall is never scored.
- **Answer-key protection**: generation logs are scanned for reference-PR
  access; the test gate (for future curated tasks) is `--network none` and
  requires every gate test to be positively observed in the run.
- **Fail-closed mounts/isolation**: docker never sees a missing bind-mount
  source (the root-owned-directory trap); gate containers are no-network and
  resource-capped.

## Layout

    corpus/<task-id>/       one frozen task: spec (idea/brainstorm), reference.patch, gate
    harness/hive_run.rb     the v2 driver: corpus × candidates through REAL hive
    harness/lib/            hive_driver, hive_stages.sh, config, judges, pricing, families
    harness/rejudge.rb      judge backfill over existing diffs (--only-missing)
    harness/deliberate.rb   judge deliberation transcripts
    harness/verify_models.rb  model-claim verification from stream logs
    harness/merge_results.rb  merge/union split results.json files
    validator/              corpus-entry acceptance (leaks, secrets, reproducibility)
    runs/                   artifacts + canonical merged results (gitignored)

## Running a pass

    HIVE_SRC=~/Dev/hive harness/build_runner.sh     # bake hive into the runner image

    OPENROUTER_API_KEY=… HB_HIVE_TIMEOUT=14400 \
      ruby harness/hive_run.rb --source ~/Dev/hive \
        [--candidate all-glm-5.2] [--task <slug>] [--seeds 3] --out runs/mypass

Each cell is ~20 min–4 h (full cycle). `HB_REVIEW=0` runs plan+execute only.
Judge backfill: `harness/rejudge.rb --only-missing`. Requirements: Docker,
Ruby 3.4, agent CLIs authenticated on the host (`claude`, `codex`; pi models
run via `OPENROUTER_API_KEY`).

## Status

v2 **published** (2026-07). v1 (a reimplemented-pipeline imitation) is retired —
its results and why it was replaced: `RESULTS-v1-deprecated.md` and
`wiki/findings.md`. The project wiki (`wiki/`) is the living map: architecture,
decisions, findings, gaps.
