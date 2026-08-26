# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class OpenCodeBenchLauncherTest < Minitest::Test
  LAUNCHER = File.expand_path("../harness/lib/opencode_bench_launcher.sh", __dir__)

  def test_unsealed_invocations_delegate_all_arguments_unchanged
    out, err, status = Open3.capture3(
      { "HB_OPENCODE_REAL_BIN" => "/bin/echo" },
      "bash", LAUNCHER, "run", "--model", "openrouter/stealth/ox-alpha"
    )

    assert_predicate status, :success?, err
    assert_equal "run --model openrouter/stealth/ox-alpha\n", out
  end

  def test_sealed_invocations_drop_privileges_and_use_only_candidate_gems
    source = File.read(LAUNCHER)

    assert_includes source, 'setpriv --reuid="$candidate_uid" --regid="$candidate_gid"'
    assert_includes source, "--bounding-set=-all --inh-caps=-all --ambient-caps=-all"
    assert_includes source, "GEM_HOME=/usr/local/bundle"
    assert_includes source, "PATH=/usr/local/bin:/usr/bin:/bin"
  end
end
