# hive-bench results — v1 (plan + execute)

**Scope, read first:** these numbers cover the **plan → execute** half of the hive
workflow. The agent gets a task, produces (or is given) a plan, and writes code.
We then judge that **first-pass execute output**. What is *not* here yet is the
**review stage** — hive's CI-fix loop and reviewer personas that turn a first draft
into something mergeable. A follow-up update will add it and re-publish as the
**full workflow**. Until then, read every score as *"quality of the first execute
pass,"* not *"quality of what would ship."*

The corpus is small (v1 = **2 tasks**, Ruby/CLI), so treat **cross-band differences
as the signal and within-band agent ordering as suggestive, not settled.** See
[Limitations](#limitations).

---

## How a run is scored

- **Corpus:** frozen, completed hive tasks — each ships an `idea`, the `brainstorm`
  (the clarifying Q&A that pins requirements), the refined `plan`, any referenced
  screenshots, the merged `reference.patch` (answer key only — never a contestant),
  and a test `gate`. v1 tasks: `add-i-key-with-legend` (TUI info-panel) and
  `figure-out-way-to-install` (packaging).
- **Dual judge, reference-withheld:** every diff is graded by two independent
  judges — **opus-4.8** (local Claude CLI) and **gpt-5.5-pro** (OpenRouter) — on the
  plan + diff alone, with the reference withheld. They are a **cross-family** pair;
  the cross-family judge is the de-anchored headline. (1 seed.)
- **Run types:**
  - **Frozen-plan execution** — execute the corpus's already-refined plan. Measures
    *execution* in isolation.
  - **From-idea self-plan (e2e)** — the agent gets the **full hive ideation context**
    (idea + brainstorm + screenshot + repo), writes its **own** plan, then executes
    it. Measures the *whole* plan→execute loop. (Planner == executor.)
  - **Handoff** — planner-A authors the plan, executor-B implements it (the prod
    pattern: opus plans, codex executes). The executor gets the plan only, so the
    sole variable vs a frozen-plan run is *whose* plan.
  - **Raw incumbent** — the recorded claude-4.7 production run, scored from its raw
    execute diff, reference-withheld; never re-run.

---

## Leaderboard

Per-task scores are `opus-4.8 / gpt-5.5-pro`. **gpt-5.5-pro is the cross-family
headline.** **Cost is API-equivalent**, computed from each run's recorded token
counts (uncached-in / cached-in / output) × **OpenRouter standard rates** — gpt-5.5
`$5 / $30 / $0.50` per M, opus-4.8 `$5 / $25 / $0.50`, glm-5.2 `$0.95 / $3 / $0.18`,
kimi `$0.74 / $3.50 / $0.15`. These are the **usual** (standard) tiers, not the
priced-up "fast" tiers. For the open models this *equals* the actual billed spend;
for the closed models it is what those tokens *would* cost at API rates (they ran
flat-rate on subscription). Note the Claude CLI self-reports a higher per-run cost
because it accounts at the fast tier — we ignore that and price tokens at the usual
tier. `wall` is end-to-end wall-clock.

### Frozen-plan execution

| Agent | add-i-key | install | mean (o / g) | API-equiv $ | wall |
|---|---|---|---|---|---|
| **codex** (gpt-5.5-xhigh) | 9.0 / 8.0 | 8.0 / 5.0 | **8.5 / 6.5** | $10.1 | 19 m |
| **claude-4.8** | 9.0 / 8.0 | 8.0 / 4.0 | **8.5 / 6.0** | $7.3 | 29 m |
| **kimi-k2.7** | 8.0 / 8.0 | 7.0 / 2.0 | **7.5 / 5.0** | $3.63 | 21 m |

### From-idea self-plan (e2e — agent plans *and* executes)

| Agent | add-i-key | install | mean (o / g) | API-equiv $ | wall |
|---|---|---|---|---|---|
| **codex-selfplan** | 8.0 / 5.0 | 8.0 / 3.0 | **8.0 / 4.0** | n/a\* | ~40 m\* |
| **opus-4.8-selfplan** | 8.0 / 4.0 | 8.0 / 3.0 | **8.0 / 3.5** | n/a\* | ~35 m\* |
| **glm-selfplan** | 8.0 / 4.0 | 7.0 / 2.0 | **7.5 / 3.0** | $3.47† | 32 m |
| **kimi-selfplan** | 8.0 / 4.0 | 4.0 / 2.0 | **6.0 / 3.0** | $3.97 | 29 m |

### Handoff (planner → executor)

| Pair | add-i-key | install | mean (o / g) | API-equiv $ | wall |
|---|---|---|---|---|---|
| **opus-4.8 → codex** (prod) | 8.0 / 4.0 | 8.0 / 2.0 | **8.0 / 3.0** | ≈$10§ | 36 m |
| **glm-5.2 → kimi-k2.7** | 8.0 / 4.0 | 5.0 / 2.0 | **6.5 / 3.0** | $6.58 | 69 m |

### Raw incumbent

| Agent | add-i-key | install | mean (o / g) | API-equiv $ | wall |
|---|---|---|---|---|---|
| **claude-4.7** (recorded prod) | excluded‡ | 8.0 / 5.0 | **(8.0 / 5.0)** | n/a | — |

\* codex/opus self-plan: per-cell telemetry was lost when the inline gpt-judge hit a
billing wall mid-run (generation is subscription, unbilled). By comparison to their
frozen-execute cost plus a planning pass, expect roughly **$11–15** (codex) and
**$8–12** (opus) API-equivalent per task. Wall is approximate, from the run log.
† glm-selfplan cost is the add-i-key cell only; its install telemetry was lost.
§ opus→codex is estimated: the planner (opus) + executor (codex) tokens are
recorded, but the pipeline did not retain the per-phase cached split, so the
codex executor's cache ratio is assumed at its observed ~98%.
‡ claude-4.7 add-i-key is excluded: the reused-incumbent range diff
(`base..execute_base_head`) swept in 166 unrelated files / 22.5k lines of repo-wide
history — a capture artifact, not the agent's work on the task.

---

## What the numbers say

1. **The refined plan is worth ~2 points — and this is the robust result.** For every
   agent we could compare, executing the corpus's *refined* plan beat the agent
   writing its *own* plan from the idea, on the strict judge:
   - codex: **6.5** (frozen) vs **4.0** (self-plan)
   - kimi: **5.0** (frozen) vs **3.0** (self-plan)

   The plan-quality effect (~1.5–2.5 gpt points) is *larger and more consistent* than
   any agent-to-agent gap within a band. The hard part of these tasks is the
   planning/scoping, not the typing.

2. **`install` is the discriminating task; `add-i-key` saturates.** Almost everyone
   lands opus 8.0 / gpt 4.0 on add-i-key. The separation is entirely on `install`,
   where the strict judge ranges 2.0–5.0. A leaderboard built only on easy tasks
   would look like a tie.

3. **Closed frontier models lead the strict judge in every band**, but the gap is
   modest and the open models keep pace on the lenient judge. On gpt-5.5-pro:
   codex/claude-4.8 (frozen 6.0–6.5) > kimi (frozen 5.0) > the from-idea pack (3–4).

4. **Self-plan ≈ handoff for a given agent.** glm executing its own plan (7.5/3.0)
   slightly beat kimi executing glm's plan (6.5/3.0); codex-selfplan (8.0/4.0) ≈
   opus→codex (8.0/3.0). Who *executes* matters more than whether one agent or two
   produced the plan.

5. **Judge calibration:** opus-4.8 grades generously (6.0–8.5), gpt-5.5-pro strictly
   (3.0–6.5). They **agree on the cross-band ordering** (frozen > from-idea), which is
   why we trust that ordering and report both columns.

6. **Cost inverts the intuition — at API rates the *closed* models are the expensive
   ones.** Priced from tokens at standard rates: **codex-frozen ≈ $10/task**,
   **claude-4.8 ≈ $7/task**, vs the open models at **$3.5–4/task**. The closed agents
   burn 10–17M *cached* input tokens per task re-reading context (≈$5–8.5/task in
   cache reads alone); the open models are simply cheaper per token. Subscription
   hides this — you pay flat — but the API-equivalent column shows what the compute
   actually costs. The one genuinely pricey *billed* run is the **glm→kimi handoff
   ($6.6/task, ~69 min)** — two slow open-model sessions back-to-back. Fastest
   end-to-end: **codex-frozen (~19 min)**. Producing the whole benchmark (all
   open-model generation + every gpt-5.5-pro judgement) cost **$44.78** of OpenRouter
   credit.

---

## Limitations

- **2 tasks, 1 seed.** Within-band agent ordering (e.g. codex-selfplan 4.0 vs
  opus-selfplan 3.5) is **not statistically robust** — do not read it as a ranking.
  The cross-band differences are large and repeat across agents; those we stand by.
- **Plan + execute only — no review stage.** Scores are first-pass execute quality.
  The reference PRs went through CI + review + fixes; the agents' diffs did not. A
  review stage would likely lift everyone and is the next addition.
- **Corpus is Ruby/CLI-weighted** and drawn from one maintainer's repos; frozen plans
  were authored mostly by the incumbent agents. "Best on this corpus," not "best
  agent."
- **One incumbent cell excluded** (claude-4.7 add-i-key) for a range-diff capture
  artifact; the reused-incumbent capture needs tightening.

---

## Next

- **Add the review stage** → measure *mergeable* output, not first draft: run the
  gate/CI, feed failures back for bounded fix iterations, optionally run reviewer
  personas. Re-publish as the **full workflow**.
- **Expand the corpus** (more tasks, more domains) for robust per-agent resolution
  and to de-weight the easy-task saturation.
- **Tighten the incumbent capture** so raw-execute range diffs can't sweep in
  unrelated history.

*Generated from `runs/results.json` (corpus v1). Reproduce the merge with
`ruby harness/merge_results.rb`.*
