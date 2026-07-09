# gpt-5.5-pro external design review — 2026-07-09

COI acknowledged: I am the named `gpt-5.5-pro` judge and same broad family as the `all-codex` contestant. I would not treat my own judging behavior as neutral evidence.

## 1. THREATS TO VALIDITY — ranked by severity

1. **Critical: the “cross-family headline” compares different rulers, not just different candidates.**  
   Critiqued: `RESULTS.md / Cross-family headline`, `README.md / Integrity model`, `wiki/decisions.md / Same-family judge scores can't headline`.  
   The docs disclose same-family exclusion, but the missed consequence is scale non-comparability. `all-codex` is headlined by `fable-5` at **5.2**, while `all-glm`, `all-kimi`, and `all-opus` are headlined mostly by `gpt-5.5-pro`. The board itself shows `fable-5` is usually 1–2+ points more generous. For example, `all-codex` is **3.45** by GPT but **5.2** by Fable. `all-opus` is **3.83** by GPT and about **5.26** by available Fable cells. So the published “codex leads” headline can be a judge-scale artifact. Family-disjointness prevents one kind of bias while introducing a larger rater-calibration confound.

2. **Critical: exclusions and missingness are not ignorable, but the aggregates treat them as mostly ignorable.**  
   Critiqued: `wiki/decisions.md / 2026-07-06 — pair install/fix-tmux: EXCLUDED`, `README.md / Integrity model / Limits are never failures`, `RESULTS.md / Caveats`.  
   The docs name the exclusions, but the missed validity problem is conditioning on finishability. The `glm-plan→kimi-exec` pair’s repeated execute failures are precisely evidence about whether that configuration can drive hive. Removing those cells from aggregates turns “fails reproducibly on hard cells” into “evaluated on easier remaining cells.” Similarly, subscription walls are operationally relevant to “which model should drive my daily autonomous pipeline”; treating them as pending rather than as availability failures makes the quality board answer a narrower question than the headline suggests.

3. **High: judge-only static diff reading is too weak for these task types.**  
   Critiqued: `harness/judge-prompt.md / How to score`, `wiki/architecture.md / hive_run.rb no-op gate`, `corpus/SCHEMA.md / gate`.  
   The docs disclose “no curated test gates yet,” but the underplayed consequence is that several tasks are runtime/integration tasks: install scripts, tmux readiness detection, review stop-hooks, terminal daemon retries. A plausible diff can look decent to an LLM and still fail in a shell, tmux session, or review-state transition. Conversely, a non-reference implementation can look suspicious despite working. The published 0–10 scores are therefore mostly “LLM-estimated plausibility,” not observed task success.

4. **High: the task contract is inconsistent across docs, and judges may grade against material candidates did not see.**  
   Critiqued: `README.md / How it works step 2`, `wiki/architecture.md / Flow steps 2–4`, `corpus/SCHEMA.md / What the candidate sees`, `harness/judge-prompt.md / <plan>{{PLAN}}</plan>`.  
   README/architecture say the run is seeded with frozen idea + brainstorm and hive re-plans. `corpus/SCHEMA.md` says the candidate sees `idea`, `brainstorm`, and `plan`. The judge prompt grades “the task” using `{{PLAN}}`. If `PLAN` is the frozen original plan but the candidate actually re-planned from brainstorm, judges can penalize deviations from a plan that was not part of the candidate-visible contract. If the plan was authored by the original agent/human, it can also encode reference-solution choices while being presented as task scope.

5. **High: answer-key contamination is still materially possible, and log scanning is not enough.**  
   Critiqued: `wiki/decisions.md / Answer-key leakage is flagged, not prevented`, `wiki/architecture.md / Driver hardening / answer-key access`, `README.md / Corpus table with public PR links`.  
   The docs disclose this partially, but the practical failure mode is broader than explicit `gh pr view` or repo-qualified PR URLs in logs. A model/tool could search GitHub by task text, fetch patches through alternate URLs, use cached search/RAG, or simply have public PRs in pretraining. Future models trained after publication may ingest `reference.patch` directly. “No suspect log hit” is therefore weak evidence of no answer-key access.

6. **High: one generation sample and mostly one judge seed make rank differences look more precise than they are.**  
   Critiqued: `RESULTS.md / Caveats`, `RESULTS.md / board footnote ᵃ`, `wiki/decisions.md / Don't add a /ce-plan variance hack`, `wiki/architecture.md / hive_run.rb --seeds`.  
   The board already has evidence of `/ce-plan` bifurcation. A single sampled run per candidate-task measures one draw from a stochastic workflow, not expected performance. The ranking gaps are often smaller than plausible judge noise plus run variance. Also, docs conflict: architecture says “≥3 for published cells,” while results say mostly single-judge-seed. For this benchmark, seed policy is not a detail; it directly determines whether the leaderboard is stable.

7. **Medium-high: the benchmark measures model + CLI + hive profile + ecosystem affordances, but the result names mostly read like model rankings.**  
   Critiqued: `wiki/architecture.md / Full cycle`, `RESULTS.md / Caveats / codex default reasoning effort`, `README.md / Model claims verified`.  
   Some of this is intentional, but it should be more explicit in rankings. `pr-review-toolkit` runs only for Claude candidates; Codex ran at default reasoning effort; utility models are allowlisted; provider CLIs differ in hidden effort, context handling, retries, tool semantics, and failure markers. “all-codex” versus “all-opus” is therefore not just model ability. It is a whole stack comparison.

8. **Medium: corpus selection is not protected from maintainer degrees of freedom.**  
   Critiqued: `README.md / The corpus v2`, `corpus/SCHEMA.md / provenance`, `wiki/decisions.md / exclusion decisions`.  
   The docs disclose n=6/single repo, but the deeper issue is selection plus post-run decision freedom. The same maintainer selected tasks, owns the repo, judges task relevance, and made exclusion calls. `corpus/SCHEMA.md` has `original_model` and `plan_authorship` fields, but the published ranking does not appear stratified by them. If original hive tasks/plans were produced by a model family close to a contestant, the corpus can inherit that family’s assumptions.

9. **Medium: simple means over six ordinal LLM scores are overinterpreted.**  
   Critiqued: `RESULTS.md / Cross-family headline`.  
   A 0–10 LLM score is not a calibrated interval scale. Equal-weight averaging also assumes each task is equally important and independent. With six tasks, a one-point score change on one task moves the mean by 0.17; a single judge-scale offset moves it by far more. The table even orders `all-opus` below `all-kimi` despite a higher displayed mean, which makes the “headline” presentation feel less rigorously leaderboard-like than claimed.

---

## 2. JUDGE DESIGN

- **The judge prompt contains a false premise.**  
  Critiqued: `harness/judge-prompt.md / opening paragraph`.  
  It tells the judge: “your model family is disjoint from every contestant.” That is false for this benchmark. I, `gpt-5.5-pro`, am same-family with `all-codex`; `fable-5` is same broad family as Claude/Opus contestants. Even if same-family scores are later flagged, the judge should not be given a false neutrality instruction. Better: “Some scores may later be excluded for family overlap; do not account for that yourself.”

- **“Blind” is weaker than it sounds.**  
  Critiqued: `harness/judge-prompt.md`, `wiki/architecture.md / capture candidate.patch`.  
  Judges are blind to the declared candidate, but diffs can leak style: generated comments, tool-specific formatting, over/under-editing, file choices, or known model habits. The prompt says not to guess, but implicit style priors can still affect scoring. If blindness matters, diffs should be scrubbed for obvious provenance artifacts and randomized in batches.

- **Two judges are not enough when both are conflicted in opposite directions.**  
  Critiqued: `wiki/decisions.md / judge slate exactly two`, `README.md / Family-disjoint headline`.  
  The setup avoids self-family headline scoring, but uses rival/other-family scoring as the replacement. That is not the same as neutral scoring. A two-rater design also cannot separate candidate effect from judge severity without strong assumptions.

- **The family-disjoint headline is the wrong aggregate.**  
  Critiqued: `RESULTS.md / Cross-family headline`.  
  It should not compare Fable-only codex means against GPT-only GLM/Kimi/Opus means. For open-model candidates, both judges are apparently disjoint, yet the headline uses GPT only. For mixed OpenAI+Anthropic candidates, there is no clean disjoint judge, so they become second-class rows. This is not a coherent ranking model.

- **Deliberation is a weak diagnostic and may be self-validating.**  
  Critiqued: `harness/deliberate-prompt.md`, `README.md / Judge deliberation`, `RESULTS.md / Integrity verification`.  
  Keeping independent scores for the leaderboard is good, but the diagnostic claim that Fable revised downward after checking GPT’s claims does not prove GPT was more correct. It may show anchoring, verbosity advantage, or GPT stubbornness. The 15 discussed verdicts are not obviously random, and the other judge’s reasoning can reveal style/identity despite anonymization.

- **My own role is especially problematic.**  
  I may favor or disfavor OpenAI-style solutions, overcorrect because I “know” I am conflicted, anchor heavily on the reference PR, or recognize public hive code/PRs from training. My unchanged deliberation mean should not be interpreted as calibration or reliability. At most, my scores are one rater’s opinions with a known conflict flag.

- **Judge-version documentation is inconsistent.**  
  Critiqued: `wiki/architecture.md / Flow step 7`, `wiki/decisions.md / Dual independent judge`, `README.md / How it works`.  
  Some docs still say the Claude judge is `opus-4.8`; others say `fable-5`. Since judge identity is central to the validity claim, stale architecture/decision text is not harmless.

---

## 3. CORPUS & TASK DESIGN

- **n=6 is not merely small; the effective n is smaller.**  
  Critiqued: `README.md / The corpus v2`, `RESULTS.md / What the numbers say / task structure replicated v1`.  
  The tasks are all from one Ruby/CLI repo, several are install/terminal/review-adjacent, and recent PRs are clustered. These are correlated samples, not six independent draws from “software development.” One task like `fix-tmux` can dominate perceived competence.

- **Single-repo self-hosting creates idiosyncratic bias.**  
  Critiqued: `README.md / Which AI model runs hive`, `wiki/architecture.md / target repo clone`.  
  The target repo is the pipeline’s own ecosystem. That is relevant for the maintainer’s private use, but it means results may mostly measure familiarity with hive’s architecture, conventions, and failure modes. Public PRs also increase contamination risk.

- **The task mix is not balanced against the benchmark claim.**  
  Critiqued: `README.md / corpus table`.  
  Four feature-ish tasks, two bugfixes, many terminal/install/review tasks, no broad library/API/data tasks, no multi-repo tasks, no frontend-heavy tasks except limited web-install. If the intended use is “autonomous development pipeline,” the mix under-samples many common maintenance modes.

- **Exclusion policy should be intention-to-treat, not post-hoc removal.**  
  Critiqued: `wiki/decisions.md / 2026-07-06 exclusion`.  
  “Unfinishable after two funded failures” is exactly a result. It should count in an end-to-end benchmark, perhaps as `0 quality` for E2E utility and separately as “quality conditional on completion.” Removing it from aggregates makes pair configurations look less risky than they are.

- **The candidate-visible spec needs one authoritative definition.**  
  Critiqued: `corpus/SCHEMA.md / What the candidate sees`, `wiki/architecture.md / Flow`, `harness/judge-prompt.md`.  
  Decide whether the benchmark is “execute this frozen plan” or “re-plan from idea+brainstorm.” Right now the schema, README, architecture, and judge prompt do not consistently say the same thing. That ambiguity is enough to change fair scoring.

- **The original-model/plan-authorship bias is collected but not used.**  
  Critiqued: `corpus/SCHEMA.md / provenance`.  
  If tasks, brainstorms, or plans were generated by a particular model family, report that in `RESULTS.md` and stratify or at least flag rows. Otherwise the corpus may privilege models whose planning assumptions match the original artifacts.

---

## 4. WHAT I WOULD CHANGE FIRST

1. **Replace the current headline with a calibrated rater model.**  
   Concrete mechanism:
   - Immediately stop publishing a single sorted “cross-family” leaderboard that compares GPT-only and Fable-only means.
   - Recompute current results as separate `gpt-only` and `fable-only` tables, with same-family scores visibly flagged but not mixed into a cross-rater rank.
   - For the next run, add at least one third-family judge or a small human maintainer panel.
   - Add anchor diffs per task: empty diff, reference PR, known-bad diff, and possibly a hand-written acceptable alternative.
   - Fit/report a simple rater-calibrated model: `score ~ candidate + task + judge_bias/severity`, or at minimum z-normalize judges on shared anchor/cell scores.
   - Publish confidence intervals or rank probabilities, not just means.

2. **Make objective gates primary for the six existing tasks.**  
   Concrete mechanism:
   - Fill `gate/gate.yml` for every current task and require base-fails/reference-passes validation before use.
   - Examples:
     - `add-i-key`: TUI keybinding/snapshot test that `i` opens task-info and legend advertises it.
     - `install` / `web-install`: smoke install into a temp prefix/home, assert executable/web UI starts without Docker.
     - `fix-tmux`: scripted tmux or mocked terminal fixture for Claude ready-prompt detection.
     - `fix-review`: state-machine test where stop-hook failure must not leave passes stuck in `REVIEW_ERROR`.
     - `daemon`: fixture emitting recoverable terminal error markers, assert retry behavior and no infinite retry.
   - Run gates in the no-network resource-capped gate container and require positive test observation as already specified in `corpus/SCHEMA.md`.
   - Publish gate pass/fail as the primary success measure; use LLM judges only for quality among passing or partially passing diffs.

3. **Pre-register an intention-to-treat replicated campaign.**  
   Concrete mechanism:
   - Commit a `campaign.yml` before running: task IDs, candidate profiles, model/effort flags, budgets, timeouts, seed count, exclusion criteria, and aggregation formula.
   - Run at least 3 generation samples per candidate-task, with fresh clean worktrees/conversations.
   - Run at least 3 judge samples per judge or a multi-judge panel with randomized order.
   - Score all launched cells in two axes:
     - `completion_rate_within_budget`
     - `quality_conditional_on_completion`
     - plus `end_to_end_utility = completion_rate * quality`
   - Treat provider walls separately as availability, not silently as missing, when answering “what should drive hive daily.”
   - Only exclude cells for pre-registered harness bugs affecting fairness across candidates; otherwise failures remain failures.
   - Add an egress allowlist/proxy and keep future reference patches/tests private until after the run to reduce answer-key access.

---

## 5. WHAT THE DESIGN GETS RIGHT

- **Running real hive instead of an imitation is a materially good choice.** `wiki/decisions.md / Drive real hive` fixes a major class of toy-harness error.

- **Keeping independent judge scores rather than deliberated scores in the leaderboard is the right default.** The deliberation diagnostic is weak, but not contaminating the main scores is important.

- **Model-claim verification from stream logs is a useful integrity primitive.** `README.md / Model claims verified` does not solve hidden config/tooling issues, but it catches blatant profile mismatch.

- **The future gate contract is well-designed.** `corpus/SCHEMA.md / Gate contract` requiring positive observation of tests is exactly the right fail-closed behavior.

- **Publishing cell statuses and naming exclusions is better than silently dropping runs.** The exclusion policy is still methodologically wrong for E2E ranking, but the transparency makes the damage auditable.
