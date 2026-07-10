# Decisions

Methodology decisions and the reasoning. See [[findings]] for evidence, [[architecture]] for
how they're implemented.

- **Drive real hive, don't imitate it** (the v2 pivot). v1's reimplemented planner measured a
  toy workflow; the gap between real `/ce-plan` and the toy planner was ~2 judge points. Use
  hive exactly, with different model settings.
- **Full workflow incl. review** is the default v2 path. The early v2 bring-up
  shipped plan+execute first, then added open-pr + review with a bench-local
  origin and `gh` shim. `HB_REVIEW=0` remains the opt-out for plan+execute-only
  smoke runs.
- **Judge against the reference PR** (reference-PROVIDED), as a SIGNAL with an absolute rubric
  ("does this accomplish the task," not "how close to the gold"). v1 used reference-withheld;
  v2 flips it on.
- **Seed the frozen brainstorm** (the recorded human Q&A) for every candidate, then run
  plan→execute. Fair, deterministic, same task. The brainstorm is the scope authority.
- **Hive-in-container** for isolation (real hive runs agents on the host with skip-perms; we
  add the isolation ourselves).
- **Dual independent judge** — v1 ran opus-4.8 + gpt-5.5-pro; superseded 2026-07-01 by
  the fable-5 + gpt-5.5-pro slate, and 2026-07-09 by single-ruler presentation (below).
- **Cost is API-equivalent at usual-tier rates**, computed from token counts (the CLIs report
  tokens even on subscription). Closed models priced at gpt-5.5 `$5/$30/$0.50` and opus-4.8
  `$5/$25/$0.50` per M — NOT the fast tier.
- **Don't add a `/ce-plan` variance hack.** A correct brainstorm usually (2/3) yields a clean
  full-scope plan; the minimal fork is the exception. (Considered: auto-answering open
  questions, multi-seed, seeding human answers — all rejected per maintainer guidance.)

## 2026-07-09 — candidate self-review parity

Review now runs on the candidate configuration instead of silently falling back
to claude defaults. Single-agent candidates review themselves with their native
CE code-review skill (`codex-ce-code-review`, `pi-ce-code-review` through pi's
skill tree, etc.); mixed claude+codex candidates derive the prod-like tri-set
(`claude-ce-code-review`, `codex-ce-code-review`, `pr-review-toolkit`). This
keeps review quality part of the candidate's measured workflow rather than a
free claude post-processor. The bench deviation is still deliberate:
`github_publish` is disabled and the PR lives on a local origin.

## 2026-07-09 — explicit model pins for CLIs without hive model fields

hive has no native pi or grok model field and codex effort is a CLI config
setting, so the benchmark owns those pins at the container boundary:
`HB_PI_MODEL_<STAGE>` for glm/kimi and mixed open-model pairs,
`HB_GROK_MODEL`/`HB_GROK_EFFORT` for grok, and generated per-cell codex
`config.toml` for plugin registration plus xhigh effort. Operator-local CLI
configuration is not used as benchmark configuration.

## 2026-07-10 — freeze a campaign once paid work starts

`campaign.yml` is the pre-registration contract, so a campaign that has spent
must not be amended in place. The generate gate proves only that the file is
tracked, clean, and valid at dispatch time; it does not prove that current HEAD
matches the version used for the first paid cell. Increasing `seeds` later is
not retroactive because `rejudge --only-missing` preserves existing judge
scores, while shrinking the matrix surfaces paid cells as `UNEXPECTED_CELL`.
Start a new campaign folder for any post-spend contract change. Persisting and
checking a first-spend fingerprint remains a gap in [[gaps]].

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

## 2026-07-06 — pair install/fix-tmux: EXCLUDED from the bench (maintainer decision)

`glm-plan->kimi-exec` failed execute on figure-out-install and fix-tmux twice
each WITH funds available — unfinishable, so per maintainer decision those two
cells are REMOVED from the board: dropped from the published cells and
aggregates, with the exclusion (and its reason) named in RESULTS.md caveats.
The pair is evaluated over its remaining tasks. The handoff-fragility finding
survives in [[findings]] prose — the exclusion removes the cells, not the
lesson. (Daemon/web-install failures coincided with balance drains and remain
retry-eligible if ever funded — NOT part of this exclusion.)

## 2026-07-09 — single-ruler leaderboards (external-review fix)

gpt-5.5-pro's adversarial design review (reviews/external-design-review-gpt-
2026-07-09.md) showed the "cross-family headline" compared different rulers:
codex ranked by the generous judge, everyone else by the strict one — so
"codex 5.2 leads glm 4.0" was a judge-scale artifact (codex by gpt's own
scoring: 3.4, below glm). Published rankings are now ONE TABLE PER JUDGE, all
candidates in each, same-family rows flagged rather than excluded; scores
from different judges are never mixed into one column. Each table also
carries an intention-to-treat "end-to-end" mean (failures/exclusions score
0) so unfinishable configurations are penalized instead of averaged over
their survivors. The judge prompt's false "your family is disjoint from
every contestant" premise is fixed. Remaining review items (objective gates
primary, pre-registered replicated campaign, anchor diffs, rater-calibrated
model) are the v3 agenda in [[gaps]].
