# 2026-07-10 — v3 workflow post-residue revalidation

- Revalidated the global wiki after
  v3-bench-as-hive-workflow-260709-b3nc's documentation-residue change. The
  change removes branch-local wiki coverage and log fragments but does not
  modify workflow or harness sources, so it does not supersede the
  source-backed behavior already recorded in [[v3-workflow]].
- Re-read the canonical and installed generate stages at the branch tip. The
  canonical stage still contains the broader contract, retry, stderr, and
  atomic campaign-result protections; the committed `.hive-state` copy still
  predates them, and the smoke still checks copy equality before its scenarios.
  [[gaps]] therefore correctly retains both the copy-drift blocker and the
  unexercised hardening cases.
- The first captured-diff judge-wall recovery and the extract/judge/publish
  anchor and key-handling asymmetries also remain source-visible and unresolved
  in [[gaps]]. Page coverage did not change, so [[index]] remains current.
  `wiki/log.md` was left for the post-commit compiler.
