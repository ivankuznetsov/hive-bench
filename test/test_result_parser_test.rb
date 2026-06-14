# frozen_string_literal: true

require "minitest/autorun"
require "lib/test_result_parser"

class TestResultParserTest < Minitest::Test
  P = HiveBench::TestResultParser

  GREEN = <<~OUT
    Run options: --seed 123

    # Running:

    ......

    Finished in 0.01s
    6 runs, 18 assertions, 0 failures, 0 errors, 0 skips
  OUT

  RED = <<~OUT
    # Running:

    .F.E.

    1) Failure:
    InfoPanelTest#test_renders_key [test/tui_test.rb:42]:
    Expected the footer to include "[i] info".

    2) Error:
    InfoPanelTest#test_opens_panel:
    NoMethodError: undefined method `open'

    5 runs, 9 assertions, 1 failures, 1 errors, 0 skips
  OUT

  def test_parses_a_green_suite
    r = P.parse(GREEN)

    assert r.ran
    assert_predicate r, :suite_green?
    assert_equal 6, r.passed
    assert_equal 0, r.failed
  end

  def test_parses_a_red_suite_with_named_failures
    r = P.parse(RED)

    assert r.ran
    refute_predicate r, :suite_green?
    assert_equal 1, r.failed
    assert_equal 1, r.errored
    refute r.by_name["InfoPanelTest#test_renders_key"]
    refute r.by_name["InfoPanelTest#test_opens_panel"]
  end

  def test_test_passed_reports_named_failure_and_implicit_pass
    r = P.parse(RED)

    refute P.test_outcome(r, "InfoPanelTest#test_renders_key"), "a named failure is not passed"
    assert P.test_outcome(r, "InfoPanelTest#test_some_other"), "a test not in the failure list passed"
  end

  def test_unparseable_output_is_not_run
    r = P.parse("compilation error: cannot load such file")

    refute r.ran
    refute_predicate r, :suite_green?, "unparseable output must never read as green"
    assert_nil P.test_outcome(r, "X#y")
  end

  def test_handles_empty
    refute P.parse("").ran
    refute P.parse(nil).ran
  end
end
