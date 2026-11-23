# decision-bench

`decision-bench/` is a separate benchmark in this repository. It replays 4,806 past
[hive](https://github.com/ivankuznetsov/hive) decisions from 11 decision points
against two decision-model APIs: OpenAI Decisions (`gpt-6-luna`) and TypeSafe Jev
(`jev-1.14.0`). Each case runs in two variants: one direct question, and decomposed
atomic questions combined by that point's `rule.py`. Results are scored against
Hive's own decision (the incumbent), later outcome evidence, and a gold set.

It shares no code with the v2/v3 harness: plain Python (`run_decisions.py`,
`results/summarize.py`), the `openai` SDK and `urllib`, with keys from
`OPENAI_API_KEY` and `TYPESAFE_API_KEY`.

## Decisions

- **Gold is Claude∩Neon.** Claude adjudicated 563 cases first; Gemini 4 Neon then
  labelled them blind. The 499 cases where they agree are gold. The 64 disagreements
  wait for the owner's tie-break (`annotations/disagreements.md`).
- **Published results double as the runner's cache.** A rerun sends nothing unless
  `--results-dir` points elsewhere.
- **Compression and stripping.** Datasets ship as `dataset.jsonl.xz`: about 190 MB
  of JSONL becomes 7.4 MB, because states repeat across rows and a gzip window cannot
  see that. Result records drop `request`, which is rebuildable from the dataset.
- **Post-run publication redactions.** The local username, one production IP, a
  storage vendor, an unreleased product and a company name were redacted. They
  changed `state` in 356 of 9,612 rows, and the scores come from the states the models
  saw. See `decision-bench/README.md`.

## Headline (test split, pooled gold, n = 392)

| | incumbent | OpenAI direct | OpenAI decomposed | Jev direct | Jev decomposed |
|---|---|---|---|---|---|
| accuracy | 0.648 | 0.926 | 0.842 | 0.941 | 0.847 |

- Both models beat every regex or heuristic incumbent that has gold, but not Hive's
  LLM steps.
- Direct beats decomposed.
- OpenAI and Jev tie on accuracy; Jev costs about half as much and has a tighter p95.

Details: `decision-bench/results/SUMMARY.md`.

## Gaps

- The 64 annotator disagreements are unresolved, so gold leaves out the hardest cases.
- Gold sets are 26–67 test cases per point, and the adjudicated sample leans toward
  incumbent misfires.
- Everything comes from one owner's history. task_workflow_routing is labelled in
  hindsight, and no routing exists in Hive today.
