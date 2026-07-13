# Gaps — unverified / left to build

What's NOT done or NOT yet known. See `HANDOFF.md` for the run/build commands.

## Candidate matrix (opus, codex, and the mixed candidate PROVEN 2026-07-02)

- ~~codex container posture~~ — SOLVED: tmpfs `~/.codex` (root-owned bind-parent
  killed the CLI at startup, same as `.claude`). all-codex and opus-plan→codex-exec
  ran the full cycle in the smoke.
- **open models (glm/kimi via pi)** — hive has **no `--model` flag for pi**; the model comes
  from pi's provider config. To vary glm vs kimi, configure `~/.pi/agent` per run or add an
  `agents.pi.args` passthrough. UNVERIFIED.
- **codex usage shape** — codex's stream reports input tokens with no cache split, so the
  token-priced cost is likely overstated (4.2M input at full rate in the smoke). Verify how
  codex reports cached tokens before publishing cost columns.

## Review stage (SHIPPED 2026-07-02 — leftovers)

- Full cycle runs (open-pr + review with prod-default config, gh shim, bench-local origin;
  see [[architecture]]). Leftovers:
  - `review_status` marker capture found nothing in status.md — locate hive's terminal
    REVIEW_COMPLETE/WAITING/STALE marker (file/format) and wire it into telemetry.
  - CI-fix phase is inert while `ci.command` is null (prod parity); once gates are curated,
    feed the gate's `test_cmd` in as `ci_command` so review runs real CI.

## Cleanup (Stage E)

- Retire the v1 path: `harness/lib/pipeline.rb`, `pipeline_run.rb`, the planner/executor seams
  in `lib/isolation_exec.rb`, and the v1 `RESULTS.md` (→ `RESULTS-v1-deprecated.md`).
- Publish a v2 `RESULTS.md` framed as "real hive, judged vs the merged PR."

## Integrity round leftovers (2026-07-01)

- **Egress allowlist proxy for generation** — `HB_GEN_NETWORK` accepts a proxied docker
  network, but nothing builds one yet. Until then answer-key leakage is detected
  (`answer_key_access_suspect` scan), not prevented.
- **Mixed-family cost attribution** — `opus-plan→codex-exec` tokens span two price rows;
  needs per-stage token attribution (stage → agent from the log filename) before
  `cost_usd` can be estimated for mixed candidates. Currently nil by design.
- **Model self-verification** — `model_version` is asserted by the candidate config, not
  verified. The stream logs carry model ids; parse and cross-check, flag mismatched cells.
- **Recovered-artifact wall time** — if generation completed but result assembly
  aborted, elapsed time existed only in the interrupted driver process. Recovery
  marks `recovered_artifact: true` and leaves `wall_clock_sec` unknown rather than
  inventing a duration. Persist start/end timestamps if recovered cells must enter
  time comparisons. Pre-identity artifacts also cannot prove their external model
  pins; their explicit recovery path marks `artifact_provenance: legacy-unverified`.
- **Execute-resume crash window and CLI drift** — transport recovery fails closed
  if Codex changes its terminal event/message shape. Also, a host/container crash
  after the exact error marker is cleared but before `hive develop` starts can
  leave the preserved task markerless; a durable resume-intent journal would
  close that narrow window.
- **Gate curation is still the biggest lever** — v2 runs a no-op gate; the objective floor
  returns only when tasks carry curated verbose gates. Corpus is now 6 accepted tasks
  (2026-07-01 extraction round); PRs #623/#624/#625 ship unit tests → best F2P candidates.
- **Paid v3 workflow validation** — the Fable and Sol judge paths are proven by
  the completed v2 campaign, and the native workflow has no-cost fixture
  coverage. A fresh paid campaign using campaign-declared Fable + Sol `ultra`,
  three samples, undersample repair, candidate-plan judging, and adversarial
  deliberation has not yet completed end to end.

## Finish-the-board queue (2026-07-04)

- **9 opus/mixed cells pending** on claude limit windows — `tmp/retry-pending.sh`
  babysits them (sweeps each window, max 6). Re-launch it if it exhausts sweeps.
- **11 open-model cells to re-run** after the balance drain: all 6 glm→kimi pair
  cells, 4 kimi cells (plus diagnose kimi's pre-drain execute_faileds), 1 glm
  daemon cell.
- **Judge backfill** (`harness/rejudge.rb`): fable-5 missing on most codex/glm
  cells (claude wall), gpt missing on the smoke cells.
- **Classifier patterns still missing**: OpenRouter's "requires more credits, or
  fewer max_tokens" (402 variant) isn't in AgentLimit; a plan stage stuck at
  `:agent_working` after an instant agent death classifies as execute_failed
  rather than a limit when the balance is the cause.
- **Recompute open-cell telemetry at merge time** — cells generated before the
  pi camelCase fix carry zero tokens; the stream logs persist, so a merge-time
  backfill can price them.

## Known open questions

- **`/ce-plan` variance** is 2/3-good but real. For a publishable single-seed leaderboard,
  decide: accept + report spread, or take a representative/median run. (No hack per [[decisions]].)
- The reused-incumbent range-diff capture can sweep unrelated history — needs tightening.
- Corpus is 6 tasks (Ruby/CLI, single repo) — small; correlated samples. v3 grows it with fresh PRs as they merge (also the contamination mitigation).

## v3 agenda (from the external design review, 2026-07-09)

Full review: reviews/external-design-review-gpt-2026-07-09.md. Not fixed in v2:
- **Objective gates primary** for all 6 tasks (concrete gate designs are in the
  review §4.2); judges then score quality among passing diffs only.
- **Pre-registered, replicated campaign**: campaign.yml committed before
  running; N>=3 generations/cell; completion x quality axes; exclusions only
  per pre-registered criteria.
- **Anchor diffs** per task (empty / reference / known-bad) + rater-calibrated
  score model (score ~ candidate + task + judge severity) instead of raw means.
- ~~**{{PLAN}} contract ambiguity**~~ — RESOLVED for v3: the workflow judges
  the plan generated by the candidate in that cell. Published v2 remains
  frozen-plan-scored and is labeled as historical methodology.
- Style-provenance scrubbing of diffs before judging; third rater for the
  mixed-family candidates; stratify results by plan_authorship provenance.

## Native workflow publication and scheduling

- **Hive release dependency** — the named `bench` workflow and its packaged
  stage instructions must ship in a Hive release before the no-copy setup works
  for public installs. Honeycomb is not deployed and is not part of this path.
- **Public submission automation** — users can run a local campaign through
  the native workflow, but public inclusion still needs a documented review
  path for corpus manifests, frozen source/base/reference artifacts, objective
  gates, contamination checks, and campaign pre-registration. The website now
  needs to distinguish local results from accepted public-benchmark tasks.
- **Campaign-level fan-out** — Hive owns concurrency between ordinary workflow
  tasks, but one campaign stage currently walks its cell matrix serially.
  Native descriptor-level cell fan-out/join is not available. Use separate
  campaign tasks under the daemon's per-project cap; do not point concurrent
  tasks at the same campaign id.
