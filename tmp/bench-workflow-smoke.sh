#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HIVE_SRC="${HIVE_SRC:-$HOME/Dev/hive}"
export RUBYLIB="$HIVE_SRC/lib${RUBYLIB:+:$RUBYLIB}"

cd "$ROOT"

parse_descriptor() {
  local path="$1"
  ruby -e '
    require "hive/workflows/descriptor_parser"
    workflow = Hive::Workflows::DescriptorParser.parse_file(ARGV.fetch(0))
    expected = %w[1-inbox 2-extract 3-generate 4-judge 5-publish 6-done]
    abort("bad stages: #{workflow.stage_dirs.inspect}") unless workflow.stage_dirs == expected
  ' "$path"
}

parse_descriptor "workflows/bench.yml"
parse_descriptor ".hive-state/workflows/bench.yml"
diff -qr workflows/bench .hive-state/workflows/bench >/dev/null
diff -u workflows/bench.yml .hive-state/workflows/bench.yml >/dev/null

broken="$(mktemp)"
trap 'rm -f "$broken"; [ -z "${WORKDIR:-}" ] || rm -rf "$WORKDIR"' EXIT
sed 's/state_file: task.md/state_file: nested\/task.md/' workflows/bench.yml >"$broken"
if parse_descriptor "$broken" >/dev/null 2>&1; then
  echo "broken descriptor unexpectedly parsed" >&2
  exit 1
fi

ruby -ryaml -e 'data = YAML.safe_load_file("campaign.yml.example"); abort("campaign example must be a map") unless data.is_a?(Hash)'
ruby -I harness -ryaml -e '
  require "profiles/candidates"
  data = YAML.safe_load_file("campaign.yml.example")
  known = HiveBench::Candidates.all.map(&:id)
  missing_candidates = data.fetch("candidates") - known
  missing_tasks = data.fetch("tasks").reject { |slug| File.file?(File.join("corpus", slug, "manifest.yml")) }
  abort("missing candidate(s): #{missing_candidates.join(", ")}") unless missing_candidates.empty?
  abort("missing task(s): #{missing_tasks.join(", ")}") unless missing_tasks.empty?
'

WORKDIR="$(mktemp -d)"
PROJECT="$WORKDIR/project"
STATE="$PROJECT/.hive-state"
SLUG="bench-smoke-260709-aa11"
mkdir -p "$STATE/workflows" "$STATE/stages/1-inbox/$SLUG" "$PROJECT/harness"
cp -R workflows/bench.yml workflows/bench "$STATE/workflows/"
printf '# stub hive_run for path anchor smoke\n' >"$PROJECT/harness/hive_run.rb"

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

GATE_DIR="$STATE/stages/3-generate/$SLUG-gate"
mkdir -p "$GATE_DIR"
awk '/^```bash$/ { in_block = 1; next } /^```$/ && in_block { exit } in_block { print }' \
  workflows/bench/generate.md >"$GATE_DIR/generate.sh"
(
  cd "$GATE_DIR"
  bash generate.sh
)

tail -n 1 "$GATE_DIR/generate.md" | grep -qx '<!-- WAITING -->'
grep -q 'Missing campaign.yml' "$GATE_DIR/generate.md"

echo "bench workflow smoke ok"
