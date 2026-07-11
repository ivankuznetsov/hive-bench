# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "open3"
require "fileutils"

class HiveStagesTest < Minitest::Test
  SCRIPT = File.expand_path("../harness/lib/hive_stages.sh", __dir__)

  def test_failed_review_restores_the_execute_patch
    with_patch_functions do |functions|
      Dir.mktmpdir("hb-review-patch") do |work|
        File.write(File.join(work, "candidate-execute.patch"), "execute diff\n")
        File.write(File.join(work, "candidate.patch"), "polluted review diff\n")
        out, err, status = run_shell(
          "#{functions}\nfinalize_candidate_patch 3 \"$1\"", work
        )

        assert status.success?, err
        assert_equal "execute diff\n", File.read(File.join(work, "candidate.patch"))
        assert_includes out, "review_fallback=execute"
      end
    end
  end

  def test_failed_review_restores_an_empty_execute_patch
    with_patch_functions do |functions|
      Dir.mktmpdir("hb-empty-review-patch") do |work|
        File.write(File.join(work, "candidate-execute.patch"), "")
        File.write(File.join(work, "candidate.patch"), "polluted review diff\n")
        out, err, status = run_shell(
          "#{functions}\nfinalize_candidate_patch 3 \"$1\"", work
        )

        assert status.success?, err
        assert_empty File.read(File.join(work, "candidate.patch"))
        assert_includes out, "review_fallback=execute"
      end
    end
  end

  def test_capture_includes_solution_files_without_staging_local_bundle
    source = File.read(SCRIPT)
    excludes = source[/^CAPTURE_EXCLUDES=\(.*?^\)/m]
    capture = source[/^capture\(\) \{.*?^\}/m]
    refute_nil excludes
    refute_nil capture

    Dir.mktmpdir("hb-capture") do |root|
      repo = File.join(root, "repo")
      state = File.join(root, ".hive-state", "stages", "4-execute", "task")
      FileUtils.mkdir_p(repo)
      FileUtils.mkdir_p(state)
      sh!("git", "init", "-q", "-b", "main", chdir: repo)
      sh!("git", "config", "user.email", "t@example.com", chdir: repo)
      sh!("git", "config", "user.name", "T", chdir: repo)
      File.write(File.join(repo, "app.rb"), "puts :base\n")
      sh!("git", "add", ".", chdir: repo)
      sh!("git", "commit", "-qm", "base", chdir: repo)
      base = sh!("git", "rev-parse", "HEAD", chdir: repo).strip
      File.write(File.join(repo, "solution.rb"), "puts :solution\n")
      FileUtils.mkdir_p(File.join(repo, ".bundle-local", "gems"))
      File.write(File.join(repo, ".bundle-local", "gems", "cache.rb"), "GENERATED\n")
      File.write(File.join(state, "worktree.yml"), "path: #{repo}\nexecute_base_head: #{base}\n")
      patch = File.join(root, "candidate.patch")

      out, err, status = Open3.capture3(
        "bash", "-c", "#{excludes}\n#{capture}\nBASE=\"$1\"; capture \"$2\" test \"$3\"",
        "hive-stages-test", base, patch, root
      )

      assert status.success?, "#{err}\n#{out}"
      assert_includes File.read(patch), "solution.rb"
      refute_includes File.read(patch), ".bundle-local"
      assert_empty sh!("git", "ls-files", "--", ".bundle-local", chdir: repo)
    end
  end

  def test_candidate_patch_copy_failure_returns_nonzero
    source = File.read(SCRIPT)
    replace = source[/^replace_candidate_patch\(\) \{.*?^\}/m]
    refute_nil replace

    Dir.mktmpdir("hb-copy-failure") do |root|
      execute = File.join(root, "candidate-execute.patch")
      destination = File.join(root, "missing", "candidate.patch")
      File.write(execute, "execute diff\n")
      _out, err, status = Open3.capture3(
        "bash", "-c", "#{replace}\nreplace_candidate_patch \"$1\" \"$2\"",
        "hive-stages-test", execute, destination
      )

      refute status.success?
      assert_includes err, "candidate_patch_copy_failed"
      refute_path_exists destination
    end
  end

  private

  def with_patch_functions
    source = File.read(SCRIPT)
    functions = %w[replace_candidate_patch finalize_candidate_patch].map do |name|
      source[/^#{name}\(\) \{.*?^\}/m]
    end
    refute functions.any?(&:nil?), "stage script must expose testable patch finalization functions"
    yield functions.join("\n")
  end

  def run_shell(command, argument)
    Open3.capture3("bash", "-c", command, "hive-stages-test", argument)
  end

  def sh!(*command, chdir:)
    out, err, status = Open3.capture3(*command, chdir: chdir)
    raise "#{command.join(" ")} failed: #{err}#{out}" unless status.success?

    out
  end
end
