#!/usr/bin/env ruby
# frozen_string_literal: true

harness_dir = File.expand_path("../harness", __dir__)
$LOAD_PATH.unshift(harness_dir) unless $LOAD_PATH.include?(harness_dir)

# Validates one corpus entry and writes a machine-readable verdict. Run by the
# validate-submission workflow inside the isolated runner; exits non-zero on
# reject so the PR check fails.
#
#   ruby validator/cli.rb <entry_dir> [--result result.json]

require "json"
require_relative "validate"
require_relative "../harness/gate"
require_relative "../harness/lib/isolation_exec"

entry_dir = ARGV.find { |a| !a.start_with?("--") } or abort("usage: validator/cli.rb <entry_dir>")
result_path = (i = ARGV.index("--result")) ? ARGV[i + 1] : nil

# Reproducibility runs the task's gate inside the no-network runner.
gate_runner = lambda do |entry:, gate_spec:, candidate_patch:, work_dir:|
  HiveBench::Gate.new(exec: HiveBench::IsolationExec.gate_exec).call(
    entry: entry, gate_spec: gate_spec, candidate_patch: candidate_patch, work_dir: work_dir
  )
end

work = File.join(Dir.pwd, "tmp", "validate-work")
res = HiveBench::Validator.new(gate_runner: gate_runner).call(entry_dir: entry_dir, work_dir: work)

warn res
if result_path
  File.write(result_path, JSON.pretty_generate(
                            "entry" => entry_dir, "ok" => res.ok, "subset" => res.subset,
                            "failures" => res.failures, "warnings" => res.warnings
                          ))
end
exit(res.ok ? 0 : 1)
