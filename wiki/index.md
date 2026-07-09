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
- [[v3-workflow]] — hive custom workflow for one campaign per task folder
- [[findings]] — everything learned across v1 and v2 (the headline results + gotchas)
- [[decisions]] — methodology decisions and why
- [[gaps]] — what's unverified / left to build
- [[log]] — work log

## Status (2026-06-27)

v2 is **proven and committed** for the `all-opus-4.8` candidate: real hive produces
reference-quality diffs (1300 lines matching the reference PR's file set), judged vs the
gold. Ships **plan+execute**; review is the next phase. See [[gaps]] for what's left and
`HANDOFF.md` (repo root) for the run/build commands to continue on another machine.

## Query protocol

1. Read `.llm-wiki/config.json`.
2. `qmd search "<topic>"` when QMD is available; else `rg "<topic>" wiki/`.
3. Check the main cross-project wiki at `/home/asterio/wikis/master/wiki/` before
   architectural decisions.

Use `[[page-name]]` backlinks between pages. Ground everything in code/results; note
unknowns in [[gaps]].
