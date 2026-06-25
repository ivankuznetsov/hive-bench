# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "run"
require "lib/profile"

class RunTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("hb-run")
    @source = File.join(@root, "source")
    @base = build_source_repo
    @profile = HiveBench::Profile.new(
      id: "claude@opus-4.8", harness: "claude", model: "opus-4.8", bin: "claude",
      headless_argv: ->(prompt:) { ["claude", "-p", prompt] }
    )
    @entry = build_entry
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def sh!(*, chdir:)
    _o, e, s = Open3.capture3(*, chdir: chdir)
    raise "git failed: #{e}" unless s.success?
  end

  def build_source_repo
    FileUtils.mkdir_p(@source)
    sh!("git", "init", "-q", "-b", "main", chdir: @source)
    sh!("git", "config", "user.email", "t@e.c", chdir: @source)
    sh!("git", "config", "user.name", "T", chdir: @source)
    File.write(File.join(@source, "app.rb"), "puts 'v1'\n")
    sh!("git", "add", ".", chdir: @source)
    sh!("git", "commit", "-qm", "base", chdir: @source)
    Open3.capture2("git", "rev-parse", "HEAD", chdir: @source).first.strip
  end

  # A minimal on-disk corpus entry shaped as run.rb reads it.
  def build_entry
    dir = File.join(@root, "entry")
    FileUtils.mkdir_p(File.join(dir, "spec"))
    File.write(File.join(dir, "spec", "plan.md"), "# Plan\nMake app.rb print 'done'.\n")
    File.write(File.join(dir, "reference.patch"), "REFERENCE-DIFF\n")
    {
      "task_id" => "demo-task",
      "entry_dir" => dir,
      "checkout_source" => @source,
      "source" => { "base_commit" => @base, "repo" => "owner/demo" },
      "spec" => { "plan" => "spec/plan.md" }
    }
  end

  def out_dir = File.join(@root, "cells", "demo")

  def run_cell(spawn: nil, reuse_resolver: ->(_e, _p) {})
    HiveBench::Run.new(spawn: spawn, reuse_resolver: reuse_resolver,
                       clock: lambda {
                         @clock_calls = (@clock_calls || 0) + 1
                         Time.utc(2026, 6, 14, 12, 0, @clock_calls)
                       })
                  .call(entry: @entry, profile: @profile, out_dir: out_dir)
  end

  # A spawn that actually edits the restored worktree, so the real GitRestore
  # diff has something to capture (no mock of the git layer).
  def editing_spawn(content: "puts 'done'\n", status: :ok, stdout: "implemented it")
    lambda do |profile:, prompt:, cwd:|
      _ = [profile, prompt]
      File.write(File.join(cwd, "app.rb"), content)
      { stdout: stdout, stderr: "", status: status, model: "opus-4.8",
        usage: { input: 120, output: 40, cached: 10 } }
    end
  end

  # --- Covers AE3: fresh run produces a captured diff ---

  def test_fresh_run_captures_diff_and_telemetry
    cell = run_cell(spawn: editing_spawn)

    assert_equal "fresh", cell.mode
    assert_equal "generated", cell.status
    assert_equal "opus-4.8", cell.model_version
    diff = File.read(cell.diff_path)

    assert_includes diff, "+puts 'done'"
    assert_includes diff, "-puts 'v1'"
    assert_operator cell.telemetry["wall_clock_sec"], :>, 0, "fresh runs are timed"
    assert_equal 120, cell.telemetry["input_tokens"]
    refute cell.telemetry.key?("cost_usd"), "a spawn that reports no cost leaves cost_usd absent (not 0)"
  end

  def test_agent_failure_reason_falls_back_to_stdout_when_stderr_empty
    failing = lambda do |profile:, prompt:, cwd:|
      _ = [profile, prompt, cwd]
      { stdout: "fatal: could not resolve model", stderr: "", status: :error, model: "opus-4.8", usage: {} }
    end
    cell = run_cell(spawn: failing)

    assert_match(/could not resolve model/, cell.reason, "stdout is the fallback diagnostic when stderr is empty")
  end

  # The focused limit signal: when a spawn supplies provider_errors, the agent's
  # own solution prose must NOT be scanned (or a throttling-themed task would
  # false-positive into limit_hit and wrongly park a success).
  def test_provider_errors_channel_focuses_limit_detection
    prose_only = lambda do |profile:, prompt:, cwd:|
      _ = [profile, prompt]
      File.write(File.join(cwd, "app.rb"), "puts 'done'\n")
      { stdout: %({"text":"I made it raise when the rate limit is reached, returning HTTP 429"}),
        stderr: "", status: :ok, model: "opus-4.8", usage: { input: 10 }, provider_errors: "" }
    end
    cell = run_cell(spawn: prose_only)

    refute_equal "limit_hit", cell.status, "limit prose in the solution must not park the cell"
  end

  def test_provider_errors_still_detects_a_real_limit
    real_limit = lambda do |profile:, prompt:, cwd:|
      _ = [profile, prompt, cwd]
      { stdout: "", stderr: "", status: :error, model: "opus-4.8", usage: {},
        provider_errors: "402 Insufficient credits" }
    end
    cell = run_cell(spawn: real_limit)

    assert_equal "limit_hit", cell.status, "a real provider error in the focused channel is still caught"
  end

  def test_empty_diff_when_candidate_changes_nothing
    cell = run_cell(spawn: editing_spawn(content: "puts 'v1'\n")) # rewrites identical content

    assert_equal "empty_diff", cell.status
  end

  def test_agent_failure_is_recorded_not_raised
    cell = run_cell(spawn: editing_spawn(status: :error))

    assert_equal "agent_failed", cell.status
  end

  def test_timeout_kill_is_recorded_as_timed_out_with_partial_diff_kept
    cell = run_cell(spawn: editing_spawn(status: :timeout))

    assert_equal "timed_out", cell.status, "a wall-clock kill is distinct from a clean run"
    assert_includes File.read(cell.diff_path), "+puts 'done'", "the partial diff is still captured and judged"
    assert_match(/HB_AGENT_TIMEOUT/, cell.reason)
  end

  def test_agent_failure_reason_captures_a_diagnostic_snippet
    failing = lambda do |profile:, prompt:, cwd:|
      _ = [profile, prompt, cwd]
      { stdout: "", stderr: "pi: model handshake failed", status: :error, model: "opus-4.8", usage: {} }
    end
    cell = run_cell(spawn: failing)

    assert_equal "agent_failed", cell.status
    assert_match(/model handshake failed/, cell.reason, "agent_failed cells stay debuggable")
  end

  def test_fresh_run_records_provider_cost_when_the_spawn_reports_it
    paid = lambda do |profile:, prompt:, cwd:|
      _ = [profile, prompt]
      File.write(File.join(cwd, "app.rb"), "puts 'done'\n")
      { stdout: "ok", stderr: "", status: :ok, model: "opus-4.8",
        usage: { input: 120, output: 40, cached: 10, cost: 0.0031 } }
    end
    cell = run_cell(spawn: paid)

    assert_in_delta 0.0031, cell.telemetry["cost_usd"], 1e-9, "real provider cost is threaded into telemetry"
  end

  # --- usage limit -> re-run later, never scored ---

  def test_usage_limit_marks_cell_for_rerun
    limited = lambda do |profile:, prompt:, cwd:|
      _ = [profile, prompt, cwd]
      { stdout: "You've hit your usage limit · resets 8pm", stderr: "", status: :error, model: "opus-4.8", usage: {} }
    end
    cell = run_cell(spawn: limited)

    assert_equal "limit_hit", cell.status
    assert_nil cell.diff_path, "a limit-hit cell produces no scored diff"
    assert_match(/re-run/, cell.reason)
  end

  # --- reuse path ---

  def test_reused_cell_uses_reference_diff_and_omits_wall_clock
    resolver = lambda do |entry, profile|
      _ = [entry, profile]
      { diff: File.read(File.join(@entry["entry_dir"], "reference.patch")),
        model_version: "claude-opus-4-8-original",
        telemetry: { "cost_usd" => 0.11, "fix_passes" => 1 } }
    end
    cell = run_cell(reuse_resolver: resolver)

    assert_equal "reused", cell.mode
    assert_equal "claude-opus-4-8-original", cell.model_version
    assert_equal "REFERENCE-DIFF\n", File.read(cell.diff_path)
    assert_nil cell.telemetry["wall_clock_sec"], "reused cells have no comparable wall-clock"
    assert_equal 1, cell.telemetry["fix_passes"]
  end

  def test_fresh_run_without_spawn_seam_raises
    err = assert_raises(ArgumentError) { run_cell(spawn: nil) }
    assert_match(/spawn/, err.message)
  end
end
