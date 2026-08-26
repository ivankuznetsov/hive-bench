# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "lib/profile"

class ProfileTest < Minitest::Test
  def build(**overrides)
    defaults = {
      id: "claude@opus-4.8", harness: "claude", model: "opus-4.8", bin: "claude",
      auth_path: "~/.claude/.credentials.json",
      headless_argv: ->(prompt:) { ["claude", "-p", "--model", "opus-4.8", prompt] }
    }
    HiveBench::Profile.new(**defaults, **overrides)
  end

  def probe_result(installed: true, version: "2.1.170", auth: :configured,
                   diagnostic: nil)
    AgentCliRuntime::ProbeResult.new(
      provider: :claude,
      ready: installed && version && auth != :missing,
      installed: installed,
      executable: "claude",
      version: version,
      minimum_version: "2.1.118",
      auth_configuration: AgentCliRuntime::AuthConfiguration.new(status: auth),
      capability_evidence: [],
      diagnostic: diagnostic
    )
  end

  def with_probe(result)
    lambda do |_profile, home:, env:|
      assert_nil home
      assert_equal "claude", env.fetch("AGENT_CLI_RUNTIME_CLAUDE_BIN")
      result
    end
  end

  def test_command_bakes_in_the_model
    argv = build.command(prompt: "do the thing")

    assert_includes argv, "--model"
    assert_includes argv, "opus-4.8"
    assert_equal "do the thing", argv.last
  end

  def test_preflight_available_in_a_healthy_environment
    result = build.preflight(runtime_probe: with_probe(probe_result))

    assert result.available, "a present binary + auth + new-enough version must be available"
    assert_equal "2.1.170", result.version
  end

  def test_preflight_reports_missing_binary_precisely
    runtime = probe_result(installed: false, version: nil, auth: :not_checked,
                           diagnostic: "claude binary not runnable: claude")
    result = build.preflight(runtime_probe: with_probe(runtime))

    refute result.available
    assert_match(/not runnable/, result.reason)
  end

  def test_preflight_reports_missing_auth_precisely
    result = build.preflight(
      runtime_probe: with_probe(probe_result(auth: :missing))
    )

    refute result.available
    assert_match(/not logged in/, result.reason)
  end

  def test_preflight_reports_stale_version_with_the_number
    stale = probe_result(
      version: nil,
      diagnostic: "claude 1.0.0 below minimum 2.1.118"
    )
    result = build.preflight(runtime_probe: with_probe(stale))

    refute result.available
    assert_match(/1.0.0 below minimum 2.1.118/, result.reason)
    assert_nil result.version
  end

  def test_preflight_handles_version_probe_failure
    failed = probe_result(
      version: nil,
      diagnostic: "could not parse claude --version output"
    )
    result = build.preflight(runtime_probe: with_probe(failed))

    refute result.available
    assert_match(/could not parse/, result.reason)
  end

  def test_profile_without_auth_path_skips_the_auth_check
    p = build(auth_path: nil)
    result = p.preflight(
      runtime_probe: with_probe(probe_result(auth: :missing))
    )

    assert result.available
  end

  def test_preflight_reports_provider_outside_the_shared_runtime
    profile = build(harness: "gemini", bin: "gemini")

    result = profile.preflight(
      runtime_probe: ->(*) { flunk "unsupported provider must not be probed" }
    )

    refute result.available
    assert_match(/does not support "gemini"/, result.reason)
  end

  def test_real_runtime_probe_handles_local_binary_and_auth_configuration
    Dir.mktmpdir("hive-bench-agent-runtime") do |dir|
      bin = File.join(dir, "claude")
      File.write(bin, "#!/bin/sh\nprintf '%s\\n' 'claude-code 2.1.170'\n")
      File.chmod(0o755, bin)
      credentials = File.join(dir, ".claude", ".credentials.json")
      FileUtils.mkdir_p(File.dirname(credentials))
      File.write(credentials, '{"configured":true}')

      result = build(bin: bin).preflight(home: dir, env: { "PATH" => "/usr/bin:/bin" })

      assert result.available
      assert_equal "2.1.170", result.version
    end
  end
end
