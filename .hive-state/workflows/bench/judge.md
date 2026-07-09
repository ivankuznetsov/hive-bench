# Bench Judge Stage

Run this stage from the task folder after generation. It fills missing judge
scores and writes deliberation transcripts without changing scoring semantics.

```bash
set -euo pipefail

STATE_FILE="judge.md"
REPO_ROOT="$(cd ../../../.. && pwd)"

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
    printf 'Generated cells carry the campaign judge set at the requested seed count; deliberation transcript is written when applicable.\n\n'
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

CAMPAIGN_ID="$(ruby -ryaml -e 'puts YAML.safe_load_file("campaign.yml").fetch("campaign_id")')"
SOURCE="$(ruby -ryaml -e 'puts YAML.safe_load_file("campaign.yml").fetch("source")')"
SEEDS="$(ruby -ryaml -e 'puts YAML.safe_load_file("campaign.yml").fetch("seeds")')"
RESULTS="runs/$CAMPAIGN_ID/results.json"

if [ ! -f "$REPO_ROOT/$RESULTS" ]; then
  write_waiting "Missing $RESULTS. Re-run generate before judge."
  exit 0
fi

(cd "$REPO_ROOT" && ruby harness/rejudge.rb --source "$SOURCE" --results "$RESULTS" --out "$RESULTS" --seeds "$SEEDS" --only-missing "runs/$CAMPAIGN_ID") \
  >.judge-rejudge.out 2>.judge-rejudge.err || {
  write_waiting "$(cat .judge-rejudge.err .judge-rejudge.out)"
  exit 0
}

(cd "$REPO_ROOT" && ruby harness/deliberate.rb --source "$SOURCE" --results "$RESULTS" --out "runs/$CAMPAIGN_ID/deliberation.json" --min-disagreement 0 "runs/$CAMPAIGN_ID") \
  >.judge-deliberate.out 2>.judge-deliberate.err || {
  write_waiting "$(cat .judge-deliberate.err .judge-deliberate.out)"
  exit 0
}

ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  failed = data.fetch("failed", [])
  pending = data.fetch("pending", [])
  cells = data.fetch("cells", [])
  incomplete = cells.select { |cell| cell.fetch("judges", {}).empty? }
  unless pending.empty? && failed.empty? && incomplete.empty?
    puts "pending=#{pending.size} failed=#{failed.size} cells_without_judges=#{incomplete.size}"
    incomplete.each { |cell| puts "MISSING_JUDGES #{cell["agent_id"]} #{cell["task_id"]}" }
    exit 2
  end
' "$REPO_ROOT/$RESULTS" >.judge-validate.out 2>.judge-validate.err || {
  write_waiting "$(cat .judge-validate.err .judge-validate.out)"
  exit 0
}

write_complete
```
