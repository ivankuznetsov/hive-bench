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

  # One named judge by default; pass a hash for multi-judge cases.
  def judges(mean: 8.0)
    { "opus-4.8" => judge_result(mean: mean) }
  end

  def cell(agent:, mode: "fresh", cost: 0.10, wall: 30.0, run_status: "generated")
    { task_id: "t#{rand(1000)}", agent_id: agent, mode: mode, model_version: "m",
      run_status: run_status, telemetry: { "cost_usd" => cost, "wall_clock_sec" => wall } }
  end

  def scorer = HiveBench::Score.new

  def test_cell_record_shape
    rec = scorer.cell_record(
      cell: cell(agent: "claude@opus-4.8"),
      gate: gate_result(status: :pass, subset: "gated"),
      judges: judges(mean: 8.0)
    )

    assert_equal "gated", rec["subset"]
    assert_equal "pass", rec.dig("gate", "status")
    assert_in_delta(8.0, rec.dig("judges", "opus-4.8", "mean"))
    assert_equal "unspecified", rec.dig("judges", "opus-4.8", "reasoning_effort")
    refute rec.dig("judges", "opus-4.8", "reasoning_effort_explicit")
    assert_in_delta(0.10, rec.dig("efficiency", "cost_usd"))
  end

  def test_cell_record_holds_multiple_independent_judges
    rec = scorer.cell_record(
      cell: cell(agent: "pi@glm-5.2"),
      gate: gate_result(status: :no_gate, subset: "judged"),
      judges: { "opus-4.8" => judge_result(mean: 6.0), "gpt-5.5-pro" => judge_result(mean: 4.0) }
    )

    assert_in_delta(6.0, rec.dig("judges", "opus-4.8", "mean"))
    assert_in_delta(4.0, rec.dig("judges", "gpt-5.5-pro", "mean"))
  end

  def test_aggregate_separates_gated_and_judged_and_computes_pass_rate
    records = [
      scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :pass, subset: "gated"), judges: judges(mean: 8.0)),
      scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :fail, subset: "gated"), judges: judges(mean: 5.0)),
      scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :no_gate, subset: "judged"), judges: judges(mean: 7.0))
    ]
    out = scorer.results(records: records, corpus_version: "v1", generated_at: "2026-06-14T00:00:00Z")
    a = out["agents"]["A"]

    assert_equal 2, a.dig("gated", "total")
    assert_equal 1, a.dig("gated", "passed")
    assert_in_delta(0.5, a.dig("gated", "pass_rate"))
    assert_equal 3, a.dig("judged", "scored_cells")
    assert_in_delta 6.667, a.dig("judged", "mean_quality", "opus-4.8"), 0.01
  end

  def test_mean_quality_is_per_judge
    records = [
      scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :no_gate, subset: "judged"),
                         judges: { "opus-4.8" => judge_result(mean: 8.0), "gpt-5.5-pro" => judge_result(mean: 2.0) }),
      scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :no_gate, subset: "judged"),
                         judges: { "opus-4.8" => judge_result(mean: 6.0), "gpt-5.5-pro" => judge_result(mean: 4.0) })
    ]
    mq = scorer.results(records: records, corpus_version: "v1", generated_at: "t")["agents"]["A"].dig("judged", "mean_quality")

    assert_in_delta 7.0, mq["opus-4.8"], 0.01
    assert_in_delta 3.0, mq["gpt-5.5-pro"], 0.01, "two judges are never collapsed into one number"
  end

  def test_preliminary_flag_below_minimum_cells
    records = [scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :pass, subset: "gated"),
                                  judges: judges(mean: 8.0))]
    out = scorer.results(records: records, corpus_version: "v1", generated_at: "t", min_cells: 10)

    assert out["agents"]["A"]["preliminary"], "1 cell < 10 must be flagged preliminary"
  end

  def test_wall_clock_only_aggregates_fresh_cells
    records = [
      scorer.cell_record(cell: cell(agent: "A", mode: "fresh", wall: 40.0), gate: gate_result(status: :pass, subset: "gated"), judges: {}),
      scorer.cell_record(cell: cell(agent: "A", mode: "reused", wall: nil), gate: gate_result(status: :pass, subset: "gated"), judges: {})
    ]
    out = scorer.results(records: records, corpus_version: "v1", generated_at: "t")
    eff = out["agents"]["A"]["efficiency"]

    assert_equal 1, eff["wall_clock_sample"], "reused cells contribute no wall-clock"
    assert_in_delta 40.0, eff["mean_wall_clock_sec"], 0.01
    assert_equal 1, out["agents"]["A"].dig("provenance", "reused")
  end

  def test_cell_record_carries_run_status
    rec = scorer.cell_record(
      cell: cell(agent: "pi@glm-5.2", run_status: "timed_out"),
      gate: gate_result(status: :no_gate, subset: "judged"),
      judges: judges(mean: 1.25)
    )

    assert_equal "timed_out", rec["run_status"], "a truncated run is visibly distinct from a clean completion"
  end

  def test_agent_summary_tallies_generation_outcomes
    records = [
      scorer.cell_record(cell: cell(agent: "A", run_status: "generated"), gate: gate_result(status: :no_gate, subset: "judged"),
                         judges: judges(mean: 8.0)),
      scorer.cell_record(cell: cell(agent: "A", run_status: "timed_out"), gate: gate_result(status: :no_gate, subset: "judged"),
                         judges: judges(mean: 2.0))
    ]
    gen = scorer.results(records: records, corpus_version: "v1", generated_at: "t")["agents"]["A"]["generation"]

    assert_equal 1, gen["generated"]
    assert_equal 1, gen["timed_out"], "the tally makes a mean built partly on truncated work transparent"
  end

  def test_same_family_judge_scores_are_flagged_and_excluded_from_cross_family_mean
    rec = scorer.cell_record(
      cell: cell(agent: "all-opus-4.8").merge(model_version: "claude-opus-4-8"),
      gate: gate_result(status: :no_gate, subset: "judged"),
      judges: { "fable-5" => judge_result(mean: 8.0), "gpt-5.5-pro" => judge_result(mean: 4.0) }
    )

    assert rec.dig("judges", "fable-5", "same_family"), "fable judging an anthropic candidate is same-family"
    refute rec.dig("judges", "gpt-5.5-pro", "same_family")

    out = scorer.results(records: [rec], corpus_version: "v2", generated_at: "2026-07-01T00:00:00Z")
    cross = out["agents"]["all-opus-4.8"].dig("judged", "mean_quality_cross_family")

    assert_nil cross["fable-5"], "same-family scores must not enter the headline mean"
    assert_in_delta 4.0, cross["gpt-5.5-pro"]
  end

  # merge_results.rb unions STORED judge hashes — legacy records have no
  # same_family key. The cross-family mean must recompute from the record's own
  # agent/model fields, never trust (or miss) the stored flag.
  def test_cross_family_mean_recomputes_family_for_legacy_records_without_flag
    legacy = scorer.cell_record(
      cell: cell(agent: "all-opus-4.8").merge(model_version: "claude-opus-4-8"),
      gate: gate_result(status: :no_gate, subset: "judged"),
      judges: { "opus-4.8" => judge_result(mean: 9.0) }
    )
    legacy["judges"]["opus-4.8"].delete("same_family") # simulate a pre-flag record

    out = scorer.results(records: [legacy], corpus_version: "v1", generated_at: "2026-07-01T00:00:00Z")

    assert_nil out["agents"]["all-opus-4.8"].dig("judged", "mean_quality_cross_family", "opus-4.8"),
               "a missing flag must not smuggle a same-family score into the headline"
  end

  def test_results_json_round_trips
    records = [scorer.cell_record(cell: cell(agent: "A"), gate: gate_result(status: :pass, subset: "gated"),
                                  judges: judges(mean: 8.0))]
    out = scorer.results(records: records, corpus_version: "v1", generated_at: "t")
    reparsed = JSON.parse(JSON.generate(out))

    assert_equal "hive-bench-results", reparsed["schema"]
    assert_equal 1, reparsed["cells"].size
  end
end
