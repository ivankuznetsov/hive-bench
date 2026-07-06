# Decisions

Methodology decisions and the reasoning. See [[findings]] for evidence, [[architecture]] for
how they're implemented.

- **Drive real hive, don't imitate it** (the v2 pivot). v1's reimplemented planner measured a
  toy workflow; the gap between real `/ce-plan` and the toy planner was ~2 judge points. Use
  hive exactly, with different model settings.
- **Full workflow incl. review** is the target — but v2 ships **plan+execute first**; the
  review chain (`open-pr` needs gh-stub, `review` needs CI + reviewer personas) is the next
  phase. Sequencing chosen to land a correct result fast.
- **Judge against the reference PR** (reference-PROVIDED), as a SIGNAL with an absolute rubric
  ("does this accomplish the task," not "how close to the gold"). v1 used reference-withheld;
  v2 flips it on.
- **Seed the frozen brainstorm** (the recorded human Q&A) for every candidate, then run
  plan→execute. Fair, deterministic, same task. The brainstorm is the scope authority.
- **Hive-in-container** for isolation (real hive runs agents on the host with skip-perms; we
  add the isolation ourselves).
- **Dual independent judge** = opus-4.8 (local claude CLI) + gpt-5.5-pro (OpenRouter),
  cross-family; gpt-5.5-pro is the de-anchored headline (stricter, but agrees on ordering).
- **Cost is API-equivalent at usual-tier rates**, computed from token counts (the CLIs report
  tokens even on subscription). Closed models priced at gpt-5.5 `$5/$30/$0.50` and opus-4.8
  `$5/$25/$0.50` per M — NOT the fast tier.
- **Don't add a `/ce-plan` variance hack.** A correct brainstorm usually (2/3) yields a clean
  full-scope plan; the minimal fork is the exception. (Considered: auto-answering open
  questions, multi-seed, seeding human answers — all rejected per maintainer guidance.)

## 2026-07-01 — integrity hardening round

- **Gate tests must be positively observed.** A FAIL_TO_PASS or PASS_TO_PASS name absent
  from the run (typo, deleted guard, not collected) errors the cell — absence is never a
  pass. Corollary: every gated `test_cmd` must emit per-test results (`TESTOPTS=-v`).
- **Same-family judge scores can't headline.** Both judge families (anthropic, openai) also
  compete, so full disjointness is impossible. Every judge score carries `same_family`;
  the publishable aggregate is `mean_quality_cross_family`.
- **The judge slate is exactly two: fable-5 + gpt-5.5-pro** (maintainer decision,
  2026-07-01 — no third-family judge). The claude judge defaults to `claude-fable-5` and
  the results.json judge key derives from the pinned model, so a key never claims a model
  that didn't judge. Cross-family coverage: fable-5 headlines openai-family candidates,
  gpt-5.5-pro headlines anthropic-family ones; mixed candidates have no cross-family judge
  and rank on the flagged means.
- **Canonical cost is the token-priced estimate** (`lib/pricing.rb`, usual-tier table
  `2026-06-usual`), because self-reported CLI cost is inconsistent across agents (claude
  reports fast-tier, codex/pi may report nothing). Reported cost is kept as
  `cost_usd_reported`. Mixed-family candidates get no estimate rather than a wrong one.
- **Answer-key leakage is flagged, not (yet) prevented.** Generation can't be
  network-isolated, and the reference PR is public. Until an egress-allowlist proxy
  (`HB_GEN_NETWORK`) is standing, the driver scans agent logs for reference-PR access and
  invalidates flagged cells via `answer_key_access_suspect`. The README states the honest
  posture.
- **A timeout is `timed_out`, not `plan_failed`** — a slow candidate and a candidate that
  cannot plan are different findings; rc=124 from the stage `timeout` is classified apart.
- **Leak checking is audience-aware.** Reference lines in the CANDIDATE-VISIBLE spec
  (idea/brainstorm — what v2 seeds into hive) reject the entry; overlap with plan.md only
  warns, because the candidate never sees the plan (hive re-plans) and a detailed plan
  legitimately quotes the code it prescribes. Content-specified docs tasks whose brainstorm
  quotes the deliverable text are rejected as transcription tasks (see the three
  `update-the-openclaw-hive-skill` extractions, corpus/MANIFEST.md).

## 2026-07-06 — pair install/fix-tmux: no further retries (maintainer decision)

`glm-plan->kimi-exec` failed execute on figure-out-install and fix-tmux twice
each WITH funds available — that is reproducible signal, not infra noise. The
recorded `execute_failed` cells stand on the board as honest outcomes; no
budget retries them again. (The pair's daemon/web-install failures coincided
with balance drains and remain retry-eligible if ever funded — they are NOT
part of this exclusion.)
