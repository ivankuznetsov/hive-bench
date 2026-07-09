#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HIVE_SRC="${HIVE_SRC:-$HOME/Dev/hive}"
if [ ! -d "$HIVE_SRC/lib" ]; then
  echo "hive source not found at $HIVE_SRC (set HIVE_SRC to a hive checkout)" >&2
  exit 1
fi
export RUBYLIB="$HIVE_SRC/lib${RUBYLIB:+:$RUBYLIB}"

cd "$ROOT"

parse_descriptor() {
  local path="$1"
  ruby -e '
    require "hive"
    require "hive/workflows/descriptor_parser"
    workflow = Hive::Workflows::DescriptorParser.parse_file(ARGV.fetch(0))
    expected = %w[1-inbox 2-extract 3-generate 4-judge 5-publish 6-done]
    abort("bad stages: #{workflow.stage_dirs.inspect}") unless workflow.stage_dirs == expected
  ' "$path"
}

# Extract a stage instruction's script by its named marker — never "the first
# ```bash block", which silently grabs doc examples added above the script.
extract_stage_script() {
  local md="$1" out="$2"
  awk '/^<!-- bench-stage-script -->$/ { armed = 1; next }
       /^```bash$/ && armed { in_block = 1; armed = 0; next }
       /^```$/ && in_block { exit }
       in_block { print }' "$md" >"$out"
  if [ ! -s "$out" ]; then
    echo "no <!-- bench-stage-script --> block extracted from $md" >&2
    exit 1
  fi
}

# Marker + message assertions against a stage state file.
assert_state() {
  local file="$1" marker="$2" needle="$3"
  if ! tail -n 1 "$file" | grep -qx "$marker"; then
    echo "FAIL: $file does not end with $marker" >&2
    tail -n 5 "$file" >&2
    exit 1
  fi
  if ! grep -q "$needle" "$file"; then
    echo "FAIL: $file missing expected text: $needle" >&2
    cat "$file" >&2
    exit 1
  fi
}

parse_descriptor "workflows/bench.yml"
parse_descriptor ".hive-state/workflows/bench.yml"
diff -qr workflows/bench .hive-state/workflows/bench >/dev/null
diff -u workflows/bench.yml .hive-state/workflows/bench.yml >/dev/null

# The broken copy must still be named bench.yml: the parser checks id-vs-filename
# first, and a mismatched temp name would fail for the wrong reason.
broken_dir="$(mktemp -d)"
broken="$broken_dir/bench.yml"
broken_err="$broken_dir/err"
trap 'rm -rf "$broken_dir"; [ -z "${WORKDIR:-}" ] || rm -rf "$WORKDIR"' EXIT
sed 's/state_file: task.md/state_file: nested\/task.md/' workflows/bench.yml >"$broken"
if parse_descriptor "$broken" >/dev/null 2>"$broken_err"; then
  echo "broken descriptor unexpectedly parsed" >&2
  exit 1
fi
# The rejection must be the nested-state_file rule, not an unrelated load error.
if ! grep -q "must be a bare filename" "$broken_err"; then
  echo "broken descriptor failed for an unexpected reason:" >&2
  cat "$broken_err" >&2
  exit 1
fi

ruby -ryaml -e 'data = YAML.safe_load_file("campaign.yml.example"); abort("campaign example must be a map") unless data.is_a?(Hash)'
ruby -I harness -ryaml -e '
  require "profiles/candidates"
  data = YAML.safe_load_file("campaign.yml.example")
  known = HiveBench::Candidates.all.map(&:id)
  abort("example candidates must be a non-empty array") unless data.fetch("candidates").is_a?(Array) && !data.fetch("candidates").empty?
  abort("example tasks must be a non-empty array") unless data.fetch("tasks").is_a?(Array) && !data.fetch("tasks").empty?
  missing_candidates = data.fetch("candidates") - known
  missing_tasks = data.fetch("tasks").reject { |slug| File.file?(File.join("corpus", slug, "manifest.yml")) }
  abort("missing candidate(s): #{missing_candidates.join(", ")}") unless missing_candidates.empty?
  abort("missing task(s): #{missing_tasks.join(", ")}") unless missing_tasks.empty?
'

WORKDIR="$(mktemp -d)"
PROJECT="$WORKDIR/project"
STATE="$PROJECT/.hive-state"
SLUG="bench-smoke-260709-aa11"
mkdir -p "$STATE/workflows" "$STATE/stages/1-inbox/$SLUG" "$PROJECT/harness/profiles" "$PROJECT/corpus"
cp -R workflows/bench.yml workflows/bench "$STATE/workflows/"

# Stub hive_run.rb: satisfies the repo-root anchor AND simulates a provider
# wall — it parks the requested cell in pending[] (no cells[] record, no
# artifacts), exactly the U2 wall-discipline fixture.
cat >"$PROJECT/harness/hive_run.rb" <<'RUBY'
require "json"
require "fileutils"
out = ARGV[ARGV.index("--out") + 1]
candidate = ARGV[ARGV.index("--candidate") + 1]
task = ARGV[ARGV.index("--task") + 1]
FileUtils.mkdir_p(out)
File.write(File.join(out, "results.json"), JSON.pretty_generate(
  "cells" => [],
  "pending" => [{ "task_id" => task, "agent_id" => candidate, "reason" => "stub provider wall (limit_hit)" }],
  "failed" => []
) + "\n")
warn "stub hive_run: parked #{candidate}/#{task} pending"
RUBY

# Stub candidate profiles + corpus manifests mirroring campaign.yml.example, so
# generate.md's REAL contract validator runs against the example's structure
# (a required key dropped from the example fails here, not on a live campaign).
ruby -ryaml -rfileutils -e '
  data = YAML.safe_load_file("campaign.yml.example")
  ids = data.fetch("candidates").map(&:to_s)
  stub = <<~RUBY
    module HiveBench
      module Candidates
        Candidate = Struct.new(:id, :grok_model)
        def self.all = #{ids.inspect}.map { |id| Candidate.new(id, id.include?("grok") ? "grok-stub" : nil) }
        def self.by_id(id) = all.find { |c| c.id == id }
      end
    end
  RUBY
  File.write(ARGV.fetch(0), stub)
  data.fetch("tasks").each do |task|
    dir = File.join(ARGV.fetch(1), task.to_s)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "manifest.yml"), "task_id: #{task}\n")
  end
' "$PROJECT/harness/profiles/candidates.rb" "$PROJECT/corpus"

write_campaign() {
  local id="$1" dest="$2"
  ruby -ryaml -e '
    data = YAML.safe_load_file("campaign.yml.example")
    data["campaign_id"] = ARGV.fetch(0)
    File.write(ARGV.fetch(1), data.to_yaml)
  ' "$id" "$dest"
}

cat >"$STATE/config.yml" <<YAML
hive_state_path: .hive-state
default_workflow: coding
project_name: bench-smoke
YAML

cat >"$STATE/stages/1-inbox/$SLUG/task.md" <<'MD'
---
workflow: bench
---

# Bench smoke campaign

<!-- COMPLETE -->
MD

cat >"$STATE/stages/1-inbox/$SLUG/meta.yml" <<YAML
id: 1
slug: $SLUG
display_name: Bench smoke campaign
workflow: bench
YAML

git -C "$STATE" init -q
git -C "$STATE" config user.email smoke@example.invalid
git -C "$STATE" config user.name "Bench Smoke"
git -C "$STATE" add .
git -C "$STATE" commit -qm "seed bench smoke"

ruby -e '
  require "hive"
  require "hive/commands/approve"
  folder = ARGV.fetch(0)
  expected = %w[2-extract 3-generate 4-judge 5-publish 6-done]
  expected.each do |stage|
    Hive::Commands::Approve.new(folder, quiet: true).call
    folder = File.join(File.dirname(File.dirname(folder)), stage, File.basename(folder))
    abort("missing #{folder}") unless Dir.exist?(folder)
    state_file = case stage
                 when "2-extract" then "extract.md"
                 when "3-generate" then "generate.md"
                 when "4-judge" then "judge.md"
                 when "5-publish" then "publish.md"
                 else "task.md"
                 end
    File.open(File.join(folder, state_file), "a") { |f| f.puts "\n<!-- COMPLETE -->" } unless stage == "6-done"
  end
' "$STATE/stages/1-inbox/$SLUG"

test -d "$STATE/stages/6-done/$SLUG"

extract_stage_script workflows/bench/extract.md "$WORKDIR/extract.sh"
extract_stage_script workflows/bench/generate.md "$WORKDIR/generate.sh"
extract_stage_script workflows/bench/judge.md "$WORKDIR/judge.sh"
extract_stage_script workflows/bench/publish.md "$WORKDIR/publish.sh"

# --- generate gate: missing campaign.yml -------------------------------------
GATE_DIR="$STATE/stages/3-generate/$SLUG-gate"
mkdir -p "$GATE_DIR"
(cd "$GATE_DIR" && bash "$WORKDIR/generate.sh")
assert_state "$GATE_DIR/generate.md" '<!-- WAITING -->' 'Missing campaign.yml'

# --- generate gate: campaign.yml present but untracked ------------------------
UNTRACKED_DIR="$STATE/stages/3-generate/$SLUG-untracked"
mkdir -p "$UNTRACKED_DIR"
write_campaign bench-smoke-untracked "$UNTRACKED_DIR/campaign.yml"
(cd "$UNTRACKED_DIR" && bash "$WORKDIR/generate.sh")
assert_state "$UNTRACKED_DIR/generate.md" '<!-- WAITING -->' 'not committed in the hive-state checkout'

# --- generate gate: campaign.yml committed but dirty ---------------------------
DIRTY_DIR="$STATE/stages/3-generate/$SLUG-dirty"
mkdir -p "$DIRTY_DIR"
write_campaign bench-smoke-dirty "$DIRTY_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-dirty/campaign.yml"
git -C "$STATE" commit -qm "smoke: dirty-gate campaign"
printf '# local edit after commit\n' >>"$DIRTY_DIR/campaign.yml"
(cd "$DIRTY_DIR" && bash "$WORKDIR/generate.sh")
assert_state "$DIRTY_DIR/generate.md" '<!-- WAITING -->' 'uncommitted changes'

# --- generate: REPO_ROOT misanchor parks with the ERROR message ----------------
MISANCHOR_DIR="$WORKDIR/misanchor/w/x/y/z"
mkdir -p "$MISANCHOR_DIR"
(cd "$MISANCHOR_DIR" && bash "$WORKDIR/generate.sh")
assert_state "$MISANCHOR_DIR/generate.md" '<!-- WAITING -->' 'did not resolve to the hive-bench repo root'

# --- extract: missing corpus slug parks WAITING --------------------------------
EXTRACT_DIR="$STATE/stages/2-extract/$SLUG-missing-slug"
mkdir -p "$EXTRACT_DIR"
printf 'tasks:\n  - no-such-task-smoke\n' >"$EXTRACT_DIR/campaign.yml"
(cd "$EXTRACT_DIR" && bash "$WORKDIR/extract.sh")
assert_state "$EXTRACT_DIR/extract.md" '<!-- WAITING -->' 'Missing corpus task(s): no-such-task-smoke'

# --- judge: missing campaign results parks WAITING -----------------------------
JUDGE_DIR="$STATE/stages/4-judge/$SLUG-no-results"
mkdir -p "$JUDGE_DIR"
write_campaign bench-smoke-judge "$JUDGE_DIR/campaign.yml"
(cd "$JUDGE_DIR" && bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_DIR/judge.md" '<!-- WAITING -->' 'Missing runs/bench-smoke-judge/results.json'

# --- publish: missing campaign results parks WAITING ---------------------------
PUBLISH_DIR="$STATE/stages/5-publish/$SLUG-no-results"
mkdir -p "$PUBLISH_DIR"
write_campaign bench-smoke-publish "$PUBLISH_DIR/campaign.yml"
(cd "$PUBLISH_DIR" && bash "$WORKDIR/publish.sh")
assert_state "$PUBLISH_DIR/publish.md" '<!-- WAITING -->' 'Missing runs/bench-smoke-publish/results.json'

# --- generate wall discipline: pending[] fixture -> WAITING with retry note ----
# Runs the FULL generate script past the gate: the real contract validator over
# a campaign derived from campaign.yml.example, per-cell command generation,
# and the outcome inspection, with the stub hive_run.rb simulating a wall.
WALL_DIR="$STATE/stages/3-generate/$SLUG-wall"
mkdir -p "$WALL_DIR"
write_campaign bench-smoke-wall "$WALL_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-wall/campaign.yml"
git -C "$STATE" commit -qm "smoke: wall campaign"
(cd "$WALL_DIR" && bash "$WORKDIR/generate.sh")
assert_state "$WALL_DIR/generate.md" '<!-- WAITING -->' 'UNFINISHED'
grep -q 'stub provider wall' "$WALL_DIR/generate.md"
grep -q 'Retry: fix the condition above' "$WALL_DIR/generate.md"
ls "$PROJECT"/runs/bench-smoke-wall/*--*/results.json >/dev/null
# Scratch files must not survive to be swept into hive-state commits.
if ls "$WALL_DIR"/.generate-* >/dev/null 2>&1; then
  echo "FAIL: generate stage left scratch files behind:" >&2
  ls "$WALL_DIR"/.generate-* >&2
  exit 1
fi

echo "bench workflow smoke ok"
