# frozen_string_literal: true

require "minitest/autorun"
require "profiles/slate"

class SlateTest < Minitest::Test
  def profiles = HiveBench::Slate.profiles

  def test_slate_has_the_six_v1_cells
    ids = profiles.map(&:id)

    assert_equal(
      ["claude@opus-4.8", "codex@gpt-5.5-xhigh",
       "pi@kimi-k2.7", "pi@minimax-3", "pi@qwen-2.6-coder", "pi@glm-5.2"].sort,
      ids.sort
    )
  end

  def test_every_cell_pins_its_model_in_the_command
    profiles.each do |p|
      argv = p.command(prompt: "PROMPT")

      assert_includes argv, p.model, "#{p.id} must bake its model into the argv"
      assert_equal "PROMPT", argv.last, "#{p.id} must place the prompt last"
    end
  end

  # The origin's flagged feasibility risk: open models depend on the harness
  # being able to run them. Evidence captured here — all four open models pin
  # via `pi --model`, which the installed Pi (v0.79.3) supports.
  def test_open_models_run_on_pi_via_model_flag
    open_cells = profiles.select { |p| p.harness == "pi" }

    assert_equal 4, open_cells.size

    open_cells.each do |p|
      argv = p.command(prompt: "x")

      assert_equal "pi", argv.first
      assert_includes argv, "--model", "#{p.id}: open model must be pinned with pi --model"
    end
  end

  def test_codex_cell_pins_model_and_reasoning_effort
    argv = HiveBench::Slate.by_id("codex@gpt-5.5-xhigh").command(prompt: "x")

    assert_includes argv, "-m"
    assert_includes argv, "gpt-5.5"
    assert(argv.any? { |a| a.include?("model_reasoning_effort") }, "xhigh effort must be pinned via -c")
  end

  def test_by_id_returns_nil_for_unknown
    assert_nil HiveBench::Slate.by_id("nope@nope")
  end

  def test_each_cell_carries_a_min_version_and_auth_path
    profiles.each do |p|
      refute_nil p.min_version, "#{p.id} needs a min version floor"
      refute_nil p.auth_path, "#{p.id} needs an auth path for the not-logged-in check"
    end
  end
end
