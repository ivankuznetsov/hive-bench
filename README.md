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

- The candidate agent sees only the **frozen task inputs** (`idea` +
  `brainstorm` + `plan`). It is never handed the reference solution
  (`reference.patch`) or the grading tests — they are held out of the
  agent-visible inputs.
- The **test gate** runs in an isolated, `--network none`, resource-capped
  container, with git hardened against hostile-repo `.git/config` code
  execution — and it requires every gate test to be **positively observed**
  in the run (verbose per-test output): a test that never executed is never
  scored as a pass.
- **Generation** needs model-API egress, so it cannot run `--network none`.
  The container is resource-capped; an egress-allowlisted docker network can
  be attached via `HB_GEN_NETWORK`, and every cell is **scanned for
  answer-key access** (the public reference PR) — a flagged cell is invalid
  until adjudicated. Until an egress proxy is standing, that scan is
  detection, not prevention; stated here so the guarantee is never overstated.
- Judging is **blind** (identities stripped, length-normalized) and **dual**
  (opus-4.8 + gpt-5.5-pro). Full judge/contestant family-disjointness is
  impossible when both judge families also compete, so every judge score
  carries a `same_family` flag and the headline aggregate
  (`mean_quality_cross_family`) uses cross-family scores only.
- The harness **fails closed** where isolation is enforceable, and flags
  loudly where it is not: a score is never published from a run whose posture
  is unknown.

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

## Running a pass

    ruby harness/preflight.rb              # confirm the slate is installed + authed
    docker build -f Dockerfile.runner -t hive-bench-runner:latest .   # one-time

    # corpus x slate -> runs/results.json. Generation runs each candidate inside
    # the isolated runner; the blind judge is the local claude CLI.
    OPENROUTER_API_KEY=sk-or-... \
      ruby harness/run_all.rb --source <local-clone-of-source-repo> [--agent pi@glm-5.2]

Runner knobs (env): `HB_AGENT_TIMEOUT` (per-cell seconds, default 7200 — slower
open models need the room), `HB_RUNNER_IMAGE` (default `hive-bench-runner:latest`),
`HB_CPUS`/`HB_MEMORY`/`HB_PIDS` (container caps, default 8 / 16g / 4096). A cell
whose agent runs past the ceiling is recorded `run_status: timed_out` (its partial
diff is still judged, but it is never counted as a clean completion). The driver
exits `2` if any cell could not be isolated, `1` on a usage/validation error, `0`
otherwise (pending provider-limit cells are not an error).

`--source` is a local clone restored at each task's `base_commit` (offline, so a
hostile repo never runs code on the host). `--agent` narrows the slate to one
cell — currently only the `pi@…` open-model cells have a wired generation path,
so `--agent pi@glm-5.2` is the verified invocation; the `claude@…`/`codex@…`
cells (fresh generation and recorded-cell reuse) are not wired yet and are
parked as `failed` if a pass reaches them. A pass scores each fresh cell via the
gate + blind judge and writes `runs/results.json`. Cells that hit a provider
limit (including an OpenRouter `402 Insufficient credits`) are recorded
`pending` for re-run, never scored as failures; cells whose isolation could not
be enforced are parked as `failed`, never scored.

## Status

Pre-1.0, under construction. Built from the plan in `hive-private`.
