# frozen_string_literal: true

require "lib/profile"

module HiveBench
  # The v1 benchmark slate: 6 cells = harness@model. hive pins a model for
  # claude only, so each cell here bakes its own model flag into the headless
  # argv (`claude --model`, `codex -m`, `pi --model`). Min versions match hive's
  # AgentProfile floors; auth paths match hive's logged-in? checks.
  #
  # Open-model feasibility (the origin's flagged risk) is RESOLVED: `pi --model
  # <pattern>` exists and "supports provider/id and optional :<thinking>", so the
  # four open models run on Pi. The exact provider/id pattern per model depends
  # on Pi's configured providers (OpenRouter) — recorded here as the `model`
  # field; a smoke run (U8) confirms each pattern resolves to a live model.
  module Slate
    module_function

    CLAUDE_AUTH = "~/.claude/.credentials.json"
    CODEX_AUTH = "~/.codex/auth.json"
    PI_AUTH = "~/.pi/agent/auth.json"

    def profiles
      [claude_opus, codex_gpt, *pi_open_models].freeze
    end

    def by_id(id)
      profiles.find { |p| p.id == id }
    end

    def claude_opus
      Profile.new(
        id: "claude@opus-4.8", harness: "claude", model: "opus-4.8", bin: "claude",
        min_version: "2.1.118", auth_path: CLAUDE_AUTH,
        headless_argv: lambda do |prompt:|
          ["claude", "-p", "--model", "opus-4.8", "--dangerously-skip-permissions", prompt]
        end
      )
    end

    def codex_gpt
      # "gpt-5.5 xhigh" = model gpt-5.5 at reasoning effort xhigh. codex pins the
      # model with -m and the effort via a -c config override.
      Profile.new(
        id: "codex@gpt-5.5-xhigh", harness: "codex", model: "gpt-5.5", bin: "codex",
        min_version: "0.125.0", auth_path: CODEX_AUTH,
        headless_argv: lambda do |prompt:|
          ["codex", "exec", "-m", "gpt-5.5", "-c", 'model_reasoning_effort="xhigh"',
           "--dangerously-bypass-approvals-and-sandbox", prompt]
        end
      )
    end

    # Each open model is `pi --model <pattern> -p`. Patterns are pi provider/id
    # forms; adjust to match the local Pi provider config if a smoke run reports
    # an unresolved pattern.
    PI_MODELS = {
      "kimi-k2.7" => "kimi-k2.7",
      "minimax-3" => "minimax-3",
      "qwen-2.6-coder" => "qwen-2.6-coder",
      "glm-5.2" => "glm-5.2"
    }.freeze

    def pi_open_models
      PI_MODELS.map do |label, pattern|
        Profile.new(
          id: "pi@#{label}", harness: "pi", model: pattern, bin: "pi",
          min_version: "0.70.2", auth_path: PI_AUTH,
          headless_argv: lambda do |prompt:|
            ["pi", "-p", "--model", pattern, prompt]
          end
        )
      end
    end
  end
end
