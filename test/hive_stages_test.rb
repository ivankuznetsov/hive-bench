# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "open3"
require "fileutils"

class HiveStagesTest < Minitest::Test
  SCRIPT = File.expand_path("../harness/lib/hive_stages.sh", __dir__)

  def test_grok_auth_path_is_linked_for_hive_preflight
    Dir.mktmpdir("hb-grok-preflight") do |root|
      home = File.join(root, "home")
      auth = File.join(root, "shared-auth", "auth.json")
      FileUtils.mkdir_p(File.dirname(auth))
      File.write(auth, '{"scope":{"key":"access","refresh_token":"refresh"}}')

      _out, err, status = run_grok_preflight(home:, auth:)

      assert_predicate status, :success?, err

      link = File.join(home, ".grok", "auth.json")

      assert_predicate File.lstat(link), :symlink?, "Hive preflight needs ~/.grok/auth.json"
      assert_equal auth, File.readlink(link)
    end
  end

  def test_stage_models_are_owned_by_hive_without_legacy_cli_shims
    source = File.read(SCRIPT)

    refute_includes source, "HB_CODEX_MODEL_"
    refute_includes source, "HB_PI_MODEL_"
    refute_includes source, "HB_GROK_MODEL"
    assert_includes source, 'hive plan "/work/.hive-state/stages/2-brainstorm/$SLUG"'
    assert_includes source, 'hive develop "$PLAN_TASK"'
  end

  def test_failed_plan_never_advances_a_partial_artifact_to_develop
    source = File.read(SCRIPT)
    plan_block = source[/hive plan .*?PLAN_TASK=.*?\n/m]

    refute_nil plan_block
    assert_includes plan_block, 'PLAN_RC=$?'
    assert_includes plan_block, 'if [ "$PLAN_RC" -ne 0 ]'
    assert_includes plan_block, 'HB_NOTE plan_failed'
    assert_operator plan_block.index('exit 4'), :<,
                    plan_block.index('PLAN_TASK=')
  end

  def test_opencode_preflight_requires_the_complete_pinned_ce_corpus
    source = File.read(SCRIPT)

    assert_includes source, "preflight_opencode_ce_skills"
    assert_includes source, "missing CE skill path"
    assert_includes source, "incomplete CE skill corpus"
    assert_includes source, 'HB_NOTE opencode_ce_skills enabled count=33'
  end

  def test_grok_auth_preflight_fails_when_credential_disappears
    Dir.mktmpdir("hb-grok-preflight") do |root|
      home = File.join(root, "home")
      auth = File.join(root, "missing", "auth.json")

      _out, err, status = run_grok_preflight(home:, auth:)

      refute_predicate status, :success?
      assert_includes err, "HB_ERROR grok_auth_preflight missing credential: #{auth}"
    end
  end

  def test_grok_auth_preflight_fails_when_legacy_directory_cannot_be_created
    Dir.mktmpdir("hb-grok-preflight") do |root|
      home = File.join(root, "home")
      auth = File.join(root, "shared-auth", "auth.json")
      FileUtils.mkdir_p([home, File.dirname(auth)])
      File.write(auth, '{"scope":{"key":"access","refresh_token":"refresh"}}')
      File.write(File.join(home, ".grok"), "not a directory")

      _out, err, status = run_grok_preflight(home:, auth:)

      refute_predicate status, :success?
      assert_includes err, "HB_ERROR grok_auth_preflight cannot create #{home}/.grok"
    end
  end

  def test_failed_review_restores_the_execute_patch
    with_patch_functions do |functions|
      Dir.mktmpdir("hb-review-patch") do |work|
        File.write(File.join(work, "candidate-execute.patch"), "execute diff\n")
        File.write(File.join(work, "candidate.patch"), "polluted review diff\n")
        out, err, status = run_shell(
          "#{functions}\nfinalize_candidate_patch 3 \"$1\"", work
        )

        assert_predicate status, :success?, err
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

        assert_predicate status, :success?, err
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
      File.write(File.join(repo, ":(glob)**"), "PATHSPEC_MAGIC\n")
      File.write(File.join(repo, ".gitignore"), "vendor/bundle/\n")
      FileUtils.mkdir_p(File.join(repo, ".bundle-local", "gems"))
      File.write(File.join(repo, ".bundle-local", "gems", "cache.rb"), "GENERATED\n")
      FileUtils.mkdir_p(File.join(repo, "vendor", "bundle"))
      File.write(File.join(repo, "vendor", "bundle", "ignored.rb"), "IGNORED\n")
      File.write(File.join(state, "worktree.yml"), "path: #{repo}\nexecute_base_head: #{base}\n")
      patch = File.join(root, "candidate.patch")

      out, err, status = Open3.capture3(
        "bash", "-c", "#{excludes}\n#{capture}\nBASE=\"$1\"; capture \"$2\" test \"$3\"",
        "hive-stages-test", base, patch, root
      )

      assert_predicate status, :success?, "#{err}\n#{out}"
      assert_includes File.read(patch), "solution.rb"
      assert_includes File.read(patch), "PATHSPEC_MAGIC"
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

      refute_predicate status, :success?
      assert_includes err, "candidate_patch_copy_failed"
      refute_path_exists destination
    end
  end

  def test_capture_rejects_an_index_lock_without_leaving_a_patch
    source = File.read(SCRIPT)
    excludes = source[/^CAPTURE_EXCLUDES=\(.*?^\)/m]
    capture = source[/^capture\(\) \{.*?^\}/m]

    Dir.mktmpdir("hb-capture-lock") do |root|
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
      File.write(File.join(repo, ".git", "index.lock"), "locked\n")
      File.write(File.join(state, "worktree.yml"), "path: #{repo}\nexecute_base_head: #{base}\n")
      patch = File.join(root, "candidate.patch")

      _out, err, status = Open3.capture3(
        "bash", "-c", "#{excludes}\n#{capture}\nBASE=\"$1\"; capture \"$2\" test \"$3\"",
        "hive-stages-test", base, patch, root
      )

      refute_predicate status, :success?
      assert_includes err, "phase=intent_to_add"
      refute_path_exists patch
    end
  end

  def test_force_plan_complete_ignores_transient_state_lock_changes
    source = File.read(SCRIPT)
    force = source[/^force_plan_complete\(\) \{.*?^\}/m]

    refute_nil force

    Dir.mktmpdir("hb-force-plan") do |root|
      state_root = File.join(root, ".hive-state")
      plan_dir = File.join(state_root, "stages", "3-plan", "task")
      plan = File.join(plan_dir, "plan.md")
      FileUtils.mkdir_p(plan_dir)
      sh!("git", "init", "-q", "-b", "main", chdir: state_root)
      sh!("git", "config", "user.email", "t@example.com", chdir: state_root)
      sh!("git", "config", "user.name", "T", chdir: state_root)
      File.write(plan, "# Plan\n\n<!-- WAITING -->\n")
      File.write(File.join(plan_dir, ".lock"), "owned\n")
      sh!("git", "add", ".", chdir: state_root)
      sh!("git", "commit", "-qm", "base", chdir: state_root)

      FileUtils.rm_f(File.join(plan_dir, ".lock"))
      File.write(File.join(state_root, ".commit-lock"), "runtime\n")
      out, err, status = Open3.capture3(
        "bash", "-c", "#{force}\nforce_plan_complete \"$1\" \"$2\"",
        "hive-stages-test", plan, state_root
      )

      assert_predicate status, :success?, "#{err}\n#{out}"
      assert_includes File.read(plan), "<!-- COMPLETE -->"
      assert_includes out, "plan_forced_complete"
      assert_equal ["stages/3-plan/task/plan.md"],
                   sh!("git", "show", "--pretty=", "--name-only", "HEAD", chdir: state_root).lines.map(&:strip).reject(&:empty?)
      assert_includes sh!("git", "status", "--short", chdir: state_root), " D stages/3-plan/task/.lock"
      assert_includes sh!("git", "status", "--short", chdir: state_root), "?? .commit-lock"
    end
  end

  def test_normalize_null_plan_dependency_removes_only_the_invalid_frontmatter_field
    source = File.read(SCRIPT)
    normalize = source[/^normalize_null_plan_dependency\(\) \{.*?^\}/m]

    refute_nil normalize

    Dir.mktmpdir("hb-normalize-plan") do |root|
      state_root = File.join(root, ".hive-state")
      plan_dir = File.join(state_root, "stages", "3-plan", "task")
      plan = File.join(plan_dir, "plan.md")
      FileUtils.mkdir_p(plan_dir)
      sh!("git", "init", "-q", "-b", "main", chdir: state_root)
      sh!("git", "config", "user.email", "t@example.com", chdir: state_root)
      sh!("git", "config", "user.name", "T", chdir: state_root)
      File.write(plan, "---\ntitle: Plan\ndepends_on: null\n---\n\n# Plan\n")
      sh!("git", "add", ".", chdir: state_root)
      sh!("git", "commit", "-qm", "base", chdir: state_root)

      out, err, status = Open3.capture3(
        "bash", "-c", "#{normalize}\nnormalize_null_plan_dependency \"$1\" \"$2\"",
        "hive-stages-test", plan, state_root
      )

      assert_predicate status, :success?, "#{err}\n#{out}"
      assert_equal "---\ntitle: Plan\n---\n\n# Plan\n", File.read(plan)
      assert_includes out, "plan_dependency_null_removed"
      assert_equal ["stages/3-plan/task/plan.md"],
                   sh!("git", "show", "--pretty=", "--name-only", "HEAD", chdir: state_root).lines.map(&:strip).reject(&:empty?)
    end
  end

  def test_missing_plan_artifact_runs_the_markerless_plan_stage_once
    source = File.read(SCRIPT)
    ensure_plan = source[/^ensure_plan_artifact\(\) \{.*?^\}/m]

    refute_nil ensure_plan

    Dir.mktmpdir("hb-plan-resume") do |root|
      state_root = File.join(root, ".hive-state")
      hb_root = File.join(root, ".hb")
      plan_task = File.join(state_root, "stages", "3-plan", "task")
      bin = File.join(root, "bin")
      FileUtils.mkdir_p([plan_task, hb_root, bin])
      hive = File.join(bin, "hive")
      File.write(hive, <<~SH)
        #!/usr/bin/env bash
        printf '# Plan\n\n<!-- COMPLETE -->\n' >"$2/plan.md"
        printf '{}\n'
      SH
      FileUtils.chmod(0o755, hive)

      out, err, status = Open3.capture3(
        { "PATH" => "#{bin}:#{ENV.fetch("PATH")}" },
        "bash", "-c",
        "stage() { echo \"HB_STAGE $1 rc=$2\"; }\n#{ensure_plan}\n" \
          "ensure_plan_artifact \"$1\" \"$2\" \"$3\"; printf 'PLAN_MD=%s\\n' \"$PLAN_MD\"",
        "hive-stages-test", plan_task, state_root, hb_root
      )

      assert_predicate status, :success?, "#{err}\n#{out}"
      assert_includes out, "HB_STAGE plan-run rc=0"
      assert_includes out, "HB_NOTE plan_stage_resumed"
      assert_includes out, "PLAN_MD=#{plan_task}/plan.md"
      assert_path_exists File.join(hb_root, "plan-run.json")
    end
  end

  private

  def run_grok_preflight(home:, auth:)
    script = File.read(SCRIPT)
    block = script[/# BEGIN grok-auth-preflight\n(.*?)# END grok-auth-preflight/m, 1]

    refute_nil block, "hive_stages.sh must expose the Grok preflight compatibility block"

    Open3.capture3({ "HOME" => home, "GROK_AUTH_PATH" => auth }, "bash", "-c", block)
  end

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
