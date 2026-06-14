# frozen_string_literal: true

require "json"

module HiveBench
  # Scoring tier 3 + assembly. Combines a cell's gate verdict, judge result, and
  # efficiency telemetry into one cell record, then aggregates cells per agent
  # into the results.json the leaderboard (U7) renders.
  #
  # The aggregate keeps the gated and judged subsets SEPARATE (the gate is the
  # objective floor; judged-only cells have no gate), and flags an agent
  # "preliminary" below a minimum cell count so a thin sample isn't ranked as if
  # it were settled (the LMSYS pattern).
  class Score
    PRELIMINARY_MIN_CELLS = 10

    # cell: { task_id, agent_id, mode, model_version, telemetry }
    # gate: HiveBench::Gate::Result ; judge: HiveBench::Judge::Result | nil
    def cell_record(cell:, gate:, judge:)
      {
        "task_id" => cell.fetch(:task_id),
        "agent_id" => cell.fetch(:agent_id),
        "mode" => cell.fetch(:mode),
        "model_version" => cell[:model_version],
        "subset" => gate.subset,
        "gate" => { "status" => gate.status.to_s, "reason" => gate.reason },
        "judge" => judge && {
          "mean" => judge.mean, "interval" => judge.interval,
          "reference_withheld" => judge.reference_withheld
        },
        "efficiency" => cell[:telemetry] || {}
      }
    end

    # records: array of cell_record hashes. Returns the full results.json hash.
    def results(records:, corpus_version:, generated_at:, min_cells: PRELIMINARY_MIN_CELLS)
      by_agent = records.group_by { |r| r["agent_id"] }
      agents = by_agent.transform_values { |rs| agent_summary(rs, min_cells) }
      {
        "schema" => "hive-bench-results",
        "schema_version" => 1,
        "corpus_version" => corpus_version,
        "generated_at" => generated_at,
        "cells" => records,
        "agents" => agents
      }
    end

    private

    def agent_summary(records, min_cells)
      gated = records.select { |r| r["subset"] == "gated" }
      judged_scored = records.select { |r| r.dig("judge", "mean") }
      passed = gated.count { |r| r.dig("gate", "status") == "pass" }

      {
        "cells" => records.size,
        "preliminary" => records.size < min_cells,
        "gated" => {
          "total" => gated.size,
          "passed" => passed,
          "pass_rate" => gated.empty? ? nil : (passed.to_f / gated.size).round(3)
        },
        "judged" => {
          "scored_cells" => judged_scored.size,
          "mean_quality" => mean_of(judged_scored.map { |r| r.dig("judge", "mean") })
        },
        "efficiency" => efficiency_summary(records),
        "provenance" => {
          "reused" => records.count { |r| r["mode"] == "reused" },
          "fresh" => records.count { |r| r["mode"] == "fresh" }
        }
      }
    end

    def efficiency_summary(records)
      costs = records.filter_map { |r| r.dig("efficiency", "cost_usd") }
      # wall-clock only from fresh cells (reused cells have none — by design).
      walls = records.select { |r| r["mode"] == "fresh" }.filter_map { |r| r.dig("efficiency", "wall_clock_sec") }
      {
        "total_cost_usd" => costs.empty? ? nil : costs.sum.round(4),
        "mean_wall_clock_sec" => mean_of(walls),
        "wall_clock_sample" => walls.size
      }
    end

    def mean_of(values)
      return nil if values.empty?

      (values.sum.to_f / values.size).round(3)
    end
  end
end
