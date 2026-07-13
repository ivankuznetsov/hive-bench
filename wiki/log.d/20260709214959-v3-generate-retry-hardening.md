# 2026-07-09 — v3 generate retry and merge hardening

- Refreshed [[v3-workflow]] for
  v3-bench-as-hive-workflow-260709-b3nc's stricter generate contract: execute
  the marker-anchored script verbatim, guard repo-root anchoring, reject
  multiline source/corpus fields and fully excluded matrices, preserve a valid
  environment judge key when the key file is empty, and surface bounded command
  stderr on WAITING paths.
- The re-buy guard now treats any captured `target/candidate.patch` as paid
  work regardless of whether the cell landed in `pending[]`, `failed[]`, a
  non-terminal `cells[]` record, or has no readable result record. Completion
  separately requires `generated`/`empty_diff` plus empty pending/failed
  buckets.
- Campaign merging now includes any existing root result before per-cell files
  so root-only rejudge scores survive, and writes through a `.next` file plus
  rename so a failed merge cannot truncate the durable result.
- Updated [[gaps]] because the no-cost smoke does not exercise these branches,
  and because a first-pass all-judge wall can leave a paid patch with
  `cells: []` before any campaign-root result exists while `rejudge` consumes
  only recorded cells; that recovery path remains unverified. The repo-anchor
  and empty-key guards are also still generate-only rather than shared by the
  extract, judge, and publish stages.
