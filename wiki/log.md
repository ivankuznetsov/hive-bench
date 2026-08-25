# Wiki Changelog

Append-only log of all wiki operations.

<!-- BEGIN GENERATED WIKI LOG FRAGMENTS -->
# 2026-08-25 — Native model routing and production review slate

- Refreshed the installed bench runtime from source commits `90fef72` and
  `41315d5`. Candidate model/effort now flows through Hive's provider-neutral
  `models:` routes and shared Agent CLI runtime; container model shims,
  OpenCode-specific runtime/probe configuration, and the Pi/OpenCode Ox Alpha
  profiles were removed.
- Added four production-shaped candidates covering Grok-owned review, a fixed
  Sol+Grok panel, and fixed Sol+Opus 5 panels for an Opus-vs-Fable planner
  comparison. Reviewer-level model/effort pins prevent a planner route from
  leaking into a heterogeneous panel.
- Documented the narrower recovery contract: only identity-matched Codex
  `implementer_failed` transport disconnects resume in place. Review, Pi,
  provider-error, and dirty-residue resume paths are gone; outer timeout is
  always `timed_out`; the runner uses its baked Hive runtime and inherited Hive
  defaults rather than a host-runtime overlay. Plan execution no longer retries
  a markerless promotion with `hive run` or normalizes a null dependency.
- Provider-limit classification now scans only newly appended stream-log bytes
  for the current attempt. Codex judge calls allow 3600 seconds, Claude stdout
  quota detection trusts only the standalone reset banner, and deliberation
  emits task/candidate/judge-keyed failure events for both rounds.
- Recorded two refresh risks in [[gaps]]: the installed snapshot reintroduces
  Pi usage double-counting by removing the final-event filter, and the
  configured cross-project main wiki path was absent during this refresh.

Pages updated: [[architecture]], [[dependencies]], [[decisions]], [[findings]],
[[v3-workflow]], and [[gaps]]. Page coverage did not change, so [[index]] was
left untouched.

# 2026-08-16 — Count only final Pi usage events

- Corrected `HiveDriver` and `TokenReport` so Pi-backed candidates count each
  assistant `message_end`. Pi's `message_update` and `turn_end` events repeat
  the same response usage and are not additional model calls.
- Added regression coverage with two realistic update/end/turn-end sequences,
  proving finalized responses accumulate while their copies do not.
- Reconstructed all six published GLM cells from their retained final events;
  the token and usual-tier cost corrections do not alter candidate patches,
  judge scores, or wall times.
- Marked the older `RESULTS.md` Pi-backed Kimi and mixed totals as unknown
  because their retained streams are not committed and cannot be corrected.

# Make rejudge backfill effort-aware

- Changed `rejudge.rb --only-missing` to require both the configured sample
  count and, when pinned, the configured reasoning effort before reusing an
  existing judge record.
- Added regression coverage proving an `xhigh` Codex record is rejudged when a
  campaign requires `ultra`, while judges without an effort pin remain
  sample-count based.
- Fresh replacement records now take the invocation effort before they merge
  with untouched incumbents; rejudge no longer applies an effort override to
  the whole output and falsely relabels skipped judges.
- Judge-effort keys are normalized for library callers, and legacy incumbents
  regain missing provenance fields without overwriting stored values.
- An end-to-end `rejudge_cell` regression proves a wrong-effort judge is
  replaced while a satisfied judge is left unchanged.
- This aligns retry selection with judge-stage validation and prevents a retry
  loop that repeatedly skips a record validation must reject.

# Fix submission runner build

**Action:** Repaired the maintainer-gated corpus validation workflow so it
checks out Hive at immutable commit `5028d7655fb1b0fa0a223e967661c678b09b336f`
and invokes `harness/build_runner.sh`. The previous direct `docker build` call
could never satisfy `Dockerfile.runner`'s required `hive-src.tar`; the canonical
builder creates that archive with `git archive HEAD` and removes it after the
image build. Also made `validator/cli.rb` initialize the harness load path for
its documented standalone invocation; previously it stopped at
`require "lib/git_restore"` before reading an entry. The workflow now executes
validator, harness, and Dockerfile code only from the immutable trusted base SHA
and treats the PR's `corpus/**` as data. A retained approval label cannot launch
a later push: validation requires a fresh `safe-to-validate` label event and does
not rely on GitHub's size-limited path filter. The PR checkout has complete
history for the three-dot merge-base diff, and any changed
path under `corpus/<task>/**` selects that whole entry for validation; a missing
manifest fails closed. Corpus symlinks, manifest spec paths, and gate test-patch
paths that escape their entry are rejected so nested-checkout paths cannot
resolve into trusted files. The hosted validation job pins `HB_CPUS=4`; the
runner exposes four CPUs, while the workstation-oriented isolation default is
eight and would make Docker reject every gated entry before its tests start.

**Verification:** The original labeled PR run failed before validation with
`COPY hive-src.tar: not found`. A local canonical image build against the pinned
Hive revision passed, and the exact workflow validation loop accepted all four
changed corpus entries (one judged and three gated). A focused regression proves
the CLI boots without an explicit `-Iharness`; the built-in workflow smoke also
requires quota markers to carry the UTC ISO-8601 `retry_after` timestamp the
daemon needs for automatic resume. The broader checks remain the Ruby suite,
RuboCop, and built-in workflow smoke against the merged Hive revision.

---
title: Runtime shell lint compatibility
type: change
date: 2026-07-13
---

- Parse optional runner-image build arguments into a Bash array before passing
  them to Docker, avoiding implicit word splitting.
- Inventory mounted Codex and Pi skill directories with `find` instead of
  parsing `ls`, keeping the canonical harness synchronized with Hive's
  packaged runtime snapshot.

# 2026-07-13 — Add serialized mixed-model follow-up workflows

- Added Sol xhigh plan → Terra xhigh execute, Fable 5 high plan → Grok 4.5
  xhigh execute, and Sol xhigh plan → Grok 4.5 xhigh execute candidate profiles.
- All three profiles use Sol xhigh as the sole production reviewer through
  Codex `ce-code-review`, keeping review policy fixed while planner/executor vary.
- Added stage-specific Codex model/effort pins and container shim propagation so
  Sol and Terra can occupy different stages even though both use Hive's `codex`
  agent profile.
- Kept the native bench campaign serial: one task walks one cell at a time; the
  campaign contract retains three Fable + Sol-ultra judge samples and adversarial
  deliberation.
- Synchronized the runtime into Hive's packaged `bench` workflow; GPT-5.6 cells
  select the Codex-0.144+ `sol` runner, which also contains Grok for mixed cells.

---
title: Self-contained built-in benchmark runtime
type: change
date: 2026-07-13
---

- The Hive package now owns a versioned copy of the maintained harness,
  `Dockerfile.runner`, `.dockerignore`, and `campaign.yml.example`.
- `hive init --workflow bench` installs that snapshot under
  `.hive-state/bench-runtime`, removing the separate hive-bench checkout from
  the local campaign path.
- The hive-bench repository remains canonical for public corpus submissions,
  published evidence, methodology, and future runtime synchronization.

# Use Hive's built-in benchmark workflow

- Removed the duplicate project workflow descriptor and stage instructions;
  Hive now owns the named `bench` workflow and its packaged prompts.
- Updated the no-cost smoke to load `Hive::Workflows::Registry.fetch(:bench)`,
  verify the packaged instructions, and prove `hive init --workflow bench`
  needs no `.hive-state/workflows` copy.
- Corrected four June-task corpus manifests that had inferred Haiku from Claude
  utility activity: their execute logs and Codex rollouts show GPT-5.5 via
  Codex implemented web-install, fix-tmux, fix-review, and daemon; Claude
  authored the plans.
- Documented that Honeycomb is not deployed and is not required.
- Scoped UsageDb provenance lookup to the `4-execute` stage so an unknown
  executor model cannot be misattributed to a later review or finalize model.

# Fix native benchmark workflow installation on a fresh clone

- Removed the checked-in `.hive-state/workflows/bench*` copy. `.hive-state` is
  created as a Hive-managed Git worktree, and pre-populating it in the main
  checkout made `hive init` fail with `already exists` on a fresh clone.
- Kept `workflows/bench.yml` and `workflows/bench/` as the canonical sources.
- Documented and smoke-tested the correct order: initialize the project, copy
  the canonical files into the state worktree, commit them there, then create a
  task with `--workflow bench`.

# Align the native benchmark workflow with maintained campaigns

- Made `campaign.yml` declare the enabled judge backends, exact model ids,
  Codex reasoning effort, and judge sample count. Validation rejects unknown
  backends and model combinations that collapse to the same results key before
  any generation spend.
- Defaulted the example to Fable 5 plus GPT-5.6 Sol at `ultra`, with three
  independent samples per judge and cell.
- Persisted individual judge scores, reasons, sample counts, intervals, and
  reasoning-effort provenance; undersampled records are now repair targets.
- Switched v3 judging and deliberation to each candidate's generated plan.
- Added the adversarial deliberation round where judges argue against their own
  initial scores without changing the independent leaderboard score.
- Kept scheduling in Hive: deterministic cell order inside a campaign and
  normal daemon concurrency between separate workflow tasks.
- Expanded the no-cost workflow smoke and unit coverage for judge slate,
  sample-count, and effort invariants.

# Publish the complete v2-ce preliminary evidence

Published the canonical 36-cell preliminary campaign as an auditable result
bundle under `runs/v2-ce/`. The bundle keeps the merged board plus every
per-cell result and final candidate patch, with a manifest that records
candidate/task identity, model version, byte size, and SHA-256 for each patch.

The repository's canonical secret scanner reported zero findings across all 72
published per-cell files. Raw model streams, target clones, Git databases,
credentials, and build logs remain untracked. The snapshot is explicitly
preliminary: one sample per Fable 5 / GPT-5.6 Sol judge-cell pair, Sol judging
at `xhigh`; the three-sample Sol-`ultra` replication remains follow-up work.

---
title: Record judge reasoning effort in benchmark results
date: 2026-07-12
---

- New and rejudged `results.json` cells include `reasoning_effort` and
  `reasoning_effort_explicit` on every judge record.
- GPT-5.6-sol is recorded as explicitly `xhigh`; Fable 5, legacy GPT-5.5-pro,
  and unknown judge IDs are recorded as `unspecified` rather than assigning an
  unverified provider default.
- Added a metadata-only annotator for existing result artifacts. It does not
  invoke judges or change scores.

# Align provider retries with explicit UTC reset hints

- Added a narrow parser for Claude's `resets <time> (UTC)` session-limit hint.
- Retry timestamps use the next stated boundary plus one minute; absent or
  non-UTC hints continue to use the one-hour fallback.
- This keeps Hive as the sole lane dispatcher while avoiding an extra cooldown
  when a generic one-hour retry lands just before the provider reset.

# Resume interrupted Codex execute turns

- Added identity-verified in-place recovery for Hive tasks parked at
  `4-execute` after a terminal Codex model-transport disconnect.
- The resume path clears only the matching `implementer_failed` marker, reuses
  the existing plan/worktree, and records `execute_resumed` telemetry.
- Authentication, usage-limit, provenance-mismatch, and ordinary implementation
  failures remain ineligible for automatic resume.
- Review-only provider limits now preserve the trustworthy execute fallback as
  generated; plan/execute limits continue to park the cell even when the stage
  wrapper consequently exits nonzero.

# 2026-07-11 — isolate forced-plan bookkeeping from runtime locks

- `hive_stages.sh` now force-completes a WAITING plan by staging and committing
  only `plan.md`, rather than sweeping the entire Hive state checkout with
  `git add -A`.
- This prevents transient `.lock` deletion and `.commit-lock` creation from
  aborting a completed generation before candidate diff capture.
- Added a real-Git regression that keeps both lock changes dirty while proving
  the plan-only commit succeeds.

# Review patch fallback and local Bundler exclusion

- Made failed review stages restore `candidate-execute.patch` as the scored
  `candidate.patch`, preventing partial review side effects from replacing a
  valid implementation.
- Changed in-container diff capture from `git add -A` plus cached diff to
  intent-to-add plus working-tree diff, so excluded build trees are not staged
  into the branch consumed by review.
- Added `.bundle-local/` to both host and container capture exclusions after a
  live GLM cell swept 4,991 local gem files into a 47 MB patch.
- Added regression coverage for the failed-review fallback and the new
  generated-tree exclusion.
- Follow-up review made capture and fallback-copy failures fail closed, covered
  zero-byte execute patches, consolidated shell exclusions, and replaced the
  source-text assertion with a real temporary-Git capture test.
- The host `GitRestore` now also rejects intent-to-add failures instead of
  returning a tracked-only patch that silently omits new solution files.
- Capture now enumerates non-ignored, non-vendored untracked paths before
  intent-to-add. This avoids false failures when an excluded build tree is also
  ignored (for example `vendor/bundle/`) while preserving index-error detection.
- Intent-to-add consumes the NUL-delimited file list with literal pathspec mode,
  so legal filenames containing Git pathspec magic cannot expand back into an
  excluded generated tree.

# Preserve Codex judge limit markers

Codex judge failures now inspect the complete CLI stderr stream before
truncating its diagnostic. A usage wall is promoted to a leading
`limits_reached` marker so the benchmark workflow can distinguish a temporary
provider limit from a real judge failure and let the Hive daemon retry the lane.

A regression covers the live failure shape where the usage message follows a
long Codex banner.

# Stream GLM tool arguments in Pi benchmark cells

- Added a Pi request extension that enables `tool_stream` for the pinned
  `z-ai/glm-5.2` candidate.
- Mounted and activated the extension in every Pi runner cell.
- This prevents large `write(plan.md)` calls from going silent until
  OpenRouter terminates them for upstream idleness, while preserving the
  benchmark's model, prompt, tools, and output.

# Surface Claude judge authentication failures

`ClaudeJudge` now includes bounded stdout when Claude Code exits nonzero with
an empty stderr stream. Claude Code emits expired-session 401 details in its
JSON stdout, so this turns previously blank Fable judge failures into an
actionable authentication diagnostic.

The dependency guide now requires a real `claude -p` smoke probe rather than
trusting `claude auth status`, which can report logged in for an expired token
that has no refresh token.

# Recover generated benchmark artifacts after result failures

- Hardened Hive stream telemetry parsing for valid events whose `message` is a
  string rather than a usage object.
- Made v2 retries reuse a non-empty `candidate.patch` when the persisted Hive
  stage transcript proves the cell completed plan and develop successfully and
  persisted task/base/candidate identity matches. Legacy artifacts require an
  explicit unverified-recovery opt-in; `--no-reuse-existing-artifacts` opts into
  a fresh generation. Provenance mismatches fail without deleting the saved run.
- Preserved generated cell records when every judge fails, with the missing
  scores represented by an empty `judges` map and the retry reason retained in
  `pending` or `failed`.
- Added regressions for Codex error events, artifact reuse/incomplete-artifact
  rejection, and all-judge outages.

# Grok benchmark auth is visible to Hive's legacy preflight

Hive 0.3.6 checks only `~/.grok/auth.json` before it launches the Grok agent.
After the benchmark moved its canonical refreshable credential to
`GROK_AUTH_PATH`, Hive returned a successful no-agent plan transition and the
harness surfaced `execute_failed` without ever starting Grok.

The in-container stage shim now exposes a symlink from the legacy path inside
the per-cell tmpfs to the canonical benchmark auth file. A regression test
executes that exact shell block and verifies the link target. Missing
credentials or symlink-setup failures now stop with an explicit `HB_ERROR`
instead of falling through to Hive's opaque no-agent result. This preserves a
single credential and refresh-lock domain while satisfying the older Hive
preflight.

# Grok benchmark containers can persist automatic authentication refresh

Grok candidate cells now use a separately authenticated benchmark credential
directory. Mounting only that directory read-write lets the CLI atomically
replace `auth.json` and coordinate through `auth.json.lock`, while each cell's
sessions, config, and leader state stay in a fresh `~/.grok` tmpfs. The
operator's normal refresh-token chain is neither copied nor mounted.

The driver regression tests require the isolated writable auth mount, the
`GROK_AUTH_PATH` override, and a trusted mode-0600 credential. This fixes the
live failure where authorization succeeded but ended with `Failed to save
credentials: Operation not permitted`, without duplicating a rotating refresh
token across independent lock domains.

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

# 2026-07-10 — v3 workflow final wiki reconciliation

- Revalidated the global wiki after
  v3-bench-as-hive-workflow-260709-b3nc's documentation-only residual change.
  The change alters branch-local wiki pages and log fragments but does not
  modify workflow, harness, campaign-example, or smoke-test sources, so the
  source-backed behavior in [[v3-workflow]] remains current.
- Kept the post-spend campaign-freeze decision in [[decisions]] and its
  first-spend-fingerprint gap in [[gaps]]. The committed generate gate still
  proves only that `campaign.yml` is tracked and clean at dispatch, while judge
  validation still reports paid cells removed from a later matrix as
  `UNEXPECTED_CELL`; no source now binds a campaign to its first-spend version.
- Kept first captured-diff judge-wall recovery open in [[gaps]]. Generate still
  disarms regeneration when a paid patch exists, but an all-judge-wall first
  pass can park before a campaign-root cell exists and `harness/rejudge.rb`
  still consumes only `results["cells"]`. The no-cost smoke verifies the
  never-re-buy guard, not recovery of that state; no paid end-to-end campaign
  has established the live path.
- Page coverage did not change, so [[index]] remains current. `wiki/log.md` was
  left for the post-commit compiler.

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
