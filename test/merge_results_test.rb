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

  # The same cell split across files (opus inline, gpt-5.5-pro backfilled later)
  # merges into ONE dual-judged cell — not two rows.
  def test_unions_judges_for_the_same_cell_across_files
    inline = file([cell(agent: "codex-selfplan", task: "t1", judge_mean: 8.0)])
    gpt = { "cells" => [{ "task_id" => "t1", "agent_id" => "codex-selfplan", "mode" => "fresh",
                          "run_status" => "generated",
                          "judges" => { "gpt-5.5-pro" => { "mean" => 4.0, "interval" => [4.0, 4.0] } },
                          "efficiency" => {} }] }
    out = HiveBench::Merge.combine([inline, gpt], corpus_version: "v1", generated_at: "t")

    assert_equal 1, out["cells"].size, "the split cell is unioned, not duplicated"
    judges = out["cells"].first["judges"]

    assert_in_delta 8.0, judges.dig("opus-4.8", "mean")
    assert_in_delta 4.0, judges.dig("gpt-5.5-pro", "mean")
  end

  # A judge-only backfill carries no telemetry; the union must keep the run's cost.
  def test_judge_only_backfill_does_not_erase_generation_cost
    run = file([cell(agent: "pi@kimi-k2.7", task: "t1", judge_mean: 6.0)]) # efficiency cost_usd 0.5
    backfill = { "cells" => [{ "task_id" => "t1", "agent_id" => "pi@kimi-k2.7", "mode" => "fresh",
                               "run_status" => "generated",
                               "judges" => { "gpt-5.5-pro" => { "mean" => 3.0, "interval" => [3.0, 3.0] } },
                               "efficiency" => {} }] }
    out = HiveBench::Merge.combine([run, backfill], corpus_version: "v1", generated_at: "t")
    cell = out["cells"].first

    assert_in_delta 0.5, cell.dig("efficiency", "cost_usd"), 1e-9, "generation cost survives the judge backfill"
    assert_in_delta 3.0, cell.dig("judges", "gpt-5.5-pro", "mean")
  end
end
