# frozen_string_literal: true

require "minitest/autorun"
require "merge_results"

# Verifies that per-agent result files combine into one leaderboard artifact:
# cells unioned, per-agent summaries re-aggregated, pending/failed unioned.
class MergeResultsTest < Minitest::Test
  def cell(agent:, task:, mode: "fresh", run_status: "generated", judge_mean: 7.0)
    { "task_id" => task, "agent_id" => agent, "mode" => mode, "run_status" => run_status,
      "subset" => "judged", "gate" => { "status" => "no_gate" },
      "judges" => { "opus-4.8" => { "mean" => judge_mean, "interval" => [judge_mean, judge_mean] } },
      "efficiency" => { "cost_usd" => 0.5, "wall_clock_sec" => 100.0 } }
  end

  def file(cells, pending: [], failed: [])
    { "cells" => cells, "pending" => pending, "failed" => failed }
  end

  def test_unions_cells_and_reaggregates_per_agent
    glm = file([cell(agent: "pi@glm-5.2", task: "t1", run_status: "timed_out", judge_mean: 7.75)])
    inc = file([cell(agent: "claude@opus-4.7", task: "t1", mode: "reused", judge_mean: 4.5)])
    out = HiveBench::Merge.combine([glm, inc], corpus_version: "v1", generated_at: "t")

    assert_equal 2, out["cells"].size
    assert_equal %w[claude@opus-4.7 pi@glm-5.2], out["agents"].keys.sort
    assert_equal({ "timed_out" => 1 }, out["agents"]["pi@glm-5.2"]["generation"])
    assert_equal 1, out["agents"]["claude@opus-4.7"].dig("provenance", "reused")
  end

  def test_unions_pending_and_failed
    a = file([cell(agent: "A", task: "t1")], pending: [{ "agent_id" => "A", "task_id" => "t9" }])
    b = file([cell(agent: "B", task: "t1")], failed: [{ "agent_id" => "B", "task_id" => "t8" }])
    out = HiveBench::Merge.combine([a, b], corpus_version: "v1", generated_at: "t")

    assert_equal 1, out["pending"].size
    assert_equal 1, out["failed"].size
  end

  def test_tolerates_files_missing_optional_keys
    out = HiveBench::Merge.combine([{ "cells" => [cell(agent: "A", task: "t1")] }, {}],
                                   corpus_version: "v1", generated_at: "t")

    assert_equal 1, out["cells"].size
    assert_empty out["pending"]
  end
end
