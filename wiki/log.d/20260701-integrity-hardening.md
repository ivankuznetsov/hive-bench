# 2026-07-01 — benchmark integrity hardening round

Design-review-driven changes (see `tmp/bench-2.md` for the full review):

- Gate: positive observation required for every FAIL_TO_PASS / PASS_TO_PASS name
  (`TestResultParser` learns verbose per-test lines + `observed?`; unobserved
  gate tests error the cell).
- HiveDriver: resource caps + `HB_GEN_NETWORK`, `timed_out` classification via
  `HB_EXIT rc=124`, `plan_forced_complete` telemetry, answer-key access scan
  (`answer_key_access_suspect`).
- Scoring: `same_family` flag on every judge score + `mean_quality_cross_family`
  aggregate (`lib/model_family.rb`).
- Cost: canonical `cost_usd` = tokens × versioned usual-tier table
  (`lib/pricing.rb`); CLI-reported figure demoted to `cost_usd_reported`.
- `hive_run.rb --seeds N`; README integrity section rewritten to the honest v2
  posture.

Second round (same day):

- Corpus: extracted the 7 done tasks from hive's `.hive-state` history; 4
  accepted (PRs #622–#625: 2 features + 2 bugfixes), 3 rejected
  (`update-the-openclaw-hive-skill-*` — brainstorm quotes the reference lines).
  Corpus now 6 accepted tasks; see `corpus/MANIFEST.md`.
- Validator: leak check is audience-aware (idea/brainstorm reject, plan.md
  warns — v2 candidates never see the plan); `Result` gains `warnings`; secret
  scan no longer reads Ruby predicates (`Rails.env.local?`) as hostnames.
- Judges: the slate is exactly fable-5 + gpt-5.5-pro (maintainer decision, no
  third judge). Claude judge defaults to `claude-fable-5`; the results.json
  judge key derives from the pinned model; ModelFamily maps fable/mythos →
  anthropic.

Pages touched: [[architecture]], [[decisions]], [[gaps]].
