# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require "lib/git_restore"
require "lib/agent_limit"

module HiveBench
  # Runs one benchmark cell = (corpus task, candidate agent) and produces the
  # cell's diff + telemetry, ready for scoring (U4). Two modes:
  #
  #   reused — the cell's agent is the task's original producer at a compatible
  #            model version, so the diff is the held-out reference and cost /
  #            fix-passes come from existing hive data. wall_clock is N/A (the
  #            original run wasn't timed for the bench). Tagged "reused".
  #   fresh  — restore the repo at base_commit, run the candidate from the frozen
  #            plan, capture the diff + telemetry. Tagged "fresh".
  #
  # Generation and evaluation are separated: this unit persists the diff and
  # stops. Scoring (gate + judge) is U4 — so an infra failure never forces an
  # expensive re-run of the agent.
  #
  # External effects are seams:
  #   restorer:       GitRestore (real git, hardened)
  #   spawn:          ->(profile:, prompt:, cwd:) => { stdout:, status:, started_at:, ended_at:, usage: }
  #                   (in production: runs profile.command inside the isolated,
  #                    egress-allowlisted runner container — see Dockerfile.runner)
  #   reuse_resolver: ->(entry, profile) => { diff:, model_version:, telemetry: }|nil
  class Run
    Cell = Data.define(:task_id, :agent_id, :mode, :model_version, :status, :diff_path, :telemetry, :reason)

    def initialize(restorer: GitRestore.new, spawn: nil, reuse_resolver: ->(_e, _p) {},
                   clock: -> { Time.now.utc })
      @restorer = restorer
      @spawn = spawn
      @reuse_resolver = reuse_resolver
      @clock = clock
    end

    # entry: a loaded manifest hash (from a corpus entry) augmented with
    #   "entry_dir" (where spec/, reference.patch live) and "source" path.
    # profile: a HiveBench::Profile.
    # out_dir: where to persist this cell's artifacts.
    def call(entry:, profile:, out_dir:)
      task_id = entry.fetch("task_id")
      FileUtils.mkdir_p(out_dir)

      if (reused = @reuse_resolver.call(entry, profile))
        return persist_reused(task_id, profile, reused, out_dir)
      end

      run_fresh(entry, profile, task_id, out_dir)
    end

    private

    def persist_reused(task_id, profile, reused, out_dir)
      diff_path = File.join(out_dir, "candidate.patch")
      File.write(diff_path, reused.fetch(:diff))
      telemetry = { "wall_clock_sec" => nil }.merge(reused[:telemetry] || {})
      cell(task_id, profile, mode: "reused", status: "generated",
                             model_version: reused[:model_version] || profile.model,
                             diff_path: diff_path, telemetry: telemetry, reason: "reused recorded producer output")
    end

    def run_fresh(entry, profile, task_id, out_dir)
      raise ArgumentError, "fresh run needs a spawn seam" unless @spawn

      work = File.join(out_dir, "work")
      source = entry["checkout_source"] or raise ArgumentError, "entry has no checkout_source (clone path/URL)"
      @restorer.restore(source: source, base_commit: base_commit(entry), into: work)

      prompt = File.read(File.join(entry.fetch("entry_dir"), entry.dig("spec", "plan")))
      started = @clock.call
      result = @spawn.call(profile: profile, prompt: prompt, cwd: work)
      ended = @clock.call

      stream = "#{result[:stdout]}\n#{result[:stderr]}"
      if AgentLimit.limit_hit?(stream)
        return cell(task_id, profile, mode: "fresh", status: "limit_hit",
                                      model_version: result[:model] || profile.model, diff_path: nil,
                                      telemetry: {}, reason: "provider usage/credit limit — re-run after cooldown")
      end

      # Persist the diff BEFORE any scoring (generation/evaluation split).
      diff = @restorer.diff(work_dir: work, base_commit: base_commit(entry))
      diff_path = File.join(out_dir, "candidate.patch")
      File.write(diff_path, diff)

      status = result[:status] == :ok ? generation_status(diff) : "agent_failed"
      cell(task_id, profile, mode: "fresh", status: status,
                             model_version: result[:model] || profile.model, diff_path: diff_path,
                             telemetry: fresh_telemetry(result, started, ended), reason: nil)
    end

    def generation_status(diff)
      diff.strip.empty? ? "empty_diff" : "generated"
    end

    def fresh_telemetry(result, started, ended)
      usage = result[:usage] || {}
      {
        "wall_clock_sec" => (ended - started).round(2),
        "input_tokens" => usage[:input],
        "output_tokens" => usage[:output],
        "cached_tokens" => usage[:cached]
        # cost ($) is derived in U4 from a versioned price table — not here.
      }
    end

    def base_commit(entry)
      entry.dig("source", "base_commit") or raise ArgumentError, "entry has no source.base_commit"
    end

    def cell(task_id, profile, mode:, status:, model_version:, diff_path:, telemetry:, reason:)
      Cell.new(task_id: task_id, agent_id: profile.id, mode: mode, model_version: model_version,
               status: status, diff_path: diff_path, telemetry: telemetry, reason: reason)
    end
  end
end
