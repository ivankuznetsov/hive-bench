# Gaps — unverified / left to build

What's NOT done or NOT yet known. See `HANDOFF.md` for the run/build commands.

## Blocked

- **OpenRouter balance ~$4** — the gpt-5.5-pro judge (each call reserves ~$6) can't run until
  topped up. Blocks completing the gpt-judge half of the v2 cells.

## Candidate matrix (only `all-opus-4.8` proven)

- **codex candidate** — needs container-posture work. v1 ran codex as root ("app-server needs
  root"); claude needs non-root. For a mixed candidate (opus-plan → codex-exec) the two stages
  want different postures in one container. UNVERIFIED whether codex runs non-root in the v2
  image — test first.
- **open models (glm/kimi via pi)** — hive has **no `--model` flag for pi**; the model comes
  from pi's provider config. To vary glm vs kimi, configure `~/.pi/agent` per run or add an
  `agents.pi.args` passthrough. UNVERIFIED.

## Review stage (the deferred phase)

- `plan → execute → open-pr → review`. `open-pr` creates a GitHub PR (needs gh) — use hive's
  babysitter dry-run stubs (`bin/hive-babysitter-stub-gh`, `Hive::Babysitter::DryRunEnv`).
- `review` runs CI-fix + reviewers + triage + fix loop. Config: `review.ci.command`,
  `review.max_passes`, `review.max_wall_clock_sec`, and **`review.reviewers` must be HASHES**
  (v2 currently emits `reviewers: []` — empty is valid; the hash shape is unwritten).
- Terminal markers `REVIEW_COMPLETE`/`REVIEW_WAITING`/`REVIEW_STALE` should map to `run_status`.

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
