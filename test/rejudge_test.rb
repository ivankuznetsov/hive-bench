# frozen_string_literal: true

require "minitest/autorun"
require "rejudge"
require "tmpdir"

class RejudgeTest < Minitest::Test
  Rejudge = HiveBench::Rejudge

  def record(samples: 3, effort: "ultra")
    {
      "mean" => 6.0,
      "scores" => Array.new(samples, 6.0),
      "sample_count" => samples,
      "reasoning_effort" => effort
    }
  end

  def test_only_missing_treats_legacy_mean_as_one_sample
    record = { "mean" => 7.0, "interval" => [7.0, 7.0] }

    assert HiveBench::Rejudge.judge_satisfied?(record, minimum_samples: 1)
    refute HiveBench::Rejudge.judge_satisfied?(record, minimum_samples: 3)
  end

  def test_only_missing_accepts_persisted_three_sample_record
    record = { "mean" => 7.0, "sample_count" => 3, "scores" => [6.0, 7.0, 8.0] }

    assert HiveBench::Rejudge.judge_satisfied?(record, minimum_samples: 3)
  end

  def test_only_missing_replaces_a_judge_record_with_the_wrong_effort
    refute Rejudge.judge_satisfied?(
      record(effort: "xhigh"),
      minimum_samples: 3,
      expected_effort: "ultra"
    )
  end

  def test_only_missing_keeps_a_complete_record_with_the_expected_effort
    assert Rejudge.judge_satisfied?(
      record,
      minimum_samples: 3,
      expected_effort: "ultra"
    )
  end

  def test_judges_without_an_effort_pin_are_checked_by_sample_count_only
    assert Rejudge.judge_satisfied?(record(effort: "unspecified"), minimum_samples: 3)
    refute Rejudge.judge_satisfied?(record(samples: 2), minimum_samples: 3)
  end

  def test_merge_stamps_fresh_records_without_relabeling_untouched_incumbents
    existing = { "fable-5" => record(effort: "custom") }
    fresh = { "gpt-5.6-sol" => record(effort: "xhigh") }

    merged = Rejudge.merge_judge_records(existing, fresh, "gpt-5.6-sol" => "ultra")

    assert_equal "ultra", merged.dig("gpt-5.6-sol", "reasoning_effort")
    assert merged.dig("gpt-5.6-sol", "reasoning_effort_explicit")
    assert_equal "custom", merged.dig("fable-5", "reasoning_effort")
  end

  def test_rejudge_cell_replaces_only_the_wrong_effort_judge
    Dir.mktmpdir do |root|
      old = {
        "task_id" => "task-1", "agent_id" => "candidate-1", "mode" => "fresh",
        "model_version" => "candidate-model", "run_status" => "generated",
        "judges" => {
          "fable-5" => record(effort: "unspecified").merge("reasoning_effort_explicit" => false),
          "gpt-5.6-sol" => record(effort: "xhigh").merge("reasoning_effort_explicit" => true)
        }
      }
      cell_dir = File.join(root, "task-1", "candidate_1", "target")
      FileUtils.mkdir_p(cell_dir)
      File.write(File.join(cell_dir, "candidate.patch"), "diff --git a/a b/a\n")
      entry_dir = File.join(root, "entry")
      FileUtils.mkdir_p(entry_dir)
      entry = { "entry_dir" => entry_dir, "spec" => {} }
      bases = { "task-1" => { base: "unused", entry: entry } }
      calls = Hash.new(0)
      result = HiveBench::Judge::Result.new(
        mean: 8.0, stddev: 0.0, scores: [8.0, 8.0, 8.0],
        interval: [8.0, 8.0], reference_withheld: true
      )
      judges = %w[fable-5 gpt-5.6-sol].to_h do |name|
        [name, lambda do |**|
          calls[name] += 1
          result
        end]
      end

      rejudged = Rejudge.rejudge_cell(
        old, bases, [root], judges, HiveBench::Score.new, Object.new,
        withhold_reference: true, only_missing: true, minimum_samples: 3,
        judge_efforts: { "gpt-5.6-sol": "ultra" }
      )

      assert_equal 0, calls["fable-5"]
      assert_equal 1, calls["gpt-5.6-sol"]
      assert_equal old.dig("judges", "fable-5"), rejudged.dig("judges", "fable-5")
      assert_in_delta 8.0, rejudged.dig("judges", "gpt-5.6-sol", "mean")
      assert_equal "ultra", rejudged.dig("judges", "gpt-5.6-sol", "reasoning_effort")
    end
  end

  def test_merge_backfills_missing_provenance_without_overwriting_stored_values
    existing = {
      "fable-5" => { "mean" => 6.0 },
      "gpt-5.6-sol" => { "mean" => 7.0, "reasoning_effort" => "custom" }
    }

    merged = Rejudge.merge_judge_records(existing, {}, "gpt-5.6-sol" => "ultra")

    assert_equal "unspecified", merged.dig("fable-5", "reasoning_effort")
    refute merged.dig("fable-5", "reasoning_effort_explicit")
    assert_equal "custom", merged.dig("gpt-5.6-sol", "reasoning_effort")
    assert merged.dig("gpt-5.6-sol", "reasoning_effort_explicit")
  end
end
