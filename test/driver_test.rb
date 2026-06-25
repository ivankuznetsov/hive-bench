# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "run_all"
require "profiles/slate"

# Covers the Driver's run-guards and operator feedback (the new README
# entrypoint). The live Docker/claude wiring is the edge, validated by the
# run-pass dry-run; here we test the pure orchestration around it.
class DriverTest < Minitest::Test
  D = HiveBench::Driver

  def with_env(key, value)
    old = ENV.fetch(key, nil)
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    old.nil? ? ENV.delete(key) : ENV[key] = old
  end

  # assert_raises around the abort, swallowing its stderr message.
  def assert_aborts(&)
    assert_raises(SystemExit) { capture_io(&) }
  end

  def test_validate_requires_a_source
    assert_aborts { D.validate!({ source: nil }) }
  end

  def test_validate_rejects_a_source_that_is_not_a_directory
    assert_aborts { D.validate!({ source: "/no/such/dir/hb-#{Process.pid}" }) }
  end

  def test_validate_requires_the_openrouter_key
    Dir.mktmpdir do |dir|
      with_env("OPENROUTER_API_KEY", "") do
        assert_aborts { D.validate!({ source: dir }) }
      end
    end
  end

  def test_validate_passes_with_source_dir_and_key
    Dir.mktmpdir do |dir|
      with_env("OPENROUTER_API_KEY", "sk-or-test") do
        assert_nil D.validate!({ source: dir })
      end
    end
  end

  def test_select_profiles_returns_the_whole_slate_by_default
    assert_equal HiveBench::Slate.profiles.map(&:id).sort, D.select_profiles(nil).map(&:id).sort
  end

  def test_select_profiles_narrows_to_one_cell
    picked = D.select_profiles("pi@glm-5.2")

    assert_equal ["pi@glm-5.2"], picked.map(&:id)
  end

  def test_select_profiles_aborts_on_unknown_agent_and_names_the_slate
    _out, err = capture_io { assert_raises(SystemExit) { D.select_profiles("nope@nope") } }

    assert_match(/unknown agent nope@nope/, err)
    assert_match(/pi@glm-5.2/, err, "the abort lists the real slate ids")
  end

  def test_report_surfaces_scored_pending_and_failed_lines
    results = { "cells" => [{ "subset" => "judged", "agent_id" => "pi@glm-5.2", "task_id" => "t1",
                              "run_status" => "generated", "gate" => { "status" => "no_gate" },
                              "judges" => { "opus-4.8" => { "mean" => 7.5 } } }] }
    outcome = HiveBench::RunAll::Outcome.new(
      results: results,
      pending: [{ "agent_id" => "pi@glm-5.2", "task_id" => "t2", "reason" => "402 credits" }],
      failed: [{ "agent_id" => "codex@gpt-5.5-xhigh", "task_id" => "t3", "reason" => "not wired" }]
    )

    _out, err = capture_io { D.report(outcome, "runs/results.json") }

    assert_match(/1 scored cell.*1 pending.*1 failed/, err)
    assert_match(/pending  pi@glm-5.2  t2  \(402 credits\)/, err)
    assert_match(/FAILED   codex@gpt-5.5-xhigh  t3  \(not wired\)/, err)
    assert_match(/judged  pi@glm-5.2  t1  gen=generated  gate=no_gate  judge\[opus-4.8=7.5\]/, err)
  end
end
