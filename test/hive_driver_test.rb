# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
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

  OK_STDOUT = "HB_STAGE plan rc=0\nHB_STAGE develop rc=0\nHB_DONE\nHB_EXIT rc=0\n"

  # A runner seam that fabricates the container's side effects, then returns stdout.
  def driver(stdout: OK_STDOUT, patch: "diff --git a/app.rb b/app.rb\n", log_lines: [])
    seen = @seen_cmd = []
    work = @work
    runner = lambda do |cmd|
      seen.concat(cmd)
      File.write(File.join(work, "candidate.patch"), patch) if patch
      unless log_lines.empty?
        dir = File.join(work, ".hive-state", "logs", "add-i-key")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "execute-1.log"), log_lines.join("\n"))
      end
      stdout
    end
    HiveBench::HiveDriver.new(runner: runner)
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

  def test_no_token_telemetry_means_no_cost_not_zero_cost
    cell = driver.call(entry: entry, candidate: candidate, out_dir: @out)

    refute cell.telemetry.key?("cost_usd"), "a telemetry gap must read as unknown, not as a $0 run"
  end

  def test_timeout_is_timed_out_not_plan_failed
    cell = driver(stdout: "HB_STAGE plan rc=0\nHB_EXIT rc=124\n", patch: nil)
           .call(entry: entry, candidate: candidate, out_dir: @out)

    assert_equal "timed_out", cell.status
    assert_match(/HB_HIVE_TIMEOUT/, cell.reason)
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
end
