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
      if [ "${1:-}" = "worktree" ]; then
        [ "${HIVE_RECOVERY_FAIL:-0}" = "1" ] && exit 1
        worktree="$HB_WORK_ROOT/.worktrees/$(basename "${3:-}")"
        git -C "$worktree" add -A || exit 1
        git -C "$worktree" -c user.name=Hive -c user.email=hive@example.invalid \
          commit -m 'guarded residue recovery' --quiet || exit 1
        exit 0
      fi
      printf '%s\n' "$@" >"$HIVE_CAPTURE"
    SH
    FileUtils.chmod(0o755, File.join(@bin, "hive"))
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_helper(marker_id)
    env = {
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "HIVE_CAPTURE" => @capture,
      "HB_WORK_ROOT" => @root
    }
    Open3.capture3(env, "bash", HELPER, @task, marker_id,
                   File.join(@root, "out.json"), File.join(@root, "err.log"))
  end

  def test_clears_only_the_host_verified_marker_id_and_reason
    File.write(File.join(@task, "task.md"),
               "<!-- ERROR reason=implementer_failed status=error marker_id=verified123 -->\n")

    _out, _err, status = run_helper("verified123")

    assert_predicate status, :success?
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

  def test_clears_verified_provider_error_reason
    File.write(File.join(@task, "task.md"),
               "<!-- ERROR reason=provider_error provider=pi marker_id=provider123 -->\n")

    _out, _err, status = run_helper("provider123")

    assert_predicate status, :success?
    assert_equal ["markers", "clear", @task, "--name", "ERROR", "--match-attr",
                  "marker_id=provider123,reason=provider_error", "--json"],
                 File.readlines(@capture, chomp: true)
  end

  def test_dirty_worktree_reason_requires_a_now_clean_owned_worktree
    worktree = File.join(@root, ".worktrees", "task")
    FileUtils.mkdir_p(worktree)
    _out, _err, status = Open3.capture3("git", "init", "-q", worktree)

    assert_predicate status, :success?
    File.write(File.join(@task, "task.md"),
               "<!-- ERROR reason=dirty_worktree marker_id=dirty123 -->\n")

    _out, _err, status = run_helper("dirty123")

    assert_predicate status, :success?
    assert_equal ["markers", "clear", @task, "--name", "ERROR", "--match-attr",
                  "marker_id=dirty123,reason=dirty_worktree", "--json"],
                 File.readlines(@capture, chomp: true)

    FileUtils.rm_f(@capture)
    File.write(File.join(worktree, "residue.txt"), "dirty\n")
    _out, _err, status = run_helper("dirty123")

    assert_predicate status, :success?
    assert_equal "guarded residue recovery",
                 `git -C #{worktree} log -1 --pretty=%s`.strip
    assert_equal ["markers", "clear", @task, "--name", "ERROR", "--match-attr",
                  "marker_id=dirty123,reason=dirty_worktree", "--json"],
                 File.readlines(@capture, chomp: true)

    FileUtils.rm_f(@capture)
    FileUtils.rm_rf(File.join(worktree, ".git"))
    FileUtils.rm_f(File.join(worktree, "residue.txt"))
    _out, _err, status = run_helper("dirty123")

    assert_equal 5, status.exitstatus
    refute_path_exists @capture
  end

  def test_dirty_worktree_recovery_failure_does_not_clear_marker
    worktree = File.join(@root, ".worktrees", "task")
    FileUtils.mkdir_p(worktree)
    _out, _err, status = Open3.capture3("git", "init", "-q", worktree)
    assert_predicate status, :success?
    File.write(File.join(worktree, "residue.txt"), "dirty\n")
    File.write(File.join(@task, "task.md"),
               "<!-- ERROR reason=dirty_worktree marker_id=dirty123 -->\n")

    env = {
      "PATH" => "#{@bin}:#{ENV.fetch("PATH")}",
      "HIVE_CAPTURE" => @capture,
      "HIVE_RECOVERY_FAIL" => "1",
      "HB_WORK_ROOT" => @root
    }
    _out, _err, status = Open3.capture3(
      env, "bash", HELPER, @task, "dirty123",
      File.join(@root, "out.json"), File.join(@root, "err.log")
    )

    assert_equal 5, status.exitstatus
    refute_path_exists @capture
    assert_includes File.read(File.join(@root, "err.log")),
                    "execute_resume_worktree_recovery_failed"
  end
end
