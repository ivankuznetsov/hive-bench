# v3 Workflow

`bench` is the user-facing built-in Hive workflow for running one benchmark
campaign per task folder. It drives the same real-hive harness, candidate
profiles, scoring records, and judge provenance used by the maintained public
benchmark. A local campaign can use a smaller matrix, but it does not fall back
to a toy planner/executor or a different scoring path.

## Running a campaign

Use a Hive release that includes the named `bench` workflow, then initialize a
fresh hive-bench clone with that workflow as its project default:

```bash
git clone https://github.com/ivankuznetsov/hive-bench.git
cd hive-bench
bundle install
hive init . --workflow bench
```

The workflow descriptor and stage instructions ship with Hive; do not copy
them into `.hive-state`, and no Honeycomb deployment is required. Create a
campaign task with `hive new hive-bench "benchmark
campaign"` (substitute the project name printed by `hive init` if the clone
directory has another name). Copy and edit `campaign.yml.example` in the task
folder when the extract stage requests it, then commit that file in
`.hive-state`; generate refuses to spend until it is tracked and clean. The
workflow stages are:

```text
1-inbox -> 2-extract -> 3-generate -> 4-judge -> 5-publish -> 6-done
```

The task folder is the campaign boundary. Copy `campaign.yml.example` into that
task folder as `campaign.yml`, edit the campaign id, source clone, tasks,
candidates, exact judge backends/models/effort, judge sample count, budget
declarations, timeout declarations, exclusions, and aggregation prose, then
commit it in the hive-state checkout before generate. The example defaults to
the maintained follow-up methodology: Fable 5 plus GPT-5.6 Sol at `ultra`, with
three independent score samples per judge and cell.

`3-generate` refuses to run if `campaign.yml` is missing, untracked, or dirty.
This keeps the campaign pre-registration immutable before spending on
generation.

Treat the committed `campaign.yml` as frozen once generation has spent
anything: the tracked+clean gate only proves the file matches HEAD, not that
it is unchanged since first spend, so an amended-and-committed campaign passes
it. Amendments silently invalidate the pre-registration. The repair path can
detect a judge record below the configured `seeds` count and replace that
judge's record with a fully sampled one, but changing `seeds` after spending is
still a methodology change rather than a legitimate repair. Shrinking the
matrix strands already-paid cells (judge validation reports them as
`UNEXPECTED_CELL` rather than publishing de-registered cells). Start a new
campaign folder instead of amending one that has spent.

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
  single-line scalar `corpus_version`, an exact judge map with at least two
  enabled backends, exclusion entry shape, at least one non-excluded
  task/candidate cell, and `timeouts.hive_seconds`). It then runs `ruby
  harness/hive_run.rb` once for each non-excluded cell, passing the configured
  judge backend, exact model, Codex reasoning effort, and sample count.
  `HB_HIVE_TIMEOUT`
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
  root file. `--only-missing` also treats legacy or undersampled judge records
  as incomplete, so a three-sample campaign cannot complete with a one-sample
  score. Every judge record persists the individual scores, reasons,
  `sample_count`, interval, model family, and reasoning-effort provenance.
  Judges grade the candidate-generated plan rather than silently substituting
  the frozen reference plan.

  Deliberation writes a scratch transcript which is unioned into
  `deliberation.json` by `[task_id, agent_id]`, preserving paid transcripts on
  a zero-new-cell retry. Its second round explicitly makes each judge argue the
  strongest evidence-based case that its own initial score was wrong before
  choosing a final diagnostic score. Deliberated scores never replace the
  independent leaderboard scores. Both commands search the per-cell run
  directories (`runs/<campaign_id>/*--*`) for artifacts. Validation requires
  every non-excluded matrix cell, the campaign's exact judge slate by name,
  the requested sample count and reasoning effort on every non-`empty_diff`
  cell, matching deliberation coverage, and no `UNEXPECTED_CELL` outside the
  frozen matrix. A soft-failed rejudge's stderr tail is included in the WAITING
  report.
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

## Scheduling, provider walls, and retries

The workflow deliberately does not create its own background runner, rescue
loop, or detached scheduler. Hive owns dispatch, collision avoidance, daemon
reloads, and project concurrency. One campaign task executes its matrix in a
stable serial order; multiple ordinary `bench` tasks may be scheduled in
parallel, subject to Hive's global and per-project limits. For quota sharing,
set the Hive per-project cap to two rather than adding shell-level fan-out.
Never run two tasks against the same `campaign_id`/result root concurrently.

Every stage failure is durable and idempotent: it appends status and ends with
`<!-- WAITING -->`, while already-bought candidate patches, judge scores, and
deliberations are reused on the next dispatch. Hive's installed daemon version
decides whether a particular provider-limit marker is eligible for automatic
cooldown recovery. If that version does not redispatch a generic custom-stage
WAITING marker, touching the current state file (for example `touch
generate.md`) remains the manual edit-resume signal. The benchmark workflow
does not duplicate Hive's retry policy.

When a candidate patch already exists, the generate status directs judge
backfill at the campaign-root `runs/<campaign_id>/results.json`, never at the
per-cell result (rejudge overwrites its output and can otherwise erase the
pending evidence that keeps generation disarmed). A first pass where every
judge walls is recovered by the harness's captured-artifact path; the paid diff
is promoted into a scoreable cell rather than regenerated. See [[architecture]]
for the recovery provenance recorded when original timing or model identity is
not recoverable.

Every retry appends a fresh `## Status` section to the state file;
last-marker-wins keeps the semantics correct, but the file grows across
retries — operators may truncate it to the last `## Status` section at any
time.

## What remains manual

- Author and commit `campaign.yml`.
- Extract new corpus tasks when `2-extract` reports missing slugs.
- Touch the current state file after a provider wall only when the installed
  Hive daemon does not auto-recover that marker.
- Publish any website artifacts after `5-publish`; `assemble/gen-site-data`
  does not exist here today.
- Enforce budgets and effort pins by review. They are pre-registered in
  `campaign.yml`, but current harness flags do not enforce them per run.
  Timeouts are the exception: `timeouts.hive_seconds` is enforced because
  generate exports it as `HB_HIVE_TIMEOUT` for every `hive_run.rb` invocation.

Retry policy and the packaged workflow belong in Hive. Keep its stage
instructions limited to durable WAITING/COMPLETE markers and idempotent
benchmark operations; changes to cooldown classification or redispatch should
be proposed and tested in the Hive repository so every workflow benefits.

## Smoke

Run:

```bash
tmp/bench-workflow-smoke.sh
```

The smoke is no-cost. It loads Hive's built-in `bench` descriptor, verifies its
packaged instructions, initializes a throwaway project with
`--workflow bench`, proves no project-local workflow copy was created, and
advances a throwaway task through all six stages with
`Hive::Commands::Approve`. Stage scripts are extracted from Hive by the
`<!-- bench-stage-script -->` marker. Every run gets a fake `$HOME`, and the
duplicated campaign-id validation lines are diffed across generate, judge, and
publish to catch drift.

Failure-path fixtures cover missing/untracked/dirty/malformed campaigns,
repo-root misanchors, extract missing-source and missing-slug paths,
judge/publish missing-results and malformed-campaign paths, provider walls,
nonzero command exits with bounded stderr, grok runner-image selection,
contradictory terminal results, and judge `MISSING_CELL`, named
`MISSING_JUDGES`, `UNDERSAMPLED_JUDGE`, reasoning-effort mismatches,
`UNEXPECTED_CELL`, and pending guards.

Success fixtures drive extract, generate, judge, and publish to
`<!-- COMPLETE -->`. Generate uses a success-shaped `hive_run.rb` stub and the
real `merge_results.rb`; judge stubs rejudge/deliberate while exercising slate
validation and the deliberation union; publish renders the real summary. The
never-re-buy guard is asserted by invocation count for terminal,
`pending[]`+patch, and `failed[]`+patch states. A campaign derived from
`campaign.yml.example` is also passed through the real generate validator at a
real-root-shaped fixture, and scratch cleanup is checked for every stage.

This remains fixture coverage: it does not run a paid campaign. Set
`HIVE_SRC` to the Hive checkout whose packaged workflow should be tested.
