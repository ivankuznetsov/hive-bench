# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "sqlite3"
require "lib/hive_driver"
require "profiles/candidates"

# Real git for the repo setup/seeding; the container run is the injected seam.
class HiveDriverTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("hb-hivedriver")
    @source = File.join(@root, "source")
    @base = build_source_repo
    @out = File.join(@root, "out")
    @work = File.expand_path(File.join(@out, "target"))
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
    File.write(File.join(@source, "app.rb"), "def greet = 'v1'\n")
    sh!("git", "add", ".", chdir: @source)
    sh!("git", "commit", "-qm", "base", chdir: @source)
    Open3.capture2("git", "rev-parse", "HEAD", chdir: @source).first.strip
  end

  def entry
    dir = File.join(@root, "entry")
    FileUtils.mkdir_p(File.join(dir, "spec"))
    File.write(File.join(dir, "spec", "idea.md"), "idea\n")
    File.write(File.join(dir, "spec", "brainstorm.md"), "brainstorm\n")
    { "task_id" => "add-i-key", "entry_dir" => dir, "checkout_source" => @source,
      "source" => { "base_commit" => @base, "repo" => "ivankuznetsov/hive", "reference_pr" => 123 },
      "spec" => { "idea" => "spec/idea.md", "brainstorm" => "spec/brainstorm.md" } }
  end

  def candidate = HiveBench::Candidates.by_id("all-opus-4.8")

  def fake_hive_runtime(build_sha: nil)
    { root: @source, gem_home: @root, version: "0.7.2", build_sha: }.compact
  end

  def hive_driver(hive_runtime: fake_hive_runtime, **kwargs)
    HiveBench::HiveDriver.new(hive_runtime:, **kwargs)
  end

  OK_STDOUT = "HB_STAGE plan rc=0\nHB_STAGE develop rc=0\nHB_DONE\nHB_EXIT rc=0\n"

  def with_claude_dir(dir)
    original = HiveBench::HiveDriver::CLAUDE_DIR
    HiveBench::HiveDriver.send(:remove_const, :CLAUDE_DIR)
    HiveBench::HiveDriver.const_set(:CLAUDE_DIR, dir)
    yield
  ensure
    HiveBench::HiveDriver.send(:remove_const, :CLAUDE_DIR)
    HiveBench::HiveDriver.const_set(:CLAUDE_DIR, original)
  end

  def with_grok_auth_dir(dir)
    klass = HiveBench::HiveDriver
    originals = { GROK_AUTH_DIR: klass::GROK_AUTH_DIR, GROK_AUTH: klass::GROK_AUTH }
    originals.each_key { |name| klass.send(:remove_const, name) }
    klass.const_set(:GROK_AUTH_DIR, dir)
    klass.const_set(:GROK_AUTH, File.join(dir, "auth.json"))
    yield
  ensure
    originals&.each do |name, value|
      klass.send(:remove_const, name) if klass.const_defined?(name, false)
      klass.const_set(name, value)
    end
  end

  # A runner seam that fabricates the container's side effects, then returns stdout.
  def driver(stdout: OK_STDOUT, patch: "diff --git a/app.rb b/app.rb\n", log_lines: [], **options)
    seen = @seen_cmd = []
    work = @work
    runner = lambda do |cmd|
      seen.concat(cmd)
      File.write(File.join(work, "candidate.patch"), patch) if patch
      # .hb always contains DIRECTORIES too (bin/ for the gh shim, origin.git/)
      # — the answer-key scan must skip them (regression: EISDIR).
      FileUtils.mkdir_p(File.join(work, ".hb", "bin"))
      unless log_lines.empty?
        dir = File.join(work, ".hive-state", "logs", "add-i-key")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "execute-1.log"), log_lines.join("\n"))
      end
      stdout
    end
    hive_driver(
      runner: runner, reuse_existing: false, reuse_unverified: false, **options
    )
  end

  def test_generated_cell_with_api_equivalent_cost
    usage = '[stream] 2026-01-01T00:00:00Z {"message":{"usage":{"input_tokens":1000,' \
            '"output_tokens":2000,"cache_read_input_tokens":1000000,"cache_creation_input_tokens":500}}}'
    reported = '[stream] 2026-01-01T00:00:01Z {"type":"result","total_cost_usd":9.99}'
    cell = driver(log_lines: [usage, reported]).call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "generated", cell.status
    assert_equal 1000, cell.telemetry["input_tokens"]
    # tokens x usual-tier anthropic rates, NOT the CLI's self-reported figure;
    # cache WRITES count as input-rate tokens (dropping them undercosts claude).
    expected = (((1000 + 500) * 5) + (2000 * 25) + (1_000_000 * 0.5)) / 1_000_000.0

    assert_in_delta expected, cell.telemetry["cost_usd"], 0.0001
    assert_in_delta 9.99, cell.telemetry["cost_usd_reported"], 0.001
  end

  def test_target_clone_has_hermetic_commit_identity
    driver.call(entry: entry, candidate: candidate, out_dir: @out)

    email = Open3.capture2("git", "-C", @work, "config", "--local", "user.email").first.strip
    name = Open3.capture2("git", "-C", @work, "config", "--local", "user.name").first.strip
    assert_equal "bench@hive-bench", email
    assert_equal "hive-bench", name
  end

  def test_target_clone_contains_only_the_exact_historical_base
    File.write(File.join(@source, "future.rb"), "gold descendant\n")
    sh!("git", "add", ".", chdir: @source)
    sh!("git", "commit", "-qm", "future reference", chdir: @source)
    future = Open3.capture2("git", "rev-parse", "HEAD", chdir: @source).first.strip

    driver.call(entry: entry, candidate: candidate, out_dir: @out)

    commits = Open3.capture2("git", "-C", @work, "rev-list", "--all").first.lines.map(&:strip)
    _out, _err, future_status = Open3.capture3("git", "-C", @work, "cat-file", "-e", future)
    remotes = Open3.capture2("git", "-C", @work, "remote").first

    assert_equal [@base], commits
    refute_predicate future_status, :success?
    assert_empty remotes
  end

  def test_pi_telemetry_counts_only_final_assistant_message_usage
    update = '[stream] {"type":"message_update","message":{"role":"assistant","model":"z-ai/glm-5.2",' \
             '"usage":{"input":5,"output":2,"cacheRead":50,"cacheWrite":0}}}'
    final = '[stream] {"type":"message_end","message":{"role":"assistant","model":"z-ai/glm-5.2",' \
            '"usage":{"input":10,"output":5,"cacheRead":100,"cacheWrite":1}}}'
    duplicate = '[stream] {"type":"turn_end","message":{"role":"assistant","model":"z-ai/glm-5.2",' \
                '"usage":{"input":10,"output":5,"cacheRead":100,"cacheWrite":1}}}'
    update_2 = '[stream] {"type":"message_update","message":{"role":"assistant","model":"z-ai/glm-5.2",' \
               '"usage":{"input":8,"output":3,"cacheRead":80,"cacheWrite":1}}}'
    final_2 = '[stream] {"type":"message_end","message":{"role":"assistant","model":"z-ai/glm-5.2",' \
              '"usage":{"input":20,"output":7,"cacheRead":200,"cacheWrite":3}}}'
    duplicate_2 = '[stream] {"type":"turn_end","message":{"role":"assistant","model":"z-ai/glm-5.2",' \
                  '"usage":{"input":20,"output":7,"cacheRead":200,"cacheWrite":3}}}'

    cell = driver(log_lines: [update, final, duplicate, update_2, final_2, duplicate_2]).call(
      entry: entry, candidate: HiveBench::Candidates.by_id("all-glm-5.2"), out_dir: @out
    )

    assert_equal 30, cell.telemetry["input_tokens"]
    assert_equal 12, cell.telemetry["output_tokens"]
    assert_equal 300, cell.telemetry["cached_tokens"]
    assert_equal 4, cell.telemetry["cache_creation_tokens"]
  end

  def test_opencode_telemetry_uses_the_hive_usage_database
    opencode = HiveBench::Candidates.by_id("all-ox-alpha-opencode@high")
    runner = lambda do |_cmd|
      File.write(File.join(@work, "candidate.patch"), "diff --git a/app.rb b/app.rb\n")
      log_dir = File.join(@work, ".hive-state", "logs", "add-i-key")
      FileUtils.mkdir_p(log_dir)
      File.write(File.join(log_dir, "plan-1.log"), "[opencode event omitted type=step_finish]\n")
      db_path = File.join(@work, ".hb", "hive-home", "usage.db")
      FileUtils.mkdir_p(File.dirname(db_path))
      SQLite3::Database.new(db_path) do |db|
        db.execute <<~SQL
          CREATE TABLE token_usage (
            agent TEXT NOT NULL, model TEXT, actual_backend TEXT, actual_model TEXT,
            stage TEXT, input INTEGER, output INTEGER, cached INTEGER,
            cache_read INTEGER, cache_write INTEGER,
            input_available INTEGER, output_available INTEGER, cached_available INTEGER,
            cache_read_available INTEGER, cache_write_available INTEGER
          )
        SQL
        db.execute(
          "INSERT INTO token_usage VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
          ["opencode", "openrouter/stealth/ox-alpha", "openrouter", "stealth/ox-alpha",
           "3-plan", 2_392, 130, 13_440, 13_440, 0, 1, 1, 1, 1, 1]
        )
      end
      OK_STDOUT
    end

    cell = hive_driver(runner:, reuse_existing: false, reuse_unverified: false).call(
      entry: entry, candidate: opencode, out_dir: @out
    )

    assert_equal 2_392, cell.telemetry["input_tokens"]
    assert_equal 130, cell.telemetry["output_tokens"]
    assert_equal 13_440, cell.telemetry["cached_tokens"]
    assert_equal 0, cell.telemetry["cache_creation_tokens"]
  end

  def test_no_token_telemetry_means_no_cost_not_zero_cost
    cell = driver.call(entry: entry, candidate: candidate, out_dir: @out)

    refute cell.telemetry.key?("cost_usd"), "a telemetry gap must read as unknown, not as a $0 run"
  end

  def test_string_message_stream_event_does_not_abort_cell_capture
    error_event = '[stream] 2026-01-01T00:00:00Z {"type":"error","message":"review failed"}'

    cell = driver(log_lines: [error_event]).call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "generated", cell.status
    refute cell.telemetry.key?("cost_usd")
  end

  def test_limit_prose_inside_agent_tool_output_does_not_park_a_failed_cell
    tool_output = '[stream] 2026-01-01T00:00:00Z {"type":"tool_execution_end",' \
                  '"result":{"content":[{"type":"text","text":' \
                  '"fixture: limits_reached; You have hit your session limit"}]}}'
    stdout = "HB_STAGE plan rc=0\nHB_STAGE develop rc=3\nHB_EXIT rc=0\n"

    cell = driver(stdout:, patch: nil, log_lines: [tool_output]).call(
      entry: entry, candidate: candidate, out_dir: @out
    )

    assert_equal "execute_failed", cell.status
    assert_equal "hive develop did not run", cell.reason
  end

  def test_completed_artifact_is_recovered_without_rerunning_hive
    driver.call(entry: entry, candidate: candidate, out_dir: @out)
    FileUtils.mkdir_p(File.join(@work, ".hb"))
    File.write(File.join(@work, ".hb", "stages.out"), OK_STDOUT)
    no_rerun = hive_driver(runner: ->(_cmd) { flunk "completed artifact must not be regenerated" },
                            reuse_existing: true, reuse_unverified: false)

    cell = no_rerun.call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "generated", cell.status
    assert cell.telemetry["recovered_artifact"]
    assert_equal "verified", cell.telemetry["artifact_provenance"]
    assert_nil cell.telemetry["wall_clock_sec"], "lost wall time stays unknown"
  end

  def test_legacy_artifact_requires_explicit_unverified_recovery
    driver.call(entry: entry, candidate: candidate, out_dir: @out)
    FileUtils.mkdir_p(File.join(@work, ".hb"))
    File.write(File.join(@work, ".hb", "stages.out"), OK_STDOUT)
    FileUtils.rm_f(File.join(@work, ".hb", HiveBench::HiveDriver::GENERATION_IDENTITY))
    no_rerun = hive_driver(runner: ->(_cmd) { flunk "explicit legacy recovery must reuse the artifact" },
                            reuse_existing: true, reuse_unverified: true)

    cell = no_rerun.call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "generated", cell.status
    assert_equal "legacy-unverified", cell.telemetry["artifact_provenance"]
  end

  def test_changed_candidate_identity_refuses_to_destroy_existing_artifact
    driver.call(entry: entry, candidate: candidate, out_dir: @out)
    FileUtils.mkdir_p(File.join(@work, ".hb"))
    File.write(File.join(@work, ".hb", "stages.out"), OK_STDOUT)
    changed = candidate.with(model_version: "changed-model")
    no_rerun = hive_driver(runner: ->(_cmd) { flunk "mismatched artifact must not be deleted" },
                            reuse_existing: true, reuse_unverified: false)

    error = assert_raises(HiveBench::HiveDriver::ArtifactProvenanceMismatch) do
      no_rerun.call(entry: entry, candidate: changed, out_dir: @out)
    end

    assert_match(/--no-reuse-existing-artifacts/, error.message)
    assert_path_exists File.join(@work, "candidate.patch")
  end

  def test_incomplete_artifact_is_not_recovered
    driver.call(entry: entry, candidate: candidate, out_dir: @out)
    FileUtils.mkdir_p(File.join(@work, ".hb"))
    File.write(File.join(@work, ".hb", "stages.out"), "HB_STAGE plan rc=0\nHB_EXIT rc=1\n")
    reran = false
    fresh = hive_driver(runner: lambda do |_cmd|
      reran = true
      File.write(File.join(@work, "candidate.patch"), "diff --git a/app.rb b/app.rb\n")
      OK_STDOUT
    end, reuse_existing: true, reuse_unverified: false)

    cell = fresh.call(entry: entry, candidate: candidate, out_dir: @out)

    assert reran
    refute cell.telemetry["recovered_artifact"]
  end

  def test_timeout_after_develop_promotes_execute_patch_for_judging
    execute_patch = "diff --git a/app.rb b/app.rb\n"
    runner = lambda do |_cmd|
      File.write(File.join(@work, "candidate-execute.patch"), execute_patch)
      "HB_STAGE plan rc=0\nHB_STAGE develop rc=0\nHB_STAGE open-pr rc=0\nHB_EXIT rc=124\n"
    end
    timed_review = hive_driver(runner:, reuse_existing: false, reuse_unverified: false)

    cell = timed_review.call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "generated", cell.status
    assert_equal execute_patch, File.read(File.join(@work, "candidate.patch"))
    assert cell.telemetry["stage_timed_out"]
    assert_equal "timed_out", cell.telemetry["review_status"]
  end

  def test_timeout_after_develop_is_recovered_without_replacing_target
    driver.call(entry: entry, candidate: candidate, out_dir: @out)
    sentinel = File.join(@work, "resume-sentinel")
    File.write(sentinel, "keep")
    File.write(File.join(@work, "candidate-execute.patch"), "diff --git a/app.rb b/app.rb\n")
    FileUtils.rm_f(File.join(@work, "candidate.patch"))
    File.write(
      File.join(@work, ".hb", "stages.out"),
      "HB_STAGE plan rc=0\nHB_STAGE develop rc=0\nHB_STAGE open-pr rc=0\nHB_EXIT rc=124\n"
    )
    no_rerun = hive_driver(
      runner: ->(_cmd) { flunk "timed-out review artifact must not be regenerated" },
      reuse_existing: true, reuse_unverified: false
    )

    cell = no_rerun.call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "generated", cell.status
    assert_path_exists sentinel
    assert cell.telemetry["recovered_artifact"]
    assert_equal "verified", cell.telemetry["artifact_provenance"]
  end

  def test_codex_transport_failure_resumes_identity_verified_execute_in_place
    mixed = HiveBench::Candidates.by_id("opus-plan->codex-exec-xhigh")
    driver.call(entry: entry, candidate: mixed, out_dir: @out)
    sentinel = File.join(@work, "resume-sentinel")
    File.write(sentinel, "keep")
    task = File.join(@work, ".hive-state", "stages", "4-execute", "add-i-key")
    FileUtils.mkdir_p(task)
    File.write(File.join(task, "task.md"),
               "<!-- ERROR reason=implementer_failed status=error marker_id=abc123 -->\n")
    logs = File.join(@work, ".hive-state", "logs", "add-i-key")
    FileUtils.mkdir_p(logs)
    File.write(File.join(logs, "execute-1.log"),
               "{\"type\":\"turn.failed\",\"error\":{\"message\":\"stream disconnected before completion: " \
               "error sending request for url (https://chatgpt.com/backend-api/codex/responses)\"}}\n")
    File.write(File.join(@work, ".hb", "stages.out"),
               "HB_STAGE plan rc=0\nHB_STAGE develop rc=3\nHB_EXIT rc=0\n")

    seen = nil
    resumed = hive_driver(runner: lambda do |cmd|
      seen = cmd

      assert_path_exists sentinel, "resume must not replace the persisted target"
      File.write(File.join(@work, "candidate.patch"), "diff --git a/app.rb b/app.rb\n")
      "HB_STAGE resume-clear rc=0\nHB_STAGE plan rc=0\nHB_NOTE plan_reused\n" \
        "HB_NOTE execute_resumed\nHB_STAGE develop rc=0\nHB_DONE\nHB_EXIT rc=0\n"
    end, reuse_existing: true, reuse_unverified: false)

    cell = resumed.call(entry: entry, candidate: mixed, out_dir: @out)

    assert_equal "generated", cell.status
    assert cell.telemetry["execute_resumed"]
    assert_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_EXECUTE=1"]
    assert_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_MARKER_ID=abc123"]
  end

  def test_pi_sse_failure_resumes_identity_verified_execute_in_place
    pi = HiveBench::Candidates.by_id("all-ox-alpha@high")
    driver.call(entry: entry, candidate: pi, out_dir: @out)
    sentinel = File.join(@work, "resume-sentinel")
    File.write(sentinel, "keep")
    task = File.join(@work, ".hive-state", "stages", "4-execute", "add-i-key")
    FileUtils.mkdir_p(task)
    File.write(
      File.join(task, "task.md"),
      "<!-- ERROR reason=implementer_failed provider=pi status=error " \
      "message=\"JSON error injected into SSE stream\" marker_id=pi123 -->\n"
    )
    logs = File.join(@work, ".hive-state", "logs", "add-i-key")
    FileUtils.mkdir_p(logs)
    File.write(
      File.join(logs, "execute-impl-1.log"),
      "#{JSON.generate(
        "type" => "turn_end",
        "message" => {
          "stopReason" => "error",
          "errorMessage" => "JSON error injected into SSE stream"
        }
      )}\n"
    )

    seen = nil
    resumed = hive_driver(runner: lambda do |cmd|
      seen = cmd

      assert_path_exists sentinel, "resume must retain Pi's partial worktree"
      File.write(File.join(@work, "candidate.patch"), "diff --git a/app.rb b/app.rb\n")
      "HB_STAGE resume-clear rc=0\nHB_STAGE plan rc=0\nHB_NOTE plan_reused\n" \
        "HB_NOTE execute_resumed\nHB_STAGE develop rc=0\nHB_DONE\nHB_EXIT rc=0\n"
    end, reuse_existing: true, reuse_unverified: false)

    cell = resumed.call(entry: entry, candidate: pi, out_dir: @out)

    assert_equal "generated", cell.status
    assert cell.telemetry["execute_resumed"]
    assert_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_EXECUTE=1"]
    assert_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_MARKER_ID=pi123"]
  end

  def test_pi_local_version_probe_timeout_resumes_without_replacing_partial_work
    pi = HiveBench::Candidates.by_id("all-ox-alpha@high")
    driver.call(entry: entry, candidate: pi, out_dir: @out)
    sentinel = File.join(@work, "resume-sentinel")
    File.write(sentinel, "keep")
    task = File.join(@work, ".hive-state", "stages", "4-execute", "add-i-key")
    FileUtils.mkdir_p(task)
    File.write(
      File.join(task, "task.md"),
      "<!-- ERROR reason=implementer_failed provider=pi status=error " \
      "message=\"preflight failed: agent profile :pi probe failed: pi version " \
      "check timed out after 30s: pi\" marker_id=probe123 -->\n"
    )

    seen = nil
    resumed = hive_driver(runner: lambda do |cmd|
      seen = cmd

      assert_path_exists sentinel, "resume must retain work after a local probe timeout"
      File.write(File.join(@work, "candidate.patch"), "diff --git a/app.rb b/app.rb\n")
      "HB_STAGE resume-clear rc=0\nHB_STAGE plan rc=0\nHB_NOTE plan_reused\n" \
        "HB_NOTE execute_resumed\nHB_STAGE develop rc=0\nHB_DONE\nHB_EXIT rc=0\n"
    end, reuse_existing: true, reuse_unverified: false)

    cell = resumed.call(entry: entry, candidate: pi, out_dir: @out)

    assert_equal "generated", cell.status
    assert cell.telemetry["execute_resumed"]
    assert_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_MARKER_ID=probe123"]
  end

  def test_pi_missing_finish_reason_resumes_without_replacing_partial_work
    pi = HiveBench::Candidates.by_id("all-ox-alpha@high")
    driver.call(entry: entry, candidate: pi, out_dir: @out)
    sentinel = File.join(@work, "resume-sentinel")
    File.write(sentinel, "keep")
    task = File.join(@work, ".hive-state", "stages", "4-execute", "add-i-key")
    FileUtils.mkdir_p(task)
    File.write(
      File.join(task, "task.md"),
      "<!-- ERROR reason=implementer_failed provider=pi status=error " \
      "message=\"Stream ended without finish_reason\" marker_id=finish123 -->\n"
    )
    logs = File.join(@work, ".hive-state", "logs", "add-i-key")
    FileUtils.mkdir_p(logs)
    File.write(
      File.join(logs, "execute-impl-1.log"),
      "#{JSON.generate(
        "type" => "turn_end",
        "message" => {
          "stopReason" => "error",
          "errorMessage" => "Stream ended without finish_reason"
        }
      )}\n"
    )

    seen = nil
    resumed = hive_driver(runner: lambda do |cmd|
      seen = cmd

      assert_path_exists sentinel, "resume must retain Pi work after a missing finish reason"
      File.write(File.join(@work, "candidate.patch"), "diff --git a/app.rb b/app.rb\n")
      "HB_STAGE resume-clear rc=0\nHB_STAGE plan rc=0\nHB_NOTE plan_reused\n" \
        "HB_NOTE execute_resumed\nHB_STAGE develop rc=0\nHB_DONE\nHB_EXIT rc=0\n"
    end, reuse_existing: true, reuse_unverified: false)

    cell = resumed.call(entry: entry, candidate: pi, out_dir: @out)

    assert_equal "generated", cell.status
    assert cell.telemetry["execute_resumed"]
    assert_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_MARKER_ID=finish123"]
  end

  def test_post_cleanup_dirty_worktree_marker_resumes_in_place
    driver.call(entry: entry, candidate: candidate, out_dir: @out)
    task = File.join(@work, ".hive-state", "stages", "4-execute", "add-i-key")
    FileUtils.mkdir_p(task)
    File.write(File.join(task, "task.md"),
               "<!-- ERROR reason=dirty_worktree marker_id=dirty123 -->\n")

    seen = nil
    resumed = hive_driver(runner: lambda do |cmd|
      seen = cmd
      File.write(File.join(@work, "candidate.patch"), "diff --git a/app.rb b/app.rb\n")
      "HB_STAGE resume-clear rc=0\nHB_STAGE plan rc=0\nHB_NOTE plan_reused\n" \
        "HB_NOTE execute_resumed\nHB_STAGE develop rc=0\nHB_DONE\nHB_EXIT rc=0\n"
    end, reuse_existing: true, reuse_unverified: false)

    cell = resumed.call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "generated", cell.status
    assert cell.telemetry["execute_resumed"]
    assert_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_MARKER_ID=dirty123"]
  end

  def test_terminal_review_failure_resumes_identity_verified_candidate_in_place
    opencode = HiveBench::Candidates.by_id("all-ox-alpha-opencode@high")
    driver.call(entry: entry, candidate: opencode, out_dir: @out)
    sentinel = File.join(@work, "review-resume-sentinel")
    File.write(sentinel, "keep")
    task = File.join(@work, ".hive-state", "stages", "6-review", "add-i-key")
    FileUtils.mkdir_p(task)
    File.write(
      File.join(task, "task.md"),
      "<!-- REVIEW_WORKING phase=fix pass=1 marker_id=review123 -->\n"
    )
    File.write(
      File.join(@work, "candidate-execute.patch"),
      "diff --git a/app.rb b/app.rb\n"
    )
    File.write(
      File.join(@work, ".hb", "stages.out"),
      "HB_STAGE plan rc=0\nHB_STAGE develop rc=0\nHB_STAGE open-pr rc=0\n" \
      "HB_STAGE review rc=70\nHB_EXIT rc=0\n"
    )
    File.write(
      File.join(@work, ".hb", "stage.err"),
      "requested OpenCode route is unavailable in the local model inventory\n"
    )
    state_config = File.join(@work, ".hive-state", "config.yml")
    legacy_config = YAML.safe_load(File.read(state_config))
    legacy_config.delete("attempt_launch_timeout_sec")
    legacy_config.delete("attempt_first_heartbeat_timeout_sec")
    File.write(state_config, YAML.dump(legacy_config))
    sh!("git", "add", "config.yml", chdir: File.dirname(state_config))
    sh!("git", "commit", "-qm", "legacy config", chdir: File.dirname(state_config))

    seen = nil
    resumed = hive_driver(runner: lambda do |cmd|
      seen = cmd

      assert_path_exists sentinel, "review resume must retain the candidate target"
      assert_path_exists File.join(@work, "candidate-execute.patch")
      refreshed = YAML.safe_load(File.read(state_config))
      assert_equal 300, refreshed["attempt_launch_timeout_sec"]
      assert_equal 300, refreshed["attempt_first_heartbeat_timeout_sec"]
      File.write(File.join(@work, "candidate.patch"), "diff --git a/app.rb b/app.rb\n")
      "HB_STAGE plan rc=0\nHB_NOTE plan_reused\nHB_NOTE review_resumed\n" \
        "HB_STAGE develop rc=0\nHB_STAGE open-pr rc=0\nHB_STAGE review rc=0\n" \
        "HB_DONE\nHB_EXIT rc=0\n"
    end, reuse_existing: true, reuse_unverified: false)

    cell = resumed.call(entry: entry, candidate: opencode, out_dir: @out)

    assert_equal "generated", cell.status
    assert cell.telemetry["review_resumed"]
    assert_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_REVIEW=1"]
    refute_includes seen.each_cons(2).to_a, ["-e", "HB_RESUME_EXECUTE=1"]
  end

  def test_review_resume_rejects_missing_patch_auth_limit_and_identity_drift
    opencode = HiveBench::Candidates.by_id("all-ox-alpha-opencode@high")
    driver.call(entry: entry, candidate: opencode, out_dir: @out)
    task = File.join(@work, ".hive-state", "stages", "6-review", "add-i-key")
    FileUtils.mkdir_p(task)
    File.write(File.join(task, "task.md"), "<!-- REVIEW_WORKING phase=fix pass=1 -->\n")
    File.write(
      File.join(@work, ".hb", "stages.out"),
      "HB_STAGE review rc=70\nHB_EXIT rc=0\n"
    )
    checker = hive_driver(reuse_existing: true, reuse_unverified: false)
    identity = checker.send(:generation_identity, entry, opencode, @base)

    refute checker.send(:resumable_review?, entry, @work, identity)

    File.write(File.join(@work, "candidate-execute.patch"), "diff --git a/a b/a\n")
    File.write(File.join(@work, ".hb", "stage.err"), "401 unauthorized\n")

    refute checker.send(:resumable_review?, entry, @work, identity)

    File.write(File.join(@work, ".hb", "stage.err"), "rate limit reached\n")

    refute checker.send(:resumable_review?, entry, @work, identity)

    File.write(File.join(@work, ".hb", "stage.err"), "local probe failed\n")
    changed = identity.merge("base_commit" => "different")

    refute checker.send(:resumable_review?, entry, @work, changed)
    assert checker.send(:resumable_review?, entry, @work, identity)
  end

  def test_resume_rejects_nonterminal_transport_text_auth_limits_and_identity_drift
    mixed = HiveBench::Candidates.by_id("opus-plan->codex-exec-xhigh")
    driver.call(entry: entry, candidate: mixed, out_dir: @out)
    task = File.join(@work, ".hive-state", "stages", "4-execute", "add-i-key")
    FileUtils.mkdir_p(task)
    File.write(File.join(task, "task.md"),
               "<!-- ERROR reason=implementer_failed status=error marker_id=abc123 -->\n")
    logs = File.join(@work, ".hive-state", "logs", "add-i-key")
    FileUtils.mkdir_p(logs)
    log = File.join(logs, "execute-1.log")
    checker = hive_driver(reuse_existing: true, reuse_unverified: false)
    identity = checker.send(:generation_identity, entry, mixed, @base)

    File.write(log, <<~LOG)
      {"type":"turn.failed","error":{"message":"stream disconnected before completion: error sending request for url (https://chatgpt.com/backend-api/codex/responses)"}}
      {"type":"turn.failed","error":{"message":"implementation failed validation"}}
    LOG

    assert_nil checker.send(:resumable_execute_marker, entry, mixed, @work, identity)

    ["401 unauthorized", "rate limit reached",
     "stream disconnected before completion: error sending request for url (https://example.com)"].each do |message|
      File.write(log, "{\"type\":\"turn.failed\",\"error\":{\"message\":#{JSON.generate(message)}}}\n")

      assert_nil checker.send(:resumable_execute_marker, entry, mixed, @work, identity), message
    end

    changed = identity.merge("base_commit" => "different")
    File.write(log, "{\"type\":\"turn.failed\",\"error\":{\"message\":\"stream disconnected before completion: " \
                    "error sending request for url (https://chatgpt.com/backend-api/codex/responses)\"}}\n")

    assert_nil checker.send(:resumable_execute_marker, entry, mixed, @work, changed)
    assert_nil checker.send(:resumable_execute_marker, entry, candidate, @work, identity)
  end

  def test_timeout_is_timed_out_not_plan_failed
    cell = driver(stdout: "HB_STAGE plan rc=0\nHB_EXIT rc=124\n", patch: nil)
           .call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "timed_out", cell.status
    assert_match(/HB_HIVE_TIMEOUT/, cell.reason)
  end

  def test_nonzero_stage_runner_exit_rejects_an_existing_patch
    stdout = "HB_STAGE plan rc=0\nHB_STAGE develop rc=0\nHB_NOTE final_patch_failed\nHB_EXIT rc=4\n"
    cell = driver(stdout: stdout, patch: "diff --git a/polluted b/polluted\n")
           .call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "execute_failed", cell.status
    assert_match(/trustworthy capture/, cell.reason)
  end

  def test_review_limit_preserves_the_generated_execute_fallback
    stdout = <<~OUT
      HB_STAGE plan rc=0
      HB_STAGE develop rc=0
      HB_STAGE open-pr rc=0
      HB_STAGE review rc=3
      HB_NOTE review_fallback=execute
      HB_DONE
      HB_EXIT rc=0
    OUT
    driver(stdout: stdout, patch: "diff --git a/app.rb b/app.rb\n")
      .call(entry: entry, candidate: candidate, out_dir: @out)
    File.write(File.join(@work, ".hb", "stage.err"), "You've hit your session limit\n")

    status, = hive_driver(reuse_existing: true, reuse_unverified: false)
                                   .send(:classify, stdout, @work,
                                         File.read(File.join(@work, "candidate.patch")))

    assert_equal "generated", status
  end

  def test_execute_limit_still_parks_generation_despite_nonzero_runner_exit
    stdout = "HB_STAGE plan rc=3\nHB_STAGE develop rc=4\nHB_EXIT rc=4\n"
    FileUtils.mkdir_p(File.join(@work, ".hb"))
    File.write(File.join(@work, ".hb", "stage.err"), "You've hit your session limit\n")

    status, = hive_driver(reuse_existing: true, reuse_unverified: false)
                                   .send(:classify, stdout, @work, "diff --git a/app.rb b/app.rb\n")

    assert_equal "limit_hit", status
  end

  def test_forced_plan_completion_is_surfaced
    cell = driver(stdout: "HB_STAGE plan rc=0\nHB_NOTE plan_forced_complete\nHB_STAGE develop rc=0\nHB_EXIT rc=0\n")
           .call(entry: entry, candidate: candidate, out_dir: @out)

    assert cell.telemetry["plan_forced_complete"]
  end

  def test_answer_key_access_is_flagged
    leak = "[stream] 2026-01-01T00:00:00Z fetching https://github.com/ivankuznetsov/hive/pull/123"
    cell = driver(log_lines: [leak]).call(entry: entry, candidate: candidate, out_dir: @out)

    assert_match(%r{hive/pull/123}, cell.telemetry["answer_key_access_suspect"])
  end

  def test_clean_cell_has_no_leak_flag
    cell = driver.call(entry: entry, candidate: candidate, out_dir: @out)

    refute cell.telemetry.key?("answer_key_access_suspect")
  end

  def test_container_gets_resource_caps_and_exit_marker
    driver.call(entry: entry, candidate: candidate, out_dir: @out)

    assert_includes @seen_cmd, "--pids-limit"
    assert_includes @seen_cmd, "--cpus"
    assert_match(/echo HB_EXIT rc=\$\?/, @seen_cmd.last)
  end

  def test_container_mounts_the_exact_hive_runtime_and_benchmark_plan_review_grant
    driver.call(entry: entry, candidate: candidate, out_dir: @out)

    assert_includes @seen_cmd, "#{@source}:/opt/hb/hive-current:ro"
    assert_includes @seen_cmd, "#{@root}:/usr/local/bundle:ro"
    assert_includes @seen_cmd, "RUBYLIB=#{HiveBench::HiveDriver::HIVE_RUNTIME_RUBYLIB}"
    assert_includes @seen_cmd, "HB_HIVE_VERSION=0.7.2"
    assert_includes @seen_cmd, "HIVE_BENCH_ALLOW_DISABLED_PLAN_REVIEW=1"
    identity = JSON.parse(File.read(File.join(@work, ".hb", "generation-identity.json")))
    assert_equal "0.7.2", identity.dig("hive_runtime", "version")
  end

  def test_sealed_pi_runtime_uses_matching_image_without_exposing_host_hive
    build_sha = "a" * 40
    labels = {
      "io.hive.bench.hive-build-sha" => build_sha,
      "io.hive.bench.runtime-visibility" => HiveBench::HiveDriver::SEALED_RUNTIME_VISIBILITY
    }
    previous = ENV["HB_REQUIRE_SEALED_AGENT_RUNTIME"]
    ENV["HB_REQUIRE_SEALED_AGENT_RUNTIME"] = "1"

    driver(hive_runtime: fake_hive_runtime(build_sha:), image_inspector: ->(_image) { labels }).call(
      entry: entry,
      candidate: HiveBench::Candidates.by_id("all-ox-alpha@max"),
      out_dir: @out
    )

    assert_includes @seen_cmd.each_cons(2).to_a, ["--user", "0:0"]
    assert_includes @seen_cmd.each_cons(2).to_a, ["--security-opt", "no-new-privileges:true"]
    assert_includes @seen_cmd, "GEM_HOME=/opt/hb/control-bundle"
    assert_includes @seen_cmd, "HB_HIVE_BUILD_SHA=#{build_sha}"
    assert_includes @seen_cmd, "HB_SEALED_AGENT_RUNTIME=1"
    refute_includes @seen_cmd, "#{@source}:/opt/hb/hive-current:ro"
    refute_includes @seen_cmd, "#{@root}:/usr/local/bundle:ro"
    identity = JSON.parse(File.read(File.join(@work, ".hb", "generation-identity.json")))
    assert_equal build_sha, identity.dig("hive_runtime", "build_sha")
    assert_equal "sealed-control-bundle-v1", identity.dig("isolation", "runtime_visibility")
  ensure
    ENV["HB_REQUIRE_SEALED_AGENT_RUNTIME"] = previous
  end

  def test_sealed_runtime_rejects_a_stale_or_unlabelled_image_before_model_execution
    build_sha = "a" * 40
    previous = ENV["HB_REQUIRE_SEALED_AGENT_RUNTIME"]
    ENV["HB_REQUIRE_SEALED_AGENT_RUNTIME"] = "1"
    no_model = hive_driver(
      hive_runtime: fake_hive_runtime(build_sha:),
      image_inspector: ->(_image) { {} },
      runner: ->(_cmd) { flunk "mismatched sealed image must not start" },
      reuse_existing: false,
      reuse_unverified: false
    )

    error = assert_raises(RuntimeError) do
      no_model.call(entry: entry, candidate: HiveBench::Candidates.by_id("all-ox-alpha@max"), out_dir: @out)
    end

    assert_match(/is not the sealed Hive build/, error.message)
  ensure
    ENV["HB_REQUIRE_SEALED_AGENT_RUNTIME"] = previous
  end

  def test_provider_only_generation_egress_is_recorded_and_forwarded
    previous = %w[HB_REQUIRE_EGRESS_ALLOWLIST HB_GEN_NETWORK HB_GEN_HTTPS_PROXY].to_h { |key| [key, ENV[key]] }
    ENV["HB_REQUIRE_EGRESS_ALLOWLIST"] = "1"
    ENV["HB_GEN_NETWORK"] = "bench-provider-only"
    ENV["HB_GEN_HTTPS_PROXY"] = "http://bench-proxy:3128"

    driver.call(entry: entry, candidate: candidate, out_dir: @out)

    assert_includes @seen_cmd.each_cons(2).to_a, ["--network", "bench-provider-only"]
    assert_includes @seen_cmd, "HTTPS_PROXY=http://bench-proxy:3128"
    identity = JSON.parse(File.read(File.join(@work, ".hb", "generation-identity.json")))
    assert_equal "provider-allowlist", identity.dig("isolation", "generation_egress")
  ensure
    previous&.each { |key, value| ENV[key] = value }
  end

  def test_active_runtime_resolves_the_immutable_inherited_dogfood_deployment
    state_root = File.join(@root, "state", "hive")
    staging = File.join(state_root, "deployments", "staging")
    gem_home = File.join(@root, "gem-home")
    wrapper_dir = File.join(@root, "bin")
    FileUtils.mkdir_p([File.join(staging, "bin"), File.join(staging, "lib"), gem_home, wrapper_dir])
    File.write(File.join(staging, "bin", "hive"), "#!/bin/sh\nprintf '0.7.2\\n'\n")
    FileUtils.chmod(0o755, File.join(staging, "bin", "hive"))
    File.write(File.join(staging, "lib", "hive.rb"), "# complete runtime\n")
    File.write(File.join(wrapper_dir, "hive"), "#!/bin/sh\nexit 1\n")
    FileUtils.chmod(0o755, File.join(wrapper_dir, "hive"))
    sh!("git", "init", "-q", "-b", "main", chdir: staging)
    sh!("git", "config", "user.email", "bench@example.com", chdir: staging)
    sh!("git", "config", "user.name", "Bench Test", chdir: staging)
    sh!("git", "add", ".", chdir: staging)
    sh!("git", "commit", "-qm", "dogfood runtime", chdir: staging)
    build_sha = Open3.capture2("git", "rev-parse", "HEAD", chdir: staging).first.strip
    deployment_id = "hive-dogfood-#{build_sha[0, 9]}"
    deployment = File.join(state_root, "deployments", deployment_id)
    FileUtils.mv(staging, deployment)

    script = <<~'RUBY'
      require "json"
      require "lib/hive_driver"
      puts JSON.generate(HiveBench::HiveDriver.allocate.send(:active_hive_runtime))
    RUBY
    env = {
      "PATH" => "#{wrapper_dir}:#{ENV.fetch("PATH")}",
      "HB_HIVE_BIN" => nil,
      "HB_HIVE_GEM_HOME" => gem_home,
      "HIVE_RUNTIME_CHANNEL" => "dogfood",
      "HIVE_RUNTIME_DEPLOYMENT_ID" => deployment_id,
      "HIVE_RUNTIME_BUILD_SHA" => build_sha,
      "HIVE_DOGFOOD_STATE_ROOT" => state_root
    }
    out, err, status = Open3.capture3(env, RbConfig.ruby, "-I#{File.expand_path("../harness", __dir__)}",
                                      "-e", script)

    assert status.success?, out + err
    runtime = JSON.parse(out)
    assert_equal deployment, runtime.fetch("root")
    assert_equal gem_home, runtime.fetch("gem_home")
    assert_equal "0.7.2", runtime.fetch("version")
  end

  def test_opencode_candidate_uses_its_runner_ce_preflight_and_openrouter_credential
    previous = ENV["OPENROUTER_API_KEY"]
    ENV["OPENROUTER_API_KEY"] = "test-only"
    opencode = HiveBench::Candidates.all_ox_alpha_opencode_high

    driver.call(entry: entry, candidate: opencode, out_dir: @out)

    assert_includes @seen_cmd, HiveBench::HiveDriver::OPENCODE_IMAGE
    assert_includes @seen_cmd,
                    "#{HiveBench::HiveDriver::OPENCODE_BENCH_RUNTIME}:/opt/hb/opencode_bench_runtime.rb:ro"
    assert_includes @seen_cmd,
                    "#{HiveBench::HiveDriver::OPENCODE_BENCH_LAUNCHER}:/opt/hb/opencode-bench-launcher:ro"
    assert_includes @seen_cmd, "HIVE_OPENCODE_BIN=/opt/hb/opencode-bench-launcher"
    assert_includes @seen_cmd, "HB_OPENCODE_CE_PREFLIGHT=1"
    assert_includes @seen_cmd, "HB_OPENCODE_PROBE_TIMEOUT_SEC=300"
    assert_includes @seen_cmd, "OPENROUTER_API_KEY"
  ensure
    ENV["OPENROUTER_API_KEY"] = previous
  end

  def test_claude_auth_mount_fails_before_docker_when_credentials_path_is_not_a_file
    claude_dir = File.join(@root, "claude")
    FileUtils.mkdir_p(claude_dir)

    err = assert_raises(RuntimeError) do
      with_claude_dir(claude_dir) do
        hive_driver(runner: ->(_cmd) { flunk "docker must not run with a missing auth source" },
                    reuse_existing: false, reuse_unverified: false)
                             .call(entry: entry, candidate: candidate, out_dir: @out)
      end
    end

    assert_match(/claude credentials missing or not a file/, err.message)
    refute_path_exists File.join(claude_dir, ".credentials.json"),
                       "driver must not create Docker's missing bind-mount source"
  end

  # Docker creates ANY missing bind-mount source as a root-owned host directory
  # — settings.json and plugins/ carry the same trap as the credentials file.
  def test_claude_settings_and_plugins_mounts_fail_before_docker_when_missing
    claude_dir = File.join(@root, "claude")
    FileUtils.mkdir_p(claude_dir)
    File.write(File.join(claude_dir, ".credentials.json"), "{}")
    no_docker = hive_driver(runner: ->(_cmd) { flunk "docker must not run with a missing mount source" },
                            reuse_existing: false, reuse_unverified: false)

    err = assert_raises(RuntimeError) do
      with_claude_dir(claude_dir) { no_docker.call(entry: entry, candidate: candidate, out_dir: @out) }
    end

    assert_match(/claude settings missing or not a file/, err.message)

    File.write(File.join(claude_dir, "settings.json"), "{}")
    err = assert_raises(RuntimeError) do
      with_claude_dir(claude_dir) { no_docker.call(entry: entry, candidate: candidate, out_dir: @out) }
    end

    assert_match(/claude plugins missing or not a directory/, err.message)
  end

  def test_xhigh_codex_candidate_routes_effort_in_hive_and_registers_plugins
    skip "needs ~/.codex/auth.json" unless File.file?(File.expand_path("~/.codex/auth.json"))
    xhigh = HiveBench::Candidates.by_id("all-codex-xhigh")
    driver.call(entry: entry, candidate: xhigh, out_dir: @out)
    mount = @seen_cmd.find { |a| a.to_s.include?("codex-config.toml") }

    assert mount, "xhigh candidate must mount the generated config"
    cfg = File.read(File.join(@out, "codex-config.toml"))

    refute_match(/model_reasoning_effort/, cfg)
    assert_includes cfg, 'plugins."compound-engineering@compound-engineering-plugin"'
    hive = YAML.safe_load(File.read(File.join(@work, ".hive-state", "config.yml")))
    assert_equal "xhigh", hive.dig("models", "plan", "effort")
    assert_equal "xhigh", hive.dig("models", "execute", "effort")
  end

  def test_mixed_sol_terra_candidate_gets_native_per_stage_codex_routes
    mixed = HiveBench::Candidates.by_id("sol-plan->terra-exec-sol-review")
    driver.call(entry: entry, candidate: mixed, out_dir: @out)

    config = HiveBench::HiveConfig.to_h(mixed)
    assert_equal "gpt-5.6-sol", config.dig("models", "plan", "model")
    assert_equal "gpt-5.6-terra", config.dig("models", "execute", "model")
    assert_equal "gpt-5.6-sol", config.dig("models", "review_fix", "model")
    assert_equal "xhigh", config.dig("models", "plan", "effort")
    assert_equal "xhigh", config.dig("models", "execute", "effort")
    assert_equal(["codex-ce-code-review"],
                 config.dig("review", "reviewers").map { |reviewer| reviewer["name"] })
    refute(@seen_cmd.any? { |arg| arg.to_s.start_with?("HB_CODEX_") })
  end

  def test_fable_grok_candidate_uses_sol_as_sole_reviewer
    mixed = HiveBench::Candidates.by_id("fable-plan->grok-exec-sol-review")
    driver.call(entry: entry, candidate: mixed, out_dir: @out)

    config = HiveBench::HiveConfig.to_h(mixed)

    assert_equal "claude-fable-5", config.dig("claude", "model")
    assert_equal "high", config.dig("claude", "effort")
    assert_equal "grok-4.5", config.dig("models", "execute", "model")
    assert_equal "gpt-5.6-sol", config.dig("models", "review_fix", "model")
    assert_equal(["codex-ce-code-review"], config.dig("review", "reviewers").map { |reviewer| reviewer["name"] })
  end

  def test_default_codex_candidate_config_registers_plugins_without_effort
    skip "needs ~/.codex/auth.json" unless File.file?(File.expand_path("~/.codex/auth.json"))
    plain = HiveBench::Candidates.by_id("all-codex")
    driver.call(entry: entry, candidate: plain, out_dir: @out)
    cfg = File.read(File.join(@out, "codex-config.toml"))

    refute_match(/model_reasoning_effort/, cfg, "default effort stays the CLI default")
    assert_includes cfg, 'plugins."compound-engineering@compound-engineering-plugin"'
    assert(@seen_cmd.any? { |a| a.to_s.include?("codex-plugins-cache") }, "skill cache mounted")
  end

  def test_grok_candidate_mounts_auth_and_pins_model_effort
    auth_dir = File.join(@root, "grok-auth")
    payload = '{"issuer::principal":{"key":"access","refresh_token":"refresh"}}'
    write_grok_auth(auth_dir, payload)
    grok = HiveBench::Candidates.by_id("all-grok-4.5")
    with_grok_auth_dir(auth_dir) do
      driver.call(entry: entry, candidate: grok, out_dir: @out)
    end

    assert(@seen_cmd.each_cons(2).any? { |flag, path| flag == "--tmpfs" && path.include?("/.grok:") },
           "each cell must get an ephemeral Grok home")
    assert_includes @seen_cmd, "#{auth_dir}:/home/asterio/.grok-auth:rw"
    refute_includes @seen_cmd, "#{auth_dir}:/home/asterio/.grok:rw"
    assert_includes @seen_cmd, "GROK_AUTH_PATH=/home/asterio/.grok-auth/auth.json"
    config = YAML.safe_load(File.read(File.join(@work, ".hive-state", "config.yml")))
    assert_equal "grok-4.5", config.dig("models", "plan", "model")
    assert_equal "xhigh", config.dig("models", "plan", "effort")
    refute(@seen_cmd.any? { |arg| arg.to_s.start_with?("HB_GROK_") })
  end

  def test_grok_rejects_untrusted_benchmark_credentials_before_docker
    valid_payload = '{"issuer::principal":{"key":"host","refresh_token":"refresh"}}'
    cases = {
      missing: nil,
      malformed: "{",
      missing_key: '{"issuer::principal":{"refresh_token":"refresh"}}',
      missing_refresh: '{"issuer::principal":{"key":"host"}}'
    }

    cases.each do |name, payload|
      auth_dir = File.join(@root, "grok-auth-#{name}")
      write_grok_auth(auth_dir, payload) if payload
      no_docker = hive_driver(runner: ->(_cmd) { flunk "docker must not run for #{name}" },
                              reuse_existing: false, reuse_unverified: false)

      with_grok_auth_dir(auth_dir) do
        assert_raises(RuntimeError, name.to_s) do
          no_docker.call(entry: entry, candidate: HiveBench::Candidates.by_id("all-grok-4.5"),
                         out_dir: File.join(@root, "out-#{name}"))
        end
      end
    end

    %i[symlink hardlink permissive].each do |name|
      auth_dir = File.join(@root, "grok-auth-#{name}")
      FileUtils.mkdir_p(auth_dir)
      auth = File.join(auth_dir, "auth.json")
      real = File.join(@root, "real-auth-#{name}.json")
      File.write(real, valid_payload)
      File.chmod(0o600, real)
      case name
      when :symlink then File.symlink(real, auth)
      when :hardlink then File.link(real, auth)
      when :permissive
        File.write(auth, valid_payload)
        File.chmod(0o644, auth)
      end
      no_docker = hive_driver(runner: ->(_cmd) { flunk "docker must not run for #{name}" },
                              reuse_existing: false, reuse_unverified: false)

      with_grok_auth_dir(auth_dir) do
        assert_raises(RuntimeError, name.to_s) do
          no_docker.call(entry: entry, candidate: HiveBench::Candidates.by_id("all-grok-4.5"),
                         out_dir: File.join(@root, "out-#{name}"))
        end
      end
    end
  end

  def test_grok_accepts_cli_lock_and_rejects_symlink_lock
    auth_dir = File.join(@root, "grok-auth")
    write_grok_auth(auth_dir, '{"issuer::principal":{"key":"host","refresh_token":"refresh"}}')
    lock_path = File.join(auth_dir, "auth.json.lock")
    File.write(lock_path, "123")
    File.chmod(0o644, lock_path)

    with_grok_auth_dir(auth_dir) { driver.call(entry: entry, candidate: HiveBench::Candidates.by_id("all-grok-4.5"), out_dir: @out) }

    FileUtils.rm_f(lock_path)
    File.symlink(File.join(auth_dir, "auth.json"), lock_path)
    no_docker = hive_driver(runner: ->(_cmd) { flunk "docker must not run" },
                            reuse_existing: false, reuse_unverified: false)

    with_grok_auth_dir(auth_dir) do
      assert_raises(RuntimeError) do
        no_docker.call(entry: entry, candidate: HiveBench::Candidates.by_id("all-grok-4.5"), out_dir: @out)
      end
    end
  end

  def write_grok_auth(dir, payload)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "auth.json")
    File.write(path, payload)
    File.chmod(0o600, path)
  end

  def test_pi_candidate_gets_native_per_stage_models_and_catalog
    glm_kimi = HiveBench::Candidates.by_id("glm-plan->kimi-exec")
    driver.call(entry: entry, candidate: glm_kimi, out_dir: @out)

    config = YAML.safe_load(File.read(File.join(@work, ".hive-state", "config.yml")))
    assert_equal HiveBench::Candidates::GLM, config.dig("models", "plan", "model")
    assert_equal HiveBench::Candidates::KIMI, config.dig("models", "execute", "model")
    assert_equal HiveBench::Candidates::GLM, config.dig("models", "review_fix", "model")
    refute(@seen_cmd.any? { |arg| arg.to_s.start_with?("HB_PI_MODEL") })
    assert_includes @seen_cmd,
                    "#{HiveBench::HiveDriver::PI_BENCH_LAUNCHER}:/opt/hb/pi-bench-launcher:ro"
    assert_includes @seen_cmd.each_cons(2).to_a,
                    ["-e", "HIVE_PI_BIN=/opt/hb/pi-bench-launcher"]
    assert_includes @seen_cmd,
                    "#{HiveBench::HiveDriver::PI_TOOL_STREAM}:/opt/hb/pi-tool-stream.ts:ro",
                    "Pi cells load the GLM transport fix inside the runner"
    assert_includes @seen_cmd,
                    "#{HiveBench::HiveDriver::PI_OPENROUTER_MODELS}:/opt/hb/pi-openrouter-models.json:ro"

    extension = File.read(HiveBench::HiveDriver::PI_TOOL_STREAM)

    assert_includes extension, 'pi.on("before_provider_request"'
    assert_includes extension, "tool_stream: true"
    assert_includes File.read(HiveBench::HiveDriver::STAGES_SH),
                    "--extension /opt/hb/pi-tool-stream.ts",
                    "the Pi shim must activate the mounted extension"
  end

  def test_claude_candidate_gets_no_pi_model_env
    driver.call(entry: entry, candidate: candidate, out_dir: @out)

    refute(@seen_cmd.any? { |a| a.to_s.start_with?("HB_PI_MODEL") })
  end
end
