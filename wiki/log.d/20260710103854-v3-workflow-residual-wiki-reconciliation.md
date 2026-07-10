# 2026-07-10 — v3 workflow residual wiki reconciliation

- Reconciled the global wiki after
  v3-bench-as-hive-workflow-260709-b3nc's wiki-only residual change. The
  committed diff rewrites branch-local wiki coverage and consolidates earlier
  log fragments, but it does not change workflow, harness, campaign-example,
  or smoke-test sources. The more precise source-backed coverage already in
  [[v3-workflow]], [[decisions]], and [[gaps]] therefore remains authoritative.
- Rechecked the committed generate and judge stages plus
  `harness/rejudge.rb`. A captured candidate patch still disarms regeneration,
  generate still parks before the campaign-root merge until every per-cell
  result is terminal with empty pending/failed buckets, and rejudge still
  consumes only `results["cells"]`. The first-pass all-judge-wall recovery
  therefore remains unresolved and recorded in [[gaps]].
- Retained the post-spend campaign-freeze decision and first-spend-fingerprint
  gap. The tracked-and-clean gate still binds `campaign.yml` only to current
  HEAD, while judge validation still rejects paid cells removed from a later
  matrix as `UNEXPECTED_CELL`; the residual documentation change adds no
  persisted first-spend binding.
- Confirmed the canonical and installed copies of all four bench stage files
  match. Page coverage did not change, so [[index]] remains current.
  `wiki/log.md` was left for the post-commit compiler.
