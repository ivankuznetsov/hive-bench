# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "digest"
require "open3"
require "rbconfig"
require_relative "../validator/validate"
require "gate"

class ValidateTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("hb-validate")
    @entry = File.join(@root, "entry")
    write_valid_entry
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def test_cli_boots_without_an_explicit_harness_load_path
    cli = File.expand_path("../validator/cli.rb", __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, cli)

    refute_predicate status, :success?
    assert_empty stdout
    assert_includes stderr, "usage: validator/cli.rb"
    refute_includes stderr, "LoadError"
  end

  PATCH = "--- a/app.rb\n+++ b/app.rb\n@@ -1 +1 @@\n-def greet = 'v1'\n+def greet = 'fixed and definitely longer'\n"

  def write_valid_entry(overrides: {})
    FileUtils.mkdir_p([File.join(@entry, "spec"), File.join(@entry, "gate")])
    patch = overrides[:patch] || PATCH
    File.write(File.join(@entry, "reference.patch"), patch)
    File.write(File.join(@entry, "spec", "plan.md"), overrides[:plan] || "# Plan\nMake greet return fixed.\n")
    File.write(File.join(@entry, "spec", "brainstorm.md"), overrides[:brainstorm] || "# Brainstorm\nQ&A rounds.\n")
    File.write(File.join(@entry, "gate", "gate.yml"),
               (overrides[:gate] || { "needs_curation" => false, "test_cmd" => "rake test",
                                      "fail_to_pass" => ["GreetTest#test_fixed"], "pass_to_pass" => [] }).to_yaml)
    manifest = {
      "schema" => "hive-bench-corpus-entry", "schema_version" => 1, "task_id" => "demo",
      "source" => { "repo" => "owner/demo", "base_commit" => "abc123" },
      "spec" => { "plan" => "spec/plan.md", "brainstorm" => "spec/brainstorm.md",
                  "normalized" => true, "normalization" => { "rewritten_paths" => 0, "flagged_assertions" => 0 } },
      "reference" => { "patch" => "reference.patch", "sha256" => Digest::SHA256.hexdigest(patch), "held_out" => true },
      "provenance" => { "attestation" => "I have the right to publish this." }
    }.merge(overrides[:manifest] || {})
    File.write(File.join(@entry, "manifest.yml"), manifest.to_yaml)
  end

  # gate_runner stub: reference reproduces (pass) unless told otherwise.
  def validator(reproduces: true)
    runner = lambda do |entry:, gate_spec:, candidate_patch:, work_dir:|
      _ = [entry, gate_spec, candidate_patch, work_dir]
      status = reproduces ? :pass : :fail
      HiveBench::Gate::Result.new(status: status, subset: "gated", reason: reproduces ? "ok" : "F2P failed", details: {})
    end
    HiveBench::Validator.new(gate_runner: runner)
  end

  def call(**) = validator(**).call(entry_dir: @entry, work_dir: File.join(@root, "work"))

  def test_accepts_a_valid_reproducing_gated_entry
    res = call

    assert res.ok, "valid entry should be accepted; got: #{res.failures.inspect}"
    assert_equal "gated", res.subset
  end

  def test_rejects_when_reference_does_not_reproduce
    res = call(reproduces: false)

    refute res.ok
    assert(res.failures.any? { |f| f.include?("does not reproduce") })
  end

  def test_rejects_sha_mismatch
    write_valid_entry(overrides: { manifest: { "reference" => { "patch" => "reference.patch", "sha256" => "deadbeef" } } })
    res = call

    assert(res.failures.any? { |f| f.include?("sha256 mismatch") })
  end

  def test_rejects_missing_provenance
    write_valid_entry(overrides: { manifest: { "provenance" => { "attestation" => "" } } })
    res = call

    assert(res.failures.any? { |f| f.include?("attestation") })
  end

  def test_rejects_secret_in_reference
    write_valid_entry(overrides: { patch: PATCH + "+token = ghp_#{"a" * 36}\n" })
    res = call

    assert(res.failures.any? { |f| f.include?("secret") })
  end

  LEAK_PATCH = "--- a/x\n+++ b/x\n@@ -0,0 +1,4 @@\n" \
               "#{(1..4).map { |i| "+added unique reference line number #{i} here" }.join("\n")}\n".freeze
  LEAK_TEXT = "#{(1..3).map { |i| "added unique reference line number #{i} here" }.join("\n")}\n".freeze

  def test_rejects_reference_leak_into_candidate_visible_spec
    write_valid_entry(overrides: { patch: LEAK_PATCH, brainstorm: LEAK_TEXT })
    res = call

    refute res.ok
    assert(res.failures.any? { |f| f.include?("leaks into brainstorm.md") })
  end

  # plan.md is judge context, not candidate input (v2: hive re-plans from
  # idea+brainstorm) — and a detailed plan legitimately quotes the code it
  # prescribes. Overlap there warns but does not reject.
  def test_reference_overlap_with_plan_only_warns
    write_valid_entry(overrides: { patch: LEAK_PATCH, plan: LEAK_TEXT })
    res = call

    assert res.ok, "plan-only overlap must not reject; got: #{res.failures.inspect}"
    assert(res.warnings.any? { |w| w.include?("plan.md") })
  end

  def test_no_gate_entry_is_judged_and_skips_reproducibility
    write_valid_entry(overrides: { gate: { "needs_curation" => true, "fail_to_pass" => [] } })
    res = call(reproduces: false) # would fail reproducibility, but it's skipped for judged

    assert res.ok
    assert_equal "judged", res.subset
  end

  def test_rejects_missing_manifest
    FileUtils.rm_f(File.join(@entry, "manifest.yml"))
    res = call

    refute res.ok
    assert(res.failures.any? { |f| f.include?("manifest.yml missing") })
  end

  def test_rejects_symlinks_inside_an_entry
    outside = File.join(@root, "outside.yml")
    File.write(outside, "--- {}\n")
    FileUtils.rm_f(File.join(@entry, "manifest.yml"))
    File.symlink(outside, File.join(@entry, "manifest.yml"))

    res = call

    refute res.ok
    assert(res.failures.any? { |f| f.include?("symlink not allowed: manifest.yml") })
  end

  def test_rejects_spec_paths_that_escape_the_entry
    write_valid_entry(overrides: { manifest: { "spec" => { "plan" => "../../outside.md" } } })

    res = call

    refute res.ok
    assert(res.failures.any? { |f| f.include?("spec.plan escapes corpus entry") })
  end

  def test_rejects_a_gate_tests_patch_that_escapes_the_entry
    write_valid_entry(overrides: { gate: { "needs_curation" => false, "test_cmd" => "rake test",
                                           "fail_to_pass" => ["GreetTest#test_fixed"],
                                           "tests_patch" => "../../outside.patch" } })

    res = call

    refute res.ok
    assert(res.failures.any? { |f| f.include?("gate.tests_patch escapes corpus entry") })
  end

  # A bare "owner/repo" slug must become a clonable GitHub URL (git clone treats
  # a slug as a local path and fails); URLs and local paths pass through.
  def test_clone_source_expands_slug_but_passes_through_urls_and_paths
    v = validator

    assert_equal "https://github.com/owner/repo.git", v.send(:clone_source, "owner/repo")
    assert_equal "https://example.com/x.git", v.send(:clone_source, "https://example.com/x.git")
    assert_equal "git@github.com:o/r.git", v.send(:clone_source, "git@github.com:o/r.git")
    assert_equal @root, v.send(:clone_source, @root), "an existing local path is used as-is"
  end
end
