# Gaps — unverified / left to build

What's NOT done or NOT yet known. See `HANDOFF.md` for the run/build commands.

## Candidate matrix (opus, codex, open models, and grok)

- ~~codex container posture~~ — SOLVED: tmpfs `~/.codex` (root-owned bind-parent
  killed the CLI at startup, same as `.claude`). all-codex and opus-plan→codex-exec
  ran the full cycle in the smoke.
- ~~open models (glm/kimi via pi)~~ — SOLVED in the harness: hive still has no
  native pi model field, but `hive_stages.sh` wraps pi and injects
  `HB_PI_MODEL_PLAN` / `HB_PI_MODEL_EXECUTE` / `HB_PI_MODEL_REVIEW`, so glm,
  kimi, and glm-plan→kimi-exec are explicit per cell.
- **codex usage shape** — codex's stream reports input tokens with no cache split, so the
  token-priced cost is likely overstated (4.2M input at full rate in the smoke). Verify how
  codex reports cached tokens before publishing cost columns.
- **grok usage/cost** — `all-grok-4.5` is configured with model+effort pins, but
  grok currently reports no token usage in this harness path. Cost columns stay
  unknown until telemetry exists.
- **grok runner pin** — grok needs the grok-enabled runner image
  (`HB_RUNNER_IMAGE=hive-bench-runner:grok`) until hive PR #695 is included in
  the pinned runner image.

## Review stage (SHIPPED 2026-07-02 — leftovers)

- Full cycle runs (open-pr + review with prod-default config, gh shim, bench-local origin;
  see [[architecture]]). Leftovers:
  - `review_status` marker capture now scans for REVIEW_COMPLETE/WAITING/STALE
    in `status.md`, but it has not been confirmed against a fresh successful
    full-cycle review run after the 2026-07-09 review-config changes.
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
- ~~Model self-verification~~ — SOLVED 2026-07-07: `harness/verify_models.rb`
  cross-checks substantive stage stream logs against each candidate claim; the
  recorded pass checked 101 stage logs with 0 violations.
- **Gate curation is still the biggest lever** — three tasks now carry
  reference-test overlays (#623/#624/#625), but only `fix-tmux` behaved as a
  useful behavioral gate on existing diffs. add-i-key, web-install, and install
  still need runtime-style gates, and the interface-strict gates need replacement
  before gates can be primary.
- **Fable judge model id unverified** — the claude judge now defaults to `claude-fable-5`
  (maintainer picked fable + gpt-5.5-pro as the full judge slate). If the CLI rejects that
  id, the judge fails loudly (fail-soft parks the cell); verify on the first judged pass or
  pin with `--judge-model`.

## Finish-the-board leftovers after final v2 publication

- The old 2026-07-04 pending-cell queue was resolved or superseded by the
  2026-07-06/07 final board publication. Do not relaunch those historical
  retry scripts as current work without first checking `runs/v2-merged` and
  RESULTS.md.
- **Open-model telemetry backfill** may still be useful for cells generated
  before the pi camelCase usage fix; stream logs persist, but this is now an
  analysis cleanup, not a board blocker.
- **Limit classifier drift** remains possible as providers change wording.
  OpenRouter's "requires more credits, or fewer max_tokens" variant was fixed
  in the final-board round; add new patterns only when a fresh wall is
  misclassified.

## Known open questions

- **`/ce-plan` variance** is 2/3-good but real. For a publishable single-seed leaderboard,
  decide: accept + report spread, or take a representative/median run. (No hack per [[decisions]].)
- The reused-incumbent range-diff capture can sweep unrelated history — needs tightening.
- Corpus is 6 tasks (Ruby/CLI, single repo) — small; correlated samples. v3 grows it with fresh PRs as they merge (also the contamination mitigation).

## v3 agenda (from the external design review, 2026-07-09)

Full review: reviews/external-design-review-gpt-2026-07-09.md. Not fixed in v2:
- **Bench-as-hive workflow shipped as orchestration only** — see
  [[v3-workflow]]. Remaining manual pieces: campaign authoring/commit,
  new-corpus extraction, provider-wall retry by `touch <state_file>`, website
  publishing, and review enforcement for budgets/effort pins.
  `timeouts.hive_seconds` is enforced via `HB_HIVE_TIMEOUT`.
- **Bench workflow smoke coverage is no-cost only** — the smoke now drives all
  four executable stages to `<!-- COMPLETE -->` on fixtures, uses the real
  `merge_results.rb` for generate/publish, asserts the never-re-buy guard by
  invocation count for terminal and captured-patch states, exercises
  deliberation-union retries and judge validation branches, and runs a campaign
  derived from `campaign.yml.example` through the real generate validator at a
  real-root-shaped fixture. No real paid campaign has run end to end through
  generate -> judge -> publish; live rejudge, deliberation, merge, and render
  behavior therefore remains unobserved.
- **First captured-diff judge-wall recovery is unresolved** — `3-generate` now
  correctly refuses to regenerate any cell with a `target/candidate.patch` and
  tells the operator to backfill judges against the campaign-root result only.
  However, an all-judges-walled first pass can persist `cells: []` plus
  `pending[]` in the per-cell result and park before the campaign-root merge;
  `harness/rejudge.rb` reads only `results["cells"]`. No scripted path currently
  turns that paid artifact into a rejudgeable campaign-root cell. Verify and
  cover this recovery before relying on it in a real campaign.
- **Pre-registration immutability is procedural after first spend** — the
  tracked+clean gate proves only that `campaign.yml` matches current HEAD; it
  does not bind the campaign to the file version used for the first paid cell.
  An amended-and-committed seed increase is not retroactive under
  `rejudge --only-missing`, while a matrix shrink is rejected later as
  `UNEXPECTED_CELL`. Until a first-spend fingerprint is persisted and checked,
  start a new campaign folder instead of amending a campaign that has spent.
- **Judge seed count is not re-verifiable from results.json** — judge records
  persist mean/interval only, not per-seed scores, so `4-judge` validation can
  require the dual-judge slate per non-empty-diff cell but must trust the
  `--seeds` flag it passed to `harness/rejudge.rb` for seed count.
- **Objective gates primary** for all 6 tasks (concrete gate designs are in the
  review §4.2); judges then score quality among passing diffs only.
- **Pre-registered, replicated campaign**: campaign.yml committed before
  running; N>=3 generations/cell; completion x quality axes; exclusions only
  per pre-registered criteria.
- **Anchor diffs** per task (empty / reference / known-bad) + rater-calibrated
  score model (score ~ candidate + task + judge severity) instead of raw means.
- **{{PLAN}} contract ambiguity**: judges grade against the frozen plan while
  v2 candidates re-plan from brainstorm — pick one authoritative contract.
- Style-provenance scrubbing of diffs before judging; third rater for the
  mixed-family candidates; stratify results by plan_authorship provenance.
