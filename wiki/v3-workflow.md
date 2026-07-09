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
- `3-generate` validates the committed campaign contract (required keys, strict
  `campaign_id` slug — it becomes the `runs/<campaign_id>` path segment — with
  the unedited `v3-example` id rejected, exclusion entry shape, and
  `timeouts.hive_seconds`), then runs `ruby harness/hive_run.rb` once for each
  non-excluded task/candidate cell. `HB_HIVE_TIMEOUT` comes from the
  pre-registered `timeouts.hive_seconds` (harness defaults apply when unset);
  the grok runner image is keyed on the candidate profile's `grok_model`
  field. A cell is never re-bought once its per-cell results.json shows
  `generated`/`empty_diff`, once the file exists but does not parse (fail
  closed: a truncated file must not read as "never ran"), or once a diff was
  captured but every judge walled (`pending[]` + `target/candidate.patch`) —
  that last state is reported as `judges_pending` for rejudge backfill, never
  regenerated (the hive driver would rm-rf the paid work tree). If a harness
  command exits nonzero, the stage folds that note into the status and still
  inspects every per-cell result at
  `runs/<campaign_id>/<candidate>--<task>/results.json`, reporting unfinished
  cells with their `pending[]`/`failed[]` reasons. When every cell is
  `generated`/`empty_diff`, the stage merges all per-cell files into
  `runs/<campaign_id>/results.json` via `harness/merge_results.rb` — the
  handoff `4-judge` and `5-publish` consume.
- `4-judge` extracts campaign fields in one guarded ruby block (a malformed
  campaign.yml parks WAITING instead of dying marker-less), sources
  `~/.openrouter_key` like generate, then runs `harness/rejudge.rb
  --only-missing` and `harness/deliberate.rb --min-disagreement 0 --skip-done`
  (wall retries never re-buy deliberated cells) with the PER-CELL run dirs
  (`runs/<campaign_id>/*--*`) as artifact search dirs — rejudge resolves
  artifacts at `<search-dir>/<task_id>/<cell>`. Validation then requires every
  non-excluded matrix cell to be present in the merged results and every
  non-`empty_diff` cell to carry both campaign judges (`empty_diff` cells are
  never judged by design); `cells: []` no longer sails to COMPLETE.
- `5-publish` extracts fields with the same guarded pattern, runs
  `harness/merge_results.rb`, and renders the leaderboard summary to a scratch
  file first — a render failure parks WAITING instead of stranding a
  half-written table with no marker. An empty `agents` map refuses to publish.
  The summary covers cells, cross-family judge means, judged-cell count, gate
  pass rate, fresh/reused provenance, and total cost. There is no site
  generator in this repo yet.

All four stages clean up their scratch files (`.extract-*`, `.generate-*`,
`.judge-*`, `.publish-*`) on exit, so nothing untracked leaks into hive-state
residual commits.

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
`Hive::Workflows::DescriptorParser` (asserting the broken-descriptor rejection
is the nested-state_file rule, not an unrelated load error), verifies the
installed copy matches the canonical copy, validates `campaign.yml.example`
against current candidates and corpus, and advances a throwaway task through
all six stages with `Hive::Commands::Approve`. Stage scripts are extracted by
the `<!-- bench-stage-script -->` marker (never "first bash block"), and the
smoke exercises: the generate gates (missing, untracked, and dirty
campaign.yml), the REPO_ROOT misanchor ERROR path, extract's missing-slug
WAITING path, judge's and publish's missing-results WAITING paths, and a full
generate pass past the gate — the real contract validator runs over a campaign
derived from `campaign.yml.example` (so a required key dropped from the
example fails the smoke, not a live campaign) with a stub `hive_run.rb`
simulating a provider wall, asserting WAITING with the retry note, the
surfaced `pending[]` reason, and scratch-file cleanup. The parser smoke
requires `hive` before loading the descriptor parser, matching the real gem
load path.
