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

The corpus is Ruby/CLI-weighted from one maintainer's repos, and scores are **raw execute
output** (no review stage) judged against a *post-review* merged PR. So absolute numbers are
"first-pass quality," and rankings are "best on this corpus," not "best agent." The review
stage (next phase) would lift everyone toward "mergeable."
