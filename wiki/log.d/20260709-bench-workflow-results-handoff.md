# 2026-07-09 — bench workflow results handoff uncertainty

- Refreshed [[v3-workflow]] after HEAD's workflow documentation pass and the
  later generate-stage per-cell result check: `3-generate` now verifies
  `runs/<campaign_id>/<candidate>--<task>/results.json`, while `4-judge` and
  `5-publish` still consume `runs/<campaign_id>/results.json`.
- Recorded the remaining uncertainty in [[gaps]]: a real campaign or explicit
  merge step still needs to prove the handoff from per-cell generation outputs
  to the campaign-level result file before the workflow can be considered
  end-to-end covered.
