# frozen_string_literal: true

module HiveBench
  # Detects when a candidate run hit a provider usage/credit/rate limit rather
  # than genuinely failing. A limit is not a clean exit code — it surfaces as a
  # message in the agent's stream ("you've hit your usage limit", a 429, quota
  # text). Mirrors hive's Hive::AgentLimit learning: a limit-hit cell must be
  # marked **re-run later**, never scored 0, or the leaderboard punishes an
  # agent for the maintainer's billing window.
  #
  # Biased toward false negatives: a missed limit degrades to an ordinary failed
  # cell (re-run anyway); a false positive would wrongly excuse a real failure,
  # so benign "limit" chrome is filtered first.
  module AgentLimit
    module_function

    BENIGN = [
      /included in your plan/i,
      /to see usage limits?/i,
      /usage limits? (?:reset|renew)s? (?:on|at|in)/i,
      /approaching[^\n]{0,40}(?:session|usage) limit/i
    ].freeze

    LIMIT = [
      /(?:hit|reached) your (?:usage|session) limit/i,
      /stop and wait for limit to reset/i,
      /(?:out of|no remaining|purchase(?:\s+more)?) usage credits/i,
      /insufficient[_\s-]*quota/i,
      /quota (?:exhausted|exceeded|reached)/i,
      /rate limit (?:reached|exceeded|reset|hit)/i,
      /too many requests/i,
      /\b(?:http|status|response)[:=\s-]*429\b/i,
      /resource[_\s-]*exhausted/i
    ].freeze

    # True if any non-benign line matches a limit pattern.
    def limit_hit?(text)
      normalize(text).each_line.any? do |line|
        stripped = line.strip
        next false if stripped.empty?
        next false if BENIGN.any? { |re| stripped.match?(re) }

        LIMIT.any? { |re| stripped.match?(re) }
      end
    end

    def normalize(text)
      text.to_s.scrub.gsub(%r{\e\[[0-9;?]*[ -/]*[@-~]}, "")
    end
  end
end
