# Bench Generate Stage

Run this stage from the task folder. It refuses to spend tokens until
`campaign.yml` exists, is tracked, is clean, and validates against the v3
campaign contract.

```bash
set -euo pipefail

STATE_FILE="generate.md"
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
    printf 'Every campaign cell has a generation outcome; `pending` and `failed` are empty.\n\n'
    printf '<!-- COMPLETE -->\n'
  } >>"$STATE_FILE"
}

if [ ! -f "$REPO_ROOT/harness/hive_run.rb" ]; then
  write_waiting "ERROR: ../../../.. did not resolve to the hive-bench repo root; missing harness/hive_run.rb at $REPO_ROOT."
  exit 0
fi

if [ ! -f campaign.yml ]; then
  write_waiting "Missing campaign.yml. Copy campaign.yml.example into this task folder, edit it, and commit it."
  exit 0
fi

if ! git ls-files --error-unmatch campaign.yml >/dev/null 2>&1; then
  write_waiting "campaign.yml exists but is not committed in the hive-state checkout. Add and commit it before generation."
  exit 0
fi

if [ -n "$(git status --porcelain -- campaign.yml)" ]; then
  write_waiting "campaign.yml has uncommitted changes. Commit the final pre-registration before generation."
  exit 0
fi

ruby -ryaml -rjson -e '
  repo = ARGV.fetch(0)
  data = YAML.safe_load_file("campaign.yml")
  abort("campaign.yml must be a YAML mapping") unless data.is_a?(Hash)
  required = %w[campaign_id source corpus_version tasks candidates effort_pins seeds budgets timeouts exclusions aggregation]
  missing = required.reject { |key| data.key?(key) }
  abort("campaign.yml missing required key(s): #{missing.join(", ")}") unless missing.empty?
  abort("tasks must be a non-empty array") unless data["tasks"].is_a?(Array) && !data["tasks"].empty?
  abort("candidates must be a non-empty array") unless data["candidates"].is_a?(Array) && !data["candidates"].empty?
  abort("seeds must be a positive integer") unless data["seeds"].is_a?(Integer) && data["seeds"].positive?
  require File.join(repo, "harness/profiles/candidates")
  known = HiveBench::Candidates.all.map(&:id)
  unknown = data["candidates"].map(&:to_s) - known
  abort("unknown candidate id(s): #{unknown.join(", ")}") unless unknown.empty?
  missing_tasks = data["tasks"].map(&:to_s).reject { |slug| File.file?(File.join(repo, "corpus", slug, "manifest.yml")) }
  abort("unknown corpus task(s): #{missing_tasks.join(", ")}") unless missing_tasks.empty?
' "$REPO_ROOT" >.generate-validate.out 2>.generate-validate.err || {
  write_waiting "$(cat .generate-validate.err .generate-validate.out)"
  exit 0
}

ruby -ryaml -rshellwords -e '
  data = YAML.safe_load_file("campaign.yml")
  exclusions = data.fetch("exclusions", []).map { |item| [item.fetch("task").to_s, item.fetch("candidate").to_s] }
  data.fetch("tasks").each do |task|
    data.fetch("candidates").each do |candidate|
      next if exclusions.include?([task.to_s, candidate.to_s])
      args = [
        "ruby", "harness/hive_run.rb",
        "--source", data.fetch("source").to_s,
        "--candidate", candidate.to_s,
        "--task", task.to_s,
        "--out", File.join("runs", data.fetch("campaign_id").to_s),
        "--seeds", data.fetch("seeds").to_s,
        "--corpus-version", data.fetch("corpus_version").to_s
      ]
      puts Shellwords.join(args)
    end
  end
' >.generate-commands

generate_status=0
while IFS= read -r command; do
  set +e
  (cd "$REPO_ROOT" && bash -lc "$command")
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    generate_status="$status"
  fi
done <.generate-commands

if [ "$generate_status" -ne 0 ]; then
  printf 'One or more generation commands exited nonzero; inspecting results.json for pending/failed cells.\n' >.generate-run.err
fi

ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  pending = data.fetch("pending", [])
  failed = data.fetch("failed", [])
  unless pending.empty? && failed.empty?
    puts "pending=#{pending.size}"
    pending.each { |cell| puts "PENDING #{cell.inspect}" }
    puts "failed=#{failed.size}"
    failed.each { |cell| puts "FAILED #{cell.inspect}" }
    exit 2
  end
' "$REPO_ROOT/runs/$(ruby -ryaml -e 'puts YAML.safe_load_file("campaign.yml").fetch("campaign_id")')/results.json" \
  >.generate-outcome.out 2>.generate-outcome.err || {
  write_waiting "$(cat .generate-outcome.err .generate-outcome.out)"
  exit 0
}

write_complete
```
