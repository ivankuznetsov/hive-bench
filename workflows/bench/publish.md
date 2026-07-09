# Bench Publish Stage

Run this stage from the task folder after judging. It only uses existing
harness publishing primitives: merge results and write a human-readable
leaderboard summary into this state file.

```bash
set -euo pipefail

STATE_FILE="publish.md"
REPO_ROOT="$(cd ../../../.. && pwd)"

write_waiting() {
  {
    printf '\n## Status\n\n'
    printf '%s\n\n' "$1"
    printf 'Retry: fix the condition above, then run `touch %s` after hive daemon debounce has elapsed.\n\n' "$STATE_FILE"
    printf '<!-- WAITING -->\n'
  } >>"$STATE_FILE"
}

if [ ! -f "$REPO_ROOT/harness/hive_run.rb" ]; then
  write_waiting "ERROR: ../../../.. did not resolve to the hive-bench repo root; missing harness/hive_run.rb at $REPO_ROOT."
  exit 0
fi

if [ ! -f campaign.yml ]; then
  write_waiting "Missing campaign.yml. Restore the committed campaign pre-registration before publishing."
  exit 0
fi

CAMPAIGN_ID="$(ruby -ryaml -e 'puts YAML.safe_load_file("campaign.yml").fetch("campaign_id")')"
CORPUS_VERSION="$(ruby -ryaml -e 'puts YAML.safe_load_file("campaign.yml").fetch("corpus_version")')"
RESULTS="runs/$CAMPAIGN_ID/results.json"

if [ ! -f "$REPO_ROOT/$RESULTS" ]; then
  write_waiting "Missing $RESULTS. Re-run generate/judge before publish."
  exit 0
fi

(cd "$REPO_ROOT" && ruby harness/merge_results.rb --out "$RESULTS" --corpus-version "$CORPUS_VERSION" "$RESULTS") \
  >.publish-merge.out 2>.publish-merge.err || {
  write_waiting "$(cat .publish-merge.err .publish-merge.out)"
  exit 0
}

ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  agents = data.fetch("agents", {})
  puts "## Leaderboard Summary"
  puts
  puts "| Agent | Cells | Mean | Pass rate |"
  puts "|---|---:|---:|---:|"
  agents.keys.sort.each do |agent|
    row = agents.fetch(agent)
    mean = row["mean"] || row["score_mean"] || row["judge_mean"] || "n/a"
    pass = row["pass_rate"] || row["gate_pass_rate"] || "n/a"
    cells = row["cells"] || row["n"] || "n/a"
    puts "| #{agent} | #{cells} | #{mean} | #{pass} |"
  end
  puts
  puts "Merged results: `#{ARGV.fetch(0)}`"
  puts
  puts "Manual site step: no assemble/gen-site-data script exists in this repo yet; publish stops at merged results plus this summary."
  puts
  puts "<!-- COMPLETE -->"
' "$REPO_ROOT/$RESULTS" >>"$STATE_FILE"
```
