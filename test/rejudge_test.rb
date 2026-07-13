# frozen_string_literal: true

require "minitest/autorun"
require "rejudge"

class RejudgeTest < Minitest::Test
  def test_only_missing_treats_legacy_mean_as_one_sample
    record = { "mean" => 7.0, "interval" => [7.0, 7.0] }

    assert HiveBench::Rejudge.judge_satisfied?(record, minimum_samples: 1)
    refute HiveBench::Rejudge.judge_satisfied?(record, minimum_samples: 3)
  end

  def test_only_missing_accepts_persisted_three_sample_record
    record = { "mean" => 7.0, "sample_count" => 3, "scores" => [6.0, 7.0, 8.0] }

    assert HiveBench::Rejudge.judge_satisfied?(record, minimum_samples: 3)
  end
end
