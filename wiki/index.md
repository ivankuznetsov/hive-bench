# hive-bench wiki

`hive-bench` benchmarks coding agents on real, completed [hive](https://github.com/ivankuznetsov/hive)
tasks. A corpus of frozen hive tasks (idea / brainstorm / plan / reference PR / gate) is
replayed against candidate agents; the produced diff is scored by a blind dual LLM judge.

It is the implementer-side sibling of `agent-reviewer-eval` (which benchmarks reviewers).

## Two generations

- **v1 (deprecated)** — *imitated* hive with a reimplemented planner/executor
  (`frame_plan_prompt`/`frame_prompt`). Useful but it measured a toy workflow, not hive's.
  See [[findings]] for why it was retired and what it taught us.
- **v2 (current)** — *drives REAL hive* (`/ce-plan` → execute) in a container, judged
  against the merged reference PR. See [[architecture]].

## Pages

- [[architecture]] — how v2 drives real hive (driver, config, candidates, container recipe)
- [[dependencies]] — confirmed runtime tools, CLIs, services, and local auth assumptions
- [[v3-workflow]] — built-in Hive benchmark workflow for one campaign per task folder
- [[findings]] — everything learned across v1 and v2 (the headline results + gotchas)
- [[decisions]] — methodology decisions and why
- [[gaps]] — what's unverified / left to build
- [[log]] — work log

## Status (2026-07-13)

v2 is **published** as a real-hive benchmark: plan, execute, open-pr, and
review run in the container by default, then the final post-review diff is
judged against the merged reference PR. The current preliminary publication is
the complete 36-cell matrix across six tasks and six candidates: Opus 4.8,
Codex 5.5 xhigh, GPT-5.6 Sol xhigh, GLM 5.2, Grok 4.5, and Opus-plan → Codex
xhigh. It uses one Fable 5 and one Sol xhigh score per non-empty cell; the
three-sample Sol `ultra` follow-up remains a separate campaign.

v3 adds campaign orchestration, stronger runtime gates, replication, and
calibrated judge presentation. The native `bench` Hive workflow has guarded,
idempotent stages and full no-cost fixture paths through
extract/generate/judge/publish. Hive installs its versioned harness snapshot in
the benchmark project's `.hive-state/bench-runtime`, so local users do not need
to clone this repository merely to run the named workflow. Its maintained defaults are Fable plus Sol
`ultra`, three samples, candidate-plan judging, and adversarial deliberation;
the first paid campaign with that complete contract has not yet run end to end.
See [[gaps]] and [[v3-workflow]].

## Query protocol

1. Read `.llm-wiki/config.json`.
2. `qmd search "<topic>"` when QMD is available; else `rg "<topic>" wiki/`.
3. Check the main cross-project wiki at `/home/asterio/wikis/master/wiki/` before
   architectural decisions.

Use `[[page-name]]` backlinks between pages. Ground everything in code/results; note
unknowns in [[gaps]].
