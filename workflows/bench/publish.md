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
  puts "| Agent | Cells | Cross-family mean | Judged cells | Gate pass rate | Fresh | Reused | Cost USD |"
  puts "|---|---:|---|---:|---:|---:|---:|---:|"
  def fmt(value)
    value.nil? ? "n/a" : value
  end
  def mean_map(values)
    return "n/a" unless values.is_a?(Hash) && !values.empty?
    values.map { |judge, mean| "#{judge}=#{fmt(mean)}" }.join("<br>")
  end
  agents.keys.sort.each do |agent|
    row = agents.fetch(agent)
    cells = row["cells"]
    cross_mean = mean_map(row.dig("judged", "mean_quality_cross_family"))
    judged = row.dig("judged", "scored_cells")
    pass_rate = row.dig("gated", "pass_rate")
    fresh = row.dig("provenance", "fresh")
    reused = row.dig("provenance", "reused")
    cost = row.dig("efficiency", "total_cost_usd")
    puts "| #{agent} | #{fmt(cells)} | #{cross_mean} | #{fmt(judged)} | #{fmt(pass_rate)} | #{fmt(fresh)} | #{fmt(reused)} | #{fmt(cost)} |"
  end
  puts
  puts "Merged results: `#{ARGV.fetch(0)}`"
  puts
  puts "Manual site step: no assemble/gen-site-data script exists in this repo yet; publish stops at merged results plus this summary."
  puts
  puts "<!-- COMPLETE -->"
' "$REPO_ROOT/$RESULTS" >>"$STATE_FILE"
```
