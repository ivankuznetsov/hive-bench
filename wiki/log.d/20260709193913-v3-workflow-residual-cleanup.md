# 2026-07-09 — v3 workflow residual cleanup

- Inspected v3-bench-as-hive-workflow-260709-b3nc's residual wiki cleanup and
  removed the duplicate handoff/residue log fragments from the global wiki
  source fragments. `wiki/log.md` was left for the post-commit compiler.
- Rechecked the workflow sources: `3-generate` writes per-cell results under
  `runs/<campaign_id>/<candidate>--<task>/results.json`, while `4-judge` and
  `5-publish` require the campaign-root
  `runs/<campaign_id>/results.json`.
- Kept [[v3-workflow]] and [[gaps]] explicit about the unresolved campaign-level
  results handoff and unverified publish summary, because no source-backed
  merge from per-cell outputs into the campaign-root result file was found for
  v3-bench-as-hive-workflow-260709-b3nc.
