# frozen_string_literal: true

module HiveBench
  # v2 slate: a CANDIDATE is a hive model configuration (which agent+model drives
  # each stage), run through REAL hive. Replaces the v1 Profile/Pair slate that fed
  # the reimplemented pipeline. `model_version` is what the leaderboard records;
  # `claude_model` is the CLI model id for hive's `claude.model` (nil for codex/pi,
  # which take no model flag). Review fields are configured but unused until the
  # review phase ships (v2 = plan+execute).
  module Candidates
    module_function

    Candidate = Data.define(:id, :plan, :execute, :review, :claude_model, :model_version,
                            :review_max_passes, :review_wall_clock_sec, :reviewers, :ci_command)

    def all
      [all_opus, all_codex, opus_plan_codex_exec].freeze
    end

    def by_id(id)
      all.find { |c| c.id == id }
    end

    def claude_candidate(id, model)
      Candidate.new(id: id, plan: "claude", execute: "claude", review: "claude",
                    claude_model: model, model_version: model,
                    review_max_passes: 2, review_wall_clock_sec: 7200,
                    reviewers: [], ci_command: nil)
    end

    def all_opus = claude_candidate("all-opus-4.8", "claude-opus-4-8")

    def all_codex
      Candidate.new(id: "all-codex", plan: "codex", execute: "codex", review: "codex",
                    claude_model: nil, model_version: "gpt-5.5",
                    review_max_passes: 2, review_wall_clock_sec: 7200,
                    reviewers: [], ci_command: nil)
    end

    def opus_plan_codex_exec
      Candidate.new(id: "opus-plan->codex-exec", plan: "claude", execute: "codex", review: "claude",
                    claude_model: "claude-opus-4-8", model_version: "opus-plan/codex-exec",
                    review_max_passes: 2, review_wall_clock_sec: 7200,
                    reviewers: [], ci_command: nil)
    end
  end
end
