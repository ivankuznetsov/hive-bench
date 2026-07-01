# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require "gate"

# Real restored repo + real git apply (offline); only the install/test command
# execution is a seam (that's the container's job, exercised by a smoke).
class GateTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("hb-gate")
    @source = File.join(@root, "source")
    @base = build_source_repo
    @patch = candidate_patch
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

  # A diff that, applied at base, changes app.rb. Built with real git so it applies.
  def candidate_patch
    work = File.join(@root, "mk")
    HiveBench::GitRestore.new.restore(source: @source, base_commit: @base, into: work)
    File.write(File.join(work, "app.rb"), "def greet = 'fixed'\n")
    HiveBench::GitRestore.new.diff(work_dir: work, base_commit: @base)
  end

  def entry
    { "checkout_source" => @source, "source" => { "base_commit" => @base } }
  end

  def gate_spec(**over)
    { "needs_curation" => false, "install_cmd" => nil, "test_cmd" => "rake test",
      "fail_to_pass" => ["GreetTest#test_fixed"], "pass_to_pass" => ["GreetTest#test_exists"] }
      .merge(over.transform_keys(&:to_s))
  end

  def gate(exec:)
    HiveBench::Gate.new(exec: exec)
  end

  def work = File.join(@root, "gatework")

  # exec stub returning canned minitest output.
  def exec_returning(output, succeeds: true)
    lambda { |cmd:, work_dir:|
      _ = [cmd, work_dir]
      { output: output, ok: succeeds }
    }
  end

  # Gate fixtures are VERBOSE (per-test lines): the gate requires every declared
  # gate test to be positively observed — a bare summary line is not enough.
  GREEN = <<~OUT
    GreetTest#test_fixed = 0.00 s = .
    GreetTest#test_exists = 0.00 s = .

    2 runs, 2 assertions, 0 failures, 0 errors, 0 skips
  OUT
  F2P_STILL_FAILS = <<~OUT
    GreetTest#test_fixed = 0.00 s = F
    GreetTest#test_exists = 0.00 s = .

    1) Failure:
    GreetTest#test_fixed [test/x.rb:1]:
    not fixed
    2 runs, 2 assertions, 1 failures, 0 errors, 0 skips
  OUT
  P2P_BROKE = <<~OUT
    GreetTest#test_fixed = 0.00 s = .
    GreetTest#test_exists = 0.00 s = F

    1) Failure:
    GreetTest#test_exists [test/x.rb:1]:
    regressed
    2 runs, 2 assertions, 1 failures, 0 errors, 0 skips
  OUT
  # A green-looking run in which the gate tests never executed (empty suite,
  # renamed test, deleted guard) — must be an error, never a pass.
  GREEN_BUT_UNOBSERVED = "2 runs, 2 assertions, 0 failures, 0 errors, 0 skips\n"
  P2P_GUARD_DELETED = <<~OUT
    GreetTest#test_fixed = 0.00 s = .

    1 runs, 1 assertions, 0 failures, 0 errors, 0 skips
  OUT

  # --- Covers AE3 ---

  def test_passes_when_f2p_flips_and_p2p_holds
    res = gate(exec: exec_returning(GREEN)).call(entry: entry, gate_spec: gate_spec, candidate_patch: @patch, work_dir: work)

    assert_equal :pass, res.status
    assert_predicate res, :gated?
  end

  def test_fails_when_f2p_test_still_fails
    res = gate(exec: exec_returning(F2P_STILL_FAILS)).call(entry: entry, gate_spec: gate_spec, candidate_patch: @patch, work_dir: work)

    assert_equal :fail, res.status
    assert_match(/FAIL_TO_PASS/, res.reason)
  end

  def test_fails_on_p2p_regression
    res = gate(exec: exec_returning(P2P_BROKE)).call(entry: entry, gate_spec: gate_spec, candidate_patch: @patch, work_dir: work)

    assert_equal :fail, res.status
    assert_match(/PASS_TO_PASS|regression/, res.reason)
  end

  # --- no-gate -> judged subset ---

  def test_uncurated_gate_is_judged_subset
    res = gate(exec: exec_returning(GREEN)).call(entry: entry, gate_spec: gate_spec(needs_curation: true), candidate_patch: @patch,
                                                 work_dir: work)

    assert_equal :no_gate, res.status
    refute_predicate res, :gated?
    assert_equal "judged", res.subset
  end

  def test_empty_fail_to_pass_is_judged_subset
    res = gate(exec: exec_returning(GREEN)).call(entry: entry, gate_spec: gate_spec(fail_to_pass: []), candidate_patch: @patch,
                                                 work_dir: work)

    assert_equal :no_gate, res.status
  end

  # --- positive observation (a gate test that never ran is never a pass) ---

  def test_green_run_without_observed_gate_tests_is_an_error
    res = gate(exec: exec_returning(GREEN_BUT_UNOBSERVED)).call(entry: entry, gate_spec: gate_spec,
                                                                candidate_patch: @patch, work_dir: work)

    assert_equal :error, res.status
    assert_match(/not observed/, res.reason)
    assert_match(/GreetTest#test_fixed/, res.reason)
  end

  def test_deleted_p2p_guard_is_an_error_not_a_pass
    res = gate(exec: exec_returning(P2P_GUARD_DELETED)).call(entry: entry, gate_spec: gate_spec,
                                                             candidate_patch: @patch, work_dir: work)

    assert_equal :error, res.status
    assert_match(/GreetTest#test_exists/, res.reason)
  end

  # --- error paths ---

  def test_non_applying_patch_is_a_gate_error
    res = gate(exec: exec_returning(GREEN)).call(entry: entry, gate_spec: gate_spec, candidate_patch: "garbage not a diff\n",
                                                 work_dir: work)

    assert_equal :error, res.status
    assert_match(/did not apply/, res.reason)
  end

  def test_install_failure_is_a_gate_error
    g = gate(exec: lambda do |cmd:, work_dir:|
      _ = work_dir
      cmd == "bundle install" ? { output: "", ok: false } : { output: GREEN, ok: true }
    end)
    res = g.call(entry: entry, gate_spec: gate_spec(install_cmd: "bundle install"), candidate_patch: @patch, work_dir: work)

    assert_equal :error, res.status
    assert_match(/install failed/, res.reason)
  end

  def test_unparseable_test_output_is_a_gate_error
    res = gate(exec: exec_returning("segfault, no summary")).call(entry: entry, gate_spec: gate_spec, candidate_patch: @patch,
                                                                  work_dir: work)

    assert_equal :error, res.status
    assert_match(/no parseable result/, res.reason)
  end
end
