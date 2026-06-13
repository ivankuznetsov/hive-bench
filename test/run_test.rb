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
  end

  def test_empty_diff_when_candidate_changes_nothing
    cell = run_cell(spawn: editing_spawn(content: "puts 'v1'\n")) # rewrites identical content

    assert_equal "empty_diff", cell.status
  end

  def test_agent_failure_is_recorded_not_raised
    cell = run_cell(spawn: editing_spawn(status: :error))

    assert_equal "agent_failed", cell.status
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
