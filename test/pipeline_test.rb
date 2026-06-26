# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "lib/pipeline"
require "lib/isolation_exec"
require "lib/profile"

# Exercises the planner->executor pipeline with stubbed spawns over a REAL git
# restore (no Docker): the planner stub writes a plan, the executor stub edits
# the tree, and we assert the orchestration (plan capture, re-restore, diff,
# merged telemetry, plan_failed, limit_hit).
class PipelineTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("hb-pipe")
    @source = File.join(@root, "source")
    @base = build_source_repo
    @entry = build_entry
    @planner = profile("pi@glm-5.2", "glm")
    @executor = profile("pi@kimi-k2.7", "kimi")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def profile(id, model)
    HiveBench::Profile.new(id: id, harness: "pi", model: model, bin: "x", headless_argv: ->(prompt:) { [prompt] })
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

  def build_entry
    dir = File.join(@root, "entry")
    FileUtils.mkdir_p(File.join(dir, "spec"))
    File.write(File.join(dir, "spec", "idea.md"), "# Idea\nMake app print done.\n")
    File.write(File.join(dir, "spec", "brainstorm.md"), "# Brainstorm\nNo edge cases.\n")
    { "task_id" => "demo", "entry_dir" => dir, "checkout_source" => @source,
      "source" => { "base_commit" => @base }, "spec" => { "idea" => "spec/idea.md", "brainstorm" => "spec/brainstorm.md" } }
  end

  # Planner stub: writes the plan file (proving it saw idea + brainstorm in the prompt).
  def planner_spawn(writes_plan: true, status: :ok, usage: { input: 100, output: 20, cost: 0.01 }, stream: "")
    lambda do |profile:, prompt:, cwd:|
      _ = profile
      raise "planner did not get idea" unless prompt.include?("Make app print done")
      raise "planner did not get brainstorm" unless prompt.include?("No edge cases")

      File.write(File.join(cwd, HiveBench::IsolationExec::PLAN_OUTPUT_FILE), "STEP 1: edit app.rb\n") if writes_plan
      { stdout: stream, stderr: "", status: status, model: "glm", usage: usage, provider_errors: stream }
    end
  end

  def executor_spawn(content: "puts 'done'\n", status: :ok, usage: { input: 200, output: 40, cost: 0.02 }, stream: "")
    lambda do |profile:, prompt:, cwd:|
      _ = [profile, prompt]
      File.write(File.join(cwd, "app.rb"), content)
      { stdout: stream, stderr: "", status: status, model: "kimi", usage: usage, provider_errors: stream }
    end
  end

  def pipeline(plan: planner_spawn, exec: executor_spawn)
    HiveBench::Pipeline.new(plan_spawn: plan, exec_spawn: exec,
                            clock: lambda {
                              @t = (@t || 0) + 1
                              Time.utc(2026, 6, 25, 0, 0, @t)
                            })
  end

  def run_cell(plan: planner_spawn, exec: executor_spawn)
    pipeline(plan: plan, exec: exec).call(entry: @entry, planner: @planner, executor: @executor,
                                          pair_id: "glm->kimi", out_dir: File.join(@root, "out"))
  end

  def test_planner_authors_plan_then_executor_implements_it
    cell = run_cell

    assert_equal "pipeline", cell.mode
    assert_equal "generated", cell.status
    assert_equal "glm->kimi", cell.agent_id
    diff = File.read(cell.diff_path)

    assert_includes diff, "+puts 'done'"
    assert_includes diff, "-puts 'v1'"
  end

  def test_merged_telemetry_sums_planner_and_executor
    cell = run_cell

    assert_in_delta 0.03, cell.telemetry["cost_usd"], 1e-9, "pipeline cost = planner + executor"
    assert_operator cell.telemetry["wall_clock_sec"], :>, 0
    assert cell.telemetry.key?("planner_cost_usd"), "per-phase breakdown is retained"
    assert cell.telemetry.key?("executor_cost_usd")
  end

  def test_plan_failed_when_planner_writes_no_plan
    cell = run_cell(plan: planner_spawn(writes_plan: false))

    assert_equal "plan_failed", cell.status
    assert_nil cell.diff_path
    assert_match(/no #{HiveBench::IsolationExec::PLAN_OUTPUT_FILE}/, cell.reason)
  end

  def test_executor_provider_limit_parks_the_cell
    cell = run_cell(exec: executor_spawn(stream: "You've hit your usage limit"))

    assert_equal "limit_hit", cell.status
    assert_nil cell.diff_path
  end

  def test_planner_provider_limit_parks_before_executing
    cell = run_cell(plan: planner_spawn(stream: "rate limit exceeded"))

    assert_equal "limit_hit", cell.status
    assert_match(/planner/, cell.reason)
  end

  # The planner must receive the spec screenshots a human had: each is staged into
  # the planner's checkout (so `assets/<file>` refs resolve) and named in the prompt.
  def test_planner_receives_staged_screenshot_assets
    asset_dir = File.join(@entry["entry_dir"], "spec", "assets")
    FileUtils.mkdir_p(asset_dir)
    File.write(File.join(asset_dir, "shot.png"), "PNGDATA")

    captured = {}
    plan = lambda do |profile:, prompt:, cwd:|
      _ = profile
      captured[:prompt] = prompt
      captured[:staged] = File.read(File.join(cwd, "assets", "shot.png"))
      File.write(File.join(cwd, HiveBench::IsolationExec::PLAN_OUTPUT_FILE), "STEP 1: edit app.rb\n")
      { stdout: "", stderr: "", status: :ok, model: "glm", usage: {}, provider_errors: "" }
    end

    run_cell(plan: plan)

    assert_equal "PNGDATA", captured[:staged], "screenshot must be copied into the planner checkout"
    assert_includes captured[:prompt], "assets/shot.png", "prompt must point the planner at the screenshot"
  end
end
