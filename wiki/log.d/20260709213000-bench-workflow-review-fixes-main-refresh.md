# 2026-07-09 — bench workflow review fix pass refresh

- Refreshed [[v3-workflow]] from v3-bench-as-hive-workflow-260709-b3nc: `3-generate`
  now merges per-cell results into the campaign-root `runs/<campaign_id>/results.json`
  via `harness/merge_results.rb`, tightening the handoff consumed by `4-judge`
  and `5-publish`.
- Documented the no-re-buy semantics for generated/empty-diff cells, unparseable
  per-cell results, and captured diffs whose judges all walled (`judges_pending`
  for rejudge backfill); plus campaign contract checks, `HB_HIVE_TIMEOUT`, grok
  runner selection, guarded judge/publish extraction, `--skip-done`, and scratch
  cleanup.
- Updated [[gaps]] to remove the stale "campaign merge missing" uncertainty while
  keeping the remaining limits explicit: no real campaign has run end to end
  through generate -> judge -> publish, judge/publish paid paths are fixture-only
  so far, and judge seed count is not re-derivable from `results.json`.
