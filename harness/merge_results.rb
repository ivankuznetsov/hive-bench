# frozen_string_literal: true

# Make the harness dir importable when run directly (`ruby harness/merge_results.rb`).
$LOAD_PATH.unshift(__dir__) unless $LOAD_PATH.include?(__dir__)

require "json"
require "score"

module HiveBench
  # Combines several per-agent results.json files (each from a separate `run_all`
  # pass) into ONE leaderboard results.json: unions their cells, re-aggregates the
  # per-agent summaries, and unions pending/failed. This lets agents run in
  # separate passes — the expensive fresh glm/claude passes, the cheap reused 4.7
  # pass — without re-running everything to get a single artifact.
  module Merge
    module_function

    def combine(results_list, corpus_version:, generated_at:, scorer: Score.new)
      cells = results_list.flat_map { |r| r["cells"] || [] }
      out = scorer.results(records: cells, corpus_version: corpus_version, generated_at: generated_at)
      out["pending"] = results_list.flat_map { |r| r["pending"] || [] }
      out["failed"] = results_list.flat_map { |r| r["failed"] || [] }
      out
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"
  require "fileutils"

  opts = { out: "runs/results.json", corpus_version: "v1" }
  OptionParser.new do |o|
    o.banner = "Usage: ruby harness/merge_results.rb [--out PATH] [--corpus-version V] <results.json>..."
    o.on("--out PATH", "combined output (default: runs/results.json)") { |v| opts[:out] = v }
    o.on("--corpus-version V", "default: v1") { |v| opts[:corpus_version] = v }
  end.parse!(ARGV)
  abort("give at least one results.json to merge") if ARGV.empty?

  results = ARGV.map { |p| JSON.parse(File.read(p)) }
  combined = HiveBench::Merge.combine(results, corpus_version: opts[:corpus_version],
                                               generated_at: Time.now.utc.iso8601)
  FileUtils.mkdir_p(File.dirname(opts[:out]))
  File.write(opts[:out], "#{JSON.pretty_generate(combined)}\n")
  warn "merged #{ARGV.size} file(s) -> #{opts[:out]}: #{combined["cells"].size} cells, " \
       "agents=#{combined["agents"].keys.sort.join(", ")}"
end
