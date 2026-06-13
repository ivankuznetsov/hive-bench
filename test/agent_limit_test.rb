# frozen_string_literal: true

require "minitest/autorun"
require "lib/agent_limit"

class AgentLimitTest < Minitest::Test
  L = HiveBench::AgentLimit

  def test_detects_session_and_usage_limit_walls
    assert L.limit_hit?("You've hit your session limit · resets 8pm")
    assert L.limit_hit?("Error: you've hit your usage limit for today")
    assert L.limit_hit?("Purchase more usage credits to continue")
  end

  def test_detects_429_and_quota_errors
    assert L.limit_hit?("HTTP 429 Too Many Requests")
    assert L.limit_hit?("RESOURCE_EXHAUSTED: quota exceeded")
    assert L.limit_hit?("insufficient_quota")
  end

  def test_ignores_benign_limit_chrome
    refute L.limit_hit?("Included in your plan limits until Jun 22")
    refute L.limit_hit?("Run /status to see usage limits and account info")
    refute L.limit_hit?("Your usage limits reset on July 1")
    refute L.limit_hit?("Approaching session limit — consider /compact")
  end

  def test_ignores_unrelated_text
    refute L.limit_hit?("implemented the feature and all tests pass")
    refute L.limit_hit?("")
    refute L.limit_hit?(nil)
  end

  def test_strips_ansi_before_matching
    assert L.limit_hit?("\e[31myou've hit your usage limit\e[0m")
  end
end
