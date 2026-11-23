# frozen_string_literal: true

require "agent_cli_runtime"

module HiveBench
  # A candidate cell's invocation contract: which agent harness + which model,
  # and how to pin that model on the CLI. hive (the source project) pins a model
  # only for claude — `Hive::Agent#build_cmd` rejects model flags for codex/pi —
  # so hive-bench carries its own thin profile layer instead of reusing hive's.
  #
  # The model-pinning argv fragment is the whole point of this class; the full
  # run invocation (cwd, isolation, output capture) is the runner's job (U3).
  # `command(prompt:)` returns a headless, model-pinned argv the runner extends.
  #
  # Deterministic local prerequisite checks are delegated to
  # agent-cli-runtime. HiveBench keeps its benchmark-specific command and model
  # policy; the shared package owns binary discovery, bounded version probing,
  # minimum versions, and auth-configuration discovery.
  class Profile
    Preflight = Data.define(:available, :reason, :version)

    attr_reader :id, :harness, :model, :bin, :version_flag, :min_version, :auth_path

    # headless_argv: ->(prompt:) => [argv...] — must bake in the model + headless flag.
    def initialize(id:, harness:, model:, bin:, headless_argv:, auth_path: nil)
      @id = id
      @harness = harness
      @model = model
      @bin = bin
      @headless_argv = headless_argv
      @runtime_profile = runtime_profile(harness)
      @version_flag = @runtime_profile&.version_flag || "--version"
      @min_version = @runtime_profile&.min_version
      @auth_path = auth_path
      freeze
    end

    def command(prompt:)
      @headless_argv.call(prompt: prompt)
    end

    # Returns a Preflight value: is this cell runnable here, and if not, exactly why?
    # Never raises — an unavailable agent reports a precise reason rather than
    # blowing up a benchmark pass (a cell that can't run is recorded, not skipped).
    #
    # runtime_probe is injectable so tests never need a live provider CLI.
    def preflight(home: nil, env: ENV,
                  runtime_probe: AgentCliRuntime.method(:probe))
      unless @runtime_profile
        return unavailable(
          "agent-cli-runtime does not support #{@harness.inspect}"
        )
      end

      result = runtime_probe.call(
        @runtime_profile,
        home: home,
        env: runtime_environment(env)
      )
      return unavailable(result.diagnostic || "binary `#{@bin}` not found on PATH") unless result.installed

      if @auth_path && result.auth_configuration.status == :missing
        return unavailable(
          "not logged in (#{@auth_path} absent) — run the #{@harness} login first"
        )
      end
      return unavailable(result.diagnostic || "`#{@bin} #{@version_flag}` failed") unless result.version

      Preflight.new(available: true, reason: "ok", version: result.version)
    end

    private

    def runtime_profile(harness)
      AgentCliRuntime::Profiles.fetch(harness)
    rescue AgentCliRuntime::UnknownProvider
      nil
    end

    def unavailable(reason, version: nil)
      Preflight.new(available: false, reason: reason, version: version)
    end

    def runtime_environment(env)
      env.to_h.merge(
        "AGENT_CLI_RUNTIME_#{@runtime_profile.name.to_s.upcase}_BIN" => @bin
      )
    end
  end
end
