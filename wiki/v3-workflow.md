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
after generation is NOT applied retroactively (`rejudge --only-missing` skips
judges that already have scores, so existing cells keep their lower seed
count), and shrinking the matrix strands already-paid cells (judge validation
reports them as `UNEXPECTED_CELL` rather than silently publishing
de-registered cells). Start a new campaign folder instead of amending.

## Stage behavior

- `2-extract` requires the same `source` contract as generate (no silent
  default to `.`, which would validate the corpus against the wrong checkout),
  checks that every `tasks[]` slug has `corpus/<slug>/manifest.yml`, and loads
  them through `HiveBench::Corpus`. It reports missing slugs and parks; it
  does not guess source PR coordinates for `harness/extract.rb`.
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
- `4-judge` extracts campaign fields in one guarded, type-checked ruby block
  (a malformed campaign.yml or multi-line `source` parks WAITING instead of
  dying marker-less or misaligning the `read` extraction), sources
  `~/.openrouter_key` like generate (an empty key file never clobbers a valid
  env key), and checks `pending[]`/`failed[]` are empty BEFORE rejudging —
  rejudge output carries no pending/failed keys, so a post-rewrite check would
  be vacuous. It then runs `harness/rejudge.rb --only-missing` writing to
  `results.json.next` + `mv` (backfills exist only in the campaign root; the
  sole copy is never rewritten in place) and `harness/deliberate.rb
  --min-disagreement 0 --skip-done` to a scratch transcript that is UNIONED
  into `deliberation.json` by `[task_id, agent_id]` (deliberate's `--out`
  writes only newly deliberated cells, so writing it straight onto the
  transcript would destroy prior paid deliberations on a wall retry). Both use
  the PER-CELL run dirs (`runs/<campaign_id>/*--*`) as artifact search dirs.
  Validation then requires every non-excluded matrix cell to be present, the
  exact judge slate BY NAME (`fable-5` + `gpt-5.5-pro`) on every
  non-`empty_diff` cell, deliberation-transcript coverage of every dual-judged
  cell (deliberate silently drops cells missing from the corpus), and no
  `UNEXPECTED_CELL` outside the pre-registered matrix; a soft-failed rejudge's
  stderr tail is folded into the WAITING report so `MISSING_JUDGES` lines
  carry their cause.
- `5-publish` extracts fields with the same guarded, type-checked pattern,
  runs `harness/merge_results.rb` to `results.json.next` + `mv`, and renders
  the leaderboard summary to a scratch file first — a render failure parks
  WAITING instead of stranding a half-written table with no marker; the final
  state-file append is guarded the same way. An empty `agents` map refuses to
  publish. The summary covers cells, cross-family judge means, judged-cell
  count, gate pass rate, fresh/reused provenance, and total cost. There is no
  site generator in this repo yet.

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
- Enforce budgets and effort pins by review. They are pre-registered in
  `campaign.yml`, but current harness flags do not enforce them per run.
  Timeouts are the exception: `timeouts.hive_seconds` IS enforced — generate
  exports it as `HB_HIVE_TIMEOUT` for every `hive_run.rb` invocation.

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
installed copy matches the canonical copy, and advances a throwaway task
through all six stages with `Hive::Commands::Approve`. Stage scripts are
extracted by the `<!-- bench-stage-script -->` marker (never "first bash
block"); every stage-script run gets a fake `$HOME` so the real
`~/.openrouter_key` is never exported into stub runs, and the slug-validation
lines duplicated across the generate/judge/publish scripts are diffed against
each other so the three copies cannot drift silently.

Failure-path coverage: the generate gates (missing, untracked, dirty, and
missing-required-key campaign.yml), the REPO_ROOT misanchor ERROR path,
extract's missing-slug and missing-source WAITING paths, judge's and publish's
missing-results and malformed-campaign WAITING paths, the wall fixture (WAITING
with the retry note, the surfaced `pending[]` reason, the `HB_HIVE_TIMEOUT`
env echoed back by the stub, and captured per-command stderr tails), the
nonzero-exit run_note prefix, the grok `HB_RUNNER_IMAGE` branch, the
contradictory terminal-plus-nonempty-buckets result, and judge's
MISSING_CELL / MISSING_JUDGES-by-name / UNEXPECTED_CELL / pending-guard
branches.

Success-path coverage: all four stages run to `<!-- COMPLETE -->` — a
success-shaped stub `hive_run.rb` drives generate through the real per-cell
merge (`merge_results.rb` and its deps are symlinked from the real harness),
stub rejudge/deliberate drive judge through slate validation and the
deliberation union (a second judge run asserts the transcript survives a
zero-new-cell retry), and publish renders the real leaderboard summary.
The never-re-buy guard is asserted directly: re-runs over a terminal cell, a
pending[]+patch cell, and a failed[]+patch cell must not re-invoke the stub
(counted via an invocation log), with the latter two reported as
`judges_pending`/do-NOT-regenerate. `campaign.yml.example` is validated by
pointing the REAL generate contract validator at the REAL repo root (symlinked
`harness/profiles` + `corpus`, a loudly-aborting `hive_run.rb`, and the single
cell pre-seeded as bought), replacing the old smoke-local re-implementation of
the candidate/task checks. Scratch-file cleanup is asserted for all four
stages. The parser smoke requires `hive` before loading the descriptor parser,
matching the real gem load path.
