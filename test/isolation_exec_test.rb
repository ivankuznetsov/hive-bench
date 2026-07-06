# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "lib/isolation_exec"
require "lib/profile"

# Unit-tests the pure parts of the gen seam (pi JSON parsing, command building,
# prompt framing). The Docker edge itself is exercised by the run-pass dry-run,
# not here, so these stay fast and offline.
class IsolationExecTest < Minitest::Test
  IE = HiveBench::IsolationExec

  def pi_profile(model = "openrouter/z-ai/glm-5.2")
    HiveBench::Profile.new(id: "pi@glm-5.2", harness: "pi", model: model, bin: "pi",
                           headless_argv: ->(prompt:) { ["pi", prompt] })
  end

  # A two-turn assistant stream (tool call then final answer), in pi's real
  # `--mode json` shape. Usage must SUM across both assistant message_end events.
  def two_turn_stream
    [
      { "type" => "session", "id" => "x" },
      { "type" => "message_start", "message" => { "role" => "user", "content" => [] } },
      { "type" => "message_end", "message" => {
        "role" => "assistant", "model" => "z-ai/glm-5.2", "provider" => "openrouter",
        "usage" => { "input" => 1000, "output" => 50, "cacheRead" => 200,
                     "cost" => { "total" => 0.0021 } }
      } },
      { "type" => "message_start", "message" => { "role" => "tool", "content" => [] } },
      { "type" => "message_end", "message" => {
        "role" => "assistant", "model" => "z-ai/glm-5.2", "provider" => "openrouter",
        "usage" => { "input" => 1500, "output" => 80, "cacheRead" => 300,
                     "cost" => { "total" => 0.0034 } }
      } },
      { "type" => "agent_end", "messages" => [] }
    ].map { |o| JSON.generate(o) }.join("\n")
  end

  # --- gen_exec / gate_exec lifecycle against a fake isolation script ---

  def setup
    @dir = Dir.mktmpdir("hb-genexec")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def test_parse_sums_usage_and_cost_across_assistant_turns
    parsed = IE.parse_pi_stream(two_turn_stream)

    assert_equal 2500, parsed[:usage][:input], "input tokens sum across turns"
    assert_equal 130, parsed[:usage][:output]
    assert_equal 500, parsed[:usage][:cached]
    assert_in_delta 0.0055, parsed[:usage][:cost], 1e-9, "provider cost sums across turns"
    assert_equal "z-ai/glm-5.2", parsed[:model]
  end

  def test_parse_ignores_non_json_and_non_assistant_lines
    stream = "boot log line\n#{JSON.generate({ "type" => "message_end",
                                               "message" => { "role" => "user" } })}\nnot json"
    parsed = IE.parse_pi_stream(stream)

    assert_empty parsed[:usage], "no assistant turns -> no usage recorded"
    assert_nil parsed[:model]
  end

  def test_parse_handles_the_402_credit_stream_as_zero_usage
    # The real drained-balance stream: an assistant message_end with an error and
    # zero usage. Parsing must not blow up; AgentLimit handles the limit signal.
    err = { "type" => "message_end", "message" => {
      "role" => "assistant", "model" => "z-ai/glm-5.2",
      "usage" => { "input" => 0, "output" => 0, "cacheRead" => 0, "cost" => { "total" => 0 } },
      "stopReason" => "error", "errorMessage" => "402 Insufficient credits. Add more using https://openrouter.ai/settings/credits"
    } }
    parsed = IE.parse_pi_stream(JSON.generate(err))

    assert_equal 0, parsed[:usage][:input]
    assert_equal "z-ai/glm-5.2", parsed[:model]
  end

  def test_agent_command_pins_model_and_reads_prompt_from_work
    cmd = IE.agent_command(pi_profile)

    assert_includes cmd, "--model openrouter/z-ai/glm-5.2"
    assert_includes cmd, "--mode json"
    assert_includes cmd, "timeout #{HiveBench::IsolationExec::DEFAULT_AGENT_TIMEOUT} pi", "a wedged agent is bounded"
    assert_includes cmd, %("$(cat /work/#{HiveBench::IsolationExec::PROMPT_FILE})"), "plan delivered verbatim via cat"
  end

  def test_agent_command_timeout_is_operator_overridable
    ENV["HB_AGENT_TIMEOUT"] = "42"

    assert_includes IE.agent_command(pi_profile), "timeout 42 pi"
  ensure
    ENV.delete("HB_AGENT_TIMEOUT")
  end

  def test_agent_command_rejects_an_unwired_harness
    other = HiveBench::Profile.new(id: "gemini@x", harness: "gemini", model: "g", bin: "gemini",
                                   headless_argv: ->(prompt:) { [prompt] })
    err = assert_raises(HiveBench::IsolationExec::UnsupportedHarness) { IE.agent_command(other) }

    assert_match(/no wired command for gemini@x/, err.message)
  end

  def test_agent_command_builds_a_claude_invocation
    claude = HiveBench::Profile.new(id: "claude@opus-4.8", harness: "claude", model: "opus-4.8", bin: "claude",
                                    auth_path: "~/.claude/.credentials.json", headless_argv: ->(prompt:) { [prompt] })
    cmd = IE.agent_command(claude)

    assert_includes cmd, "claude -p --model opus-4.8 --dangerously-skip-permissions --output-format json"
    assert_includes cmd, %("$(cat /work/#{HiveBench::IsolationExec::PROMPT_FILE})")
  end

  def test_parse_claude_result_extracts_usage_and_cost
    out = JSON.generate({ "type" => "result", "is_error" => false, "total_cost_usd" => 0.1234,
                          "usage" => { "input_tokens" => 5000, "output_tokens" => 800, "cache_read_input_tokens" => 1200 },
                          "modelUsage" => { "claude-haiku-4-5" => {} } })
    parsed = IE.parse_claude_result(out)

    assert_equal 5000, parsed[:usage][:input]
    assert_equal 800, parsed[:usage][:output]
    assert_equal 1200, parsed[:usage][:cached]
    assert_in_delta 0.1234, parsed[:usage][:cost], 1e-9
    assert_nil parsed[:model], "model is taken from the requested profile, not claude's mixed modelUsage"
  end

  def test_agent_command_builds_a_codex_invocation
    codex = HiveBench::Profile.new(id: "codex@gpt-5.5-xhigh", harness: "codex", model: "gpt-5.5", bin: "codex",
                                   auth_path: "~/.codex/auth.json", headless_argv: ->(prompt:) { [prompt] })
    cmd = IE.agent_command(codex)

    assert_includes cmd, "codex exec --json -m gpt-5.5"
    assert_includes cmd, %(model_reasoning_effort="xhigh")
    assert_includes cmd, "--dangerously-bypass-approvals-and-sandbox"
    assert_includes cmd, %("$(cat /work/#{HiveBench::IsolationExec::PROMPT_FILE})")
  end

  def test_parse_codex_stream_sums_turn_usage
    stream = [
      { "type" => "turn.started" },
      { "type" => "turn.completed", "usage" => { "input_tokens" => 1000, "output_tokens" => 50,
                                                 "cached_input_tokens" => 200, "reasoning_output_tokens" => 30 } },
      { "type" => "turn.completed", "usage" => { "input_tokens" => 1500, "output_tokens" => 80,
                                                 "cached_input_tokens" => 300, "reasoning_output_tokens" => 20 } }
    ].map { |o| JSON.generate(o) }.join("\n")
    parsed = IE.parse_codex_stream(stream)

    assert_equal 2500, parsed[:usage][:input]
    assert_equal 180, parsed[:usage][:output], "reasoning tokens count toward output (they bill as output)"
    assert_equal 500, parsed[:usage][:cached]
  end

  def test_gen_env_passes_codex_creds_path_only_for_codex_cells
    codex = HiveBench::Profile.new(id: "codex@x", harness: "codex", model: "gpt-5.5", bin: "codex",
                                   auth_path: "~/.codex/auth.json", headless_argv: ->(prompt:) { [prompt] })
    env = IE.gen_env(codex)

    assert_equal File.expand_path("~/.codex/auth.json"), env["HB_CODEX_AUTH"]
    refute env.key?("HB_CLAUDE_AUTH")
    refute IE.gen_env(pi_profile).key?("HB_CODEX_AUTH")
  end

  def test_parse_claude_result_surfaces_an_error_for_limit_detection
    out = JSON.generate({ "type" => "result", "is_error" => true,
                          "result" => "Claude usage limit reached", "usage" => {} })
    parsed = IE.parse_claude_result(out)

    assert_includes parsed[:errors], "Claude usage limit reached"
  end

  def test_gen_env_passes_claude_creds_path_only_for_claude_cells
    claude = HiveBench::Profile.new(id: "claude@opus-4.8", harness: "claude", model: "opus-4.8", bin: "claude",
                                    auth_path: "~/.claude/.credentials.json", headless_argv: ->(prompt:) { [prompt] })
    env = IE.gen_env(claude)

    assert_equal "1", env["HB_ALLOW_EGRESS"]
    assert_equal File.expand_path("~/.claude/.credentials.json"), env["HB_CLAUDE_AUTH"]
    refute IE.gen_env(pi_profile).key?("HB_CLAUDE_AUTH"), "pi cells never mount claude creds"
  end

  def test_isolation_script_rejects_missing_claude_auth_before_docker_run
    bin = File.join(@dir, "bin")
    FileUtils.mkdir_p(bin)
    docker = File.join(bin, "docker")
    File.write(docker, "#!/usr/bin/env bash\necho docker must not run >&2\nexit 99\n")
    FileUtils.chmod(0o755, docker)
    missing_auth = File.join(@dir, "missing", ".credentials.json")
    env = {
      "PATH" => "#{bin}:#{ENV.fetch("PATH")}",
      "HB_ALLOW_EGRESS" => "1",
      "HB_CLAUDE_AUTH" => missing_auth
    }

    _out, err, status = Open3.capture3(env, "bash", IE::SCRIPT, "gen", @dir, "true")

    assert_equal IE::FAIL_ISOLATION, status.exitstatus
    assert_match(/claude auth path is missing or not a file/, err)
    refute File.exist?(missing_auth), "missing bind-mount source must not be created"
  end

  def test_frame_prompt_wraps_plan_with_uniform_instruction
    framed = IE.frame_prompt("# Plan\nDo the thing.")

    assert_includes framed, "autonomous coding agent"
    assert_includes framed, "<plan>"
    assert_includes framed, "Do the thing."
  end

  # --- cost-shape and turn-filtering edge cases (scoring fidelity) ---

  def test_parse_tolerates_scalar_cost_and_missing_cost
    scalar = JSON.generate({ "type" => "message_end", "message" => {
                             "role" => "assistant", "model" => "m", "usage" => { "input" => 10, "cost" => 0.5 }
                           } })
    missing = JSON.generate({ "type" => "message_end", "message" => {
                              "role" => "assistant", "model" => "m", "usage" => { "input" => 10 }
                            } })

    assert_in_delta 0.5, IE.parse_pi_stream(scalar)[:usage][:cost], 1e-9, "scalar cost is read, not crashed on"
    assert_in_delta 0.0, IE.parse_pi_stream(missing)[:usage][:cost], 1e-9, "missing cost is 0.0, not nil, when turns exist"
  end

  def test_parse_counts_only_assistant_turns_when_user_events_interleave
    stream = [
      { "type" => "message_end", "message" => { "role" => "assistant", "model" => "m", "usage" => { "input" => 100 } } },
      { "type" => "message_end", "message" => { "role" => "user", "content" => [] } },
      { "type" => "message_end", "message" => { "role" => "assistant", "model" => "m", "usage" => { "input" => 200 } } }
    ].map { |o| JSON.generate(o) }.join("\n")

    assert_equal 300, IE.parse_pi_stream(stream)[:usage][:input], "user message_end events never contribute usage"
  end

  # A stand-in for isolation.sh that emits canned output and a chosen exit code,
  # so the seam's orchestration is testable without the real runner.
  def fake_script(stdout: "", exit_code: 0)
    path = File.join(@dir, "fake_#{exit_code}_#{stdout.hash.abs}.sh")
    File.write(path, "#!/usr/bin/env bash\ncat <<'HB_EOF'\n#{stdout}\nHB_EOF\nexit #{exit_code}\n")
    path
  end

  def assistant_stream(model: "z-ai/glm-5.2", input: 1000, cost: 0.002)
    JSON.generate({ "type" => "message_end", "message" => {
                    "role" => "assistant", "model" => model,
                    "usage" => { "input" => input, "output" => 10, "cacheRead" => 0, "cost" => { "total" => cost } }
                  } })
  end

  def prompt_path = File.join(@dir, HiveBench::IsolationExec::PROMPT_FILE)

  def test_gen_exec_returns_ok_with_usage_and_removes_the_prompt_file
    result = IE.gen_exec(script: fake_script(stdout: assistant_stream)).call(
      profile: pi_profile, prompt: "# Plan\ndo it", cwd: @dir
    )

    assert_equal :ok, result[:status]
    assert_equal 1000, result[:usage][:input]
    assert_in_delta 0.002, result[:usage][:cost], 1e-9
    assert_equal "z-ai/glm-5.2", result[:model]
    refute_path_exists prompt_path, "the plan file is cleaned out of the work tree before the diff is captured"
  end

  def test_gen_exec_maps_nonzero_agent_exit_to_error_status
    result = IE.gen_exec(script: fake_script(stdout: "boom", exit_code: 1)).call(
      profile: pi_profile, prompt: "x", cwd: @dir
    )

    assert_equal :error, result[:status], "a genuine agent failure is :error (scored as agent_failed), not raised"
  end

  def test_gen_exec_maps_timeout_kill_to_timeout_status
    # exit 124 is what the in-container `timeout` wrapper returns when it kills a
    # candidate that ran past HB_AGENT_TIMEOUT.
    result = IE.gen_exec(script: fake_script(stdout: assistant_stream, exit_code: 124)).call(
      profile: pi_profile, prompt: "x", cwd: @dir
    )

    assert_equal :timeout, result[:status], "a timeout-kill is distinct from a clean failure"
    assert_equal 1000, result[:usage][:input], "partial usage is still captured"
  end

  def test_gen_exec_falls_back_to_profile_model_when_stream_has_none
    result = IE.gen_exec(script: fake_script(stdout: "no json here", exit_code: 0)).call(
      profile: pi_profile("openrouter/z-ai/glm-5.2"), prompt: "x", cwd: @dir
    )

    assert_equal "openrouter/z-ai/glm-5.2", result[:model]
  end

  def test_gen_exec_fails_closed_and_still_cleans_up_on_isolation_refusal
    gen = IE.gen_exec(script: fake_script(stdout: "egress not acknowledged", exit_code: 70))

    assert_raises(HiveBench::IsolationExec::IsolationError) do
      gen.call(profile: pi_profile, prompt: "x", cwd: @dir)
    end
    refute_path_exists prompt_path, "prompt file is removed even when isolation is refused"
  end

  def test_gen_exec_treats_container_start_failure_as_isolation_not_agent
    gen = IE.gen_exec(script: fake_script(stdout: "invalid mount", exit_code: 125))

    err = assert_raises(HiveBench::IsolationExec::IsolationError) do
      gen.call(profile: pi_profile, prompt: "x", cwd: @dir)
    end
    assert_match(/exit 125/, err.message)
  end

  def test_gate_exec_fails_closed_on_isolation_refusal_but_passes_real_results_through
    refusal = IE.gate_exec(script: fake_script(stdout: "runner unavailable", exit_code: 70))
    assert_raises(HiveBench::IsolationExec::IsolationError) { refusal.call(cmd: "rake test", work_dir: @dir) }

    failing = IE.gate_exec(script: fake_script(stdout: "1 failure", exit_code: 1)).call(cmd: "rake", work_dir: @dir)

    refute failing[:ok], "a real test failure (exit 1) is a normal gate result, not an isolation error"
  end

  def test_gen_exec_fails_closed_on_all_container_start_codes
    [126, 127].each do |code|
      gen = IE.gen_exec(script: fake_script(stdout: "container did not start", exit_code: code))
      err = assert_raises(HiveBench::IsolationExec::IsolationError, "exit #{code} must fail closed") do
        gen.call(profile: pi_profile, prompt: "x", cwd: @dir)
      end
      assert_match(/exit #{code}/, err.message)
    end
  end

  def test_agent_command_malformed_timeout_falls_back_to_default
    ENV["HB_AGENT_TIMEOUT"] = "30m"
    cmd = IE.agent_command(pi_profile)

    assert_includes cmd, "timeout #{HiveBench::IsolationExec::DEFAULT_AGENT_TIMEOUT} pi",
                    "a non-integer override must not crash; it falls back to the default"
  ensure
    ENV.delete("HB_AGENT_TIMEOUT")
  end

  def test_parse_collects_provider_error_messages
    stream = JSON.generate({ "type" => "message_end", "message" => {
                             "role" => "assistant", "model" => "z-ai/glm-5.2", "stopReason" => "error",
                             "usage" => { "input" => 0 }, "errorMessage" => "402 Insufficient credits"
                           } })

    assert_includes IE.parse_pi_stream(stream)[:errors], "402 Insufficient credits"
  end

  def test_gen_exec_exposes_provider_errors_for_focused_limit_detection
    stream = JSON.generate({ "type" => "message_end", "message" => {
                             "role" => "assistant", "model" => "z-ai/glm-5.2", "stopReason" => "error",
                             "usage" => { "input" => 0 }, "errorMessage" => "429 rate limit exceeded"
                           } })
    result = IE.gen_exec(script: fake_script(stdout: stream)).call(profile: pi_profile, prompt: "x", cwd: @dir)

    assert result.key?(:provider_errors), "gen exposes a focused limit signal channel"
    assert_includes result[:provider_errors], "429 rate limit exceeded"
  end
end
