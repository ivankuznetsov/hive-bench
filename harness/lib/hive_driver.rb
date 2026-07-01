# frozen_string_literal: true

require "fileutils"
require "json"
require "yaml"
require "open3"
require "lib/hive_config"
require "lib/agent_limit"
require "lib/pricing"

module HiveBench
  # Drives REAL hive (plan -> execute) for one (task x candidate) in the
  # hive-bench-runner container, then captures the candidate diff + telemetry.
  # This REPLACES the reimplemented Pipeline: the scored diff is hive's ACTUAL
  # output (real /ce-plan + real execute), not a toy prompt's. Returns a cell
  # shaped like Run::Cell so RunAll/Score consume it unchanged. (Review is a later
  # phase; v2 ships plan+execute.)
  #
  # Container recipe (proven in the Stage A/B bring-up):
  #   - non-root runner (claude refuses --dangerously-skip-permissions as root)
  #   - HOME=/home/asterio on a world-writable tmpfs, with the claude creds /
  #     settings / plugins bind-mounted at that SAME absolute path so the plugin
  #     installPaths resolve and `/ce-plan` is available
  #   - the target clone at /work; hive baked into the image as a gem
  class HiveDriver
    Cell = Data.define(:task_id, :agent_id, :mode, :model_version, :status,
                       :diff_path, :telemetry, :reason)

    IMAGE = ENV.fetch("HB_RUNNER_IMAGE", "hive-bench-runner:latest")
    STAGES_SH = File.expand_path("hive_stages.sh", __dir__)
    CLAUDE_DIR = File.expand_path("~/.claude")
    HOME = "/home/asterio"
    PLAN_TIMEOUT = Integer(ENV.fetch("HB_HIVE_TIMEOUT", "5400")) # per container run, sec

    def initialize(clock: -> { Time.now.utc }, runner: nil)
      @clock = clock
      @runner = runner # injectable container runner for tests; default shells docker
    end

    # entry: corpus entry hash (manifest + entry_dir + checkout_source).
    # candidate: a Slate candidate (id, plan/execute/review agents, claude_model, …).
    def call(entry:, candidate:, out_dir:)
      FileUtils.mkdir_p(out_dir)
      slug = entry.fetch("task_id")
      base = entry.dig("source", "base_commit") or raise ArgumentError, "entry has no source.base_commit"
      source = entry["checkout_source"] or raise ArgumentError, "entry has no checkout_source"
      work = File.expand_path(File.join(out_dir, "target")) # absolute: docker -v needs it

      setup_repo(source, base, work)
      seed_task(entry, slug, work)
      File.write(File.join(work, ".hive-state", "config.yml"), HiveConfig.to_yaml(candidate))
      init_state_repo(work)

      started = @clock.call
      stdout = run_container(slug, base, work, candidate)
      wall = (@clock.call - started).round(2)

      build_cell(entry, candidate, work, stdout, wall)
    end

    private

    # Clone the target, reset local main to the task's base_commit, drop origin so
    # the execute worktree branches off base_commit (not origin/main).
    def setup_repo(source, base, work)
      FileUtils.rm_rf(work)
      git("clone", "--quiet", "--no-local", source, work)
      git("-C", work, "checkout", "-q", "-B", "main", base)
      git("-C", work, "remote", "remove", "origin")
    end

    def seed_task(entry, slug, work)
      tdir = File.join(work, ".hive-state", "stages", "2-brainstorm", slug)
      FileUtils.mkdir_p(tdir)
      File.write(File.join(tdir, "idea.md"), read_spec(entry, "idea"))
      File.write(File.join(tdir, "brainstorm.md"), read_spec(entry, "brainstorm"))
      File.write(File.join(tdir, "meta.yml"), "---\nid: 1\nslug: #{slug}\n")
      stage_assets(entry, tdir)
    end

    # The .hive-state is its own git repo (hive version-controls task state there).
    def init_state_repo(work)
      state = File.join(work, ".hive-state")
      git("-C", state, "init", "-q", "-b", "main")
      git("-C", state, "config", "user.email", "bench@hive-bench")
      git("-C", state, "config", "user.name", "hive-bench")
      git("-C", state, "add", "-A")
      git("-C", state, "commit", "-q", "-m", "seed @ 2-brainstorm")
    end

    # Copy spec screenshots into the task folder so the idea's `assets/<f>` refs
    # resolve for the plan agent (the same visual context the human had).
    def stage_assets(entry, tdir)
      src = File.join(entry.fetch("entry_dir"), "spec", "assets")
      return unless File.directory?(src)

      FileUtils.cp_r(src, File.join(tdir, "assets"))
    end

    def run_container(slug, base, work, candidate)
      cmd = ["docker", "run", "--rm",
             "-e", "HOME=#{HOME}",
             # Resource caps: comparability (wall-clock cells shouldn't vary with
             # host contention) as much as containment. Generous — hive runs a
             # full plan+execute agent session in here.
             "--cpus", ENV.fetch("HB_CPUS", "4"),
             "--memory", ENV.fetch("HB_MEMORY", "8g"),
             "--pids-limit", ENV.fetch("HB_PIDS", "4096"),
             *network_args,
             "--tmpfs", "#{HOME}:exec,mode=1777",
             # .claude must be WRITABLE (claude's Bash tool mkdir's session-env
             # there) — a plain bind-mount parent is root-owned/ro and kills Bash,
             # so the agent gives up mid-execute. tmpfs it; the config is bound ro within.
             "--tmpfs", "#{HOME}/.claude:exec,mode=1777",
             "-v", "#{STAGES_SH}:/hive_stages.sh:ro",
             "-v", "#{work}:/work",
             *auth_mounts(candidate),
             *env_args(candidate),
             IMAGE,
             # HB_EXIT lets classify() tell a timeout (rc=124) from a stage failure.
             "timeout #{PLAN_TIMEOUT} bash /hive_stages.sh #{slug} #{base}; echo HB_EXIT rc=$?"]
      (@runner || method(:capture)).call(cmd)
    end

    # Generation needs model-API egress, so `--network none` is impossible here —
    # but the default bridge leaves the answer key (the public reference PR)
    # fetchable. HB_GEN_NETWORK names a docker network (e.g. one behind an egress
    # allowlist proxy) to attach instead; until that's standing, the post-run
    # answer-key scan (`answer_key_suspect?`) is the detection layer.
    def network_args
      net = ENV.fetch("HB_GEN_NETWORK", nil)
      net ? ["--network", net] : []
    end

    # Mount the auth each used agent needs. claude: creds+settings+plugins at the
    # matching absolute path (so /ce-plan resolves). codex: its OAuth, read-only.
    def auth_mounts(candidate)
      mounts = []
      if uses?(candidate, "claude")
        mounts += ["-v", "#{CLAUDE_DIR}/.credentials.json:#{HOME}/.claude/.credentials.json:ro",
                   "-v", "#{CLAUDE_DIR}/settings.json:#{HOME}/.claude/settings.json:ro",
                   "-v", "#{CLAUDE_DIR}/plugins:#{HOME}/.claude/plugins:ro"]
      end
      codex = File.expand_path("~/.codex/auth.json")
      mounts += ["-v", "#{codex}:#{HOME}/.codex/auth.json:ro"] if uses?(candidate, "codex") && File.file?(codex)
      mounts
    end

    # OPENROUTER_API_KEY is forwarded (never echoed) when a pi/open-model stage runs.
    def env_args(candidate)
      return [] unless uses?(candidate, "pi") && ENV["OPENROUTER_API_KEY"]

      ["-e", "OPENROUTER_API_KEY"]
    end

    def uses?(candidate, agent)
      [candidate.plan, candidate.execute, candidate.review].include?(agent)
    end

    # ---- result assembly ----

    def build_cell(entry, candidate, work, stdout, wall)
      diff_path = File.join(work, "candidate.patch")
      diff = File.file?(diff_path) ? File.read(diff_path) : ""
      tel = telemetry(work).merge("wall_clock_sec" => wall)
      price_telemetry(tel, candidate)
      # The plan ended WAITING (open questions) and the bench force-completed it —
      # a covariate of the known scope-fork variance; surfaced so it's analyzable.
      tel["plan_forced_complete"] = true if stdout&.match?(/^HB_NOTE plan_forced_complete$/)
      if (hit = answer_key_suspect(entry, work, stdout))
        # The agent appears to have touched the held-out reference PR — the score
        # would measure retrieval, not skill. Flag loudly; a curator adjudicates.
        tel["answer_key_access_suspect"] = hit
        warn "hive-bench: ANSWER-KEY ACCESS SUSPECT — #{entry["task_id"]}: #{hit}"
      end
      status, reason = classify(stdout, work, diff)
      cell(entry, candidate, status, status == "generated" ? diff_path : nil, tel, reason)
    end

    # run_status from the stage markers + the captured diff. limit_hit (a provider
    # wall) parks the cell; an empty/failed plan or execute is surfaced honestly.
    def classify(stdout, work, diff)
      err = File.file?(f = File.join(work, ".hb", "stage.err")) ? File.read(f) : ""
      return ["limit_hit", "provider limit during a hive stage"] if AgentLimit.limit_hit?("#{stdout}\n#{err}")
      # timeout(1) kills the whole stage script — a slow candidate, not one that
      # cannot plan. rc=124 comes from the HB_EXIT marker run_container appends.
      return ["timed_out", "hive run exceeded HB_HIVE_TIMEOUT (#{PLAN_TIMEOUT}s)"] if stdout =~ /^HB_EXIT rc=124$/
      return ["plan_failed", "hive plan produced no plan.md"] unless stage_ok?(stdout, "plan")
      return ["execute_failed", "hive develop did not run"] unless stage_ok?(stdout, "develop")
      return ["empty_diff", "execute produced no diff"] if diff.strip.empty?

      ["generated", nil]
    end

    # Detects the one leakage that invalidates a cell outright: the candidate
    # reaching the held-out reference PR. Narrow on purpose (repo-qualified pull
    # URL or a `gh pr` invocation of that number) — the repo URL alone appears
    # legitimately in gemspecs/READMEs. Scans the agent stream logs + stdout.
    # Returns the matched evidence string, or nil.
    def answer_key_suspect(entry, work, stdout)
      repo = entry.dig("source", "repo")
      pr = entry.dig("source", "reference_pr")
      return nil unless repo && pr

      pattern = %r{#{Regexp.escape(repo)}/pulls?/#{pr}\b|\bgh\s+pr\s+(?:view|diff|checkout)\s+#{pr}\b}
      haystacks = Dir.glob(File.join(work, ".hive-state", "logs", "**", "*.log")) +
                  Dir.glob(File.join(work, ".hb", "*.json"))
      haystacks.each do |f|
        File.foreach(f) { |line| return line.strip[0, 200] if line.match?(pattern) }
      end
      (m = stdout.to_s[pattern]) ? m : nil
    end

    def stage_ok?(stdout, name)
      stdout =~ /^HB_STAGE #{name} rc=0$/
    end

    # Canonical cost is API-EQUIVALENT: tokens × the versioned usual-tier price
    # table (comparable across agents). The CLI's self-reported figure — fast-tier
    # for claude, often absent for codex/pi — is kept as cost_usd_reported. Mixed-
    # family candidates get no estimate (needs per-stage attribution): reported
    # stands alone and the leaderboard sees the gap instead of a wrong number.
    def price_telemetry(tel, candidate)
      est = Pricing.estimate_usd(model_strings: [candidate.id, candidate.model_version],
                                 input: tel["input_tokens"], output: tel["output_tokens"],
                                 cached: tel["cached_tokens"])
      reported = tel.delete("cost_usd")
      tel["cost_usd_reported"] = reported if reported
      tel["cost_usd"] = est if est
      tel
    end

    # Sum token usage + cost across every stage's persisted agent stream log
    # (.hive-state/logs/<slug>/<stage>-*.log, lines prefixed `[stream] <ts> `).
    def telemetry(work)
      logs = Dir.glob(File.join(work, ".hive-state", "logs", "**", "*.log"))
      input = output = cached = 0
      cost = 0.0
      logs.each do |log|
        File.foreach(log) do |line|
          obj = stream_json(line) or next
          u = obj.dig("message", "usage") || obj["usage"]
          if u.is_a?(Hash)
            input += u["input_tokens"].to_i
            output += u["output_tokens"].to_i
            cached += u["cache_read_input_tokens"].to_i
          end
          cost += obj["total_cost_usd"].to_f if obj["type"] == "result"
        end
      end
      { "input_tokens" => input, "output_tokens" => output, "cached_tokens" => cached,
        "cost_usd" => cost.round(6) }.reject { |_, v| v.zero? }
    end

    # Extract the JSON object from a `[stream] <ts> {json}` log line (or a bare
    # json line); nil for narration lines.
    def stream_json(line)
      brace = line.index("{")
      return nil unless brace

      JSON.parse(line[brace..])
    rescue JSON::ParserError
      nil
    end

    def cell(entry, candidate, status, diff_path, telemetry, reason)
      Cell.new(task_id: entry.fetch("task_id"), agent_id: candidate.id, mode: "hive",
               model_version: candidate.model_version, status: status,
               diff_path: diff_path, telemetry: telemetry, reason: reason)
    end

    def read_spec(entry, key)
      rel = entry.dig("spec", key) or return ""
      path = File.join(entry.fetch("entry_dir"), rel)
      File.file?(path) ? File.read(path) : ""
    end

    def git(*args)
      _o, e, s = Open3.capture3("git", *args)
      raise "git #{args.first(3).join(" ")} failed: #{e.strip}" unless s.success?
    end

    def capture(cmd)
      out, _e, _s = Open3.capture3(*cmd)
      out
    end
  end
end
