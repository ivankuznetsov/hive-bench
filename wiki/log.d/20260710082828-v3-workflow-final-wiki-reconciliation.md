# 2026-07-10 — v3 workflow final wiki reconciliation

- Revalidated the global wiki after
  v3-bench-as-hive-workflow-260709-b3nc's documentation-only residual change.
  The change alters branch-local wiki pages and log fragments but does not
  modify workflow, harness, campaign-example, or smoke-test sources, so the
  source-backed behavior in [[v3-workflow]] remains current.
- Kept the post-spend campaign-freeze decision in [[decisions]] and its
  first-spend-fingerprint gap in [[gaps]]. The committed generate gate still
  proves only that `campaign.yml` is tracked and clean at dispatch, while judge
  validation still reports paid cells removed from a later matrix as
  `UNEXPECTED_CELL`; no source now binds a campaign to its first-spend version.
- Kept first captured-diff judge-wall recovery open in [[gaps]]. Generate still
  disarms regeneration when a paid patch exists, but an all-judge-wall first
  pass can park before a campaign-root cell exists and `harness/rejudge.rb`
  still consumes only `results["cells"]`. The no-cost smoke verifies the
  never-re-buy guard, not recovery of that state; no paid end-to-end campaign
  has established the live path.
- Page coverage did not change, so [[index]] remains current. `wiki/log.md` was
  left for the post-commit compiler.
