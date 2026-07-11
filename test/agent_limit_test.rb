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

  def test_detects_hive_stage_limits_reached_marker
    # The exact shape hive writes to stage.err when a provider wall hits
    # mid-stage (seen live 2026-07-03: an opus cell misclassified execute_failed).
    assert L.limit_hit?('hive: stage recorded :error ({"reason" => "limits_reached", "provider" => "claude", ' \
                        '"message" => "implementer hit a usage/credit limit", "retry_after" => "2026-07-03T11:14:16Z"})')
  end

  def test_detects_429_and_quota_errors
    assert L.limit_hit?("HTTP 429 Too Many Requests")
    assert L.limit_hit?("RESOURCE_EXHAUSTED: quota exceeded")
    assert L.limit_hit?("insufficient_quota")
    assert L.limit_hit?("rate limit reached"), "OpenRouter phrases throttling as 'rate limit reached'"
    assert L.limit_hit?("Error: rate limit exceeded")
  end

  def test_detects_openrouter_402_insufficient_credits
    # The exact string Pi surfaces on a drained OpenRouter balance.
    assert L.limit_hit?('"errorMessage":"402 Insufficient credits. Add more using https://openrouter.ai/settings/credits"')
    assert L.limit_hit?("Error 402: insufficient balance")
    # The judge-path phrasing of the same wall (seen live 2026-07-06).
    assert L.limit_hit?('402: {"error":{"message":"This request requires more credits, or fewer max_tokens..."}}')
    refute L.limit_hit?("the function returns 402 widgets after the loop"), "bare 402 unrelated to billing is not a limit"
  end

  def test_detects_openrouter_403_key_limit_exceeded
    # OpenRouter 403 once a key hits its spend cap.
    assert L.limit_hit?('openrouter judge HTTP 403: {"error":{"message":"Key limit exceeded (total limit)","code":403}}')
    assert L.limit_hit?("Error: spending limit exceeded")
    refute L.limit_hit?("access forbidden: 403 you lack permission"), "a plain 403 auth error is not a spend limit"
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

  def test_retry_after_uses_explicit_utc_reset_with_boundary_grace
    now = Time.utc(2026, 7, 11, 22, 55)

    assert_equal "2026-07-12T00:01:00Z",
                 L.retry_after("You've hit your session limit · resets 12am (UTC)", now: now)
    assert_equal "2026-07-11T23:31:00Z",
                 L.retry_after("resets 11:30pm (UTC)", now: now)
  end

  def test_retry_after_falls_back_without_an_explicit_utc_hint
    now = Time.utc(2026, 7, 11, 22, 55)

    assert_equal "2026-07-11T23:55:00Z", L.retry_after("limit reached", now: now)
    assert_equal "2026-07-11T23:55:00Z", L.retry_after("resets 12am (Europe/London)", now: now)
    assert_equal "2026-07-11T23:55:00Z", L.retry_after("resets 13pm (UTC)", now: now)
    assert_equal "2026-07-11T23:55:00Z", L.retry_after("resets 12:99am (UTC)", now: now)
  end

  def test_retry_after_normalizes_the_clock_to_utc_before_choosing_the_date
    now = Time.new(2026, 7, 12, 0, 55, 0, "+02:00")

    assert_equal "2026-07-12T00:01:00Z",
                 L.retry_after("resets 12am (UTC)", now: now)
  end
end
