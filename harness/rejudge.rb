# frozen_string_literal: true

# Re-scores ALREADY-GENERATED cells without re-running the agents: re-captures
# each fresh cell's diff from its work tree (picking up the new-files capture
# fix) and judges every cell with one or more judges, then writes a combined
# results.json. Reused incumbent cells keep their recorded candidate.patch.
#
#   OPENROUTER_API_KEY=… ruby harness/rejudge.rb --source <clone> \
#     --results runs/results.json --out runs/results.json <search-dir>...
#
# Cells (and their original telemetry) come from --results; each cell's artifacts
# (work/ or candidate.patch) are located by searching the given run dirs for
# <dir>/<task>/<cell>. No generation is re-run.
$LOAD_PATH.unshift(__dir__) unless $LOAD_PATH.include?(__dir__)

require "json"
require "optparse"
require "fileutils"
require "score"
require "gate"
require "judge"
require "lib/corpus"
require "lib/git_restore"
require "lib/claude_judge"
require "lib/openrouter_judge"

module HiveBench
  # Offline re-judge: same scoring contract as RunAll, but the diff comes from
  # existing artifacts instead of a fresh generation.
  module Rejudge
    module_function

    NO_GATE = Gate::Result.new(status: :no_gate, subset: "judged", reason: "rejudge (no gate)", details: {})

    # withhold_reference: v1 rejudges graded on plan+diff alone; v2 cells are
    # judged vs the gold (RunAll runs withhold_reference: false), so a backfill
    # must match or its scores aren't comparable with the pass they fill.
    # only_missing_judges: skip judges the cell already has a score from — a
    # backfill must never re-buy existing scores.
    def run(cells:, search_dirs:, source:, corpus_root:, judges:, scorer: Score.new,
            restorer: GitRestore.new, withhold_reference: false, only_missing_judges: false)
      bases = Corpus.load(root: corpus_root, checkout_source: source)
                    .to_h { |e| [e["task_id"], { base: e.dig("source", "base_commit"), entry: e }] }
      records = cells.map do |old|
        rejudge_cell(old, bases, search_dirs, judges, scorer, restorer,
                     withhold_reference: withhold_reference, only_missing: only_missing_judges)
      end
      scorer.results(records: records, corpus_version: "v2", generated_at: Time.now.utc.iso8601)
    end

    def rejudge_cell(old, bases, search_dirs, judges, scorer, restorer, withhold_reference:, only_missing:)
      info = bases.fetch(old["task_id"])
      diff = recover_diff(search_dirs, old, info[:base], restorer)
      plan = read_plan(info[:entry])
      reference = withhold_reference ? nil : read_reference(info[:entry])
      wanted = only_missing ? judges.reject { |name, _| (old["judges"] || {}).key?(name) } : judges
      judged = diff.strip.empty? ? {} : judge_all(wanted, plan, diff, reference)
      warn "  judged #{old["agent_id"]} #{old["task_id"]} (#{diff.lines.size} diff lines): #{judged.transform_values(&:mean).inspect}"
      rec = scorer.cell_record(cell: cell_meta(old), gate: NO_GATE, judges: judged)
      # Keep the cell's existing judge scores; the fresh ones fill the gaps.
      rec["judges"] = (old["judges"] || {}).merge(rec["judges"] || {})
      rec
    end

    # Fail soft per judge: a flaky/limited judge (e.g. an OpenRouter key-limit 403)
    # is skipped with a warning rather than crashing the whole re-judge — the cell
    # keeps the judges that succeeded, and the failed one can be re-run later.
    def judge_all(judges, plan, diff, reference)
      judges.each_with_object({}) do |(name, judge), acc|
        acc[name] = judge.call(plan: plan, candidate_diff: diff, reference: reference)
      rescue StandardError => e
        warn "  judge #{name} failed (#{e.class}: #{e.message.to_s[0, 80]}) — skipping this judge"
      end
    end

    def read_reference(entry)
      path = File.join(entry.fetch("entry_dir"), "reference.patch")
      File.file?(path) ? File.read(path) : nil
    end

    # v2 cells persist the final diff at <cell>/target/candidate.patch (the
    # hive driver's capture); v1 fresh cells re-capture from <cell>/work.
    # Reused/other: the recorded candidate.patch at the cell root.
    def recover_diff(search_dirs, old, base, restorer)
      cell_path = search_dirs.map { |d| File.join(d, old["task_id"], cell_dir(old["agent_id"])) }
                             .find { |p| File.directory?(p) }
      return "" unless cell_path

      v2_patch = File.join(cell_path, "target", "candidate.patch")
      return File.read(v2_patch) if File.file?(v2_patch)

      work = File.join(cell_path, "work")
      if old["mode"] != "reused" && File.directory?(File.join(work, ".git"))
        restorer.diff(work_dir: work, base_commit: base)
      else
        patch = File.join(cell_path, "candidate.patch")
        File.file?(patch) ? File.read(patch) : ""
      end
    end

    def cell_meta(old)
      { task_id: old["task_id"], agent_id: old["agent_id"], mode: old["mode"],
        model_version: old["model_version"], run_status: old["run_status"], telemetry: old["efficiency"] || {} }
    end

    def read_plan(entry)
      rel = entry.dig("spec", "plan")
      path = rel && File.join(entry.fetch("entry_dir"), rel)
      path && File.file?(path) ? File.read(path) : ""
    end

    def cell_dir(agent_id) = agent_id.gsub(/[^a-z0-9]+/i, "_")
  end
end

if $PROGRAM_NAME == __FILE__
  opts = { source: nil, corpus: "corpus", results: "runs/results.json", out: "runs/results.json",
           seeds: 1, claude_judge: true, judge_model: nil, openrouter_judge: true,
           openrouter_model: "openai/gpt-5.5-pro", withhold_reference: false, only_missing: false }
  OptionParser.new do |o|
    o.banner = "Usage: OPENROUTER_API_KEY=… ruby harness/rejudge.rb --source <clone> [opts] <search-dir>..."
    o.on("--source PATH") { |v| opts[:source] = v }
    o.on("--corpus DIR") { |v| opts[:corpus] = v }
    o.on("--results PATH", "results.json holding the cells to re-judge") { |v| opts[:results] = v }
    o.on("--out PATH") { |v| opts[:out] = v }
    o.on("--seeds N", Integer) { |v| opts[:seeds] = v }
    o.on("--[no-]claude-judge") { |v| opts[:claude_judge] = v }
    o.on("--judge-model M") { |v| opts[:judge_model] = v }
    o.on("--[no-]openrouter-judge") { |v| opts[:openrouter_judge] = v }
    o.on("--openrouter-model M") { |v| opts[:openrouter_model] = v }
    o.on("--[no-]withhold-reference", "default off: judge vs the gold, matching v2 passes") { |v| opts[:withhold_reference] = v }
    o.on("--only-missing", "skip judges the cell already has a score from") { opts[:only_missing] = true }
    o.on("--max-tokens N", Integer, "openrouter judge output cap (reservation = cap x output rate; " \
                                    "lower it to backfill on a thin balance)") { |v| opts[:max_tokens] = v }
  end.parse!(ARGV)
  abort("--source is required") unless opts[:source]
  abort("give at least one search-dir") if ARGV.empty?

  judges = {}
  if opts[:claude_judge]
    model = opts[:judge_model] || "claude-fable-5"
    judges[model.sub(/\Aclaude-/, "")] =
      HiveBench::Judge.new(judge_fn: HiveBench::ClaudeJudge.judge_fn(model: model), seeds: opts[:seeds])
  end
  if opts[:openrouter_judge]
    or_kwargs = { model: opts[:openrouter_model] }
    or_kwargs[:max_tokens] = opts[:max_tokens] if opts[:max_tokens]
    judges[opts[:openrouter_model].split("/").last] =
      HiveBench::Judge.new(judge_fn: HiveBench::OpenRouterJudge.judge_fn(**or_kwargs), seeds: opts[:seeds])
  end
  abort("no judges enabled") if judges.empty?

  cells = JSON.parse(File.read(opts[:results]))["cells"]
  results = HiveBench::Rejudge.run(cells: cells, search_dirs: ARGV, source: opts[:source],
                                   corpus_root: opts[:corpus], judges: judges,
                                   withhold_reference: opts[:withhold_reference],
                                   only_missing_judges: opts[:only_missing])
  FileUtils.mkdir_p(File.dirname(opts[:out]))
  File.write(opts[:out], "#{JSON.pretty_generate(results)}\n")
  warn "wrote #{opts[:out]}: #{results["cells"].size} cells re-judged by #{judges.keys.join(" + ")}"
end
