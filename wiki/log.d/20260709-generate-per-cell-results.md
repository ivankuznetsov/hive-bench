# 2026-07-09 — bench generate per-cell result check

- Refreshed [[v3-workflow]] for v3-bench-as-hive-workflow-260709-b3nc:
  `3-generate` no longer expects a campaign-root `results.json` after running
  cells. `harness/hive_run.rb` writes one result file per cell under
  `runs/<campaign_id>/<candidate>--<task>/results.json`, so the final generate
  check now iterates the campaign matrix, skips exclusions, and reports
  unfinished cells by `candidate/task` with status `missing` or the observed
  `run_status`.
- Updated [[gaps]] to preserve the remaining uncertainty: the structural smoke
  exists, but a real campaign has not yet been observed completing after this
  per-cell final-check fix, and publish-summary coverage is still unverified.
