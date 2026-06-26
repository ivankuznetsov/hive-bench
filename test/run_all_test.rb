# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "run_all"
require "run"
require "gate"
require "judge"
require "lib/profile"
require "lib/isolation_exec"

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
      _ = [plan, candidate_diff]
      HiveBench::Judge::Result.new(mean: score, stddev: 0.0, scores: [score], interval: [score, score],
                                   reference_withheld: reference.nil?)
    end
    j
  end

  # A runner whose cell is a `reused` incumbent (diff = the held-out reference).
  def reused_runner
    lambda do |entry:, profile:, out_dir:|
      FileUtils.mkdir_p(out_dir)
      diff = File.join(out_dir, "candidate.patch")
      File.write(diff, File.read(File.join(entry["entry_dir"], "reference.patch")))
      HiveBench::Run::Cell.new(task_id: entry["task_id"], agent_id: profile.id, mode: "reused",
                               model_version: "claude-opus-4-7[1m]", status: "generated", diff_path: diff,
                               telemetry: { "wall_clock_sec" => nil }, reason: nil)
    end
  end

  def test_reused_incumbent_cell_is_judged_reference_withheld
    out = run_matrix(runner: reused_runner, judge: judge(score: 9.0))
    cell = out.results["cells"].first

    assert_equal "reused", cell["mode"]
    assert cell.dig("judges", "j", "reference_withheld"),
           "an incumbent's own diff must not be judged against itself (anchoring ablation)"
  end

  def test_withhold_reference_flag_grades_all_cells_on_the_task_alone
    out = run_matrix(withhold_reference: true, judge: judge(score: 6.0))
    cell = out.results["cells"].first

    assert cell.dig("judges", "j", "reference_withheld"), "withhold_reference: true de-anchors every cell"
  end

  def driver(**over)
    HiveBench::RunAll.new(
      runner: over[:runner] || runner, gate: over[:gate] || gate,
      judges: over[:judges] || { "j" => over[:judge] || judge },
      withhold_reference: over.fetch(:withhold_reference, false),
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
    assert_in_delta 7.5, cell.dig("judges", "j", "mean")
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
    assert reparsed.key?("failed")
  end

  # A runner that raises for one agent (isolation refused / harness not wired)
  # must NOT crash the pass or discard cells already produced.
  def raising_runner(error:, for_id:)
    base = runner
    lambda do |entry:, profile:, out_dir:|
      raise error if profile.id == for_id

      base.call(entry: entry, profile: profile, out_dir: out_dir)
    end
  end

  def test_isolation_failure_is_parked_in_failed_and_pass_continues
    err = HiveBench::IsolationExec::IsolationError.new("docker unavailable")
    out = run_matrix(runner: raising_runner(error: err, for_id: "pi@glm-5.2"))

    assert_equal 2, out.failed.size, "both of the un-isolated agent's cells are parked as failed"
    assert(out.failed.all? { |f| f["agent_id"] == "pi@glm-5.2" })
    assert_equal 2, out.results["cells"].size, "the other agent's cells are still scored"
    refute out.results["agents"].key?("pi@glm-5.2"), "an un-isolated agent is never scored"
  end

  def test_unwired_harness_is_parked_not_raised
    err = HiveBench::IsolationExec::UnsupportedHarness.new("codex not wired")
    out = run_matrix(runner: raising_runner(error: err, for_id: "claude@opus-4.8"))

    assert_equal 2, out.failed.size
    assert(out.failed.all? { |f| f["reason"].include?("codex not wired") })
    assert_equal %w[pi@glm-5.2], out.results["agents"].keys
  end

  # Any error from the scoring path (a flaky judge, a git/restore failure, …) must
  # also park the cell, not crash the whole pass.
  def test_arbitrary_scoring_error_is_parked_and_pass_survives
    err = RuntimeError.new("judge handshake exploded")
    out = run_matrix(runner: raising_runner(error: err, for_id: "pi@glm-5.2"))

    assert_equal 2, out.failed.size, "the failing agent's cells are parked"
    assert(out.failed.all? { |f| f["reason"].include?("judge handshake exploded") })
    assert_equal 2, out.results["cells"].size, "the other agent's cells still scored — pass did not abort"
  end

  def test_failed_reason_redacts_provider_secret_shapes
    err = RuntimeError.new("boom OPENROUTER_API_KEY=sk-or-v1-deadbeefcafef00d leaked")
    out = run_matrix(runner: raising_runner(error: err, for_id: "pi@glm-5.2"))

    reasons = out.failed.map { |f| f["reason"] }.join

    refute_match(/sk-or-v1-deadbeef/, reasons, "the key must never reach results.json")
    assert_match(/REDACTED/, reasons)
  end

  # A judge that raises (its plain `call`).
  def raising_judge(error:)
    j = Object.new
    j.define_singleton_method(:call) { |**| raise(error) }
    j
  end

  # One flaky/limited judge must NOT discard a successfully-generated cell or the
  # other judges' scores — it's skipped, the cell keeps the survivors, backfill later.
  def test_one_failing_judge_is_skipped_and_cell_keeps_the_others
    out = run_matrix(judges: { "good" => judge(score: 7.0),
                               "bad" => raising_judge(error: RuntimeError.new("judge HTTP 500")) })

    assert_equal 4, out.results["cells"].size, "every cell still scored by the surviving judge"
    assert_empty out.failed, "a partial-judge cell is not a failure"
    cell = out.results["cells"].first

    assert_in_delta 7.0, cell.dig("judges", "good", "mean")
    assert_nil cell.dig("judges", "bad"), "the failed judge is absent, not recorded as zero"
  end

  # If the ONLY judge is credit-limited (OpenRouter 402), the generated cell is
  # parked PENDING (re-judge after billing), never scored and never a hard failure.
  def test_all_judges_credit_limited_parks_pending
    err = RuntimeError.new('openrouter judge HTTP 402: {"error":{"message":"Insufficient credits"}}')
    out = run_matrix(judges: { "or" => raising_judge(error: err) })

    assert_equal 4, out.pending.size, "credit-limited judging parks the cell pending"
    assert_empty out.failed, "a billing wall is not a failure"
    assert_empty out.results["cells"], "nothing is scored when no judge succeeded"
  end

  # When every judge fails for a NON-limit reason, the cell is a genuine failure.
  def test_all_judges_failing_non_limit_parks_failed
    out = run_matrix(judges: { "j" => raising_judge(error: RuntimeError.new("judge handshake exploded")) })

    assert_equal 4, out.failed.size, "no judge could score → failed"
    assert_empty out.pending
    assert(out.failed.all? { |f| f["reason"].include?("judge handshake exploded") })
  end
end
