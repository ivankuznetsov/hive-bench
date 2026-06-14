# frozen_string_literal: true

require "yaml"
require "lib/git_restore"
require "lib/test_result_parser"

module HiveBench
  # Scoring tier 1 — the objective floor. Restores a clean repo at base, applies
  # the candidate's persisted diff (NOT the candidate's possibly-dirty worktree —
  # generation and evaluation are separate), runs install + test commands in the
  # no-network gate container, and passes the cell iff the task's FAIL_TO_PASS
  # tests flipped to passing and its PASS_TO_PASS tests stayed green
  # (SWE-bench's criterion).
  #
  # Tasks whose gate is uncurated or has no FAIL_TO_PASS are `:no_gate` and land
  # in the "judged" subset (scored by tiers 2–3 only). The gated:judged split is
  # what the leaderboard publishes so the "objective floor" isn't overstated.
  class Gate
    Result = Data.define(:status, :subset, :reason, :details) do
      def gated? = subset == "gated"
    end

    # exec: ->(cmd:, work_dir:) => { output: String, ok: Boolean }
    #   In production this runs the command inside the `--network none` runner
    #   (isolation.sh gate mode). Injected as a seam so tests run offline.
    def initialize(exec:, restorer: GitRestore.new, parser: TestResultParser)
      @exec = exec
      @restorer = restorer
      @parser = parser
    end

    # entry: loaded manifest hash (+ entry_dir, checkout_source).
    # gate_spec: the parsed gate/gate.yml.
    # candidate_patch: the diff string to score.
    def call(entry:, gate_spec:, candidate_patch:, work_dir:)
      return judged("gate not curated") if gate_spec["needs_curation"]

      f2p = Array(gate_spec["fail_to_pass"])
      p2p = Array(gate_spec["pass_to_pass"])
      return judged("no FAIL_TO_PASS tests declared") if f2p.empty?

      @restorer.restore(source: entry.fetch("checkout_source"),
                        base_commit: entry.dig("source", "base_commit"), into: work_dir)
      return error("candidate diff did not apply at base") unless @restorer.apply(work_dir: work_dir, patch: candidate_patch.to_s)

      run_gate(gate_spec, work_dir, f2p, p2p)
    end

    private

    def run_gate(gate_spec, work_dir, f2p, p2p)
      if (install = gate_spec["install_cmd"])
        ires = @exec.call(cmd: install, work_dir: work_dir)
        return error("install failed: #{install}") unless ires[:ok]
      end

      tres = @exec.call(cmd: gate_spec.fetch("test_cmd"), work_dir: work_dir)
      parsed = @parser.parse(tres[:output])
      return error("test command produced no parseable result") unless parsed.ran

      classify(parsed, f2p, p2p)
    end

    def classify(parsed, f2p, p2p)
      f2p_ok = f2p.all? { |name| @parser.test_outcome(parsed, name) }
      # PASS_TO_PASS: each named regression test must still pass; if no per-name
      # signal exists, fall back to the whole suite being green.
      p2p_ok = if parsed.by_name.empty?
                 parsed.suite_green?
               else
                 p2p.all? { |name| @parser.test_outcome(parsed, name) }
               end

      if f2p_ok && p2p_ok
        gated(:pass, "FAIL_TO_PASS flipped and PASS_TO_PASS held")
      else
        gated(:fail, failure_reason(f2p_ok, p2p_ok))
      end
    end

    # Only called when the run is not a pass, so at least one of the two is
    # false. f2p failure takes precedence; otherwise it's a p2p regression.
    # Total by construction — never returns nil.
    def failure_reason(f2p_ok, _p2p_ok)
      return "FAIL_TO_PASS tests did not all pass" unless f2p_ok

      "PASS_TO_PASS regression: a guard test broke"
    end

    def gated(status, reason)
      Result.new(status: status, subset: "gated", reason: reason, details: {})
    end

    def judged(reason)
      Result.new(status: :no_gate, subset: "judged", reason: reason, details: {})
    end

    def error(reason)
      Result.new(status: :error, subset: "gated", reason: reason, details: {})
    end
  end
end
