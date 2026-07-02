# Gaps — unverified / left to build

What's NOT done or NOT yet known. See `HANDOFF.md` for the run/build commands.

## Blocked

- **OpenRouter balance ~$4** — the gpt-5.5-pro judge (each call reserves ~$6) can't run until
  topped up. Blocks completing the gpt-judge half of the v2 cells.

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
- **Gate curation is still the biggest lever** — v2 runs a no-op gate; the objective floor
  returns only when tasks carry curated verbose gates. Corpus is now 6 accepted tasks
  (2026-07-01 extraction round); PRs #623/#624/#625 ship unit tests → best F2P candidates.
- **Fable judge model id unverified** — the claude judge now defaults to `claude-fable-5`
  (maintainer picked fable + gpt-5.5-pro as the full judge slate). If the CLI rejects that
  id, the judge fails loudly (fail-soft parks the cell); verify on the first judged pass or
  pin with `--judge-model`.

## Known open questions

- **`/ce-plan` variance** is 2/3-good but real. For a publishable single-seed leaderboard,
  decide: accept + report spread, or take a representative/median run. (No hack per [[decisions]].)
- The reused-incumbent range-diff capture can sweep unrelated history — needs tightening.
- Corpus is only 2 tasks (Ruby/CLI) — small. More tasks needed for robust per-agent resolution.
