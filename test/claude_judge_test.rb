# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "lib/claude_judge"

# Unit-tests the pure parsing of claude's print-mode output. The live claude
# call is the edge (a seam, like every other model call in this harness) and is
# exercised by the run-pass validation, keeping the suite offline — matching the
# repo's existing "judge_fn is a seam so tests run offline" design.
class ClaudeJudgeTest < Minitest::Test
  CJ = HiveBench::ClaudeJudge

  # --- judge_fn (the live subprocess seam) against a fake judge binary ---

  def setup
    @dir = Dir.mktmpdir("hb-judge")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
  end

  def test_parses_clean_last_line_json
    res = CJ.parse_score(%({"score": 8, "reason": "complete and correct"}))

    assert_equal 8, res[:score]
    assert_equal "complete and correct", res[:reason]
  end

  def test_picks_the_last_score_object_when_prose_precedes_it
    text = "Let me evaluate this diff.\nIt handles the edge cases.\n" +
           %({"score": 6.5, "reason": "minor gap"})
    res = CJ.parse_score(text)

    assert_in_delta 6.5, res[:score]
    assert_equal "minor gap", res[:reason]
  end

  def test_tolerates_trailing_whitespace_and_stray_prefix_on_the_line
    res = CJ.parse_score(%(  result: {"score": 9, "reason": "great"}  \n))

    assert_equal 9, res[:score]
  end

  def test_raises_when_no_score_json_present
    err = assert_raises(HiveBench::ClaudeJudge::Error) { CJ.parse_score("I cannot grade this.") }

    assert_match(/no parseable/, err.message)
  end

  def test_ignores_json_without_a_score_key
    err = assert_raises(HiveBench::ClaudeJudge::Error) do
      CJ.parse_score(%({"note": "no score here"}))
    end

    assert_match(/no parseable/, err.message)
  end

  def test_raises_on_non_numeric_score_instead_of_coercing_to_zero
    assert_raises(HiveBench::ClaudeJudge::Error) { CJ.parse_score(%({"score": null, "reason": "abstained"})) }
    assert_raises(HiveBench::ClaudeJudge::Error) { CJ.parse_score(%({"score": "high"})) }
  end

  def test_skips_a_non_numeric_trailing_line_to_find_the_real_numeric_score
    text = "{\"score\": 7, \"reason\": \"good\"}\n{\"score\": null}"
    res = CJ.parse_score(text)

    assert_equal 7, res[:score], "a malformed last line must not mask the valid score below it"
  end

  # A fake `claude`-like CLI: emits `stdout`, then exits `exit_code`.
  def fake_bin(stdout: "", exit_code: 0)
    path = File.join(@dir, "fake_judge_#{exit_code}.sh")
    File.write(path, "#!/usr/bin/env bash\ncat <<'HB_EOF'\n#{stdout}\nHB_EOF\nexit #{exit_code}\n")
    FileUtils.chmod(0o755, path)
    path
  end

  def test_judge_fn_runs_the_binary_and_parses_the_score
    fn = CJ.judge_fn(bin: fake_bin(stdout: %({"score": 8, "reason": "solid"})), timeout_s: 10)
    res = fn.call(prompt: "grade this", seed: 1)

    assert_equal 8, res[:score]
    assert_equal "solid", res[:reason]
  end

  def test_judge_fn_raises_on_nonzero_exit
    fn = CJ.judge_fn(bin: fake_bin(stdout: "boom", exit_code: 1), timeout_s: 10)
    err = assert_raises(HiveBench::ClaudeJudge::Error) { fn.call(prompt: "x", seed: 1) }

    assert_match(/exited 1/, err.message)
    assert_match(/boom/, err.message, "stdout must explain failures when the CLI leaves stderr empty")
  end

  def test_judge_fn_reports_a_timeout_distinctly
    # exit 124 is what the `timeout` wrapper returns when it kills a hung judge.
    fn = CJ.judge_fn(bin: fake_bin(stdout: "", exit_code: 124), timeout_s: 10)
    err = assert_raises(HiveBench::ClaudeJudge::Error) { fn.call(prompt: "x", seed: 1) }

    assert_match(/timed out/, err.message)
  end
end
