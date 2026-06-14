# frozen_string_literal: true

require "minitest/autorun"
require "score"
require "gate"
require "judge"

class ScoreTest < Minitest::Test
  def gate_result(status:, subset:)
    HiveBench::Gate::Result.new(status: status, subset: subset, reason: "", details: {})
  end

  def judge_result(mean:)
    HiveBench::Judge::Result.new(mean: mean, stddev: 0.5, scores: [mean], interval: [mean - 0.5, mean + 0.5], reference_withheld: false)
  end

  def cell(agent:, mode: "fresh", cost: 0.10, wall: 30.0)
    { task_id: "t#{rand(1000)}", agent_id: agent, mode: mode, model_version: "m",
      telemetry: { "cost_usd" => cost, "wall_clock_sec" => wall } }
  end

  def scorer = HiveBench::Score.new

  def test_cell_record_shape
    rec = scorer.cell_record(
      cell: cell(agent: "claude@opus-4.8"),
      gate: gate_result(status: :pass, subset: "gated"),
      judge: judge_result(mean: 8.0)
    )

    assert_equal "gated", rec["subset"]
    assert_equal "pass", rec.dig("gate", "status")
    assert_in_delta(8.0, rec.dig("judge", "mean"))
    assert_in_delta(0.10, rec.dig("efficiency", "cost_usd"))
  end

  def test_judged_subset_cell_has_no_gate_pass_but_keeps_judge
    rec = scorer.cell_record(
      cell: cell(agent: "pi@glm-5.2"),
      gate: gate_result(status: :no_gate, subset: "judged"),
      judge: judge_result(mean: 6.0)
    )

    assert_equal "judged", rec["subset"]
    assert_equal "no_gate", rec.dig("gate", "status")
    assert_in_delta(6.0, rec.dig("judge", "mean"))
  end

  def test_aggregate_separates_gated_and_judged_and_computes_pass_rate
    records = [
      scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :pass, subset: "gated"), judge: judge_result(mean: 8.0)),
      scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :fail, subset: "gated"), judge: judge_result(mean: 5.0)),
      scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :no_gate, subset: "judged"), judge: judge_result(mean: 7.0))
    ]
    out = scorer.results(records: records, corpus_version: "v1", generated_at: "2026-06-14T00:00:00Z")
    a = out["agents"]["A"]

    assert_equal 2, a.dig("gated", "total")
    assert_equal 1, a.dig("gated", "passed")
    assert_in_delta(0.5, a.dig("gated", "pass_rate"))
    assert_equal 3, a.dig("judged", "scored_cells")
    assert_in_delta 6.667, a.dig("judged", "mean_quality"), 0.01
  end

  def test_preliminary_flag_below_minimum_cells
    records = [scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :pass, subset: "gated"),
                                  judge: judge_result(mean: 8.0))]
    out = scorer.results(records: records, corpus_version: "v1", generated_at: "t", min_cells: 10)

    assert out["agents"]["A"]["preliminary"], "1 cell < 10 must be flagged preliminary"
  end

  def test_wall_clock_only_aggregates_fresh_cells
    records = [
      scorer.cell_record(cell: cell(agent: "A", mode: "fresh", wall: 40.0), gate: gate_result(status: :pass, subset: "gated"), judge: nil),
      scorer.cell_record(cell: cell(agent: "A", mode: "reused", wall: nil), gate: gate_result(status: :pass, subset: "gated"), judge: nil)
    ]
    out = scorer.results(records: records, corpus_version: "v1", generated_at: "t")
    eff = out["agents"]["A"]["efficiency"]

    assert_equal 1, eff["wall_clock_sample"], "reused cells contribute no wall-clock"
    assert_in_delta 40.0, eff["mean_wall_clock_sec"], 0.01
    assert_equal 1, out["agents"]["A"].dig("provenance", "reused")
  end

  def test_results_json_round_trips
    records = [scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :pass, subset: "gated"),
                                  judge: judge_result(mean: 8.0))]
    out = scorer.results(records: records, corpus_version: "v1", generated_at: "t")
    reparsed = JSON.parse(JSON.generate(out))

    assert_equal "hive-bench-results", reparsed["schema"]
    assert_equal 1, reparsed["cells"].size
  end
end
