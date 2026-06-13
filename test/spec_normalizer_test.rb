# frozen_string_literal: true

require "minitest/autorun"
require "lib/spec_normalizer"

class SpecNormalizerTest < Minitest::Test
  N = HiveBench::SpecNormalizer

  def test_rewrites_worktree_absolute_path_to_placeholder
    line = "Edit /home/asterio/Dev/hive.worktrees/add-i-key-260522/lib/hive/tui/foo.rb to add the binding.\n"
    out = N.normalize(line)

    assert_includes out, "<REPO_ROOT>/lib/hive/tui/foo.rb", "worktree path must collapse to <REPO_ROOT>/<subpath>"
    refute_includes out, "/home/asterio", "no absolute home path may survive"
  end

  def test_rewrites_plain_project_path
    out = N.normalize("See /home/asterio/Dev/hive/lib/hive/cli.rb for the entrypoint.\n")

    assert_includes out, "<REPO_ROOT>/lib/hive/cli.rb"
    refute_includes out, "/home/asterio"
  end

  def test_flags_repo_state_assertion_inline_without_deleting_it
    line = "1. There is no HTTP code in hive today. It is a CLI.\n"
    out = N.normalize(line)

    assert_includes out, "There is no HTTP code", "the assertion text must be preserved, not deleted"
    assert_includes out, "repo-state assertion", "a state assertion must be annotated for the candidate"
  end

  def test_leaves_ordinary_prose_untouched
    line = "Add a read-only info panel that renders stage-aware content.\n"

    assert_equal line, N.normalize(line)
  end

  def test_does_not_flag_code_or_table_lines
    # A fenced code line mentioning "today" or a markdown table row must not be annotated.
    text = "```\nputs \"today\"\n```\n| there is no | cell |\n"
    out = N.normalize(text)

    refute_includes out, "repo-state assertion", "code/table lines must not be annotated as prose assertions"
  end

  def test_is_idempotent
    text = "Touch /home/asterio/Dev/hive/lib/x.rb. There is no cache today.\n"
    once = N.normalize(text)
    twice = N.normalize(once)

    assert_equal once, twice, "normalization must be idempotent"
  end

  def test_analyze_reports_paths_and_assertions_without_mutating
    text = "Use /home/asterio/Dev/hive/lib/a.rb.\nThere are no migrations currently.\nplain line\n"
    report = N.analyze(text)

    assert_equal 1, report[:rewritten_paths].size
    assert_equal 1, report[:flagged_assertions].size
    assert_equal 2, report[:flagged_assertions].first[:line], "assertion is on line 2"
  end

  def test_handles_nil_and_empty
    assert_equal "", N.normalize(nil)
    assert_equal "", N.normalize("")
  end
end
