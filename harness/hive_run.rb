# frozen_string_literal: true

# hive-bench v2 driver: runs each corpus task through REAL hive (plan + execute)
# for every candidate (a model configuration), then dual-judges the diff hive
# produced AGAINST the merged reference PR. Replaces pipeline_run.rb, which drove
# a reimplemented planner/executor — the whole point of v2 is that the scored diff
# is hive's actual output. Reuses RunAll's scoring/judging (the HiveDriver cell is
# shaped like a Run cell); only the runner and the reference policy differ.
#
#   OPENROUTER_API_KEY=… ruby harness/hive_run.rb --source <hive-clone> [--candidate all-opus-4.8]
$LOAD_PATH.unshift(__dir__) unless $LOAD_PATH.include?(__dir__)

require "optparse"
require "fileutils"
require "json"
require "run_all"
require "gate"
require "lib/isolation_exec"
require "lib/hive_driver"
require "lib/corpus"
require "lib/claude_judge"
require "lib/openrouter_judge"
require "profiles/candidates"

module HiveBench
  # Thin driver: a HiveDriver-backed runner handed to RunAll, judged vs the gold.
  module HiveRun
    module_function

    def main(argv)
      opts = parse(argv)
      validate!(opts)
      entries = Corpus.load(root: opts[:corpus], checkout_source: opts[:source])
      abort("no corpus entries under #{opts[:corpus]}") if entries.empty?
      candidates = select_candidates(opts[:candidate])

      outcome = RunAll.new(runner: hive_runner, gate: Gate.new(exec: IsolationExec.gate_exec),
                           judges: Driver.judges(opts), withhold_reference: opts[:withhold_reference])
                      .call(entries: entries, profiles: candidates, out_root: opts[:out],
                            corpus_version: opts[:corpus_version])
      write_and_report(outcome, opts)
    end

    # RunAll calls runner(entry:, profile:, out_dir:); here `profile` is a candidate.
    def hive_runner
      driver = HiveDriver.new
      lambda do |entry:, profile:, out_dir:|
        driver.call(entry: entry, candidate: profile, out_dir: out_dir)
      end
    end

    def parse(argv)
      opts = { corpus: "corpus", out: "runs/v2", source: nil, candidate: nil, seeds: 1,
               corpus_version: "v2", withhold_reference: false, claude_judge: true, judge_bin: "claude",
               judge_model: nil, openrouter_judge: true, openrouter_judge_model: "openai/gpt-5.5-pro" }
      OptionParser.new do |o|
        o.banner = "Usage: OPENROUTER_API_KEY=… ruby harness/hive_run.rb --source <hive-clone> [opts]"
        o.on("--source PATH", "the target repo hive runs against (cloned at base_commit)") { |v| opts[:source] = v }
        o.on("--corpus DIR") { |v| opts[:corpus] = v }
        o.on("--out DIR") { |v| opts[:out] = v }
        o.on("--candidate ID", "run only this candidate, e.g. all-opus-4.8") { |v| opts[:candidate] = v }
        o.on("--corpus-version V") { |v| opts[:corpus_version] = v }
        o.on("--[no-]withhold-reference", "default off: judge vs the reference PR") { |v| opts[:withhold_reference] = v }
        o.on("--[no-]openrouter-judge") { |v| opts[:openrouter_judge] = v }
      end.parse!(argv)
      opts
    rescue OptionParser::ParseError => e
      abort(e.message)
    end

    def validate!(opts)
      abort("--source <target repo clone> is required") unless opts[:source]
      abort("--source path #{opts[:source]} is not a directory") unless File.directory?(opts[:source])
      abort("OPENROUTER_API_KEY must be set") if opts[:openrouter_judge] && ENV["OPENROUTER_API_KEY"].to_s.empty?
    end

    def select_candidates(id)
      all = Candidates.all
      return all unless id

      picked = all.select { |c| c.id == id }
      abort("unknown candidate #{id}; candidates are #{all.map(&:id).join(", ")}") if picked.empty?
      picked
    end

    def write_and_report(outcome, opts)
      FileUtils.mkdir_p(opts[:out])
      path = File.join(opts[:out], "results.json")
      File.write(path, "#{JSON.pretty_generate(outcome.results)}\n")
      warn "wrote #{path}: #{outcome.results["cells"].size} cell(s), #{outcome.pending.size} pending, " \
           "#{outcome.failed.size} failed"
      outcome.results["cells"].each do |c|
        judges = (c["judges"] || {}).map { |n, j| "#{n}=#{j["mean"]}" }.join(" ")
        warn "  #{c["agent_id"]}  #{c["task_id"]}  gen=#{c["run_status"]}  judge[#{judges}]"
      end
      exit(2) unless outcome.failed.empty?
    end
  end
end

HiveBench::HiveRun.main(ARGV) if $PROGRAM_NAME == __FILE__
