# frozen_string_literal: true

require "minitest/autorun"
require "lib/pricing"

class PricingTest < Minitest::Test
  P = HiveBench::Pricing

  def test_prices_a_claude_candidate_at_usual_tier
    # 1M in @ $5 + 1M out @ $25 + 10M cached @ $0.50
    est = P.estimate_usd(model_strings: ["all-opus-4.8", "claude-opus-4-8"],
                         input: 1_000_000, output: 1_000_000, cached: 10_000_000)

    assert_in_delta 35.0, est, 0.001
  end

  def test_prices_open_models_at_their_own_rates
    est = P.estimate_usd(model_strings: ["pi@glm-5.2"], input: 1_000_000, output: 1_000_000)

    assert_in_delta 3.95, est, 0.001
  end

  def test_mixed_family_candidate_gets_no_estimate
    assert_nil P.estimate_usd(model_strings: ["opus-plan->codex-exec"], input: 1_000_000),
               "mixed-family tokens cannot be priced without per-stage attribution"
  end

  def test_unknown_model_gets_no_estimate
    assert_nil P.estimate_usd(model_strings: ["mystery-model"], input: 1_000_000)
  end

  def test_nil_token_counts_price_as_zero
    assert_in_delta 0.0, P.estimate_usd(model_strings: ["gpt-5.5"], input: nil, output: nil, cached: nil), 0.0001
  end
end
