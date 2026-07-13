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

BENCH_INSTRUCTIONS="$(ruby -e '
  require "hive/workflows/registry"
  workflow = Hive::Workflows::Registry.fetch(:bench)
  expected = %w[1-inbox 2-extract 3-generate 4-judge 5-publish 6-done]
  abort("bad stages: #{workflow.stage_dirs.inspect}") unless workflow.stage_dirs == expected
  agent_stages = workflow.stages.select { |stage| stage.kind == :agent }
  instructions = agent_stages.map(&:instruction)
  abort("bench instructions are missing") unless instructions.all? { |path| path && File.file?(path) }
  dirs = instructions.map { |path| File.dirname(path) }.uniq
  abort("bench instructions span unexpected directories: #{dirs.inspect}") unless dirs.one?
  puts dirs.fetch(0)
')"
readonly BENCH_INSTRUCTIONS

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

assert_absent() {
  local file="$1" needle="$2"
  if grep -q "$needle" "$file"; then
    echo "FAIL: $file unexpectedly contains: $needle" >&2
    cat "$file" >&2
    exit 1
  fi
}

# Stage scripts must never leave scratch files to be swept into hive-state
# residual commits.
assert_no_scratch() {
  local dir="$1" prefix="$2"
  if ls "$dir/$prefix"* >/dev/null 2>&1; then
    echo "FAIL: $dir left scratch files behind:" >&2
    ls "$dir/$prefix"* >&2
    exit 1
  fi
}

# campaign.yml.example itself is validated against the REAL repo by the
# real-root generate scenario below (the real contract validator, real
# candidate profiles, real corpus) — no re-implemented validator logic here.
ruby -ryaml -e 'data = YAML.safe_load_file("campaign.yml.example"); abort("campaign example must be a map") unless data.is_a?(Hash)'

EX_TASK="$(ruby -ryaml -e 'puts YAML.safe_load_file("campaign.yml.example").fetch("tasks").first')"
EX_CAND="$(ruby -ryaml -e 'puts YAML.safe_load_file("campaign.yml.example").fetch("candidates").first')"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# --- fresh-machine installation: selecting the packaged workflow must bind the
# project and create a bench task without any project-local workflow copy. -----
FRESH_PROJECT="$WORKDIR/fresh-project"
FRESH_HIVE_HOME="$WORKDIR/fresh-hive-home"
FRESH_HOME="$WORKDIR/fresh-home"
FRESH_XDG_CONFIG_HOME="$WORKDIR/fresh-xdg-config"
FRESH_GEM_HOME="$(ruby -e 'print Gem.dir')"
FRESH_GEM_PATH="$(ruby -e 'print Gem.path.join(":")')"
mkdir -p "$FRESH_PROJECT" "$FRESH_HIVE_HOME" "$FRESH_HOME" "$FRESH_XDG_CONFIG_HOME"
git -C "$FRESH_PROJECT" init -q
git -C "$FRESH_PROJECT" config user.email smoke@example.invalid
git -C "$FRESH_PROJECT" config user.name "Bench Smoke"
touch "$FRESH_PROJECT/README.md"
git -C "$FRESH_PROJECT" add README.md
git -C "$FRESH_PROJECT" commit -qm "seed fresh project"
HOME="$FRESH_HOME" XDG_CONFIG_HOME="$FRESH_XDG_CONFIG_HOME" HIVE_HOME="$FRESH_HIVE_HOME" \
  GEM_HOME="$FRESH_GEM_HOME" GEM_PATH="$FRESH_GEM_PATH" \
  HIVE_BIN=/bin/true ruby "$HIVE_SRC/bin/hive" init "$FRESH_PROJECT" --workflow bench \
  </dev/null >/dev/null 2>"$WORKDIR/fresh-init.err"
if [ -e "$FRESH_PROJECT/.hive-state/workflows/bench.yml" ] ||
   [ -e "$FRESH_PROJECT/.hive-state/workflows/bench" ]; then
  echo "FAIL: built-in bench workflow was copied into project state" >&2
  exit 1
fi
HOME="$FRESH_HOME" XDG_CONFIG_HOME="$FRESH_XDG_CONFIG_HOME" HIVE_HOME="$FRESH_HIVE_HOME" \
  GEM_HOME="$FRESH_GEM_HOME" GEM_PATH="$FRESH_GEM_PATH" \
  HIVE_BIN=/bin/true ruby "$HIVE_SRC/bin/hive" \
  new fresh-project "benchmark smoke campaign" </dev/null >/dev/null
if ! grep -Rqx 'workflow: bench' "$FRESH_PROJECT/.hive-state/stages/1-inbox"; then
  echo "FAIL: fresh install did not create a task pinned to workflow: bench" >&2
  exit 1
fi

PROJECT="$WORKDIR/project"
STATE="$PROJECT/.hive-state"
SLUG="bench-smoke-260709-aa11"
mkdir -p "$STATE/stages/1-inbox/$SLUG" "$STATE/bench-runtime" \
  "$PROJECT/harness/profiles" "$PROJECT/corpus"
# Native bench instructions resolve the immutable runtime snapshot under
# .hive-state. Point that path at the smoke's controlled harness fixtures.
ln -s "$PROJECT/harness" "$STATE/bench-runtime/harness"

# Stage scripts run with HOME pointed here: the real ~/.openrouter_key must
# never be exported into stub runs.
FAKE_HOME="$WORKDIR/home"
mkdir -p "$FAKE_HOME"
printf 'smoke-test-key\n' >"$FAKE_HOME/.openrouter_key"

# Stub hive_run.rb: satisfies the repo-root anchor and simulates generation
# outcomes per HB_SMOKE_MODE (wall = judge wall in pending[], failed = failed[]
# bucket, success = terminal dual-judged cell). Every invocation is appended to
# hive_run.calls so the never-re-buy guard can assert "not re-invoked", and the
# received HB_HIVE_TIMEOUT / HB_RUNNER_IMAGE env is echoed into the per-cell
# reason so the smoke can assert the contract env actually arrived.
cat >"$PROJECT/harness/hive_run.rb" <<'RUBY'
require "json"
require "fileutils"
out = ARGV[ARGV.index("--out") + 1]
candidate = ARGV[ARGV.index("--candidate") + 1]
task = ARGV[ARGV.index("--task") + 1]
File.open("hive_run.calls", "a") { |f| f.puts "#{candidate}--#{task}" }
env_note = "timeout=#{ENV["HB_HIVE_TIMEOUT"]}; image=#{ENV["HB_RUNNER_IMAGE"]}"
FileUtils.mkdir_p(out)
results =
  case ENV.fetch("HB_SMOKE_MODE", "wall")
  when "success"
    { "cells" => [{ "task_id" => task, "agent_id" => candidate, "mode" => "fresh",
                    "model_version" => "stub", "run_status" => "generated", "subset" => "judged",
                    "gate" => { "status" => "no_gate", "reason" => "stub" },
                    "judges" => {
                      "fable-5" => { "mean" => 7.0, "interval" => [6.5, 7.5],
                                     "sample_count" => 3, "scores" => [6.5, 7.0, 7.5],
                                     "reasoning_effort" => "unspecified" },
                      "gpt-5.6-sol" => { "mean" => 6.0, "interval" => [5.5, 6.5],
                                        "sample_count" => 3, "scores" => [5.5, 6.0, 6.5],
                                        "reasoning_effort" => "ultra" }
                    },
                    "efficiency" => { "cost_usd" => 1.0 } }],
      "pending" => [], "failed" => [] }
  when "failed"
    { "cells" => [],
      "pending" => [],
      "failed" => [{ "task_id" => task, "agent_id" => candidate,
                     "reason" => "stub post-generation failure; #{env_note}" }] }
  else
    { "cells" => [],
      "pending" => [{ "task_id" => task, "agent_id" => candidate,
                      "reason" => "stub provider wall (limit_hit); #{env_note}" }],
      "failed" => [] }
  end
File.write(File.join(out, "results.json"), JSON.pretty_generate(results) + "\n")
warn "stub hive_run: #{ENV.fetch("HB_SMOKE_MODE", "wall")} #{candidate}/#{task}"
exit(Integer(ENV.fetch("HB_SMOKE_EXIT", "0")))
RUBY

# Stub rejudge.rb: copies the merged results through --out (Score#results
# shape: no pending/failed keys), backfilling nothing — the fixtures below
# control which judges each cell carries.
cat >"$PROJECT/harness/rejudge.rb" <<'RUBY'
require "json"
require "fileutils"
def arg(flag) = ARGV.include?(flag) ? ARGV[ARGV.index(flag) + 1] : nil
results = JSON.parse(File.read(arg("--results")))
results.delete("pending")
results.delete("failed")
out = arg("--out")
FileUtils.mkdir_p(File.dirname(out))
File.write(out, JSON.pretty_generate(results) + "\n")
warn "stub rejudge: wrote #{results.fetch("cells", []).size} cell(s) to #{out}"
RUBY

# Stub deliberate.rb: transcribes every dual-judged cell not already covered by
# --skip-done, writing ONLY the newly deliberated cells (like the real tool).
cat >"$PROJECT/harness/deliberate.rb" <<'RUBY'
require "json"
require "fileutils"
def arg(flag) = ARGV.include?(flag) ? ARGV[ARGV.index(flag) + 1] : nil
results = JSON.parse(File.read(arg("--results")))
skip = arg("--skip-done")
seen = skip && File.file?(skip) ? JSON.parse(File.read(skip)).fetch("cells", []).map { |t| [t["task_id"], t["agent_id"]] } : []
cells = results.fetch("cells", [])
               .select { |c| (c["judges"] || {}).size >= 2 }
               .reject { |c| seen.include?([c["task_id"], c["agent_id"]]) }
               .map do |c|
  { "task_id" => c["task_id"], "agent_id" => c["agent_id"],
    "judges" => {
      "fable-5" => { "initial" => 7.0, "final" => 7.0, "delta" => 0.0,
                     "reasoning_effort" => "unspecified" },
      "gpt-5.6-sol" => { "initial" => 6.0, "final" => 6.5, "delta" => 0.5,
                         "reasoning_effort" => "ultra" }
    } }
end
out = arg("--out")
FileUtils.mkdir_p(File.dirname(out))
File.write(out, JSON.pretty_generate(
  "schema" => "hive-bench-deliberation", "schema_version" => 1,
  "cells" => cells, "summary" => { "cells" => cells.size }
) + "\n")
warn "stub deliberate: wrote #{cells.size} new cell(s)"
RUBY

# The judge/publish success paths exercise the REAL merge: merge_results.rb is
# symlinked from the real harness (its __dir__ resolves through the symlink, so
# score.rb and lib/ load from the real repo too). lib/ itself is symlinked for
# extract's real HiveBench::Corpus load over the stub manifests.
ln -s "$ROOT/harness/merge_results.rb" "$PROJECT/harness/merge_results.rb"
ln -s "$ROOT/harness/lib" "$PROJECT/harness/lib"

# Stub candidate profiles + corpus manifests mirroring campaign.yml.example
# (plus Grok and Sol-flavoured candidates so both HB_RUNNER_IMAGE branches are
# reachable),
# so generate.md's contract validator accepts campaigns derived from the
# example inside this throwaway project.
ruby -ryaml -rfileutils -e '
  data = YAML.safe_load_file("campaign.yml.example")
  ids = data.fetch("candidates").map(&:to_s) + ["grok-smoke", "sol-smoke"]
  stub = <<~RUBY
    module HiveBench
      module Candidates
        Candidate = Struct.new(:id, :grok_model, :pi_models, :codex_model, :codex_models)
        def self.all
          #{ids.inspect}.map do |id|
            Candidate.new(id, id.include?("grok") ? "grok-stub" : nil, nil,
                          id.include?("sol") ? "gpt-5.6-sol" : nil, nil)
          end
        end
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
  local id="$1" dest="$2" extra_candidate="${3:-}"
  ruby -ryaml -e '
    data = YAML.safe_load_file("campaign.yml.example")
    data["campaign_id"] = ARGV.fetch(0)
    data["candidates"] = [ARGV[2]] if ARGV[2] && !ARGV[2].empty?
    File.write(ARGV.fetch(1), data.to_yaml)
  ' "$id" "$dest" "$extra_candidate"
}

# Craft a campaign-root results.json fixture for the judge validation branches.
write_judge_fixture() {
  local id="$1" variant="$2"
  PROJECT="$PROJECT" ruby -rjson -rfileutils -ryaml -e '
    id, variant = ARGV.fetch(0), ARGV.fetch(1)
    data = YAML.safe_load_file("campaign.yml.example")
    task = data.fetch("tasks").first
    cand = data.fetch("candidates").first
    full = {
      "fable-5" => { "mean" => 7.0, "sample_count" => 3, "scores" => [7.0, 7.0, 7.0],
                     "reasoning_effort" => "unspecified" },
      "gpt-5.6-sol" => { "mean" => 6.5, "sample_count" => 3, "scores" => [6.0, 6.5, 7.0],
                         "reasoning_effort" => "ultra" }
    }
    cell = ->(agent, judges) do
      { "task_id" => task, "agent_id" => agent, "mode" => "fresh",
        "run_status" => "generated", "judges" => judges, "efficiency" => {} }
    end
    results =
      case variant
      when "missing_cell" then { "cells" => [], "pending" => [], "failed" => [] }
      when "missing_judges" then { "cells" => [cell.(cand, { "fable-5" => full.fetch("fable-5") })], "pending" => [], "failed" => [] }
      when "undersampled" then { "cells" => [cell.(cand, full.merge("gpt-5.6-sol" => full.fetch("gpt-5.6-sol").merge("sample_count" => 1, "scores" => [6.5])))], "pending" => [], "failed" => [] }
      when "unexpected" then { "cells" => [cell.(cand, full), cell.("rogue-candidate", full)], "pending" => [], "failed" => [] }
      when "pending" then { "cells" => [cell.(cand, full)], "pending" => [{ "task_id" => task, "agent_id" => cand, "reason" => "stub wall" }], "failed" => [] }
      else abort("unknown fixture variant #{variant}")
      end
    dir = File.join(ENV.fetch("PROJECT"), "runs", id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "results.json"), JSON.pretty_generate(results) + "\n")
  ' "$id" "$variant"
}

hive_run_calls() {
  if [ -f "$PROJECT/hive_run.calls" ]; then wc -l <"$PROJECT/hive_run.calls"; else echo 0; fi
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

extract_stage_script "$BENCH_INSTRUCTIONS/extract.md" "$WORKDIR/extract.sh"
extract_stage_script "$BENCH_INSTRUCTIONS/generate.md" "$WORKDIR/generate.sh"
extract_stage_script "$BENCH_INSTRUCTIONS/judge.md" "$WORKDIR/judge.sh"
extract_stage_script "$BENCH_INSTRUCTIONS/publish.md" "$WORKDIR/publish.sh"

# --- campaign_id slug validation is duplicated across three stage scripts:
# assert the copies have not drifted.
for stage in judge publish; do
  for needle in 'campaign_id must be a slug' 'v3-example is the unedited example id'; do
    if ! diff <(grep -F "$needle" "$WORKDIR/generate.sh" | sed 's/^[[:space:]]*//' | sort -u) \
              <(grep -F "$needle" "$WORKDIR/$stage.sh" | sed 's/^[[:space:]]*//' | sort -u) >/dev/null; then
      echo "FAIL: campaign_id validation drifted between generate.sh and $stage.sh (needle: $needle)" >&2
      exit 1
    fi
  done
done

# --- generate gate: missing campaign.yml -------------------------------------
GATE_DIR="$STATE/stages/3-generate/$SLUG-gate"
mkdir -p "$GATE_DIR"
(cd "$GATE_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$GATE_DIR/generate.md" '<!-- WAITING -->' 'Missing campaign.yml'

# --- generate gate: campaign.yml present but untracked ------------------------
UNTRACKED_DIR="$STATE/stages/3-generate/$SLUG-untracked"
mkdir -p "$UNTRACKED_DIR"
write_campaign bench-smoke-untracked "$UNTRACKED_DIR/campaign.yml"
(cd "$UNTRACKED_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$UNTRACKED_DIR/generate.md" '<!-- WAITING -->' 'not committed in the hive-state checkout'

# --- generate gate: campaign.yml committed but dirty ---------------------------
DIRTY_DIR="$STATE/stages/3-generate/$SLUG-dirty"
mkdir -p "$DIRTY_DIR"
write_campaign bench-smoke-dirty "$DIRTY_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-dirty/campaign.yml"
git -C "$STATE" commit -qm "smoke: dirty-gate campaign"
printf '# local edit after commit\n' >>"$DIRTY_DIR/campaign.yml"
(cd "$DIRTY_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$DIRTY_DIR/generate.md" '<!-- WAITING -->' 'uncommitted changes'

# --- generate: committed campaign missing a required key parks with the real
# contract message ---------------------------------------------------------------
NOBUDGET_DIR="$STATE/stages/3-generate/$SLUG-nobudget"
mkdir -p "$NOBUDGET_DIR"
ruby -ryaml -e '
  data = YAML.safe_load_file("campaign.yml.example")
  data["campaign_id"] = "bench-smoke-nobudget"
  data.delete("budgets")
  File.write(ARGV.fetch(0), data.to_yaml)
' "$NOBUDGET_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-nobudget/campaign.yml"
git -C "$STATE" commit -qm "smoke: no-budget campaign"
(cd "$NOBUDGET_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$NOBUDGET_DIR/generate.md" '<!-- WAITING -->' 'missing required key(s): budgets'

# --- generate: judge backends that collapse to one results key fail before
# spending (e.g. claude-gpt-5.6-sol and gpt-5.6-sol) ---------------------------
DUPJUDGE_DIR="$STATE/stages/3-generate/$SLUG-dupjudge"
mkdir -p "$DUPJUDGE_DIR"
ruby -ryaml -e '
  data = YAML.safe_load_file("campaign.yml.example")
  data["campaign_id"] = "bench-smoke-dupjudge"
  data.dig("judges", "claude")["model"] = "claude-gpt-5.6-sol"
  File.write(ARGV.fetch(0), data.to_yaml)
' "$DUPJUDGE_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-dupjudge/campaign.yml"
git -C "$STATE" commit -qm "smoke: duplicate-judge-key campaign"
(cd "$DUPJUDGE_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$DUPJUDGE_DIR/generate.md" '<!-- WAITING -->' 'enabled judges must produce unique result keys'

# --- generate: REPO_ROOT misanchor parks with the ERROR message ----------------
MISANCHOR_DIR="$WORKDIR/misanchor/w/x/y/z"
mkdir -p "$MISANCHOR_DIR"
(cd "$MISANCHOR_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$MISANCHOR_DIR/generate.md" '<!-- WAITING -->' 'packaged bench runtime is missing'

# --- extract: missing corpus slug parks WAITING --------------------------------
EXTRACT_DIR="$STATE/stages/2-extract/$SLUG-missing-slug"
mkdir -p "$EXTRACT_DIR"
printf 'source: /tmp/smoke-src\ntasks:\n  - no-such-task-smoke\n' >"$EXTRACT_DIR/campaign.yml"
(cd "$EXTRACT_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/extract.sh")
assert_state "$EXTRACT_DIR/extract.md" '<!-- WAITING -->' 'Missing corpus task(s): no-such-task-smoke'
assert_no_scratch "$EXTRACT_DIR" .extract-

# --- extract: missing source key parks WAITING (no silent "." default) ---------
EXTRACT_NOSRC_DIR="$STATE/stages/2-extract/$SLUG-no-source"
mkdir -p "$EXTRACT_NOSRC_DIR"
printf 'tasks:\n  - no-such-task-smoke\n' >"$EXTRACT_NOSRC_DIR/campaign.yml"
(cd "$EXTRACT_NOSRC_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/extract.sh")
assert_state "$EXTRACT_NOSRC_DIR/extract.md" '<!-- WAITING -->' 'missing required key: source'

# --- judge: missing campaign results parks WAITING -----------------------------
JUDGE_DIR="$STATE/stages/4-judge/$SLUG-no-results"
mkdir -p "$JUDGE_DIR"
write_campaign bench-smoke-judge "$JUDGE_DIR/campaign.yml"
(cd "$JUDGE_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_DIR/judge.md" '<!-- WAITING -->' 'Missing runs/bench-smoke-judge/results.json'

# --- judge: malformed campaign.yml parks WAITING via the guarded extraction ----
JUDGE_BAD_DIR="$STATE/stages/4-judge/$SLUG-badyaml"
mkdir -p "$JUDGE_BAD_DIR"
printf 'campaign_id: BAD_Slug\nsource: /tmp/x\nseeds: 3\n' >"$JUDGE_BAD_DIR/campaign.yml"
(cd "$JUDGE_BAD_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_BAD_DIR/judge.md" '<!-- WAITING -->' 'campaign_id must be a slug'
assert_no_scratch "$JUDGE_BAD_DIR" .judge-

# --- publish: missing campaign results parks WAITING ---------------------------
PUBLISH_DIR="$STATE/stages/5-publish/$SLUG-no-results"
mkdir -p "$PUBLISH_DIR"
write_campaign bench-smoke-publish "$PUBLISH_DIR/campaign.yml"
(cd "$PUBLISH_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/publish.sh")
assert_state "$PUBLISH_DIR/publish.md" '<!-- WAITING -->' 'Missing runs/bench-smoke-publish/results.json'

# --- publish: malformed campaign.yml parks WAITING via the guarded extraction --
PUBLISH_BAD_DIR="$STATE/stages/5-publish/$SLUG-badyaml"
mkdir -p "$PUBLISH_BAD_DIR"
printf 'campaign_id: BAD_Slug\ncorpus_version: v3\n' >"$PUBLISH_BAD_DIR/campaign.yml"
(cd "$PUBLISH_BAD_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/publish.sh")
assert_state "$PUBLISH_BAD_DIR/publish.md" '<!-- WAITING -->' 'campaign_id must be a slug'
assert_no_scratch "$PUBLISH_BAD_DIR" .publish-

# --- generate wall discipline: pending[] fixture -> WAITING with retry note ----
# Runs the FULL generate script past the gate: the real contract validator over
# a campaign derived from campaign.yml.example, per-cell command generation,
# and the outcome inspection, with the stub hive_run.rb simulating a wall.
WALL_DIR="$STATE/stages/3-generate/$SLUG-wall"
mkdir -p "$WALL_DIR"
write_campaign bench-smoke-wall "$WALL_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-wall/campaign.yml"
git -C "$STATE" commit -qm "smoke: wall campaign"
(cd "$WALL_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$WALL_DIR/generate.md" '<!-- WAITING -->' 'UNFINISHED'
assert_state "$WALL_DIR/generate.md" '<!-- WAITING -->' 'stub provider wall'
assert_state "$WALL_DIR/generate.md" '<!-- WAITING -->' 'Retry: fix the condition above'
# The pre-registered timeout must reach the harness invocation as HB_HIVE_TIMEOUT.
assert_state "$WALL_DIR/generate.md" '<!-- WAITING -->' 'timeout=14400'
# Per-command stderr must be captured and surfaced next to the outcome report.
assert_state "$WALL_DIR/generate.md" '<!-- WAITING -->' 'Generation command stderr tails:'
if ! ls "$PROJECT"/runs/bench-smoke-wall/*--*/results.json >/dev/null 2>&1; then
  echo "FAIL: wall run left no per-cell results.json under runs/bench-smoke-wall" >&2
  exit 1
fi
assert_no_scratch "$WALL_DIR" .generate-

# --- never-re-buy: pending[] + captured diff must not re-run generation and
# must be reported as judges_pending with the do-NOT-regenerate advice --------
calls_before="$(hive_run_calls)"
mkdir -p "$PROJECT/runs/bench-smoke-wall/$EX_CAND--$EX_TASK/$EX_TASK/cell_1/target"
touch "$PROJECT/runs/bench-smoke-wall/$EX_CAND--$EX_TASK/$EX_TASK/cell_1/target/candidate.patch"
(cd "$WALL_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
if [ "$(hive_run_calls)" != "$calls_before" ]; then
  echo "FAIL: generate re-invoked hive_run.rb for a pending cell with a captured diff" >&2
  exit 1
fi
assert_state "$WALL_DIR/generate.md" '<!-- WAITING -->' 'judges_pending'
assert_state "$WALL_DIR/generate.md" '<!-- WAITING -->' 'do NOT regenerate'

# --- never-re-buy: failed[]-bucketed cell with a captured diff -----------------
FAILED_DIR="$STATE/stages/3-generate/$SLUG-failed"
mkdir -p "$FAILED_DIR"
write_campaign bench-smoke-failedbucket "$FAILED_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-failed/campaign.yml"
git -C "$STATE" commit -qm "smoke: failed-bucket campaign"
(cd "$FAILED_DIR" && HOME="$FAKE_HOME" HB_SMOKE_MODE=failed bash "$WORKDIR/generate.sh")
assert_state "$FAILED_DIR/generate.md" '<!-- WAITING -->' 'stub post-generation failure'
calls_before="$(hive_run_calls)"
mkdir -p "$PROJECT/runs/bench-smoke-failedbucket/$EX_CAND--$EX_TASK/$EX_TASK/cell_1/target"
touch "$PROJECT/runs/bench-smoke-failedbucket/$EX_CAND--$EX_TASK/$EX_TASK/cell_1/target/candidate.patch"
(cd "$FAILED_DIR" && HOME="$FAKE_HOME" HB_SMOKE_MODE=failed bash "$WORKDIR/generate.sh")
if [ "$(hive_run_calls)" != "$calls_before" ]; then
  echo "FAIL: generate re-invoked hive_run.rb for a failed[] cell with a captured diff" >&2
  exit 1
fi
assert_state "$FAILED_DIR/generate.md" '<!-- WAITING -->' 'judges_pending'
assert_state "$FAILED_DIR/generate.md" '<!-- WAITING -->' 'do NOT regenerate'

# --- generate: nonzero harness exit surfaces the run_note prefix ---------------
EXITCODE_DIR="$STATE/stages/3-generate/$SLUG-exitcode"
mkdir -p "$EXITCODE_DIR"
write_campaign bench-smoke-exitcode "$EXITCODE_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-exitcode/campaign.yml"
git -C "$STATE" commit -qm "smoke: exit-code campaign"
(cd "$EXITCODE_DIR" && HOME="$FAKE_HOME" HB_SMOKE_EXIT=3 bash "$WORKDIR/generate.sh")
assert_state "$EXITCODE_DIR/generate.md" '<!-- WAITING -->' 'One or more generation commands exited nonzero'

# --- generate: grok candidates must receive HB_RUNNER_IMAGE --------------------
GROK_DIR="$STATE/stages/3-generate/$SLUG-grok"
mkdir -p "$GROK_DIR"
write_campaign bench-smoke-grok "$GROK_DIR/campaign.yml" grok-smoke
git -C "$STATE" add "stages/3-generate/$SLUG-grok/campaign.yml"
git -C "$STATE" commit -qm "smoke: grok campaign"
(cd "$GROK_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$GROK_DIR/generate.md" '<!-- WAITING -->' 'image=hive-bench-runner:grok'

# --- generate: Sol/Terra candidates use the combined Codex+Grok image ----------
SOL_DIR="$STATE/stages/3-generate/$SLUG-sol"
mkdir -p "$SOL_DIR"
write_campaign bench-smoke-sol "$SOL_DIR/campaign.yml" sol-smoke
git -C "$STATE" add "stages/3-generate/$SLUG-sol/campaign.yml"
git -C "$STATE" commit -qm "smoke: sol campaign"
(cd "$SOL_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$SOL_DIR/generate.md" '<!-- WAITING -->' 'image=hive-bench-runner:sol'

# --- generate: contradictory per-cell result (terminal + nonempty buckets) -----
CONTRA_DIR="$STATE/stages/3-generate/$SLUG-contra"
mkdir -p "$CONTRA_DIR"
write_campaign bench-smoke-contra "$CONTRA_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-contra/campaign.yml"
git -C "$STATE" commit -qm "smoke: contradictory campaign"
mkdir -p "$PROJECT/runs/bench-smoke-contra/$EX_CAND--$EX_TASK"
ruby -rjson -e '
  File.write(ARGV.fetch(0), JSON.pretty_generate(
    "cells" => [{ "task_id" => ARGV.fetch(1), "agent_id" => ARGV.fetch(2), "run_status" => "generated", "judges" => {} }],
    "pending" => [{ "task_id" => ARGV.fetch(1), "agent_id" => ARGV.fetch(2), "reason" => "stub wall" }],
    "failed" => []
  ) + "\n")
' "$PROJECT/runs/bench-smoke-contra/$EX_CAND--$EX_TASK/results.json" "$EX_TASK" "$EX_CAND"
(cd "$CONTRA_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$CONTRA_DIR/generate.md" '<!-- WAITING -->' 'contradictory result'

# --- generate success: terminal cells -> per-cell merge -> COMPLETE ------------
SUCCESS_DIR="$STATE/stages/3-generate/$SLUG-success"
mkdir -p "$SUCCESS_DIR"
write_campaign bench-smoke-success "$SUCCESS_DIR/campaign.yml"
git -C "$STATE" add "stages/3-generate/$SLUG-success/campaign.yml"
git -C "$STATE" commit -qm "smoke: success campaign"
(cd "$SUCCESS_DIR" && HOME="$FAKE_HOME" HB_SMOKE_MODE=success bash "$WORKDIR/generate.sh")
assert_state "$SUCCESS_DIR/generate.md" '<!-- COMPLETE -->' 'merged campaign results written'
if [ ! -f "$PROJECT/runs/bench-smoke-success/results.json" ]; then
  echo "FAIL: generate COMPLETE without a campaign-root results.json" >&2
  exit 1
fi
assert_no_scratch "$SUCCESS_DIR" .generate-

# --- never-re-buy: terminal (generated) cells are skipped on a re-run ----------
calls_before="$(hive_run_calls)"
(cd "$SUCCESS_DIR" && HOME="$FAKE_HOME" HB_SMOKE_MODE=success bash "$WORKDIR/generate.sh")
if [ "$(hive_run_calls)" != "$calls_before" ]; then
  echo "FAIL: generate re-invoked hive_run.rb for a terminal generated cell" >&2
  exit 1
fi
assert_state "$SUCCESS_DIR/generate.md" '<!-- COMPLETE -->' 'merged campaign results written'

# --- judge success: full slate + deliberation transcript -> COMPLETE -----------
JUDGE_OK_DIR="$STATE/stages/4-judge/$SLUG-success"
mkdir -p "$JUDGE_OK_DIR"
write_campaign bench-smoke-success "$JUDGE_OK_DIR/campaign.yml"
(cd "$JUDGE_OK_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_OK_DIR/judge.md" '<!-- COMPLETE -->' 'configured judge slate'
if ! grep -q "$EX_CAND" "$PROJECT/runs/bench-smoke-success/deliberation.json"; then
  echo "FAIL: deliberation transcript missing the dual-judged cell" >&2
  cat "$PROJECT/runs/bench-smoke-success/deliberation.json" >&2
  exit 1
fi
assert_no_scratch "$JUDGE_OK_DIR" .judge-

# --- judge retry: the deliberation union must preserve prior transcripts even
# when the retry deliberates zero new cells (the old overwrite lost them) ------
(cd "$JUDGE_OK_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_OK_DIR/judge.md" '<!-- COMPLETE -->' 'configured judge slate'
if ! grep -q "$EX_CAND" "$PROJECT/runs/bench-smoke-success/deliberation.json"; then
  echo "FAIL: judge retry wiped the deliberation transcript" >&2
  cat "$PROJECT/runs/bench-smoke-success/deliberation.json" >&2
  exit 1
fi

# --- judge validation branches: MISSING_CELL / MISSING_JUDGES / UNEXPECTED_CELL
# and the pre-rejudge pending guard ---------------------------------------------
JUDGE_MISSCELL_DIR="$STATE/stages/4-judge/$SLUG-misscell"
mkdir -p "$JUDGE_MISSCELL_DIR"
write_campaign bench-smoke-misscell "$JUDGE_MISSCELL_DIR/campaign.yml"
write_judge_fixture bench-smoke-misscell missing_cell
(cd "$JUDGE_MISSCELL_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_MISSCELL_DIR/judge.md" '<!-- WAITING -->' 'MISSING_CELL'

JUDGE_MISSJUDGE_DIR="$STATE/stages/4-judge/$SLUG-missjudge"
mkdir -p "$JUDGE_MISSJUDGE_DIR"
write_campaign bench-smoke-missjudge "$JUDGE_MISSJUDGE_DIR/campaign.yml"
write_judge_fixture bench-smoke-missjudge missing_judges
(cd "$JUDGE_MISSJUDGE_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_MISSJUDGE_DIR/judge.md" '<!-- WAITING -->' 'MISSING_JUDGES'
# The slate is validated by NAME: the report must say which judge is missing.
assert_state "$JUDGE_MISSJUDGE_DIR/judge.md" '<!-- WAITING -->' 'missing: gpt-5.6-sol'

JUDGE_UNDERSAMPLED_DIR="$STATE/stages/4-judge/$SLUG-undersampled"
mkdir -p "$JUDGE_UNDERSAMPLED_DIR"
write_campaign bench-smoke-undersampled "$JUDGE_UNDERSAMPLED_DIR/campaign.yml"
write_judge_fixture bench-smoke-undersampled undersampled
(cd "$JUDGE_UNDERSAMPLED_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_UNDERSAMPLED_DIR/judge.md" '<!-- WAITING -->' 'UNDERSAMPLED_JUDGE'

JUDGE_UNEXPECTED_DIR="$STATE/stages/4-judge/$SLUG-unexpected"
mkdir -p "$JUDGE_UNEXPECTED_DIR"
write_campaign bench-smoke-unexpected "$JUDGE_UNEXPECTED_DIR/campaign.yml"
write_judge_fixture bench-smoke-unexpected unexpected
(cd "$JUDGE_UNEXPECTED_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_UNEXPECTED_DIR/judge.md" '<!-- WAITING -->' 'UNEXPECTED_CELL rogue-candidate'

JUDGE_PENDING_DIR="$STATE/stages/4-judge/$SLUG-pending"
mkdir -p "$JUDGE_PENDING_DIR"
write_campaign bench-smoke-pendingguard "$JUDGE_PENDING_DIR/campaign.yml"
write_judge_fixture bench-smoke-pendingguard pending
(cd "$JUDGE_PENDING_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/judge.sh")
assert_state "$JUDGE_PENDING_DIR/judge.md" '<!-- WAITING -->' 're-run generate until every cell is terminal'

# --- publish success: real merge + leaderboard render -> COMPLETE --------------
PUBLISH_OK_DIR="$STATE/stages/5-publish/$SLUG-success"
mkdir -p "$PUBLISH_OK_DIR"
write_campaign bench-smoke-success "$PUBLISH_OK_DIR/campaign.yml"
(cd "$PUBLISH_OK_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/publish.sh")
assert_state "$PUBLISH_OK_DIR/publish.md" '<!-- COMPLETE -->' '## Leaderboard Summary'
assert_state "$PUBLISH_OK_DIR/publish.md" '<!-- COMPLETE -->' "| $EX_CAND |"
assert_state "$PUBLISH_OK_DIR/publish.md" '<!-- COMPLETE -->' 'leaderboard summary above is appended'
assert_no_scratch "$PUBLISH_OK_DIR" .publish-

# --- extract success: real corpus manifest fixtures -> COMPLETE ----------------
EXTRACT_OK_DIR="$STATE/stages/2-extract/$SLUG-success"
mkdir -p "$EXTRACT_OK_DIR"
write_campaign bench-smoke-extract "$EXTRACT_OK_DIR/campaign.yml"
if (cd "$EXTRACT_OK_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/extract.sh"); then
  assert_state "$EXTRACT_OK_DIR/extract.md" '<!-- COMPLETE -->' 'load through'
else
  echo "FAIL: extract success scenario exited nonzero" >&2
  exit 1
fi
assert_no_scratch "$EXTRACT_OK_DIR" .extract-

# --- real-root validator: the REAL generate contract validator runs against the
# REAL repo (real candidate profiles, real corpus manifests) for a campaign
# derived from campaign.yml.example, with the single cell pre-seeded as bought
# so no generation is attempted (the anchor hive_run.rb aborts loudly if the
# never-re-buy guard regresses). This replaces the old smoke-local
# re-implementation of the candidate/task checks. -------------------------------
ANCHOR="$WORKDIR/realroot"
mkdir -p "$ANCHOR/harness"
ln -s "$ROOT/harness/profiles" "$ANCHOR/harness/profiles"
ln -s "$ROOT/harness/merge_results.rb" "$ANCHOR/harness/merge_results.rb"
ln -s "$ROOT/corpus" "$ANCHOR/corpus"
cat >"$ANCHOR/harness/hive_run.rb" <<'RUBY'
abort "SMOKE FAIL: the real-root generate scenario invoked hive_run.rb — the never-re-buy guard regressed"
RUBY
REAL_STATE="$ANCHOR/.hive-state"
REAL_DIR="$REAL_STATE/stages/3-generate/$SLUG-real"
mkdir -p "$REAL_DIR" "$REAL_STATE/bench-runtime"
ln -s "$ANCHOR/harness" "$REAL_STATE/bench-runtime/harness"
write_campaign bench-smoke-real "$REAL_DIR/campaign.yml"
git -C "$REAL_STATE" init -q
git -C "$REAL_STATE" config user.email smoke@example.invalid
git -C "$REAL_STATE" config user.name "Bench Smoke"
git -C "$REAL_STATE" add .
git -C "$REAL_STATE" commit -qm "seed real-root campaign"
mkdir -p "$ANCHOR/runs/bench-smoke-real/$EX_CAND--$EX_TASK"
ruby -rjson -e '
  cell = { "task_id" => ARGV.fetch(1), "agent_id" => ARGV.fetch(2), "mode" => "fresh",
           "model_version" => "stub", "run_status" => "generated", "subset" => "judged",
           "gate" => { "status" => "no_gate", "reason" => "stub" },
           "judges" => {
             "fable-5" => { "mean" => 7.0, "sample_count" => 3, "scores" => [7.0, 7.0, 7.0],
                            "reasoning_effort" => "unspecified" },
             "gpt-5.6-sol" => { "mean" => 6.5, "sample_count" => 3, "scores" => [6.0, 6.5, 7.0],
                                "reasoning_effort" => "ultra" }
           },
           "efficiency" => { "cost_usd" => 1.0 } }
  File.write(ARGV.fetch(0), JSON.pretty_generate("cells" => [cell], "pending" => [], "failed" => []) + "\n")
' "$ANCHOR/runs/bench-smoke-real/$EX_CAND--$EX_TASK/results.json" "$EX_TASK" "$EX_CAND"
(cd "$REAL_DIR" && HOME="$FAKE_HOME" bash "$WORKDIR/generate.sh")
assert_state "$REAL_DIR/generate.md" '<!-- COMPLETE -->' 'merged campaign results written'
assert_absent "$REAL_DIR/generate.md" 'commands exited nonzero'
if [ ! -f "$ANCHOR/runs/bench-smoke-real/results.json" ]; then
  echo "FAIL: real-root generate COMPLETE without a campaign-root results.json" >&2
  exit 1
fi
rm -rf "$ANCHOR/runs"

echo "bench workflow smoke ok"
