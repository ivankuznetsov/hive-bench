# frozen_string_literal: true

require "minitest/autorun"
require "lib/judge_provenance"

class JudgeProvenanceTest < Minitest::Test
  JP = HiveBench::JudgeProvenance

  def test_sol_records_its_explicit_xhigh_effort
    assert_equal(
      { "reasoning_effort" => "xhigh", "reasoning_effort_explicit" => true },
      JP.metadata("gpt-5.6-sol")
    )
  end

  def test_judges_without_an_effort_flag_are_recorded_as_unspecified
    %w[fable-5 gpt-5.5-pro unknown-judge].each do |name|
      assert_equal(
        { "reasoning_effort" => "unspecified", "reasoning_effort_explicit" => false },
        JP.metadata(name)
      )
    end
  end

  def test_campaign_override_records_sol_ultra
    assert_equal(
      { "reasoning_effort" => "ultra", "reasoning_effort_explicit" => true },
      JP.metadata("gpt-5.6-sol", efforts: { "gpt-5.6-sol" => "ultra" })
    )
  end

  def test_annotation_preserves_existing_scores
    document = {
      "cells" => [
        { "judges" => {
          "fable-5" => { "mean" => 7.0 },
          "gpt-5.6-sol" => { "mean" => 6.0 }
        } }
      ]
    }

    assert_same document, JP.annotate_document!(document)
    assert_in_delta(7.0, document.dig("cells", 0, "judges", "fable-5", "mean"))
    assert_equal "unspecified", document.dig("cells", 0, "judges", "fable-5", "reasoning_effort")
    assert_equal "xhigh", document.dig("cells", 0, "judges", "gpt-5.6-sol", "reasoning_effort")
  end

  def test_annotation_applies_campaign_effort_without_changing_scores
    document = { "cells" => [{ "judges" => { "gpt-5.6-sol" => { "mean" => 6.0 } } }] }

    JP.annotate_document!(document, efforts: { "gpt-5.6-sol" => "ultra" })

    assert_in_delta 6.0, document.dig("cells", 0, "judges", "gpt-5.6-sol", "mean")
    assert_equal "ultra", document.dig("cells", 0, "judges", "gpt-5.6-sol", "reasoning_effort")
  end
end
