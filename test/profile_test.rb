# frozen_string_literal: true

require "minitest/autorun"
require "lib/profile"

class ProfileTest < Minitest::Test
  def build(**overrides)
    defaults = {
      id: "claude@opus-4.8", harness: "claude", model: "opus-4.8", bin: "claude",
      min_version: "2.1.118", auth_path: "~/.claude/.credentials.json",
      headless_argv: ->(prompt:) { ["claude", "-p", "--model", "opus-4.8", prompt] }
    }
    HiveBench::Profile.new(**defaults, **overrides)
  end

  # Seams that simulate a healthy environment.
  def ok_env
    {
      which: ->(_bin) { "/usr/bin/claude" },
      file_exists: ->(_path) { true },
      probe: ->(_bin, _flag) { ["2.1.170 (Claude Code)", true] }
    }
  end

  def test_command_bakes_in_the_model
    argv = build.command(prompt: "do the thing")

    assert_includes argv, "--model"
    assert_includes argv, "opus-4.8"
    assert_equal "do the thing", argv.last
  end

  def test_preflight_available_in_a_healthy_environment
    result = build.preflight(**ok_env)

    assert result.available, "a present binary + auth + new-enough version must be available"
    assert_equal "2.1.170", result.version
  end

  def test_preflight_reports_missing_binary_precisely
    result = build.preflight(**ok_env, which: ->(_bin) {})

    refute result.available
    assert_match(/not found on PATH/, result.reason)
  end

  def test_preflight_reports_missing_auth_precisely
    result = build.preflight(**ok_env, file_exists: ->(_path) { false })

    refute result.available
    assert_match(/not logged in/, result.reason)
  end

  def test_preflight_reports_stale_version_with_the_number
    stale = ok_env.merge(probe: ->(_bin, _flag) { ["1.0.0", true] })
    result = build.preflight(**stale)

    refute result.available
    assert_match(/older than the required 2.1.118/, result.reason)
    assert_equal "1.0.0", result.version
  end

  def test_preflight_handles_version_probe_failure
    result = build.preflight(**ok_env, probe: ->(_bin, _flag) { ["", false] })

    refute result.available
    assert_match(/failed/, result.reason)
  end

  def test_profile_without_auth_path_skips_the_auth_check
    p = build(auth_path: nil)
    result = p.preflight(**ok_env, file_exists: ->(_path) { flunk("auth must not be checked when auth_path is nil") })

    assert result.available
  end
end
