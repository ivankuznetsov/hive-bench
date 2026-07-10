# Wiki Changelog

Append-only log of all wiki operations.

<!-- BEGIN GENERATED WIKI LOG FRAGMENTS -->
# 2026-07-10 — v3 workflow pass-2 documentation refresh

- Refreshed [[v3-workflow]] for
  v3-bench-as-hive-workflow-260709-b3nc's pass-2 hardening: all stage scripts
  now guard repo-root anchoring, extract shares generate's source contract,
  judge prechecks pending/failed before rejudge, campaign-root rewrites are
  atomic, deliberation retries union transcripts, and the exact two-judge slate
  plus deliberation and matrix coverage are validated before completion.
- Corrected the campaign contract: the `timeouts` key remains required, with
  `timeouts: {}` selecting harness defaults; `timeouts.hive_seconds` is enforced
  via `HB_HIVE_TIMEOUT`, while budgets and effort pins remain review-enforced.
  Added the operational decision that a campaign must be replaced, not amended,
  after paid work starts because the clean-file gate does not bind later HEADs
  to the first-spend version.
- Verified from the committed sources that the canonical and installed workflow
  copies match and that the no-cost smoke now exercises COMPLETE paths for all
  four executable stages plus never-re-buy, atomic merge, deliberation-union,
  and judge-validation fixtures. Removed the stale copy-drift and stage-guard
  gaps; page coverage itself did not change.
- Kept the first captured-diff judge-wall recovery open in [[gaps]]: generate
  can still park with a paid patch in a per-cell `cells: []` plus `pending[]`
  result before producing a campaign-root cell, while `harness/rejudge.rb`
  consumes only `results["cells"]`. The expanded smoke disarms regeneration for
  this state but does not recover it. `wiki/log.md` was left for the post-commit
  compiler.

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

# 2026-07-09 — v3 workflow residue revalidation

- Revalidated the global wiki after
  v3-bench-as-hive-workflow-260709-b3nc's wiki-only residual cleanup. Kept the
  broader generate-stage coverage in [[v3-workflow]] and [[gaps]] because the
  branch's canonical `workflows/bench/generate.md` still implements those
  guards, retry protections, and atomic campaign-root merge semantics.
- Recorded a newly verified gap: the committed
  `.hive-state/workflows/bench/generate.md` copy predates the canonical generate
  stage, so the no-cost smoke exits at its initial copy-drift assertion before
  exercising scenario coverage. The installed copy must be refreshed and the
  smoke rerun before it can be treated as green.
- Page coverage did not change, so [[index]] remains current. `wiki/log.md` was
  left for the post-commit compiler.

# 2026-07-09 — v3 generate retry and merge hardening

- Refreshed [[v3-workflow]] for
  v3-bench-as-hive-workflow-260709-b3nc's stricter generate contract: execute
  the marker-anchored script verbatim, guard repo-root anchoring, reject
  multiline source/corpus fields and fully excluded matrices, preserve a valid
  environment judge key when the key file is empty, and surface bounded command
  stderr on WAITING paths.
- The re-buy guard now treats any captured `target/candidate.patch` as paid
  work regardless of whether the cell landed in `pending[]`, `failed[]`, a
  non-terminal `cells[]` record, or has no readable result record. Completion
  separately requires `generated`/`empty_diff` plus empty pending/failed
  buckets.
- Campaign merging now includes any existing root result before per-cell files
  so root-only rejudge scores survive, and writes through a `.next` file plus
  rename so a failed merge cannot truncate the durable result.
- Updated [[gaps]] because the no-cost smoke does not exercise these branches,
  and because a first-pass all-judge wall can leave a paid patch with
  `cells: []` before any campaign-root result exists while `rejudge` consumes
  only recorded cells; that recovery path remains unverified. The repo-anchor
  and empty-key guards are also still generate-only rather than shared by the
  extract, judge, and publish stages.

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

# 2026-07-09 — wiki refresh for current harness

- Refreshed [[architecture]] for the current candidate slate, full-cycle review
  default, candidate-owned review config, per-cell codex config, pi/grok shims,
  native CE skill mounts, and the three curated held-out test gates.
- Updated [[decisions]] to replace the old "review is next phase" note with the
  current review-default posture and to record explicit harness-owned model pins
  for CLIs without hive model fields.
- Updated [[findings]] and [[gaps]] for closed pi model-selection ambiguity,
  codex CE/plugin parity, completed model verification, superseded final-board
  retry queues, grok telemetry uncertainty, and the current state of objective
  gates.
- Filled [[dependencies]] and refreshed [[index]] page coverage/status.

# 2026-07-09 — v3 bench workflow descriptor

- Added the `bench` custom hive workflow (`inbox -> extract -> generate ->
  judge -> publish -> done`) as canonical repo files plus an installed
  `.hive-state/workflows` copy for hive's loader.
- Added `campaign.yml.example` as the pre-registration contract for one
  campaign per task folder.
- Added a no-cost smoke script that parses both descriptor copies, checks drift,
  validates the campaign example, advances a throwaway task through all stages,
  and verifies the generate-stage missing-campaign gate.
- Documented operator flow, WAITING plus `touch <state_file>` retry semantics,
  and remaining manual pieces in [[v3-workflow]].

# 2026-07-09 — bench generate per-cell result check

- Refreshed [[v3-workflow]] for v3-bench-as-hive-workflow-260709-b3nc:
  `3-generate` no longer expects a campaign-root `results.json` after running
  cells. `harness/hive_run.rb` writes one result file per cell under
  `runs/<campaign_id>/<candidate>--<task>/results.json`, so the final generate
  check now iterates the campaign matrix, skips exclusions, and reports
  unfinished cells by `candidate/task` with status `missing` or the observed
  `run_status`.
- Updated [[gaps]] to preserve the remaining uncertainty: the structural smoke
  exists, but a real campaign has not yet been observed completing after this
  per-cell final-check fix, and publish-summary coverage is still unverified.

# 2026-07-09 — bench workflow follow-up refresh

- `3-generate` now records nonzero harness commands and still inspects the
  campaign results before deciding whether to park at WAITING.
- `5-publish` now summarizes the merged `agents` schema directly: cross-family
  means, judged cells, gate pass rate, fresh/reused provenance, and total cost.
- The no-cost workflow smoke now requires `hive` before loading the descriptor
  parser. [[v3-workflow]] and [[gaps]] were refreshed to match the current
  workflow coverage and remaining uncertainty.

# 2026-07-07 — model verification, opus column filling, near-final board

- `harness/verify_models.rb`: every cell's stream-log model ids cross-checked
  against its claim (CLI utility models allowlisted) — 101 substantive stage
  logs, 0 violations. Closes the design review's model-verification question.
- Opus column filling on subscription windows: install fable 6.5 (board's best
  install by far), fix-tmux 8.5, web-install 4.0; 6 cells remain (2 opus,
  4 mixed). Root causes of the two lost days: OAuth refresh-chain races
  (concurrent CLI calls at token expiry -> hard logout) and the OpenRouter KEY
  total-limit cap binding before account balance — both now monitored
  (tmp/claude-monitor.sh pages on LOGGED_OUT; key endpoint checked).
- RESULTS.md updated to near-final (pair exclusions applied, kimi 6/6 complete
  at 3.2, deliberation total: 15 verdicts, gpt revision 0.00);
  `tmp/assemble-final.sh` regenerates the board idempotently as cells land.

# 2026-07-06 — v2 campaign closed: final board published

RESULTS.md rewritten as the v2 artifact (v1 -> RESULTS-v1-deprecated.md).
30 cells; cross-family headline: codex 5.2 (fable), glm 4.0 / kimi 3.6 /
pair 4.0 (gpt), opus subscription-bound. Judge deliberation shipped
(deliberate.rb + transcripts): gpt held every score, fable only conceded
on verified facts. En-route fixes: bind-mount source guards (root-owned
dir trap), OpenRouter "requires more credits" limit pattern, rejudge v2
layout + only-missing + max-tokens. Canonical data: runs/v2-merged/final.json.

# 2026-07-04 — first full 6x6 board + provider-wall day

Ran the full corpus x slate (closed pass, open pass, retries). 29 cells merged
(`runs/v2-merged`). Headline: glm-5.2 posts the best cross-family score
(fix-tmux 8.0), codex sweeps all 6 tasks, opus mostly walled by subscription
limits, kimi + the glm->kimi pair need re-runs (balance drain + harness
failures). Fixes landed en route: limits_reached classifier, pi camelCase
usage telemetry, ~/.codex tmpfs, gh shim pr-list contract, EISDIR in the
answer-key scan, stage markers tee'd to disk. See [[findings]] and the
finish-the-board queue in [[gaps]].

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

Third round (same day): full hive cycle. `hive_stages.sh` runs open-pr + review
after execute (bench-local bare origin + gh shim; HB_REVIEW=0 opts out),
`hive_config.rb` emits the prod-default review section with candidate-agent
substitution (github_publish off; pr-review-toolkit only for claude), dual diff
capture (execute vs final) gives the review-lift signal, `hive_run --task`
filters the corpus for smoke runs.
<!-- END GENERATED WIKI LOG FRAGMENTS -->

## 2026-06-27 — v2: drive real hive

- Pivoted from v1 (imitate hive) to v2 (drive REAL hive) after v1 showed the toy planner was
  the wrong measurement — real `/ce-plan` was worth ~2 judge points. See [[findings]].
- Built the v2 driver: `hive_driver.rb`, `hive_config.rb`, `hive_stages.sh`, `candidates.rb`,
  `hive_run.rb`; baked hive into `Dockerfile.runner`. Committed `100314b`.
- Solved the container integration through a long bring-up (Stage A/B): non-root, writable
  `.claude` tmpfs (the Bash-tool bug), `/ce-plan` plugin resolution, worktree off base_commit,
  telemetry from hive's logs. See [[architecture]].
- **Proven:** all-opus-4.8 → real `/ce-plan` (15-unit plan) + execute (1300-line diff matching
  the reference file-set), judged vs gold: opus 7.5–8.0 / gpt 4.0 (add-i-key),
  7.0 / 2.0 (figure-out-install). Resolved the `/ce-plan` scope variance as 2/3-good.
- Set up this wiki + `HANDOFF.md` for cross-machine continuation.

## 2026-06-25/26 — v1: dual-judge corpus×slate pass

- Ran the v1 corpus × slate (frozen-plan exec, from-idea self-plan, handoffs, raw incumbent)
  with the dual judge (opus-4.8 + gpt-5.5-pro). Published v1 `RESULTS.md` + token-based costs.
- Findings that motivated v2: the refined `/ce-plan` plan beats from-idea by ~2 gpt-points;
  the brainstorm carries scope; cost inverts (closed models pricier at API rates); judge
  calibration (opus generous, gpt strict, agree on ordering). See [[findings]].
- Fixes: new-files capture, vendored-tree excludes, per-judge fail-soft, judge max_tokens cap.
