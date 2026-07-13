# 2026-07-09 — bench workflow review fix pass 1

- `3-generate` now ends by merging per-cell results into the campaign-root
  `runs/<campaign_id>/results.json` via `harness/merge_results.rb` — the
  judge/publish handoff that was previously missing. Its re-buy check fails
  closed on unparseable per-cell files and treats a captured-diff cell whose
  judges all walled (`pending[]` + `target/candidate.patch`) as bought
  (`judges_pending`, backfill via rejudge), never regenerating paid work.
- Generate contract tightened: strict `campaign_id` slug (rejecting the
  unedited `v3-example`), exclusion entry shape validation, and
  `HB_HIVE_TIMEOUT` sourced from pre-registered `timeouts.hive_seconds`
  (campaign.yml.example documents it; harness defaults apply when unset).
  Grok runner image now keys on the candidate profile's `grok_model` field.
- `4-judge` now searches the per-cell run dirs (`runs/<cid>/*--*`) so artifact
  recovery works, passes `--skip-done` to deliberate (wall retries stop
  re-buying full-matrix deliberation), sources `~/.openrouter_key`, extracts
  campaign fields in one guarded block, and validates the merged results
  against the campaign matrix with both judges required per non-empty-diff
  cell (`empty_diff` exempt — those are never judged).
- `5-publish` renders the leaderboard to a scratch file with a WAITING guard
  (no more marker-less half-tables), refuses an empty `agents` map, and uses
  the same guarded field extraction.
- All four stages clean scratch files on exit; shell substitutions
  (openrouter key read, `git status` cleanliness check) fail closed; the
  generate command loop redirects child stdin.
- Smoke expanded: marker-anchored script extraction, untracked/dirty gate and
  misanchor scenarios, extract/judge/publish WAITING paths, and a stubbed
  full generate pass running the real validator over a campaign derived from
  the example with a simulated provider wall. [[v3-workflow]] and [[gaps]]
  refreshed.
