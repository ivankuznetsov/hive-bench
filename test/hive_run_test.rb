# frozen_string_literal: true

require "minitest/autorun"
require "hive_run"

class HiveRunTest < Minitest::Test
  def test_parse_accepts_configured_sol_judge_effort
    opts = HiveBench::HiveRun.parse(
      %w[
        --source /tmp/source
        --judge-model claude-fable-5
        --codex-judge-model gpt-5.6-sol
        --codex-judge-effort ultra
        --no-openrouter-judge
      ]
    )

    assert opts[:claude_judge]
    assert opts[:codex_judge]
    refute opts[:openrouter_judge]
    assert_equal "gpt-5.6-sol", opts[:codex_judge_model]
    assert_equal "ultra", opts[:codex_judge_effort]
    assert_equal({ "gpt-5.6-sol" => "ultra" }, HiveBench::Driver.judge_efforts(opts))
  end
end
