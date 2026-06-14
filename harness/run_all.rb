# frozen_string_literal: true

require "yaml"
require "json"
require "run"
require "gate"
require "judge"
require "score"

module HiveBench
  # The benchmark-pass driver (plan U8): runs the full corpus × slate matrix and
  # emits results.json. For each cell it wires together the units below, so the
  # driver itself is thin orchestration — the heavy parts are tested in U3/U4.
  #
  #   Run (U3)   -> a candidate diff (reused or fresh) + telemetry
  #   Gate (U4)  -> objective pass/fail (judged subset when no gate)
  #   Judge (U4) -> blind quality score (skipped when there's no diff)
  #   Score (U4) -> per-cell record -> aggregated results.json
  #
  # A cell that hit a provider limit (Run status "limit_hit") is NOT scored — it
  # is collected as `pending` for a later re-run, never recorded as a failure.
  # All components are injected so a pass can be driven offline in tests.
  class RunAll
    Outcome = Data.define(:results, :pending)

    def initialize(runner:, gate:, judge:, scorer: Score.new, clock: -> { Time.now.utc })
      @runner = runner
      @gate = gate
      @judge = judge
      @scorer = scorer
      @clock = clock
    end

    # entries: array of corpus-entry hashes (manifest + entry_dir + checkout_source).
    # profiles: the candidate slate (HiveBench::Profile list).
    def call(entries:, profiles:, out_root:, corpus_version:)
      records = []
      pending = []

      entries.each do |entry|
        profiles.each do |profile|
          out_dir = File.join(out_root, entry.fetch("task_id"), cell_dir(profile))
          cell = @runner.call(entry: entry, profile: profile, out_dir: out_dir)

          if cell.status == "limit_hit"
            pending << { "task_id" => entry["task_id"], "agent_id" => profile.id, "reason" => cell.reason }
            next
          end

          records << score_cell(entry, profile, cell, out_dir)
        end
      end

      results = @scorer.results(records: records, corpus_version: corpus_version,
                                generated_at: @clock.call.iso8601)
      results["pending"] = pending
      Outcome.new(results: results, pending: pending)
    end

    private

    def score_cell(entry, _profile, cell, out_dir)
      gate_spec = load_gate(entry)
      candidate_patch = cell.diff_path ? File.read(cell.diff_path) : ""

      gate_res =
        if cell.diff_path && gate_spec
          @gate.call(entry: entry, gate_spec: gate_spec, candidate_patch: candidate_patch,
                     work_dir: File.join(out_dir, "gate"))
        else
          Gate::Result.new(status: :no_gate, subset: "judged", reason: "no diff or no gate", details: {})
        end

      judge_res = judge_cell(entry, candidate_patch)
      @scorer.cell_record(
        cell: { task_id: cell.task_id, agent_id: cell.agent_id, mode: cell.mode,
                model_version: cell.model_version, telemetry: cell.telemetry },
        gate: gate_res, judge: judge_res
      )
    end

    # Judge only a non-empty diff; reference + plan come from the entry.
    def judge_cell(entry, candidate_patch)
      return nil if candidate_patch.strip.empty?

      plan = read_entry_file(entry, entry.dig("spec", "plan"))
      reference = read_entry_file(entry, "reference.patch")
      @judge.call(plan: plan, candidate_diff: candidate_patch, reference: reference)
    end

    def load_gate(entry)
      path = File.join(entry.fetch("entry_dir"), "gate", "gate.yml")
      File.file?(path) ? YAML.safe_load_file(path) : nil
    end

    def read_entry_file(entry, rel)
      return nil if rel.nil?

      path = File.join(entry.fetch("entry_dir"), rel)
      File.file?(path) ? File.read(path) : nil
    end

    def cell_dir(profile)
      profile.id.gsub(/[^a-z0-9]+/i, "_")
    end
  end
end
