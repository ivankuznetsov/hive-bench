# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class HiveResumeExecuteTest < Minitest::Test
  HELPER = File.expand_path("../harness/lib/hive_resume_execute.sh", __dir__)

  def setup
    @root = Dir.mktmpdir("hb-resume")
    @task = File.join(@root, "task")
    @bin = File.join(@root, "bin")
    @capture = File.join(@root, "hive.args")
    FileUtils.mkdir_p([@task, @bin])
    File.write(File.join(@bin, "hive"), <<~SH)
      #!/usr/bin/env bash
      printf '%s\n' "$@" >"$HIVE_CAPTURE"
    SH
    FileUtils.chmod(0o755, File.join(@bin, "hive"))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_helper(marker_id)
    env = { "PATH" => "#{@bin}:#{ENV.fetch("PATH")}", "HIVE_CAPTURE" => @capture }
    Open3.capture3(env, "bash", HELPER, @task, marker_id,
                   File.join(@root, "out.json"), File.join(@root, "err.log"))
  end

  def test_clears_only_the_host_verified_marker_id_and_reason
    File.write(File.join(@task, "task.md"),
               "<!-- ERROR reason=implementer_failed status=error marker_id=verified123 -->\n")

    _out, _err, status = run_helper("verified123")

    assert status.success?
    assert_equal ["markers", "clear", @task, "--name", "ERROR", "--match-attr",
                  "marker_id=verified123,reason=implementer_failed", "--json"], File.readlines(@capture, chomp: true)
  end

  def test_rejects_a_marker_rotated_after_host_verification
    File.write(File.join(@task, "task.md"),
               "<!-- ERROR reason=implementer_failed status=error marker_id=new456 -->\n")

    _out, _err, status = run_helper("verified123")

    assert_equal 5, status.exitstatus
    refute_path_exists @capture
    assert_includes File.read(File.join(@root, "err.log")), "execute_resume_preflight_failed"
  end
end
