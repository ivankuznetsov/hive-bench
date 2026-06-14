# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "run_all"
require "run"
require "gate"
require "judge"
require "lib/profile"

# Drives a mini 2-task × 2-agent matrix with stubbed Run/Gate/Judge (their
# internals are tested in U3/U4) to prove the driver's orchestration: per-cell
# scoring, judged-vs-gated, limit-hit -> pending, and a complete results.json.
class RunAllTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("hb-runall")
    @entries = [build_entry("task-a"), build_entry("task-b")]
    @profiles = [
      profile("claude@opus-4.8"),
      profile("pi@glm-5.2")
    ]
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def profile(id)
    HiveBench::Profile.new(id: id, harness: id.split("@").first, model: id.split("@").last,
                           bin: "x", headless_argv: ->(prompt:) { [prompt] })
  end

  def build_entry(task_id)
    dir = File.join(@root, task_id)
    FileUtils.mkdir_p([File.join(dir, "spec"), File.join(dir, "gate")])
    File.write(File.join(dir, "spec", "plan.md"), "# Plan #{task_id}\n")
    File.write(File.join(dir, "reference.patch"), "REF #{task_id}\n")
    File.write(File.join(dir, "gate", "gate.yml"),
               { "needs_curation" => false, "test_cmd" => "rake test", "fail_to_pass" => ["T#t"], "pass_to_pass" => [] }.to_yaml)
    { "task_id" => task_id, "entry_dir" => dir, "checkout_source" => "/src",
      "source" => { "base_commit" => "base#{task_id}" }, "spec" => { "plan" => "spec/plan.md" } }
  end

  # Stub Run: writes a candidate.patch and returns a fresh Cell (or a limit-hit).
  def runner(limit_for: nil)
    lambda do |entry:, profile:, out_dir:|
      if profile.id == limit_for
        next HiveBench::Run::Cell.new(task_id: entry["task_id"], agent_id: profile.id, mode: "fresh",
                                      model_version: profile.model, status: "limit_hit", diff_path: nil,
                                      telemetry: {}, reason: "re-run after cooldown")
      end
      FileUtils.mkdir_p(out_dir)
      diff = File.join(out_dir, "candidate.patch")
      File.write(diff, "+change by #{profile.id}\n")
      HiveBench::Run::Cell.new(task_id: entry["task_id"], agent_id: profile.id, mode: "fresh",
                               model_version: profile.model, status: "generated", diff_path: diff,
                               telemetry: { "wall_clock_sec" => 30.0, "cost_usd" => 0.1 }, reason: nil)
    end
  end

  def gate(pass: true)
    lambda do |entry:, gate_spec:, candidate_patch:, work_dir:|
      _ = [entry, gate_spec, candidate_patch, work_dir]
      HiveBench::Gate::Result.new(status: pass ? :pass : :fail, subset: "gated", reason: "ok", details: {})
    end
  end

  def judge(score: 8.0)
    j = Object.new
    j.define_singleton_method(:call) do |plan:, candidate_diff:, reference:|
      _ = [plan, candidate_diff, reference]
      HiveBench::Judge::Result.new(mean: score, stddev: 0.0, scores: [score], interval: [score, score], reference_withheld: false)
    end
    j
  end

  def driver(**over)
    HiveBench::RunAll.new(
      runner: over[:runner] || runner, gate: over[:gate] || gate, judge: over[:judge] || judge,
      clock: -> { Time.utc(2026, 6, 14) }
    )
  end

  def run_matrix(**over)
    driver(**over).call(entries: @entries, profiles: @profiles,
                        out_root: File.join(@root, "runs"), corpus_version: "v1-test")
  end

  def test_full_matrix_produces_a_record_per_cell
    out = run_matrix

    assert_equal 4, out.results["cells"].size, "2 tasks × 2 agents = 4 cells"
    assert_equal "v1-test", out.results["corpus_version"]
    assert_equal %w[claude@opus-4.8 pi@glm-5.2].sort, out.results["agents"].keys.sort
  end

  def test_scores_gate_and_judge_per_cell
    out = run_matrix(gate: gate(pass: true), judge: judge(score: 7.5))
    cell = out.results["cells"].first

    assert_equal "pass", cell.dig("gate", "status")
    assert_in_delta 7.5, cell.dig("judge", "mean")
    a = out.results["agents"]["claude@opus-4.8"]

    assert_in_delta 1.0, a.dig("gated", "pass_rate"), 0.001
  end

  def test_limit_hit_cell_becomes_pending_not_scored
    out = run_matrix(runner: runner(limit_for: "pi@glm-5.2"))

    assert_equal 2, out.results["cells"].size, "only the non-limited agent's 2 cells are scored"
    assert_equal 2, out.pending.size, "the limited agent's 2 cells are pending"
    assert(out.pending.all? { |p| p["agent_id"] == "pi@glm-5.2" })
    refute(out.results["agents"].key?("pi@glm-5.2"), "a fully-limited agent has no scored rows")
  end

  def test_results_round_trip_to_json
    out = run_matrix
    reparsed = JSON.parse(JSON.generate(out.results))

    assert_equal "hive-bench-results", reparsed["schema"]
    assert reparsed.key?("pending")
  end
end
