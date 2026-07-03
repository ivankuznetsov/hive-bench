# frozen_string_literal: true

module HiveBench
  # v2 slate: a CANDIDATE is a hive model configuration (which agent+model drives
  # each stage), run through REAL hive. Replaces the v1 Profile/Pair slate that fed
  # the reimplemented pipeline. `model_version` is what the leaderboard records;
  # `claude_model` is the CLI model id for hive's `claude.model` (nil for codex/pi,
  # which take no model flag in hive). Open models run on pi: hive has no pi model
  # config, so `pi_models` maps stage -> pi `--model` pattern, injected by the
  # in-container pi shim via HB_PI_MODEL_<STAGE> (see hive_stages.sh). Review
  # fields feed the prod-default review config (hive_config.rb).
  module Candidates
    module_function

    Candidate = Data.define(:id, :plan, :execute, :review, :claude_model, :pi_models,
                            :model_version, :review_max_passes, :review_wall_clock_sec,
                            :reviewers, :ci_command)

    # pi --model patterns verified against the local pi + OpenRouter (2026-07-03).
    GLM = "openrouter/z-ai/glm-5.2"
    KIMI = "openrouter/moonshotai/kimi-k2.7-code"

    def all
      [all_opus, all_codex, opus_plan_codex_exec,
       all_glm, all_kimi, glm_plan_kimi_exec].freeze
    end

    def by_id(id)
      all.find { |c| c.id == id }
    end

    def base(id, plan:, execute:, review:, model_version:, claude_model: nil, pi_models: nil)
      Candidate.new(id: id, plan: plan, execute: execute, review: review,
                    claude_model: claude_model, pi_models: pi_models,
                    model_version: model_version,
                    review_max_passes: 2, review_wall_clock_sec: 7200,
                    reviewers: [], ci_command: nil)
    end

    def all_opus
      base("all-opus-4.8", plan: "claude", execute: "claude", review: "claude",
                           claude_model: "claude-opus-4-8", model_version: "claude-opus-4-8")
    end

    def all_codex
      base("all-codex", plan: "codex", execute: "codex", review: "codex",
                        model_version: "gpt-5.5")
    end

    def opus_plan_codex_exec
      base("opus-plan->codex-exec", plan: "claude", execute: "codex", review: "claude",
                                    claude_model: "claude-opus-4-8", model_version: "opus-plan/codex-exec")
    end

    def all_glm
      base("all-glm-5.2", plan: "pi", execute: "pi", review: "pi",
                          pi_models: { "plan" => GLM, "execute" => GLM, "review" => GLM },
                          model_version: "glm-5.2")
    end

    def all_kimi
      # The CODE variant, deliberately — kimi-k2.7 base is a different model.
      base("all-kimi-k2.7-code", plan: "pi", execute: "pi", review: "pi",
                                 pi_models: { "plan" => KIMI, "execute" => KIMI, "review" => KIMI },
                                 model_version: "kimi-k2.7-code")
    end

    # "glm with kimi": glm plans (and reviews), kimi implements — the open-model
    # mirror of opus-plan->codex-exec.
    def glm_plan_kimi_exec
      base("glm-plan->kimi-exec", plan: "pi", execute: "pi", review: "pi",
                                  pi_models: { "plan" => GLM, "execute" => KIMI, "review" => GLM },
                                  model_version: "glm-plan/kimi-exec")
    end
  end
end
