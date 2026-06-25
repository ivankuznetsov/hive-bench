# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "lib/judge_output"

module HiveBench
  # A judge_fn backed by an OpenRouter chat model (e.g. openai/gpt-5.5-pro) — the
  # family-disjoint judge for a slate that includes claude and glm. Mirrors
  # ClaudeJudge's contract (->(prompt:, seed:) => { score:, reason: }) and shares
  # the same score parsing, so HiveBench::Judge treats both interchangeably.
  #
  # NOTE on cost: judge prompts are input-heavy (the candidate diff), and gpt-5.5-pro
  # bills input at $30/M. Withhold the reference and use 1 seed for affordability.
  module OpenRouterJudge
    Error = JudgeOutput::Error

    ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"
    DEFAULT_TIMEOUT = 600

    module_function

    def judge_fn(model:, api_key: ENV.fetch("OPENROUTER_API_KEY", nil), timeout_s: DEFAULT_TIMEOUT)
      raise Error, "OPENROUTER_API_KEY is not set (needed for the #{model} judge)" if api_key.to_s.empty?

      lambda do |prompt:, seed:|
        body = { "model" => model, "seed" => seed, "messages" => [{ "role" => "user", "content" => prompt.to_s }] }
        content = request(body, api_key, timeout_s)
        JudgeOutput.parse_score(content)
      end
    end

    # POSTs the judge prompt and returns the assistant's text. Raises on transport
    # or API errors so a flaky judge call parks the cell rather than scoring noise.
    def request(body, api_key, timeout_s)
      uri = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 30
      http.read_timeout = timeout_s

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{api_key}"
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(body)

      res = http.request(req)
      raise Error, "openrouter judge HTTP #{res.code}: #{res.body.to_s.strip[0, 300]}" unless res.code == "200"

      parsed = JSON.parse(res.body)
      content = parsed.dig("choices", 0, "message", "content")
      raise Error, "openrouter judge returned no content: #{res.body.to_s.strip[0, 200]}" if content.to_s.empty?

      content
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise Error, "openrouter judge timed out: #{e.message}"
    end
  end
end
