# decision-bench: decision models on Hive's own decisions

[Hive](https://github.com/ivankuznetsov/hive) makes many small judgment calls between
agent runs. Is this red CI the diff's fault? Is this patrol finding a duplicate? Does
this plan need mandatory review? Today a regex, a token-overlap heuristic or a full LLM
agent pass makes each one.

`decision-bench` replays 4,644 of those past decisions from one owner's Hive history
against two *decision-model* APIs:

- **OpenAI Decisions** (`gpt-6-luna`);
- **TypeSafe Jev** (`jev-1.14.0`).

Both answer typed questions about a JSON state: a yes/no probability, a choice or a score.
Each answer is scored against what Hive decided, what happened later, and a gold set
labelled by two annotators.

This directory is independent of the implementer benchmark in the rest of the
repository: plain Python, no Docker, two HTTP APIs.

## Headline results

Test split, accuracy against gold. Gold means cases where two independent annotators gave
the same label (see [Labels](#labels)). The incumbent is Hive's own regex or heuristic.

| point | incumbent | n | incumbent | OpenAI direct | OpenAI decomposed | Jev direct | Jev decomposed |
|---|---|---|---|---|---|---|---|
| ci_failure_triage | heuristic/regex | 43 | 0.605 | 0.954 | 0.698 | 0.837 | 0.767 |
| patrol_finding_dedup | heuristic | 63 | 0.714 | 0.968 | 0.936 | 1.000 | 0.984 |
| plan_review_level | regex | 31 | 0.548 | 0.903 | 1.000 | 0.903 | 0.806 |
| provider_failure_class | regex | 64 | 0.656 | 0.891 | 0.969 | 0.953 | 0.891 |
| recovery_same_root | heuristic | 46 | 0.891 | 0.978 | 1.000 | 0.957 | 0.935 |
| refactor_merge_classifier | regex | 51 | 0.784 | 0.863 | 0.863 | 0.941 | 0.922 |
| task_workflow_routing | none (always `full`) | 26 | 0.423 | 0.808 | 0.538 | 0.846 | 0.346 |
| visual_capture_need | regex | 58 | 0.483 | 0.966 | 0.603 | 0.983 | 0.793 |
| **pooled** | | 382 | 0.654 | 0.924 | 0.840 | 0.940 | 0.843 |

- **Gold points.** Both models beat the regex/heuristic incumbent on all 8 points that
  have gold. Paired over the 382 cases, each direct model fixes 118 incumbent errors and
  introduces 15 (OpenAI) or 9 (Jev).
- **LLM steps.** The models do not beat the decisions Hive already makes with an LLM.
  - review_finding_triage, against the outcome label: incumbent 0.981, models
    0.686–0.814. That outcome is partly downstream of the incumbent's own choice.
  - plan_review_decision_triage: nobody predicts the operator's later decision; every
    system scores about 0.45.
- **Direct beats decomposed** (one question, against atomic questions combined by a
  rule): 0.924 vs 0.840 on OpenAI and 0.940 vs 0.843 on Jev.
- **OpenAI vs Jev.** Accuracy is a tie: on 13 cases only OpenAI is right, on 19 only Jev.
  Jev costs about half as much ($0.21 vs $0.42 per 1,000 direct rows at list price) and
  has a tighter latency tail (p95 284 ms vs 401 ms; p50 183 vs 168 ms).

Full tables, per-point results against every label, decisive-subset coverage and
examples are in [`results/SUMMARY.md`](results/SUMMARY.md). The headline findings with
their caveats are in [`results/headline_findings.md`](results/headline_findings.md).

## The decision points

The decomposed variant of every point asks 4–9 questions. In the table below, `cases`
is test/dev and `gold` is Claude∩Neon.

| point | the decision in Hive | incumbent | cases | labels beyond `system` |
|---|---|---|---|---|
| `ci_failure_triage` | Before spawning a CI fixer: is the red CI caused by the diff, flaky infra, the account/billing, a merge conflict, or unknown? | heuristic + billing regex (Hive spawns a fixer for most red CI) | 117 / 39 | outcome 40, adjudicated 78, gold 59 |
| `patrol_finding_dedup` | Is a new Patrol finding the same issue as an earlier known one? | token-overlap heuristic | 553 / 136 | adjudicated 77, gold 75 |
| `patrol_fix_semantic_admission` | Does an accepted Patrol finding share a root with an open Patrol Fix task (`same_root:<task>`), is it `distinct`, or is there `insufficient_evidence`? | LLM | 113 / 27 | none |
| `plan_review_decision_triage` | May the planner apply a reviewer's plan correction on its own (`auto_apply`), or must it wait for the owner (`keep_gate`)? | LLM | 580 / 148 | outcome 417 (operator's later decision) |
| `plan_review_level` | Does a plan need `skip`, `standard` or `mandatory` plan review? | regex classifier | 325 / 73 | outcome 291, adjudicated 44, gold 38 |
| `provider_failure_class` | What ended an agent run: quota, rate limit, unsupported model, auth, network, crash, merge conflict, tool denial, or nothing wrong? | regex tables | 476 / 138 | outcome 614 (retry fate, not a class), adjudicated 82, gold 80 |
| `recovery_same_root` | In daemon recovery, is this failure the same root failure as the previous attempt? | fingerprint equality | 468 / 109 | outcome 416, adjudicated 63, gold 63 |
| `refactor_merge_classifier` | Is a merged PR a `feature` (it gets an Architecture Patrol intake) or `skip`? | regex prefilter, then LLM | 274 / 69 | outcome 29, adjudicated 73, gold 64 |
| `review_finding_triage` | For each code-review finding: `auto_fix`, `resolved_no_fix`, `escalate` or `deferred`? | LLM triage agent | 480 / 125 | outcome 325 |
| `task_workflow_routing` | At intake, should a coding task run an `express`, `standard` or `full` workflow? Hive does not route today. | none: every task runs `full` | 94 / 28 | outcome 122 (hindsight), adjudicated 58, gold 35 |
| `visual_capture_need` | Does a change have a user-visible effect that needs screenshots or a recording? | path regex | 218 / 54 | outcome 10, adjudicated 73, gold 70, `llm_inference` 59 |

## How the rows were built

Each case is one past decision, rebuilt from Hive's local state:

- task directories (idea, plan, review files, escalations, closure);
- per-task event logs and agent run logs;
- CI logs from GitHub Actions;
- Patrol's admission and classification records.

The cases span Hive itself and the owner's other projects. That is 3 to 18 projects per
point, and Hive itself supplies 34–90% of cases. The decision's inputs are frozen into a
JSON `state` with named fields, so the state carries only what the decision needs.
Builders reconstructed what Hive's step saw where they could. In some points the state
differs from it; for example, plan triage sees the finding plus a plan excerpt, not the
whole repository.

Each case comes in two variants (`#direct` and `#decomposed` ids):

- **direct** asks Hive's decision as one question;
- **decomposed** asks 4–9 atomic, observable questions. That point's `rule.py` turns
  the answers into a verdict. It uses bands: yes ≥ 0.7, no ≤ 0.3, and anything between
  is unsettled. Depending on the point, an unsettled answer becomes an abstention or a
  conservative default.

Questions are identical across the rows of a point. 20% of cases are `dev`, used for
wording iterations; the other 80% are `test`, and every number above is test. Large
populations were stratified-sampled to stay under 1,500 rows per point. The row format
is in [`FORMAT.md`](FORMAT.md) (Revision 2).

Sanitization before publication:

- **Scanning.** A secret and PII scan plus a manual reading pass. Tokens, internal
  hosts, IPs, emails and account names were redacted.
- **Dropped rows.** Rows were dropped where they held exploit-level detail of live
  private products or third-party confidential material.
- **Excluded projects.** One project holding personal data was excluded entirely.
  Rows from one unreleased product were excluded at the owner's request.
- **Withheld security findings.** 324 rows (162 cases) that describe a security
  weakness in one of the owner's live private products were withheld after the run; see
  [Caveats](#caveats). Hive's own security findings stay: Hive is open source.

## Labels

Every row carries `labels.system`. Each other label exists only where the table above
says so.

- **`system`**: what Hive decided, either recorded or replayed from its regex/heuristic.
  It is the *incumbent* that a decision model would replace.
- **`outcome`**: what later evidence says was right. Examples: the fixer's commit
  turned CI green; a retry succeeded with no config change; the operator approved the
  correction. It is a proxy and sometimes circular; `results/SUMMARY.md` notes each case.
- **`adjudicated`**: Claude labelled 44–82 cases per point after reading the full
  context. The sample was stratified toward suspected incumbent misfires. 8 points have
  it.
- **gold (Claude∩Neon)**: Gemini 4 Neon (`gemini-4-neon`, via OpenCode) labelled the same
  548 adjudicated cases blind. It saw only the state and the direct question, never the
  labels. They agree on 484 cases, which form the gold set in `annotations/gold.jsonl`.
  Agreement per point is in `annotations/agreement.json` (overall 88.3%, mean κ 0.79;
  lowest task_workflow_routing at 60.3%, κ 0.39). The 64 disagreements are listed in
  `annotations/disagreements.md` and await the owner's tie-break. They are not in gold.
- **`llm_inference`** (visual_capture_need only): a second LLM label from Hive's
  artifacts.

## Running it

```sh
cd decision-bench
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt   # openai SDK; Jev uses urllib
export OPENAI_API_KEY=...      # OpenAI Decisions
export TYPESAFE_API_KEY=...    # TypeSafe Jev

.venv/bin/python probe.py jev            # one synthetic two-question call; prints the response shape
.venv/bin/python run_decisions.py run --point ci_failure_triage --provider jev \
    --split test --max-usd 1 --results-dir runs/mine      # fresh calls go to runs/mine/<point>/
.venv/bin/python run_decisions.py run --point ci_failure_triage --provider openai \
    --split test --dry-run                                 # print one payload, send nothing
python3 results/summarize.py --findings results/headline_findings.md   # rescore the published results
```

- **Keys** are read from the environment and never written or printed.
- **Caching.** The published `results/<point>/results-<provider>.jsonl` are the runner's
  cache. A row whose latest record has no error is never sent again, so pass
  `--results-dir` to make fresh calls. `summarize.py --caches runs/mine` imports such a
  run into `results/`, replacing the published files; git restores them.
- **Datasets** are `xz`-compressed and read as they are. If you decompress one
  (`xz -dk`), the runner prefers the plain `dataset.jsonl`.
- **Cost.** A full run of both variants, both splits and all points billed about $4.2 on
  OpenAI and $2.1 on Jev at November 2026 list prices. The runner estimates cost before
  sending, stops at `--max-usd`, and records every call's tokens and cost.
- **Provider quirks.** The runner handles three.
  - Jev's per-question limit is 32k tokens. Larger states get its long-context header.
  - OpenAI's predicates take no criteria, so the yes/no criteria are folded into the
    instructions.
  - OpenAI rejects a choice question with a single option. Such a question is answered
    locally as forced, which is what Jev returns.

## Layout

    README.md, FORMAT.md        this file; the shared row format
    .gitignore                  ignores .venv/, runs/, decompressed datasets
    run_decisions.py, probe.py  the runner; a one-call shape probe
    requirements.txt            the openai SDK (tested with 3.57)
    <point>/dataset.jsonl.xz    the rows, both variants (11 points)
    <point>/rule.py             verdict rule for the decomposed variant
    results/SUMMARY.md          every table; headline_findings.md is its top section
    results/summarize.py        scoring (its docstring lists how it differs from the runner's `report`)
    results/<point>/            results-{openai,jev}.jsonl (one record per call), report-{openai,jev}.json
    results/billing.json        billed totals, including calls on rows excluded after they ran
    annotations/                gold.jsonl, neon_labels.jsonl, agreement.json, disagreements.md

## What changed for publication

- **`request` stripped.** Each result record lost its `request` field, the exact
  payload. It can be rebuilt from the dataset with the runner's payload builders, and
  `--dry-run` prints one. Everything else in each record is kept: the raw response,
  normalized answers, verdict, latency, tokens and cost.
- **Excluded and withheld rows.** The calls already made on the unreleased product's
  rows (76 rows per provider) and on the 324 withheld security-finding rows are counted
  in `billing.json` and in nothing else: 400 rows per provider in all.
- **Post-run redactions**, applied identically to datasets, results and annotations:
  - one production server IP became `[REDACTED:ip]`;
  - the unreleased product's name became `[PRODUCT]`;
  - one company name became `[COMPANY]`;
  - a third party's unreleased product name became `[THIRD-PARTY PRODUCT]`.

  50 of the 9,288 rows have a changed `state`; questions and labels did not change. The
  scores come from the states the models actually saw, so rerunning those rows can give
  slightly different answers.

## Caveats

- **Single owner.** Every case comes from one person's projects and one way of working,
  and Hive itself dominates most points. Nothing here measures other teams' traffic.
- **Security findings in private products were withheld.** 324 rows (162 cases) whose
  content describes a security weakness in one of four live private products were
  withheld after the run. That covers auth, token and secret handling, injection and
  XSS, access control, rate-limit bypass, data exposure and insecure defaults, whether
  the weakness is the row's subject or appears in its context (for example, another
  finding from the same review pass). Most come from review_finding_triage (160 rows)
  and patrol_finding_dedup (82). Generic code-quality and reliability findings in those
  products stay. Every number here is computed without the withheld rows: the gold test
  set lost 10 cases, so it is 382 rather than 392.
- **task_workflow_routing is labelled in hindsight.** Hive does not route tasks today,
  so the incumbent is always `full`. The outcome is a hindsight proxy for the lightest
  workflow that would have sufficed. The state is only what was known at intake, so
  expect a ceiling, and this point has the weakest gold (annotators agree 60%).
- **The hand-labelled sample is weighted toward misfires.** Adjudication was stratified
  toward cases where the incumbent was suspected wrong. The incumbent's gold accuracy
  shows its hard cases, not its everyday error rate, and the model-vs-incumbent gap is
  not a production estimate.
- **Gold sets are small**: 26–64 test cases per point. A gap of a few cases is noise;
  the paired counts in the headline matter more than the third decimal.
- **The annotators are LLMs**: a Claude first pass, then blind Gemini 4 Neon. Errors
  they share would flatter the decision models against the regex.
- **Some outcomes are proxies**:
  - review_finding_triage's outcome partly follows from the incumbent's own label;
  - recovery_same_root's outcome measures whether retrying was pointless;
  - plan_review_level's outcome comes from adversarial reviews that flag nearly
    everything.
- **plan_review_level's adjudicated level was derived through its own `rule.py`**,
  which favours the decomposed variant on that point.
- **Snapshot.** Models are pinned (`gpt-6-luna`, `jev-1.14.0`) and prices are November
  2026 list prices. Latency is wall-clock at one client with 8 concurrent requests.
