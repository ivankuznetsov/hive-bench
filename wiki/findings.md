# Findings

Everything learned building and running hive-bench. Grounded in the run results under
`runs/` (gitignored — regenerate) and the code. See [[architecture]] and [[decisions]].

## Headline (the thesis that drove the v2 rebuild)

**The benchmark must DRIVE real hive, not imitate it.** v1 reimplemented planning with a
generic prompt; the results proved that's the wrong thing to measure: real `/ce-plan` plans
were worth **~2 judge points** the toy planner could not reach. The single best v1 score was
*codex executing opus's FROZEN plan* (gpt-5.5-pro 6.5) — better than any from-idea run (3–4)
**only because the frozen plan was a real `/ce-plan` artifact**, not because of the planner
handoff. (A handoff of a GOOD plan is fine; the top result was itself a handoff.) → v2 runs
actual hive. See [[architecture]].

## v2 findings (real hive)

- **Real `/ce-plan` produces reference-quality work.** all-opus-4.8 on add-i-key: a 15-unit
  plan → a 1253–1323-line / 18–20-file diff hitting the same `lib/hive/tui/*` + `test/unit/tui/*`
  + `wiki/*` files as the human PR (which was 1465 lines / 14 files). Judged vs the gold PR:
  **opus 7.5–8.0 / gpt-5.5-pro 4.0**. figure-out-install: **7.0 / 2.0**.
- **The container Bash-tool bug (cost the most debugging).** claude's Bash tool `mkdir`s
  `~/.claude/session-env`; if `.claude` is a read-only bind-mount parent (root-owned), Bash
  dies and the agent **gives up mid-execute** — producing a 78-line stub instead of 1323
  lines. Fix: mount `.claude` as a writable tmpfs with the config bound ro within it.
- **`/ce-plan` scope variance.** Without a human answering the plan's open questions,
  `/ce-plan` is non-deterministic on scope-ambiguous tasks: **2/3 of add-i-key runs honor the
  brainstorm's full panel (~1300 lines, ~7.5–8.0); 1/3 fork to a minimal "Path A" (110 lines,
  1.0).** Maintainer: *"plan usually not ends with open questions if brainstorm is correct"* —
  confirmed (2/3). The brainstorm is the scope authority; the fork is the exception (plausibly
  nudged by the screenshot, which shows the legend bar, not a panel). No variance hack needed.
- **Reference-provided judging works as-is.** `harness/judge.rb` already renders the gold as
  `{{REFERENCE_SECTION}}` — "a SIGNAL, not the answer key" — with an absolute rubric ("does
  this diff accomplish the task," not "how close to the reference"). v2 runs RunAll with
  `withhold_reference: false`.

## Full-cycle smoke (2026-07-02, fix-claude-tmux-ready-detector, fable-5 judge)

First run of the COMPLETE pipeline (plan → execute → open-pr → review) across the
whole slate — every cell generated, reviewed, and scored:

| candidate | fable-5 | wall | est. cost | review |
|---|---|---|---|---|
| all-opus-4.8 | 8.0 (same-family) | 38 min | $11.80 | 2 passes, diff changed |
| all-codex | 7.0 | 16 min | $21.74* | 1 pass, diff unchanged |
| opus-plan→codex-exec | 8.5 (same-family) | 52 min | n/a (mixed) | 2 passes, diff changed |

- **Codex container posture SOLVED**: tmpfs `~/.codex` (identical trap to
  `.claude` — root-owned bind-parent kills the CLI at startup). The codex and
  mixed candidates are now proven paths, closing the oldest v2 gap.
- **Review lift is real and measured**: both claude-planned cells' review passes
  changed the diff (`review_changed_diff`); codex's single pass changed nothing.
- **Prod reviewer set ran as mapped**: claude cells → ce-code-review +
  pr-review-toolkit; codex cell → codex-ce-code-review (plugin constraint).
- *Codex cost caveat: its stream reports 4.2M input tokens with no cache split —
  the $21.74 estimate prices them all uncached and is likely overstated; verify
  codex's usage shape before publishing cost columns.
- gpt-5.5-pro judging pending (OpenRouter top-up), backfill via rejudge.

## Objective gates land (2026-07-09) — plausibility vs observed success, measured

Three tasks now carry held-out-reference-test gates (see corpus/MANIFEST.md).
Run over every existing diff (17 cells, no-network container):
- **fix-tmux (behavioral gate): 6/6 candidates PASS** — every generated diff
  really makes the reference's gem-packaging test pass; the judges' 7-8 scores
  there were measuring real success.
- **fix-review + daemon (interface-strict gates): 0 passes** — the reference's
  unit tests require its internal class names; every candidate architected
  differently, so the tests can't even load. These gates measure conformance
  to the reference's internals, not task success — the external review's
  SWE-bench-limitation warning, demonstrated on our own data. Published with
  nature labels, excluded from rankings. v3's runtime gates (install smoke,
  tmux fixture, state-machine test) are the fix.

## CLI parity gaps closed (2026-07-09)

- **Codex needed an explicit per-cell config.** Mounting the plugin cache was
  not enough; codex had to see a generated `config.toml` that registers the CE
  plugin and trusts `/work`. The same file carries xhigh effort pins for the
  codex-xhigh candidates.
- **Native CE skills matter for review parity.** Codex's own review logs exposed
  that the requested CE skill was not available. The driver now mounts codex's
  plugin cache and pi's CE skill tree read-only, then links them inside each
  CLI's writable home tmpfs before hive stages run.
- **pi and grok model pins are harness-owned.** pi stage shims now inject
  `--model` per stage, closing the earlier glm/kimi ambiguity. Grok is added as
  `all-grok-4.5` with model and xhigh effort pinned through the same shim
  pattern; grok reports no token usage, so cost remains unknown by design.
- **Review is candidate-owned.** The generated review config now derives the
  reviewer set from the candidate's distinct agents, so single-model candidates
  review themselves and mixed claude+codex candidates get the prod-like tri-set.

## FINAL v2 board (2026-07-06) — see RESULTS.md

The campaign closed with 30 cells. Cross-family means: codex 5.2 (fable, 6/6),
glm-5.2 4.0 (gpt, 6/6), kimi-k2.7-code 3.6 (gpt, 5/6), pair 4.0 (gpt, 2/6),
opus 1.0 (gpt, 1/6 — subscription-limited, not capability). Best cells: glm
8.0/9.0 and kimi 8.0/8.5 on fix-tmux. Deliberation verdict across 10 discussed
cells: gpt never revised (0.00), fable revised only downward after verifying
gpt's claims — the strict judge's verdicts survive fact-checking. Full table,
caveats and cost model in RESULTS.md; unresolved holes in [[gaps]].

## First full board (2026-07-04, 6 tasks × 6 candidates, full cycle, judged vs gold)

Scores as gpt-5.5-pro/fable-5 (cross-family first; `?` = judge backfill pending):

| candidate | add-i-key | web-install | install | fix-tmux | fix-review | daemon |
|---|---|---|---|---|---|---|
| all-opus-4.8 | 1.0/1.3* | limit | limit | ?/8.0 | limit | limit |
| all-codex | 4.0/6.0 | 2.0/? | 2.0/? | 7.0/7.0 | 2.0/? | 3.7/5.7 |
| opus-plan→codex-exec | 2.0/2.0 | limit | limit | ?/8.5 | limit | 4.0/? |
| all-glm-5.2 | 4.0/6.2 | 2.0/? | 2.0/? | **8.0**/? | 4.0/? | exec-fail |
| all-kimi-k2.7-code | exec-fail | empty | 2.0/3.7 | 402† | exec-fail | exec-fail |
| glm-plan→kimi-exec | —† | —† | —† | —† | —† | —† |

\* the 1/3 minimal-fork plan variance sample. † lost to the OpenRouter balance
drain (glm's plan agent died on $0 → tasks stuck at 3-plan) — re-run, not model
signal.

**What it says so far:**

- **glm-5.2 is the surprise**: completes the full cycle reliably and posts the
  board's best cross-family score (8.0 on fix-tmux, beating codex's 7.0), at
  ~$13/task vs codex/opus subscription burn. On the scored subset its gpt mean
  (4.0) edges codex (3.4).
- **codex is the workhorse**: only candidate to sweep all 6 tasks — never hit a
  wall, never failed a stage — but scores cluster low-mid (2.0 on the three
  hard tasks).
- **The install-class tasks discriminate** (everything scores 2.0 there);
  fix-tmux separates the field — consistent with v1's "add-i-key saturates,
  install discriminates".
- **Closed-model subscriptions are the real bottleneck**: opus generated ~1
  cell per limit window; 9 of its 11 remaining cells are still pending after
  three windows. The pending/fail-soft machinery carried the whole day — no
  cell was lost or mis-scored to a wall (after the limits_reached classifier
  fix it exposed).
- **kimi-k2.7-code struggles inside hive's harness** (3 execute_failed + 1
  empty_diff *before* the drain) — needs a look at its failure mode before
  reading it as model quality.
- **Full-cycle review costs ~4× bare execute** for pay-per-token models
  (glm: ~49M cache-read tokens/task; $81 for 6 cells) — the subscription
  models hide the same burn.

## v1 findings (the imitation — still informative)

- **The refined plan is worth ~2 gpt-points, robust across agents.** Frozen-plan execution
  beat from-idea self-plan for *every* agent: codex 6.5→4.0, kimi 5.0→3.0. The hard part is
  planning/scoping, not typing.
- **The brainstorm carries the scope, not the idea or the screenshot.** add-i-key's idea is
  one line + a screenshot of the *legend bar*; the full-screen-panel scope lived in the
  brainstorm Q&A. An idea-only planner under-scoped to a footer tweak (185 lines vs the
  1465-line PR) and scored ~1/10. Restoring the brainstorm fixed it.
- **`install` is the discriminating task; `add-i-key` saturates.** Most agents land opus 8.0
  on add-i-key; separation is on figure-out-install (gpt 2.0–5.0). A leaderboard of easy
  tasks looks like a tie.
- **Judge calibration:** opus-4.8 grades generously (6.0–8.5), gpt-5.5-pro strictly (2.0–6.5);
  they **agree on cross-band ordering** (frozen > from-idea), so that ordering is trustworthy.
  Use gpt-5.5-pro as the de-anchored cross-family headline.
- **Cost inverts the intuition.** Priced from tokens at OpenRouter standard (usual, not fast)
  rates: closed frontier models are the *expensive* ones — codex ~$10/task, claude-4.8 ~$7 —
  because they re-read 10–17M *cached* input tokens/task; open models (glm/kimi) are $3.5–4.
  Subscription flat-rate hides this. The CLIs report token counts even on subscription, so
  cost is computable from tokens × rates.

## Hazards / bugs found & fixed

- **New-files capture:** `git diff <base>` dropped untracked files → a candidate that solved a
  task by *adding* files scored ~1.0. Fixed with intent-to-add + diff against base
  (`lib/git_restore.rb`).
- **Vendored-tree bloat:** glm ran `bundle install --path vendor/gems` → a **160k-line** diff
  (1217 gem files) that overflowed both judges (claude judge exited 1). Excludes now cover
  `vendor/gems`, `vendor/cache`, `vendor/bundle`, `.gems`, `node_modules`, `.bundle`.
- **One judge shouldn't lose a cell:** a drained-balance OpenRouter 402 propagated through
  `transform_values` and parked the whole generated cell. RunAll is now **per-judge fail-soft**
  — a limited judge is skipped (backfill later), and a fully-limited cell parks *pending*.
- **Judge output cap:** the gpt-5.5-pro judge left `max_tokens` unset → OpenRouter reserved
  the model's full 65536-token output (~$11.8/call) and tripped 402s. Capped at 32k.
- **Reused-incumbent capture artifact:** claude-4.7's raw-execute range diff
  (`base..execute_base_head`) swept in 166 unrelated files / 22.5k lines of repo-wide history
  on add-i-key — a capture bug, not the agent's work. That cell is excluded; the capture needs
  tightening.

## Scope caveat (true for both generations)

The corpus is Ruby/CLI-weighted from one maintainer's repos, and the v2 cells
now include the review stage by default, but they are still judged against
human-merged reference PRs from the same ecosystem. Absolute numbers mean "full
hive workflow quality on this corpus," not "best coding agent" in general.
Three tasks have curated objective gates; three remain judged-only, and the
current held-out tests show how reference-internal gates can undercount
behaviorally valid alternate implementations.
