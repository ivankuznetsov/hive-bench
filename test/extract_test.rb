# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "digest"
require "extract"

class ExtractTest < Minitest::Test
  # A diff carrying a unique marker so we can prove it never leaks into spec/.
  FAKE_PATCH = "--- a/lib/x.rb\n+++ b/lib/x.rb\n@@ -1 +1 @@\n-old\n+REFERENCE_SOLUTION_MARKER\n"
  FAKE_RESOLVER = lambda do |_repo, _pr|
    { "base_commit" => "abc123base", "merge_commit" => "def456merge", "patch" => FAKE_PATCH }
  end
  FAKE_MODEL = ->(_slug) { "claude-opus-4-8" }

  def setup
    @root = Dir.mktmpdir("hive-bench-extract")
    @task_dir = File.join(@root, "9-done", "add-i-key-260522-ca28")
    @out_dir = File.join(@root, "corpus")
    FileUtils.mkdir_p(@task_dir)
    write_fixture_task
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def write_fixture_task(overrides: {})
    files = {
      "worktree.yml" => { "branch" => "add-i-key-260522-ca28",
                          "execute_base_head" => "239c5b4112ae128f1d59650e9536968f8cc4d519" },
      "meta.yml" => { "id" => 21, "slug" => "add-i-key-260522-ca28", "display_name" => "Add Info Panel Key" }
    }.merge(overrides[:yaml] || {})
    files.each { |name, data| File.write(File.join(@task_dir, name), data.to_yaml) unless data == :skip }

    File.write(File.join(@task_dir, "pr.md"), overrides[:pr_md] ||
      "---\npr_url: https://github.com/ivankuznetsov/hive/pull/127\npr_number: 127\n---\n\n## Summary\nAdds an info panel.\n")
    File.write(File.join(@task_dir, "idea.md"), "Add an `i` info panel key to the TUI.\n")
    File.write(File.join(@task_dir, "brainstorm.md"), "### Q1. Scope?\n### A1. Read-only panel.\n")
    if overrides[:skip_plan]
      FileUtils.rm_f(File.join(@task_dir, "plan.md"))
      return
    end

    File.write(File.join(@task_dir, "plan.md"), overrides[:plan_md] ||
      "# Plan\n\nEdit /home/asterio/Dev/hive.worktrees/add-i-key-260522/lib/hive/tui/model.rb.\n" \
      "There is no info panel today.\n")
  end

  def extract(**)
    HiveBench::Extract.new(
      task_dir: @task_dir, repo_slug: "ivankuznetsov/hive", out_dir: @out_dir,
      reference_resolver: FAKE_RESOLVER, model_lookup: FAKE_MODEL, plan_authorship: "claude",
      clock: -> { Time.utc(2026, 6, 14, 12, 0, 0) }, **
    ).call
  end

  def entry_dir = File.join(@out_dir, "add-i-key-260522-ca28")

  # --- Happy path (Covers AE1) ---

  def test_extracts_a_complete_entry_with_all_artifacts
    manifest = extract

    assert_equal "hive-bench-corpus-entry", manifest["schema"]
    assert_equal 1, manifest["schema_version"]
    assert_equal "add-i-key-260522-ca28", manifest["task_id"]
    assert_equal "abc123base", manifest.dig("source", "base_commit"),
                 "base must be the reference's apply base (merge^), not execute_base_head"
    assert_equal "def456merge", manifest.dig("source", "merge_commit")
    assert_equal "239c5b4112ae128f1d59650e9536968f8cc4d519", manifest.dig("provenance", "execute_base_head"),
                 "execute_base_head is kept as provenance"
    assert_equal 127, manifest.dig("source", "reference_pr")

    %w[manifest.yml spec/idea.md spec/brainstorm.md spec/plan.md reference.patch gate/gate.yml].each do |f|
      assert File.file?(File.join(entry_dir, f)), "expected #{f} in the entry"
    end
  end

  def test_reference_patch_is_held_out_and_integrity_hashed
    manifest = extract

    assert_equal FAKE_PATCH, File.read(File.join(entry_dir, "reference.patch"))
    assert_equal Digest::SHA256.hexdigest(FAKE_PATCH), manifest.dig("reference", "sha256"),
                 "manifest must carry a sha256 of the held-out answer key"
    assert manifest.dig("reference", "held_out")
  end

  # --- Covers AE2: no leakage of the reference into agent-visible spec/ ---

  def test_reference_solution_never_appears_under_spec
    extract

    Dir.glob(File.join(entry_dir, "spec", "*")).each do |f|
      refute_includes File.read(f), "REFERENCE_SOLUTION_MARKER",
                      "the answer key must never leak into the candidate-visible spec/"
    end
    refute File.file?(File.join(entry_dir, "spec", "reference.patch")),
           "reference.patch must live outside spec/"
  end

  # --- Plan normalization (R3) ---

  def test_plan_is_normalized_and_counts_recorded
    manifest = extract
    plan = File.read(File.join(entry_dir, "spec", "plan.md"))

    assert_includes plan, "<REPO_ROOT>/lib/hive/tui/model.rb", "absolute path must be rewritten"
    refute_includes plan, "/home/asterio", "no absolute home path may survive in spec/"
    assert_includes plan, "repo-state assertion", "the 'today' assertion must be flagged"
    assert_operator manifest.dig("spec", "normalization", "rewritten_paths"), :>=, 1
    assert_operator manifest.dig("spec", "normalization", "flagged_assertions"), :>=, 1
  end

  def test_provenance_records_model_and_plan_authorship
    manifest = extract

    assert_equal "claude-opus-4-8", manifest.dig("provenance", "original_model")
    assert_equal "claude", manifest.dig("provenance", "plan_authorship")
    assert_equal "2026-06-14T12:00:00Z", manifest.dig("provenance", "extracted_at")
  end

  def test_gate_skeleton_marks_needs_curation
    extract
    gate = YAML.safe_load_file(File.join(entry_dir, "gate", "gate.yml"))

    assert gate["needs_curation"]
    assert_empty gate["fail_to_pass"]
  end

  def test_model_unknown_when_lookup_returns_nil
    manifest = extract(model_lookup: ->(_slug) {})

    assert_equal "unknown", manifest.dig("provenance", "original_model")
  end

  # --- Edge / error paths ---

  def test_refuses_when_base_commit_missing
    write_fixture_task(overrides: { yaml: { "worktree.yml" => { "branch" => "x" } } })
    err = assert_raises(HiveBench::Extract::Error) { extract }
    assert_match(/execute_base_head/, err.message)
  end

  def test_refuses_when_pr_number_missing
    write_fixture_task(overrides: { pr_md: "---\npr_url: https://example/1\n---\n\nbody\n" })
    err = assert_raises(HiveBench::Extract::Error) { extract }
    assert_match(/pr_number/, err.message)
  end

  def test_refuses_when_no_plan
    write_fixture_task(overrides: { skip_plan: true })
    err = assert_raises(HiveBench::Extract::Error) { extract }
    assert_match(/plan\.md/, err.message)
  end

  def test_refuses_when_reference_diff_empty
    empty = ->(_r, _n) { { "base_commit" => "abc", "patch" => "  \n" } }
    err = assert_raises(HiveBench::Extract::Error) { extract(reference_resolver: empty) }
    assert_match(/empty diff/, err.message)
  end

  def test_refuses_when_resolver_returns_no_base
    nobase = ->(_r, _n) { { "patch" => FAKE_PATCH } }
    err = assert_raises(HiveBench::Extract::Error) { extract(reference_resolver: nobase) }
    assert_match(/base_commit/, err.message)
  end
end
