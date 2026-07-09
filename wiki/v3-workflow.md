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

## Stage behavior

- `2-extract` checks that every `tasks[]` slug has `corpus/<slug>/manifest.yml`
  and loads through `HiveBench::Corpus`. It reports missing slugs and parks;
  it does not guess source PR coordinates for `harness/extract.rb`.
- `3-generate` validates the committed campaign contract, then runs
  `ruby harness/hive_run.rb` once for each non-excluded task/candidate cell.
  If a harness command exits nonzero, the stage records that fact and still
  inspects every per-cell result at
  `runs/<campaign_id>/<candidate>--<task>/results.json`; only cells whose
  `run_status` is not `generated` or `empty_diff`, or whose result file is
  missing, park the stage at WAITING. It does not currently write the
  campaign-root `runs/<campaign_id>/results.json`. Existing harness reuse makes
  reruns idempotent for already-scored cells.
- `4-judge` runs `harness/rejudge.rb --only-missing` and then
  `harness/deliberate.rb` for the campaign result file at
  `runs/<campaign_id>/results.json`; if that file is absent, the stage parks
  before judging. The handoff from generated per-cell files into this
  campaign-level file still needs a real campaign smoke or an explicit merge
  step; the workflow sources for v3-bench-as-hive-workflow-260709-b3nc do not
  currently show that merge.
- `5-publish` runs `harness/merge_results.rb` and writes a leaderboard summary
  into `publish.md` from the merged `agents` schema: cells, cross-family judge
  means, judged-cell count, gate pass rate, fresh/reused provenance, and total
  cost. There is no site generator in this repo yet.

Each instruction anchors from the task folder to the repo root with
`REPO_ROOT="$(cd ../../../.. && pwd)"`. Do not replace that with
`git rev-parse`; task folders live under `.hive-state`, which is its own git
checkout in normal hive operation.

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

## What remains manual

- Author and commit `campaign.yml`.
- Extract new corpus tasks when `2-extract` reports missing slugs.
- Touch the current state file after provider walls cool down.
- Publish any website artifacts after `5-publish`; `assemble/gen-site-data`
  does not exist here today.
- Enforce budgets, timeouts, and effort pins by review. They are
  pre-registered in `campaign.yml`, but current harness flags do not enforce
  them per run.

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
`Hive::Workflows::DescriptorParser`, verifies the installed copy matches the
canonical copy, validates `campaign.yml.example` against current candidates and
corpus, advances a throwaway task through all six stages with
`Hive::Commands::Approve`, and checks the generate-stage missing-campaign gate.
The parser smoke requires `hive` before loading the descriptor parser, matching
the real gem load path.
