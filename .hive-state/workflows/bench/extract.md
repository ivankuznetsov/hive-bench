# Bench Extract Stage

Run this stage from the task folder. The task folder must contain
`campaign.yml`; the repository root is four directories above the task folder.

<!-- bench-stage-script -->
```bash
set -euo pipefail

STATE_FILE="extract.md"
REPO_ROOT="$(cd ../../../.. && pwd)"

# Scratch outputs are folded into the state file below; never leave them behind
# to be swept into hive-state commits.
trap 'rm -f .extract-check.out .extract-check.err' EXIT

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
    printf 'All campaign tasks are present in the corpus and load through `HiveBench::Corpus`.\n\n'
    printf '<!-- COMPLETE -->\n'
  } >>"$STATE_FILE"
}

if [ ! -f "$REPO_ROOT/harness/hive_run.rb" ]; then
  write_waiting "ERROR: ../../../.. did not resolve to the hive-bench repo root; missing harness/hive_run.rb at $REPO_ROOT."
  exit 0
fi

if [ ! -f campaign.yml ]; then
  write_waiting "Missing campaign.yml. Copy campaign.yml.example into this task folder, edit it, and commit it before continuing."
  exit 0
fi

ruby -ryaml -e '
  path = "campaign.yml"
  data = YAML.safe_load_file(path)
  abort("#{path} must be a YAML mapping") unless data.is_a?(Hash)
  tasks = data.fetch("tasks")
  abort("#{path} tasks must be a non-empty array") unless tasks.is_a?(Array) && !tasks.empty?
  missing = tasks.reject { |slug| File.file?(File.join(ARGV.fetch(0), "corpus", slug.to_s, "manifest.yml")) }
  unless missing.empty?
    warn "Missing corpus task(s): #{missing.join(", ")}"
    warn "Run the appropriate extraction command, for example:"
    warn "  ruby harness/extract.rb --help"
    exit 2
  end
  require File.join(ARGV.fetch(0), "harness/lib/corpus")
  entries = HiveBench::Corpus.load(root: File.join(ARGV.fetch(0), "corpus"), checkout_source: data.fetch("source", "."))
  ids = entries.map { |entry| entry.fetch("task_id") }
  missing_load = tasks.map(&:to_s) - ids
  abort("corpus loader missed task(s): #{missing_load.join(", ")}") unless missing_load.empty?
' "$REPO_ROOT" >.extract-check.out 2>.extract-check.err || {
  write_waiting "$(cat .extract-check.err .extract-check.out)"
  exit 0
}

write_complete
```
