# 2026-07-10 — v3 workflow pass-2 documentation refresh

- Refreshed [[v3-workflow]] for
  v3-bench-as-hive-workflow-260709-b3nc's pass-2 hardening: all stage scripts
  now guard repo-root anchoring, extract shares generate's source contract,
  judge prechecks pending/failed before rejudge, campaign-root rewrites are
  atomic, deliberation retries union transcripts, and the exact two-judge slate
  plus deliberation and matrix coverage are validated before completion.
- Corrected the campaign contract: the `timeouts` key remains required, with
  `timeouts: {}` selecting harness defaults; `timeouts.hive_seconds` is enforced
  via `HB_HIVE_TIMEOUT`, while budgets and effort pins remain review-enforced.
  Added the operational decision that a campaign must be replaced, not amended,
  after paid work starts because the clean-file gate does not bind later HEADs
  to the first-spend version.
- Verified from the committed sources that the canonical and installed workflow
  copies match and that the no-cost smoke now exercises COMPLETE paths for all
  four executable stages plus never-re-buy, atomic merge, deliberation-union,
  and judge-validation fixtures. Removed the stale copy-drift and stage-guard
  gaps; page coverage itself did not change.
- Kept the first captured-diff judge-wall recovery open in [[gaps]]: generate
  can still park with a paid patch in a per-cell `cells: []` plus `pending[]`
  result before producing a campaign-root cell, while `harness/rejudge.rb`
  consumes only `results["cells"]`. The expanded smoke disarms regeneration for
  this state but does not recover it. `wiki/log.md` was left for the post-commit
  compiler.
