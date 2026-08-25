# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class PiBenchLauncherTest < Minitest::Test
  LAUNCHER = File.expand_path("../harness/lib/pi_bench_launcher.sh", __dir__)

  def setup
    @root = Dir.mktmpdir("pi-bench-launcher")
    @package = File.join(@root, "package.json")
    @real_pi = File.join(@root, "pi")
    File.write(@package, <<~JSON)
      {
        "name": "@earendil-works/pi-coding-agent",
        "version": "0.84.2"
      }
    JSON
    File.write(@real_pi, <<~SH)
      #!/usr/bin/env bash
      printf '%s\n' "$@"
    SH
    FileUtils.chmod(0o755, @real_pi)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_version_reads_the_installed_package_without_starting_pi
    out, err, status = run_launcher("--version")

    assert_predicate status, :success?
    assert_equal "0.84.2\n", out
    assert_empty err
  end

  def test_real_invocations_delegate_all_arguments_unchanged
    out, err, status = run_launcher("-p", "--model", "openrouter/stealth/ox-alpha")

    assert_predicate status, :success?
    assert_equal "-p\n--model\nopenrouter/stealth/ox-alpha\n", out
    assert_empty err
  end

  private

  def run_launcher(*arguments)
    Open3.capture3(
      { "HB_PI_PACKAGE_JSON" => @package, "HB_PI_REAL_BIN" => @real_pi },
      "bash", LAUNCHER, *arguments
    )
  end
end
