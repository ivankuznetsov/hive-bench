# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "lib/hive_config"
require "profiles/candidates"

# HiveConfig renders a candidate (model settings per hive stage) into a real
# hive config.yml. These cover the field mapping the Stage A/B bring-up pinned.
class HiveConfigTest < Minitest::Test
  Candidate = Data.define(:plan, :execute, :review, :claude_model, :claude_effort, :review_max_passes,
                          :review_wall_clock_sec, :reviewers, :ci_command, :pi_models,
                          :opencode_models, :opencode_effort, :codex_model, :codex_effort,
                          :codex_models, :codex_efforts, :grok_model, :grok_effort)

  def candidate(**over)
    base = { plan: "claude", execute: "claude", review: "claude", claude_model: "claude-opus-4-8",
             claude_effort: nil,
             review_max_passes: 2, review_wall_clock_sec: 7200, reviewers: [],
             ci_command: "bundle exec rake test", pi_models: nil, opencode_models: nil,
             opencode_effort: nil, codex_model: nil, codex_effort: nil,
             codex_models: nil, codex_efforts: nil, grok_model: nil, grok_effort: nil }
    Candidate.new(**base, **over)
  end

  def test_pins_claude_model_with_the_cli_id_and_headless
    h = HiveBench::HiveConfig.to_h(candidate)

    assert_equal "claude-opus-4-8", h.dig("claude", "model")
    assert_equal "headless", h.dig("claude", "mode"), "no tmux in the container"
  end

  def test_pins_claude_effort_when_candidate_declares_it
    h = HiveBench::HiveConfig.to_h(candidate(claude_model: "claude-fable-5", claude_effort: "high"))

    assert_equal "high", h.dig("claude", "effort")
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
    assert_equal "bundle exec rake test", h.dig("review", "ci", "command")
  end

  # The review section mirrors PROD hive defaults with the candidate's agent
  # substituted everywhere, github_publish forced off (offline container), and
  # the claude-plugin reviewer included only for claude candidates.
  def test_review_mirrors_prod_defaults_with_candidate_agents
    h = HiveBench::HiveConfig.to_h(candidate)
    r = h["review"]

    assert r.dig("triage", "enabled")
    assert_equal "courageous", r.dig("triage", "bias")
    assert_equal "claude", r.dig("fix", "agent")
    assert_equal "inherit", r.dig("fix", "auto_commit", "sign_policy")
    assert_equal false, r.dig("fix", "auto_commit", "scope_check", "enabled")
    refute r.dig("browser_test", "enabled")
    refute r.dig("github_publish", "enabled"), "no real GitHub in the container"
    names = r["reviewers"].map { |rev| rev["skill"] }

    assert_includes names, "ce-code-review"
    assert_includes names, "pr-review-toolkit:review-pr"
  end

  def test_single_model_candidate_reviews_itself_with_ce
    h = HiveBench::HiveConfig.to_h(candidate(plan: "codex", execute: "codex", review: "codex", claude_model: nil))
    reviewers = h.dig("review", "reviewers")

    assert_equal(["codex-ce-code-review"], reviewers.map { |r| r["name"] })
    assert_equal "reviewer_codex_ce_code_review.md.erb", reviewers.first["prompt_template"]
    assert_equal "codex", h.dig("review", "triage", "agent")
  end

  def test_claude_candidate_adds_pr_review_toolkit
    h = HiveBench::HiveConfig.to_h(candidate(plan: "claude", execute: "claude", review: "claude"))
    reviewers = h.dig("review", "reviewers")

    assert_equal(%w[claude-ce-code-review pr-review-toolkit], reviewers.map { |r| r["name"] })
  end

  def test_mixed_candidate_derives_the_full_prod_tri_set
    h = HiveBench::HiveConfig.to_h(candidate(plan: "claude", execute: "codex", review: "claude"))
    names = h.dig("review", "reviewers").map { |r| r["name"] }

    assert_equal 3, names.size, "opus+codex mixed = the prod claude+codex shop"
    assert_includes names, "claude-ce-code-review"
    assert_includes names, "codex-ce-code-review"
    assert_includes names, "pr-review-toolkit"
  end

  def test_explicit_reviewers_override_the_derived_set
    custom = [{ "name" => "x", "kind" => "agent", "agent" => "claude", "skill" => "ce-code-review" }]
    h = HiveBench::HiveConfig.to_h(candidate(reviewers: custom))

    assert_equal custom, h.dig("review", "reviewers")
  end

  def test_uncurated_task_keeps_ci_command_null_like_prod
    h = HiveBench::HiveConfig.to_h(candidate(ci_command: nil))

    assert_nil h.dig("review", "ci", "command"), "prod hive uses ci.command: null to skip the CI-fix phase"
  end

  def test_worktree_root_under_work_and_main_branch
    h = HiveBench::HiveConfig.to_h(candidate)

    assert_equal "/work/.worktrees", h["worktree_root"], "worktree persists on the host mount"
    assert_equal "main", h["default_branch"], "branch off local main (= task base_commit)"
    assert_equal 300, h["attempt_launch_timeout_sec"],
                 "parallel runner startup must fit inside the launch claim"
    assert_equal 300, h["attempt_first_heartbeat_timeout_sec"],
                 "parallel worker startup must fit before the first heartbeat"
  end

  def test_round_trips_to_yaml
    y = YAML.safe_load(HiveBench::HiveConfig.to_yaml(candidate))

    assert_equal "claude-opus-4-8", y.dig("claude", "model")
  end

  def test_benchmark_disables_plan_review_for_all_candidates
    h = HiveBench::HiveConfig.to_h(candidate)

    assert_equal false, h.dig("plan_review", "enabled")
  end

  def test_ox_alpha_pi_candidate_routes_one_high_reasoning_family_through_every_stage
    h = HiveBench::HiveConfig.to_h(HiveBench::Candidates.all_ox_alpha_high)

    assert_equal "pi", h.dig("plan", "agent")
    assert_equal "pi", h.dig("execute", "agent")
    assert_equal "pi", h.dig("review", "agent")
    assert_equal "openrouter/stealth/ox-alpha:high", h.dig("models", "plan", "model")
    assert_equal "openrouter/stealth/ox-alpha:high", h.dig("models", "execute", "model")
    %w[open_pr review_ci review_triage review_fix].each do |stage|
      assert_equal "openrouter/stealth/ox-alpha:high", h.dig("models", stage, "model")
    end
    assert_equal "openrouter/stealth/ox-alpha:high", h.dig("review", "reviewers", 0, "model")
    assert_equal "openrouter/stealth/ox-alpha:high", h.dig("models", "review_reviewers", "model")
  end

  def test_ox_alpha_pi_max_candidate_is_a_separate_explicit_route
    candidate = HiveBench::Candidates.by_id("all-ox-alpha@max")

    refute_nil candidate

    h = HiveBench::HiveConfig.to_h(candidate)

    assert_equal "ox-alpha-max", candidate.model_version
    assert_equal %w[pi pi pi], [candidate.plan, candidate.execute, candidate.review]
    %w[plan execute open_pr review_ci review_triage review_fix].each do |stage|
      assert_equal "openrouter/stealth/ox-alpha:max", h.dig("models", stage, "model")
    end
    assert_equal "openrouter/stealth/ox-alpha:max", h.dig("review", "reviewers", 0, "model")
    refute h.dig("plan_review", "enabled")
  end

  def test_ox_alpha_opencode_candidate_has_hermetic_ce_plugin_and_high_routes
    h = HiveBench::HiveConfig.to_h(HiveBench::Candidates.all_ox_alpha_opencode_high)

    assert_equal "opencode", h.dig("plan", "agent")
    assert_equal "opencode", h.dig("execute", "agent")
    assert_equal "opencode", h.dig("review", "agent")
    assert_equal "scoped", h.dig("permissions", "preset")
    assert_equal [ "Read", "Write", "Edit", "Bash(*)" ],
                 h.dig("permissions", "tools")
    assert_equal ["/opt/compound-engineering"], h.dig("agents", "opencode", "plugins")
    assert_equal ["OPENROUTER_API_KEY"], h.dig("agents", "opencode", "credential_env")
    assert_equal "hermetic", h.dig("agents", "opencode", "isolation")
    assert h.dig("agents", "opencode", "config", "provider", "openrouter", "models", "stealth/ox-alpha")
    %w[plan execute open_pr review_ci review_triage review_fix].each do |stage|
      assert_equal "openrouter/stealth/ox-alpha", h.dig("models", stage, "model")
      assert_equal "high", h.dig("models", stage, "effort")
    end
    assert_equal "openrouter/stealth/ox-alpha", h.dig("review", "reviewers", 0, "model")
    assert_equal "high", h.dig("review", "reviewers", 0, "effort")
    assert_equal "high", h.dig("models", "review_reviewers", "effort")
    assert_nil h.dig("models", "review_reviewers", "model")
  end
end
