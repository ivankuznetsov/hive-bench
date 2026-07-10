# v3 Workflow

`bench` is a hive custom workflow for running one benchmark campaign per task
folder. It is pure orchestration around the existing harness scripts; it does
not change scoring, judging, generation, or merge semantics.

## Running a campaign

Install the workflow descriptor into hive-state:

```bash
mkdir -p .hive-state/workflows
cp -R workflows/bench.yml workflows/bench .hive-state/workflows/
```

Create or move a task into the `bench` workflow by setting task meta
`workflow: bench`. The workflow stages are:

```text
1-inbox -> 2-extract -> 3-generate -> 4-judge -> 5-publish -> 6-done
```

The task folder is the campaign boundary. Copy `campaign.yml.example` into that
task folder as `campaign.yml`, edit the campaign id, source clone, tasks,
candidates, seeds, budget declarations, timeout declarations, exclusions, and
aggregation prose, then commit it in the hive-state checkout before generate.

`3-generate` refuses to run if `campaign.yml` is missing, untracked, or dirty.
This keeps the campaign pre-registration immutable before spending on
generation.

Treat the committed `campaign.yml` as frozen once generation has spent
anything: the tracked+clean gate only proves the file matches HEAD, not that
it is unchanged since first spend, so an amended-and-committed campaign passes
it. Amendments silently invalidate the pre-registration — raising `seeds`
after generation is not retroactive (`rejudge --only-missing` skips judges
that already have scores, so existing cells retain their earlier seed count),
and shrinking the matrix strands already-paid cells (judge validation reports
them as `UNEXPECTED_CELL` rather than publishing de-registered cells). Start a
new campaign folder instead of amending one that has spent.

The workflow stage files contain marker-anchored bash blocks. Every stage
instruction requires its block to be executed verbatim: the guards and single
terminal `<!-- WAITING -->` / `<!-- COMPLETE -->` marker are part of the stage
contract, not prose for an agent to reimplement.

## Stage behavior

- `2-extract` requires the same non-empty, single-line `source` contract as
  generate (there is no silent `.` default that could validate the corpus
  against the wrong checkout), checks that every `tasks[]` slug has
  `corpus/<slug>/manifest.yml`, and loads them through `HiveBench::Corpus`. It
  reports missing slugs and parks; it does not guess source PR coordinates for
  `harness/extract.rb`.
- `3-generate` validates the committed campaign contract (required keys, strict
  `campaign_id` slug — it becomes the `runs/<campaign_id>` path segment — with
  the unedited `v3-example` id rejected, non-empty single-line `source`,
  single-line scalar `corpus_version`, exclusion entry shape, at least one
  non-excluded task/candidate cell, and `timeouts.hive_seconds`). It then runs
  `ruby harness/hive_run.rb` once for each non-excluded cell. `HB_HIVE_TIMEOUT`
  comes from the pre-registered timeout (use the required `timeouts: {}` form
  to retain harness defaults; removing the key parks at WAITING); the grok
  runner image is keyed on the candidate profile's `grok_model` field.
  A cell is treated as already bought if its per-cell result is terminal
  (`generated`/`empty_diff`) or if any `target/candidate.patch` exists, even
  when the result is missing or parked in `pending[]`, `failed[]`, or a
  non-terminal `cells[]` record. An unreadable existing result also fails
  closed. Captured-diff states are reported as `judges_pending` and are never
  regenerated unless the operator deliberately removes the cell directory,
  because the hive driver starts a rerun by deleting the paid work tree.
  Completion is stricter than the re-buy guard: every per-cell result must be
  terminal with both `pending[]` and `failed[]` empty. Harness commands run
  under non-login `bash -c`; bounded stderr tails are folded into a WAITING
  status when commands fail. Once the matrix is clean, the stage merges an
  existing campaign-root result first and the per-cell results second, which
  preserves root-only rejudge scores while keeping per-cell run/gate data
  authoritative. It writes `runs/<campaign_id>/results.json.next` and renames
  it over `results.json` only after a successful merge, so the campaign-root
  handoff consumed by `4-judge` and `5-publish` is not truncated mid-write.
- `4-judge` extracts campaign fields in one guarded, type-checked ruby block (a
  malformed campaign or multi-line `source` parks WAITING instead of dying
  marker-less or misaligning the extraction), and sources
  `~/.openrouter_key` without letting an empty file clobber a valid environment
  key. It checks `pending[]`/`failed[]` before rejudging because rejudge output
  does not carry those keys. Rejudge writes `results.json.next` and renames it
  over the campaign root only on success; backfilled scores exist only in that
  root file. Deliberation writes a scratch transcript which is unioned into
  `deliberation.json` by `[task_id, agent_id]`, preserving paid transcripts on
  a zero-new-cell retry. Both commands search the per-cell run directories
  (`runs/<campaign_id>/*--*`) for artifacts. Validation requires every
  non-excluded matrix cell, the exact judge slate by name (`fable-5` and
  `gpt-5.5-pro`) on every non-`empty_diff` cell, deliberation coverage for each
  dual-judged cell, and no `UNEXPECTED_CELL` outside the frozen matrix. A
  soft-failed rejudge's stderr tail is included in the WAITING report.
- `5-publish` extracts fields with the same guarded, type-checked pattern,
  merges the campaign root through `results.json.next` plus rename, and renders
  the leaderboard summary to a scratch file first. A render or final state-file
  append failure parks WAITING rather than stranding a half-written table with
  no marker. An empty `agents` map refuses to publish. The summary covers cells,
  cross-family judge means, judged-cell count, gate pass rate, fresh/reused
  provenance, and total cost. There is no site generator in this repo yet.

All four stages clean up their scratch files (`.extract-*`, `.generate-*`,
`.judge-*`, `.publish-*`) on exit, so nothing untracked leaks into hive-state
residual commits.

Each instruction anchors from the task folder to the repo root with
`REPO_ROOT="$(cd ../../../.. && pwd)"`. Do not replace that with
`git rev-parse`; task folders live under `.hive-state`, which is its own git
checkout in normal hive operation. All four scripts now define marker helpers
before guarding that substitution, so an anchor failure parks with WAITING.

## Provider walls and retries

Hive does not automatically redispatch an agent stage parked at `WAITING`.
The v3 retry contract is explicit marker discipline:

1. A stage writes status and ends with `<!-- WAITING -->`.
2. The operator, cron, or another babysitter waits for the provider wall to
   cool down.
3. Retry by touching the current stage state file, for example
   `touch generate.md`.

The daemon's edit-resume policy sees the state file mtime change after its
debounce window and may dispatch the stage again. Automatic cooldown retry is a
hive-side feature request, not part of hive-bench v3.

When a candidate patch already exists, the generate status directs judge
backfill at the campaign-root `runs/<campaign_id>/results.json`, never at the
per-cell result (rejudge overwrites its output and can otherwise erase the
pending evidence that keeps generation disarmed). A first pass where every
judge walls can still leave a paid patch in a per-cell `cells: []` plus
`pending[]` result and park before the campaign-root merge. Rejudge consumes
only recorded `cells`, so this recovery remains unresolved; see [[gaps]].

Every retry appends a fresh `## Status` section to the state file;
last-marker-wins keeps the semantics correct, but the file grows across
retries — operators may truncate it to the last `## Status` section at any
time.

## What remains manual

- Author and commit `campaign.yml`.
- Extract new corpus tasks when `2-extract` reports missing slugs.
- Touch the current state file after provider walls cool down.
- Publish any website artifacts after `5-publish`; `assemble/gen-site-data`
  does not exist here today.
- Enforce budgets and effort pins by review. They are pre-registered in
  `campaign.yml`, but current harness flags do not enforce them per run.
  Timeouts are the exception: `timeouts.hive_seconds` is enforced because
  generate exports it as `HB_HIVE_TIMEOUT` for every `hive_run.rb` invocation.

The related hive-side ask for automatic cooldown retry should follow the same
feature-request pattern as the sibling hive task
`per-stage-claude-model-config-260709-35f7`: file it in hive, keep
hive-bench's workflow descriptor simple, and continue using WAITING plus
edit-resume until hive owns the retry policy.

## Smoke

Run:

```bash
tmp/bench-workflow-smoke.sh
```

The smoke is no-cost. It parses both descriptor copies through hive's real
`Hive::Workflows::DescriptorParser` (asserting the broken-descriptor rejection
is the nested-state-file rule, not an unrelated load error), verifies the
installed workflow matches the canonical copy, and advances a throwaway task
through all six stages with `Hive::Commands::Approve`. Stage scripts are
extracted by the `<!-- bench-stage-script -->` marker. Every run gets a fake
`$HOME`, and the duplicated campaign-id validation lines are diffed across
generate, judge, and publish to catch drift.

Failure-path fixtures cover missing/untracked/dirty/malformed campaigns,
repo-root misanchors, extract missing-source and missing-slug paths,
judge/publish missing-results and malformed-campaign paths, provider walls,
nonzero command exits with bounded stderr, grok runner-image selection,
contradictory terminal results, and judge `MISSING_CELL`, named
`MISSING_JUDGES`, `UNEXPECTED_CELL`, and pending guards.

Success fixtures drive extract, generate, judge, and publish to
`<!-- COMPLETE -->`. Generate uses a success-shaped `hive_run.rb` stub and the
real `merge_results.rb`; judge stubs rejudge/deliberate while exercising slate
validation and the deliberation union; publish renders the real summary. The
never-re-buy guard is asserted by invocation count for terminal,
`pending[]`+patch, and `failed[]`+patch states. A campaign derived from
`campaign.yml.example` is also passed through the real generate validator at a
real-root-shaped fixture, and scratch cleanup is checked for every stage.

This remains fixture coverage: it does not run a paid campaign, and it does not
turn a first-pass `cells: []` plus captured patch into a rejudgeable root cell.
The parser smoke requires `hive` before loading the descriptor parser, matching
the real gem load path.
