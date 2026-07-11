# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "lib/agent_limit"
require "lib/codex_judge"

class CodexJudgeTest < Minitest::Test
  CJ = HiveBench::CodexJudge

  def setup
    @dir = Dir.mktmpdir("hb-codex-judge")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def fake_bin(stderr:, exit_code:)
    path = File.join(@dir, "fake_codex.sh")
    File.write(path, <<~SH)
      #!/usr/bin/env bash
      cat >/dev/null
      cat >&2 <<'HB_EOF'
      #{stderr}
      HB_EOF
      exit #{exit_code}
    SH
    FileUtils.chmod(0o755, path)
    path
  end

  def test_nonzero_exit_preserves_a_limit_marker_after_a_long_cli_banner
    stderr = ("banner line\n" * 100) + "You've hit your usage limit. Try again later."
    fn = CJ.judge_fn(bin: fake_bin(stderr: stderr, exit_code: 1), timeout_s: 10)

    error = assert_raises(HiveBench::CodexJudge::Error) { fn.call(prompt: "grade", seed: 1) }

    assert HiveBench::AgentLimit.limit_hit?(error.message),
           "the rejudge warning truncates this message, so a stable limit marker must lead it"
  end
end
