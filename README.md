# hive-bench

**A benchmark for the question: which coding agent best executes a hive-style plan?**

`hive-bench` replays real, completed [hive](https://github.com/ivankuznetsov/hive)
tasks against candidate coding agents (`harness@model` — Claude Code, Codex CLI,
Pi running open models) and scores them on an objective test gate, a blind LLM
judge, and efficiency. It is the implementer-side sibling of
[`agent-reviewer-eval`](https://github.com/ivankuznetsov/agent-reviewer-eval),
which benchmarks *reviewers*; this one benchmarks *implementers*.

## The scoped claim (read this first)

The corpus is drawn from one maintainer's repos and is **Ruby/CLI-weighted**, and
every task is replayed **from a frozen plan** that was authored mostly by the
incumbent agents. So the honest headline is **"best executor of a frozen,
hive-style plan on this corpus"** — not "best coding agent" in general. The
leaderboard publishes the corpus distribution, per-task plan-authorship, and an
incumbent-anchoring ablation so you can see exactly what the number means. See
[the methodology](#) (published with the leaderboard).

## Integrity model

Like its sibling, integrity here is **structural, not requested**:

- The candidate agent sees only the **frozen spec** (`idea` + `brainstorm` +
  `plan`). It never sees the reference solution (`reference.patch`) or the
  grading tests — they are held out of the agent-visible inputs.
- Candidate execution and the test gate run in an **isolated, no-network,
  resource-capped container**, with git hardened against hostile-repo
  `.git/config` code execution. A candidate cannot fetch the answer key.
- The judge is **blind** (identities stripped, length-normalized) and from a
  model **family disjoint from every contestant**.
- The harness **fails closed**: a score is never published from a run whose
  isolation could not be enforced.

## How scoring works

Three tiers, per `(task, agent)` cell:

1. **Gate** (hard pass/fail floor) — the candidate's diff must build and flip the
   task's `FAIL_TO_PASS` tests while keeping `PASS_TO_PASS` green. Tasks with no
   runnable gate fall into a separate **judged** subset.
2. **Judge** — a blind, family-disjoint LLM scores passing diffs on an absolute
   rubric, using the reference and plan as *signals* (not "closest wins"), across
   several seeds → a stability interval.
3. **Efficiency** — cost ($), review/CI fix-passes, and wall-clock (measured on
   fresh runs only).

## Layout

    corpus/<task-id>/        one frozen, reproducible task instance
    harness/                 extract, run, gate, judge, score
    harness/profiles/        model-pinned agent definitions for the slate
    validator/               reproducibility + secret-scan CI for submissions
    leaderboard/             results.json -> public /bench table

## Status

Pre-1.0, under construction. Built from the plan in `hive-private`.
