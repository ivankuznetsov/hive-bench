# hive-bench v2 results — real hive, full cycle, judged vs the merged PR

_2026-07-06. Corpus v2 (6 tasks, ivankuznetsov/hive, judged subset). Candidates run
REAL hive (plan → execute → open-pr → review, prod review config) in an isolated
container; the final post-review diff is judged against the merged reference PR by
two blind judges. v1 (the deprecated imitation harness) is in
`RESULTS-v1-deprecated.md`._

## The board

Cell = `gpt-5.5-pro / fable-5` (independent scores, 0–10 absolute rubric, reference
provided as signal). `·` = judge missing (limits); statuses are honest outcomes.

| candidate | add-i-key | web-install | install | fix-tmux | fix-review | daemon |
|---|---|---|---|---|---|---|
| all-opus-4.8 | 1.0 / 1.3ᵃ | ✗ exec | ⏳ | · / 8.0ᵇ | ⏳ | ⏳ |
| all-codex | 4.0 / 6.0 | 2.0 / 4.5 | 2.0 / 4.0 | 7.0 / 7.0 | 2.0 / 4.0 | 3.7 / 5.7 |
| opus-plan→codex-exec | 2.0 / 2.0 | ⏳ | ⏳ | · / 8.5ᵇ | ⏳ | 4.0 / 5.0 |
| all-glm-5.2 | 4.0 / 6.2 | 2.0 / 3.5 | 2.0 / 4.5 | **8.0 / 9.0** | 4.0 / 7.0 | 4.0 / · |
| all-kimi-k2.7-code | 4.0 / · | 2.0 / 3.5 | 2.0 / 3.7 | **8.0 / 8.5** | 2.0 / · | ✗ exec |
| glm-plan→kimi-exec | 4.0 / · | ✗ empty | ✗ exec | ✗ exec | 4.0 / · | ✗ exec |

ᵃ the 1/3 `/ce-plan` minimal-fork variance sample (220-line diff vs the ~1300-line
full scope). ᵇ from the earlier smoke run of the same pipeline (opus generation was
subscription-limited before a re-run landed). ⏳ = not run: claude subscription
limit windows consumed every retry attempt across two days.

**Cross-family headline** (the judge from the family disjoint to the candidate;
mixed candidates have none and rank on flagged means only):

| candidate | cross-family judge | mean over scored tasks |
|---|---|---|
| all-codex | fable-5 | **5.2** (6/6 tasks) |
| all-glm-5.2 | gpt-5.5-pro | **4.0** (6/6 tasks) |
| glm-plan→kimi-exec | gpt-5.5-pro | 4.0 (2/6 — 4 failed) |
| all-kimi-k2.7-code | gpt-5.5-pro | **3.6** (5/6 tasks) |
| opus-plan→codex-exec | (none — both families) | gpt 3.0 / fable 5.2, flagged |
| all-opus-4.8 | gpt-5.5-pro | 1.0 (1/6 — see limits) |

## What the numbers say

1. **glm-5.2 is the efficiency frontier.** Full-cycle-reliable (6/6), the board's
   best single scores (8.0/9.0 on fix-tmux), and fully metered at ~$13/task —
   while the closed models hide their (larger) burn behind subscriptions.
2. **codex is the only candidate that never failed** — 6/6 tasks, no walls, no
   stage errors — and its cross-family 5.2 is the best complete-column mean. The
   trade: it clusters at 2.0 (gpt) on the three hardest tasks.
3. **kimi-k2.7-code is bimodal**: excellent on the discriminating fix-tmux
   (8.0/8.5) but with real execute fragility (empty final turns stalling hive's
   stage markers) beyond what infra failures explain.
4. **The glm→kimi handoff mostly doesn't work** (4 of 6 cells failed at execute)
   even though each model succeeds solo — mirror-imaging the closed mixed pair,
   which scored when it ran. Cross-model handoff inside hive is its own risk.
5. **Subscription limits, not capability, decided the opus column.** Two days of
   retry windows produced one full opus cell (plus the smoke run's 8.0-fable
   fix-tmux). For benchmarking, per-token open models are *operationally* superior:
   they can always be re-run for money.
6. **Task difficulty replicated v1**: install-class tasks floor everyone at
   gpt 2.0; fix-tmux separates the field.

## Judge deliberation (diagnostic)

After independent scoring, judges exchanged anonymized verdicts and discussed
(one round, revise only on concrete facts). Across all 10 discussed cells:
**gpt-5.5-pro's mean revision was 0.00; fable-5 revised only downward (to −2.0),
always after verifying gpt's specific claims against the diff.** The lenient
judge's generosity does not survive fact-checking; the strict judge's verdicts
do. The leaderboard keeps independent round-1 means (deliberation can anchor as
well as correct); transcripts are in `runs/v2-merged/deliberation*.json`.

## Costs (API-equivalent, usual tier)

Open models: glm ~$13/task, kimi ~$13/task full-cycle (~4× bare execute — the
review stage re-reads context heavily; ~49M cache-read tokens/task). Closed
models: same burn shape, hidden by subscription flat rates. Judging: ~$1–3/cell
(gpt-5.5-pro, 16–32k cap). Whole v2 campaign: ~$310 OpenRouter + two days of
claude/codex subscription windows.

## Caveats

Corpus is 6 Ruby/CLI tasks from one maintainer's repo, judged-subset only (no
curated test gates yet) — rankings are "best on this corpus", not "best agent".
Judge scores are single-seed for most cells (tie intervals collapse). Missing
cells are named constraints, never silent: ⏳ subscription limits, ✗ honest
stage failures, budget cuts documented in `wiki/gaps.md`.

*Reproduce: `runs/v2-merged/final.json`; harness at this commit; corpus v2.*
