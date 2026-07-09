# Bench Judge Stage

Run this stage from the task folder after generation. It fills missing judge
scores and writes deliberation transcripts without changing scoring semantics.

<!-- bench-stage-script -->
```bash
set -euo pipefail

STATE_FILE="judge.md"
REPO_ROOT="$(cd ../../../.. && pwd)"

# Scratch outputs are folded into the state file below; never leave them behind
# to be swept into hive-state commits.
trap 'rm -f .judge-campaign.out .judge-campaign.err .judge-rejudge.out .judge-rejudge.err .judge-deliberate.out .judge-deliberate.err .judge-validate.out .judge-validate.err' EXIT

write_waiting() {
  {
    printf '\n## Status\n\n'
    printf '%s\n\n' "$1"
    printf 'Retry: fix the condition above, then run `touch %s` after hive daemon debounce has elapsed.\n\n' "$STATE_FILE"
    printf '<!-- WAITING -->\n'
  } >>"$STATE_FILE"
}

write_complete() {
  {
    printf '\n## Status\n\n'
    printf 'Every expected campaign cell is present; every non-empty-diff cell carries scores from both campaign judges (seed count is set by the rejudge invocation, not re-derivable from results.json); deliberation transcript is written when applicable.\n\n'
    printf '<!-- COMPLETE -->\n'
  } >>"$STATE_FILE"
}

if [ ! -f "$REPO_ROOT/harness/hive_run.rb" ]; then
  write_waiting "ERROR: ../../../.. did not resolve to the hive-bench repo root; missing harness/hive_run.rb at $REPO_ROOT."
  exit 0
fi

if [ ! -f campaign.yml ]; then
  write_waiting "Missing campaign.yml. Restore the committed campaign pre-registration before judging."
  exit 0
fi

# One guarded extraction: a malformed campaign.yml must park WAITING, not kill
# the stage marker-less under `set -e`.
ruby -ryaml -e '
  data = YAML.safe_load_file("campaign.yml")
  id = data.fetch("campaign_id").to_s
  abort("campaign_id must be a slug matching /\\A[a-z0-9][a-z0-9-]{0,63}\\z/; got #{id.inspect}") unless id.match?(/\A[a-z0-9][a-z0-9-]{0,63}\z/)
  abort("campaign_id v3-example is the unedited example id; pick a real campaign id") if id == "v3-example"
  puts id
  puts data.fetch("source")
  puts data.fetch("seeds")
' >.judge-campaign.out 2>.judge-campaign.err || {
  write_waiting "$(cat .judge-campaign.err .judge-campaign.out)"
  exit 0
}
{ read -r CAMPAIGN_ID; read -r SOURCE; read -r SEEDS; } <.judge-campaign.out
RESULTS="runs/$CAMPAIGN_ID/results.json"

if [ ! -f "$REPO_ROOT/$RESULTS" ]; then
  write_waiting "Missing $RESULTS. Re-run generate before judge."
  exit 0
fi

if [ -f "$HOME/.openrouter_key" ]; then
  OPENROUTER_API_KEY="$(cat "$HOME/.openrouter_key")" || {
    write_waiting "Failed to read $HOME/.openrouter_key; refusing to run with an empty judge key."
    exit 0
  }
  export OPENROUTER_API_KEY
fi

# Search dirs are the PER-CELL run dirs: rejudge/deliberate resolve artifacts at
# <search-dir>/<task_id>/<cell>, and generation writes them under
# runs/<campaign_id>/<candidate>--<task>/<task_id>/<cell>.
(cd "$REPO_ROOT" && ruby harness/rejudge.rb --source "$SOURCE" --results "$RESULTS" --out "$RESULTS" --seeds "$SEEDS" --only-missing runs/"$CAMPAIGN_ID"/*--*) \
  >.judge-rejudge.out 2>.judge-rejudge.err || {
  write_waiting "$(cat .judge-rejudge.err .judge-rejudge.out)"
  exit 0
}

# --skip-done: wall retries must not re-buy deliberation for cells the
# transcript already covers (--out overwrites it every run).
(cd "$REPO_ROOT" && ruby harness/deliberate.rb --source "$SOURCE" --results "$RESULTS" --out "runs/$CAMPAIGN_ID/deliberation.json" --min-disagreement 0 --skip-done "runs/$CAMPAIGN_ID/deliberation.json" runs/"$CAMPAIGN_ID"/*--*) \
  >.judge-deliberate.out 2>.judge-deliberate.err || {
  write_waiting "$(cat .judge-deliberate.err .judge-deliberate.out)"
  exit 0
}

ruby -ryaml -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  campaign = YAML.safe_load_file("campaign.yml")
  exclusions = campaign.fetch("exclusions", []).map { |item| [item.fetch("task").to_s, item.fetch("candidate").to_s] }
  expected = campaign.fetch("tasks").flat_map { |task| campaign.fetch("candidates").map { |candidate| [task.to_s, candidate.to_s] } } - exclusions
  cells = data.fetch("cells", [])
  by_key = cells.to_h { |cell| [[cell["task_id"].to_s, cell["agent_id"].to_s], cell] }
  # The campaign judge set is the harness dual-judge slate (fable + gpt);
  # judges fail soft per cell during generation, so a single-judge cell is a
  # routine backfill target, not a success.
  judge_slate_size = 2
  problems = []
  pending = data.fetch("pending", [])
  failed = data.fetch("failed", [])
  problems << "pending=#{pending.size} failed=#{failed.size}" unless pending.empty? && failed.empty?
  expected.each do |task, candidate|
    cell = by_key[[task, candidate]]
    if cell.nil?
      problems << "MISSING_CELL #{candidate} #{task}"
    elsif cell["run_status"] != "empty_diff" && cell.fetch("judges", {}).size < judge_slate_size
      problems << "MISSING_JUDGES #{candidate} #{task} (have: #{cell.fetch("judges", {}).keys.sort.join(",")})"
    end
  end
  unless problems.empty?
    problems.each { |line| puts line }
    exit 2
  end
' "$REPO_ROOT/$RESULTS" >.judge-validate.out 2>.judge-validate.err || {
  write_waiting "$(cat .judge-validate.err .judge-validate.out)"
  exit 0
}

write_complete
```
