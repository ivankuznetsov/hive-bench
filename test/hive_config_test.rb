# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "lib/hive_config"

# HiveConfig renders a candidate (model settings per hive stage) into a real
# hive config.yml. These cover the field mapping the Stage A/B bring-up pinned.
class HiveConfigTest < Minitest::Test
  Candidate = Data.define(:plan, :execute, :review, :claude_model, :review_max_passes,
                          :review_wall_clock_sec, :reviewers, :ci_command)

  def candidate(**over)
    base = { plan: "claude", execute: "claude", review: "claude", claude_model: "claude-opus-4-8",
             review_max_passes: 2, review_wall_clock_sec: 7200, reviewers: [],
             ci_command: "bundle exec rake test" }
    Candidate.new(**base, **over)
  end

  def test_pins_claude_model_with_the_cli_id_and_headless
    h = HiveBench::HiveConfig.to_h(candidate)

    assert_equal "claude-opus-4-8", h.dig("claude", "model")
    assert_equal "headless", h.dig("claude", "mode"), "no tmux in the container"
  end

  def test_open_and_codex_agents_omit_the_claude_model
    h = HiveBench::HiveConfig.to_h(candidate(execute: "codex", claude_model: nil))

    refute h["claude"].key?("model"), "codex/pi have no model flag in hive — omit it"
    assert_equal "codex", h.dig("execute", "agent")
  end

  def test_per_stage_agents_can_differ
    h = HiveBench::HiveConfig.to_h(candidate(plan: "claude", execute: "codex", review: "claude"))

    assert_equal "claude", h.dig("plan", "agent")
    assert_equal "codex", h.dig("execute", "agent")
    assert_equal "claude", h.dig("review", "agent")
  end

  def test_review_is_bounded_for_unattended_runs
    h = HiveBench::HiveConfig.to_h(candidate)

    assert_equal 2, h.dig("review", "max_passes")
    assert_equal 7200, h.dig("review", "max_wall_clock_sec")
    assert_empty h.dig("review", "reviewers"), "v2 runs no reviewers (review phase adds the hash shape)"
    assert_equal "bundle exec rake test", h.dig("review", "ci", "command")
  end

  def test_uncurated_task_omits_the_ci_command
    h = HiveBench::HiveConfig.to_h(candidate(ci_command: nil))

    refute h.dig("review", "ci").key?("command"), "an uncurated gate (no test_cmd) leaves ci.command unset"
  end

  def test_worktree_root_under_work_and_main_branch
    h = HiveBench::HiveConfig.to_h(candidate)

    assert_equal "/work/.worktrees", h["worktree_root"], "worktree persists on the host mount"
    assert_equal "main", h["default_branch"], "branch off local main (= task base_commit)"
  end

  def test_round_trips_to_yaml
    y = YAML.safe_load(HiveBench::HiveConfig.to_yaml(candidate))

    assert_equal "claude-opus-4-8", y.dig("claude", "model")
  end
end
