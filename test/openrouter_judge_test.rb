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

  # The request body must always cap max_tokens so OpenRouter reserves only that
  # much output cost — leaving it unset reserves the model's full ceiling (~$11.8
  # for gpt-5.5-pro) and trips a 402 reservation on a low balance.
  def test_body_caps_max_tokens_to_bound_reserved_cost
    body = HiveBench::OpenRouterJudge.build_body("openai/gpt-5.5-pro", 1, "judge this", 32_768)

    assert_equal 32_768, body["max_tokens"]
    assert_operator body["max_tokens"], :<, 65_536, "must be below the model's full output ceiling"
    assert_equal "judge this", body.dig("messages", 0, "content")
  end

  def test_default_max_output_tokens_is_a_sane_cap
    assert_operator HiveBench::OpenRouterJudge::MAX_OUTPUT_TOKENS, :<=, 32_768, "keep the reservation bounded"
    assert_operator HiveBench::OpenRouterJudge::MAX_OUTPUT_TOKENS, :>=, 8_192,
                    "leave headroom for reasoning + the verdict so it isn't truncated"
  end
end
