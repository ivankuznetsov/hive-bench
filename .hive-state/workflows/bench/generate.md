# Bench Generate Stage

Run this stage from the task folder. It refuses to spend tokens until
`campaign.yml` exists, is tracked, is clean, and validates against the v3
campaign contract. On success it merges every per-cell result into
`runs/<campaign_id>/results.json`, the file the judge and publish stages
consume.

<!-- bench-stage-script -->
```bash
set -euo pipefail

STATE_FILE="generate.md"
REPO_ROOT="$(cd ../../../.. && pwd)"

# Scratch outputs are folded into the state file below; never leave them behind
# to be swept into hive-state commits (.generate-commands carries absolute
# source paths).
trap 'rm -f .generate-validate.out .generate-validate.err .generate-campaign.out .generate-campaign.err .generate-commands .generate-commands.err .generate-outcome.out .generate-outcome.err .generate-merge.out .generate-merge.err' EXIT

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
    printf '%s\n\n' "$1"
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

# Fail closed: a git error while checking cleanliness must not read as "clean".
campaign_dirty="$(git status --porcelain -- campaign.yml)" || {
  write_waiting "git status failed while checking campaign.yml cleanliness; refusing to treat it as clean."
  exit 0
}
if [ -n "$campaign_dirty" ]; then
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
  id = data["campaign_id"].to_s
  # campaign_id becomes the runs/<campaign_id> path segment (and publish merges
  # in place there): a strict slug keeps it from escaping runs/ or colliding
  # with published campaign dirs.
  abort("campaign_id must be a slug matching /\\A[a-z0-9][a-z0-9-]{0,63}\\z/; got #{id.inspect}") unless id.match?(/\A[a-z0-9][a-z0-9-]{0,63}\z/)
  abort("campaign_id v3-example is the unedited example id; pick a real campaign id") if id == "v3-example"
  abort("tasks must be a non-empty array") unless data["tasks"].is_a?(Array) && !data["tasks"].empty?
  abort("candidates must be a non-empty array") unless data["candidates"].is_a?(Array) && !data["candidates"].empty?
  abort("seeds must be a positive integer") unless data["seeds"].is_a?(Integer) && data["seeds"].positive?
  abort("exclusions must be an array") unless data["exclusions"].is_a?(Array)
  bad_exclusions = data["exclusions"].reject { |item| item.is_a?(Hash) && item.key?("task") && item.key?("candidate") }
  abort("every exclusions entry must be a {task:, candidate:} map; bad: #{bad_exclusions.inspect}") unless bad_exclusions.empty?
  abort("timeouts must be a mapping") unless data["timeouts"].is_a?(Hash)
  hive_timeout = data["timeouts"]["hive_seconds"]
  abort("timeouts.hive_seconds must be a positive integer when set") unless hive_timeout.nil? || (hive_timeout.is_a?(Integer) && hive_timeout.positive?)
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

ruby -ryaml -e '
  data = YAML.safe_load_file("campaign.yml")
  puts data.fetch("campaign_id")
  puts data.fetch("corpus_version")
' >.generate-campaign.out 2>.generate-campaign.err || {
  write_waiting "$(cat .generate-campaign.err .generate-campaign.out)"
  exit 0
}
{ read -r CAMPAIGN_ID; read -r CORPUS_VERSION; } <.generate-campaign.out

ruby -ryaml -rshellwords -rjson -e '
  repo = ARGV.fetch(0)
  require File.join(repo, "harness/profiles/candidates")
  data = YAML.safe_load_file("campaign.yml")
  exclusions = data.fetch("exclusions", []).map { |item| [item.fetch("task").to_s, item.fetch("candidate").to_s] }
  # A cell is BOUGHT once generation succeeded (generated/empty_diff) — or once
  # a diff was captured but every judge walled: hive_run.rb parks that cell in
  # `pending` with no cells[] record, and its driver starts by rm-rf-ing the
  # work tree, so re-running it would destroy the paid diff. Such cells are
  # reported by the outcome check below for judge backfill, never regenerated.
  # A parse error on an EXISTING result file fails closed (abort -> WAITING):
  # File.write is not atomic, and a truncated file must not read as "never ran".
  bought = lambda do |out_dir|
    path = File.join(repo, out_dir, "results.json")
    begin
      result = JSON.parse(File.read(path))
    rescue Errno::ENOENT
      next false
    rescue JSON::ParserError => e
      abort("#{path} exists but does not parse (#{e.message[0, 120]}); refusing to regenerate a possibly-paid cell. Inspect it (and remove the cell dir) manually if the cell is truly dead.")
    end
    cell = (result["cells"] || []).first
    next true if cell && %w[generated empty_diff].include?(cell["run_status"])
    !result.fetch("pending", []).empty? &&
      !Dir.glob(File.join(repo, out_dir, "*", "*", "target", "candidate.patch")).empty?
  end
  hive_timeout = data.fetch("timeouts", {})["hive_seconds"]
  data.fetch("tasks").each do |task|
    data.fetch("candidates").each do |candidate|
      next if exclusions.include?([task.to_s, candidate.to_s])
      # One out dir per cell: hive_run.rb OVERWRITES results.json per
      # invocation, so a shared campaign dir would keep only the last cell.
      out = File.join("runs", data.fetch("campaign_id").to_s, "#{candidate}--#{task}")
      next if bought.call(out) # a bought cell is never re-bought
      args = [
        "ruby", "harness/hive_run.rb",
        "--source", data.fetch("source").to_s,
        "--candidate", candidate.to_s,
        "--task", task.to_s,
        "--out", out,
        "--seeds", data.fetch("seeds").to_s,
        "--corpus-version", data.fetch("corpus_version").to_s
      ]
      env = ["env"]
      # Timeout comes from the pre-registered contract (timeouts.hive_seconds);
      # when unset, harness defaults apply, as campaign.yml.example documents.
      env << "HB_HIVE_TIMEOUT=#{hive_timeout}" if hive_timeout
      profile = HiveBench::Candidates.by_id(candidate.to_s)
      env << "HB_RUNNER_IMAGE=hive-bench-runner:grok" if profile && profile.grok_model
      puts Shellwords.join(env + args)
    end
  end
' "$REPO_ROOT" >.generate-commands 2>.generate-commands.err || {
  write_waiting "$(cat .generate-commands.err)"
  exit 0
}

if [ -f "$HOME/.openrouter_key" ]; then
  OPENROUTER_API_KEY="$(cat "$HOME/.openrouter_key")" || {
    write_waiting "Failed to read $HOME/.openrouter_key; refusing to run with an empty judge key."
    exit 0
  }
  export OPENROUTER_API_KEY
fi

generate_status=0
while IFS= read -r command; do
  set +e
  # </dev/null: a stdin-reading descendant must not swallow queued command lines.
  (cd "$REPO_ROOT" && bash -lc "$command" </dev/null)
  status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    generate_status="$status"
  fi
done <.generate-commands

run_note=""
if [ "$generate_status" -ne 0 ]; then
  run_note="One or more generation commands exited nonzero; per-cell results below are authoritative. "
fi

ruby -ryaml -rjson -e '
  repo = ARGV.fetch(0)
  data = YAML.safe_load_file("campaign.yml")
  exclusions = data.fetch("exclusions", []).map { |item| [item.fetch("task").to_s, item.fetch("candidate").to_s] }
  bad = []
  data.fetch("tasks").each do |task|
    data.fetch("candidates").each do |candidate|
      next if exclusions.include?([task.to_s, candidate.to_s])
      dir = File.join(repo, "runs", data.fetch("campaign_id").to_s, "#{candidate}--#{task}")
      begin
        result = JSON.parse(File.read(File.join(dir, "results.json")))
      rescue Errno::ENOENT
        bad << "#{candidate}/#{task}: missing"
        next
      rescue JSON::ParserError => e
        bad << "#{candidate}/#{task}: unreadable results.json (#{e.message[0, 80]})"
        next
      end
      cell = (result["cells"] || []).first
      status = cell ? cell["run_status"] : "missing"
      next if %w[generated empty_diff].include?(status)
      if status == "missing" && !result.fetch("pending", []).empty? &&
         !Dir.glob(File.join(dir, "*", "*", "target", "candidate.patch")).empty?
        status = "judges_pending — diff already captured; do NOT regenerate. Backfill judges via harness/rejudge.rb against #{dir}, then retry"
      end
      reasons = (result.fetch("pending", []) + result.fetch("failed", [])).filter_map { |entry| entry["reason"] }
      bad << "#{candidate}/#{task}: #{status}#{reasons.empty? ? "" : " — #{reasons.join("; ")}"}"
    end
  end
  unless bad.empty?
    puts "unfinished=#{bad.size}"
    bad.each { |line| puts "UNFINISHED #{line}" }
    exit 2
  end
' "$REPO_ROOT" >.generate-outcome.out 2>.generate-outcome.err || {
  write_waiting "${run_note}$(cat .generate-outcome.err .generate-outcome.out)"
  exit 0
}

# Judge and publish consume ONE campaign-root results.json; hive_run.rb only
# writes per-cell files, so merging them here is the handoff.
(cd "$REPO_ROOT" && ruby harness/merge_results.rb --out "runs/$CAMPAIGN_ID/results.json" --corpus-version "$CORPUS_VERSION" runs/"$CAMPAIGN_ID"/*--*/results.json) \
  >.generate-merge.out 2>.generate-merge.err || {
  write_waiting "${run_note}Per-cell merge failed: $(cat .generate-merge.err .generate-merge.out)"
  exit 0
}

write_complete "${run_note}Every non-excluded campaign cell has a per-cell \`run_status\` of \`generated\` or \`empty_diff\`; merged campaign results written to \`runs/$CAMPAIGN_ID/results.json\`."
```
