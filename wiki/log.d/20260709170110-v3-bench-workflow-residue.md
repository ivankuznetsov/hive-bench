# 2026-07-09 — v3 workflow residue refresh

- Reviewed v3-bench-as-hive-workflow-260709-b3nc's residual wiki commit against
  the workflow stage sources. The durable source-backed state remains that
  `3-generate` checks per-cell result files under
  `runs/<campaign_id>/<candidate>--<task>/results.json`, while `4-judge` and
  `5-publish` still require the campaign-root
  `runs/<campaign_id>/results.json`.
- Refreshed [[v3-workflow]] to state that `3-generate` does not currently write
  the campaign-root result file and that the campaign-level handoff still needs
  a real campaign smoke or explicit merge step.
- Left [[gaps]]' v3 workflow uncertainty in place because the stage sources
  still require verification of the per-cell to campaign-level result handoff
  and publish summary.
