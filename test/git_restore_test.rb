# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "lib/git_restore"

# Exercises the security core of the runner against REAL git repos (no Docker,
# no network — the "source" is a local repo). Proves the hardened restore +
# diff capture defuses a hostile-repo `.git/config` textconv, which is an RCE
# vector during an otherwise read-only diff (the learnings-flagged exposure).
class GitRestoreTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("hb-restore")
    @source = File.join(@root, "source")
    git_init_source
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def sh!(*args, chdir:)
    out, err, status = Open3.capture3(*args, chdir: chdir)
    raise "#{args.join(" ")} failed: #{err}#{out}" unless status.success?

    out
  end

  def git_init_source
    FileUtils.mkdir_p(@source)
    sh!("git", "init", "-q", "-b", "main", chdir: @source)
    sh!("git", "config", "user.email", "t@e.c", chdir: @source)
    sh!("git", "config", "user.name", "T", chdir: @source)
    File.write(File.join(@source, "app.rb"), "puts 'v1'\n")
    sh!("git", "add", ".", chdir: @source)
    sh!("git", "commit", "-qm", "base", chdir: @source)
    @base = sh!("git", "rev-parse", "HEAD", chdir: @source).strip
    # A later commit so the tip differs from base — restore must land on base, not tip.
    File.write(File.join(@source, "app.rb"), "puts 'v2'\n")
    sh!("git", "commit", "-aqm", "later", chdir: @source)
  end

  def restorer = HiveBench::GitRestore.new

  def test_restores_at_the_exact_base_commit_not_the_tip
    work = File.join(@root, "work1")
    restorer.restore(source: @source, base_commit: @base, into: work)

    head = sh!("git", "rev-parse", "HEAD", chdir: work).strip

    assert_equal @base, head, "must check out the base commit, not the source tip"
    assert_equal "puts 'v1'\n", File.read(File.join(work, "app.rb")), "working tree must be the base revision"
  end

  def test_captures_a_clean_diff_of_candidate_changes
    work = File.join(@root, "work2")
    restorer.restore(source: @source, base_commit: @base, into: work)
    File.write(File.join(work, "app.rb"), "puts 'candidate'\n")

    patch = restorer.diff(work_dir: work, base_commit: @base)

    assert_includes patch, "-puts 'v1'"
    assert_includes patch, "+puts 'candidate'"
  end

  def test_captures_new_files_but_excludes_vendored_trees
    work = File.join(@root, "work-new")
    restorer.restore(source: @source, base_commit: @base, into: work)
    File.write(File.join(work, "install.sh"), "#!/bin/sh\necho hi\n") # a NEW solution file
    FileUtils.mkdir_p(File.join(work, ".gems", "foo"))
    File.write(File.join(work, ".gems", "foo", "bar.rb"), "VENDORED\n") # build side-effect

    patch = restorer.diff(work_dir: work, base_commit: @base)

    assert_includes patch, "install.sh", "a candidate that solves a task by adding files must be captured"
    assert_includes patch, "echo hi"
    refute_includes patch, "VENDORED", "vendored/generated trees (.gems) are excluded"
  end

  def test_hardened_diff_does_not_execute_a_hostile_textconv
    # A malicious repo defines a textconv driver in LOCAL .git/config + maps a
    # file to it via .gitattributes. An unhardened `git diff` would execute the
    # driver command — arbitrary code execution. The hardened diff must not.
    work = File.join(@root, "evil")
    restorer.restore(source: @source, base_commit: @base, into: work)
    sentinel = File.join(@root, "PWNED")
    File.write(File.join(work, ".gitattributes"), "*.rb diff=eviltc\n")
    # Configure the textconv driver in the repo-local config (survives our hardening of HOME/system).
    sh!("git", "config", "diff.eviltc.textconv", "sh -c 'touch #{sentinel}; cat'", chdir: work)
    File.write(File.join(work, "app.rb"), "puts 'changed'\n")

    patch = restorer.diff(work_dir: work, base_commit: @base)

    refute_path_exists sentinel, "hardened diff must NOT execute the hostile textconv driver"
    assert_includes patch, "app.rb", "the diff must still be produced"
  end

  def test_restore_refuses_a_path_traversal_into_target
    err = assert_raises(HiveBench::GitRestore::Error) do
      restorer.restore(source: @source, base_commit: @base, into: File.join(@root, "ok/../../escape"))
    end
    assert_match(/unsafe|traversal|outside/i, err.message)
  end

  def test_restore_fails_clearly_on_unknown_base_commit
    err = assert_raises(HiveBench::GitRestore::Error) do
      restorer.restore(source: @source, base_commit: "deadbeef" * 5, into: File.join(@root, "w3"))
    end
    assert_match(/base commit|checkout|not/i, err.message)
  end
end
