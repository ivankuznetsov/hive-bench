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
- [[v3-workflow]] — hive custom workflow for one campaign per task folder
- [[findings]] — everything learned across v1 and v2 (the headline results + gotchas)
- [[decisions]] — methodology decisions and why
- [[gaps]] — what's unverified / left to build
- [[log]] — work log

## Status (2026-07-09)

v2 is **published** as a real-hive benchmark: plan, execute, open-pr, and
review run in the container by default, then the final post-review diff is
judged against the merged reference PR. The slate now covers opus, codex,
codex-xhigh, glm, kimi, mixed candidates, and grok. Three tasks have curated
held-out reference-test gates; three remain judged-only. v3 work is about
campaign orchestration, stronger runtime gates, replication, and calibrated
judge presentation. See [[gaps]] and [[v3-workflow]].

## Query protocol

1. Read `.llm-wiki/config.json`.
2. `qmd search "<topic>"` when QMD is available; else `rg "<topic>" wiki/`.
3. Check the main cross-project wiki at `/home/asterio/wikis/master/wiki/` before
   architectural decisions.

Use `[[page-name]]` backlinks between pages. Ground everything in code/results; note
unknowns in [[gaps]].
