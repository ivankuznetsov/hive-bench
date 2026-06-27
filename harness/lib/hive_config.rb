# frozen_string_literal: true

require "yaml"

module HiveBench
  # Renders a benchmark CANDIDATE (which agent/model drives each REAL hive stage)
  # into a hive `.hive-state/config.yml`. v2's unit of comparison is a model
  # configuration run through ACTUAL hive — not a reimplemented prompt.
  #
  # The brainstorm is seeded frozen (same requirements for every candidate), so
  # plan/execute/review are the live stages. Only claude takes a model flag in
  # hive (`claude.model`, and it must be the CLI id e.g. `claude-opus-4-8`, not
  # hive's short `opus-4.8`); codex runs its subscription model and pi its
  # provider model, so their `claude_model` is nil and simply omitted.
  #
  # Hive specifics baked in from the Stage A/B bring-up:
  #   - mode: headless         (no tmux in the container)
  #   - default_branch: main   (the target clone's local main is reset to the
  #                             task's base_commit and origin is removed, so the
  #                             execute worktree branches off base_commit)
  #   - worktree_root under /work so the worktree persists on the host mount
  #   - review bounded (max_passes + wall clock) so it runs unattended; ci.command
  #     is the corpus gate's test command (nil/omitted when the task is uncurated)
  module HiveConfig
    module_function

    DEFAULT_WORKTREE_ROOT = "/work/.worktrees"
    DEFAULT_BRANCH = "main"

    # candidate: responds to plan, execute, review (agent names: "claude"/"codex"/
    #   "pi"), claude_model (CLI id or nil), review_max_passes, review_wall_clock_sec,
    #   reviewers (Array), ci_command (String or nil).
    def to_h(candidate, worktree_root: DEFAULT_WORKTREE_ROOT, default_branch: DEFAULT_BRANCH)
      {
        "claude" => { "mode" => "headless", "model" => candidate.claude_model }.compact,
        "default_branch" => default_branch,
        "worktree_root" => worktree_root,
        "plan" => { "agent" => candidate.plan },
        "execute" => { "agent" => candidate.execute },
        "review" => review_config(candidate)
      }
    end

    def review_config(candidate)
      {
        "agent" => candidate.review,
        "max_passes" => candidate.review_max_passes,
        "max_wall_clock_sec" => candidate.review_wall_clock_sec,
        "reviewers" => Array(candidate.reviewers),
        "ci" => { "command" => candidate.ci_command }.compact
      }
    end

    def to_yaml(candidate, **)
      YAML.dump(to_h(candidate, **))
    end
  end
end
