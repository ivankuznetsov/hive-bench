# frozen_string_literal: true

require "minitest/autorun"
require "lib/openrouter_judge"

# The live HTTP call is the edge (exercised by the re-judge run); here we cover
# the offline guards. Score parsing is shared with ClaudeJudge via JudgeOutput.
class OpenRouterJudgeTest < Minitest::Test
  def test_requires_an_api_key
    err = assert_raises(HiveBench::OpenRouterJudge::Error) do
      HiveBench::OpenRouterJudge.judge_fn(model: "openai/gpt-5.5-pro", api_key: "")
    end

    assert_match(/OPENROUTER_API_KEY/, err.message)
  end

  def test_builds_a_judge_fn_with_a_key
    fn = HiveBench::OpenRouterJudge.judge_fn(model: "openai/gpt-5.5-pro", api_key: "sk-or-test")

    assert_respond_to fn, :call
  end

  def test_score_parsing_is_shared_and_rejects_non_numeric
    assert_equal 7, HiveBench::JudgeOutput.parse_score(%({"score": 7, "reason": "ok"}))[:score]
    assert_raises(HiveBench::JudgeOutput::Error) { HiveBench::JudgeOutput.parse_score(%({"score": null})) }
  end
end
