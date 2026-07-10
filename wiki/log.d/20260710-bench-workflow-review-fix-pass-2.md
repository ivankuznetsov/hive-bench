# 2026-07-10 — bench workflow review fix pass 2

- `4-judge` hardened: pending/failed checked BEFORE the rejudge rewrite
  (rejudge output carries no such keys, so the old post-check was vacuous),
  rejudge and publish merges write `results.json.next` + `mv` (the campaign
  root is the sole copy of backfilled judge scores), deliberation goes to a
  scratch transcript and is UNIONED into `deliberation.json` by
  `[task_id, agent_id]` (a wall retry used to overwrite paid transcripts),
  the judge slate is validated BY NAME (`fable-5` + `gpt-5.5-pro`) with
  deliberation-coverage and `UNEXPECTED_CELL` checks, and a soft-failed
  rejudge's stderr tail is folded into the WAITING report.
- Stage guards unified: guarded `REPO_ROOT` substitution and non-empty
  `~/.openrouter_key` sourcing in all stages that need them; extract requires
  `source` (no silent `.` default); judge/publish extraction type-guards
  multi-line `source`/`corpus_version`; publish's state-file append is
  guarded; every instruction file now tells the stage agent to execute the
  marked script verbatim.
- Docs corrected: `campaign.yml.example` no longer suggests removing the
  required `timeouts` key; [[v3-workflow]] scopes the review-only caveat to
  budgets/effort pins (timeouts ARE enforced via `HB_HIVE_TIMEOUT`) and warns
  that mid-campaign `campaign.yml` amendments invalidate the pre-registration.
- Smoke expanded from 9 WAITING-only assertions to full success-path COMPLETE
  coverage for all four stages, never-re-buy assertions (terminal,
  pending+patch, failed+patch), judges_pending rewrite, judge validation
  branches, malformed-campaign gates, a negative contract-message test, env
  assertions (`HB_HIVE_TIMEOUT`, `HB_RUNNER_IMAGE`), slug-validation drift
  diffing, fake-`$HOME` key isolation, and a real-root validator scenario
  replacing the smoke-local re-implementation of the example checks.
