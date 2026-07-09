# 2026-07-09 — v3 workflow residual refresh

- Inspected v3-bench-as-hive-workflow-260709-b3nc's residual wiki commit and
  the workflow stage sources. The commit was wiki-only, but the source-backed
  workflow state remains that `3-generate` checks per-cell results under
  `runs/<campaign_id>/<candidate>--<task>/results.json` while `4-judge` and
  `5-publish` consume the campaign-level
  `runs/<campaign_id>/results.json`.
- Kept [[v3-workflow]] and [[gaps]] explicit about the unresolved handoff: no
  merge from per-cell generation outputs into the campaign-level result file
  was found in the workflow sources for this branch, and the publish summary is
  still unverified against merged results.
