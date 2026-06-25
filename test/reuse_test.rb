# frozen_string_literal: true

require "minitest/autorun"
require "lib/reuse"
require "lib/profile"

class ReuseTest < Minitest::Test
  # A fake differ recording the range it was asked for, returning a canned diff.
  class FakeDiffer
    attr_reader :calls

    def initialize(diff: "RAW EXECUTE DIFF\n")
      @diff = diff
      @calls = []
    end

    def range_diff(repo:, base:, head:)
      @calls << { repo: repo, base: base, head: head }
      @diff
    end
  end

  def entry(producer: "claude-opus-4-7[1m]", head: "execHEAD")
    { "task_id" => "t1", "checkout_source" => "/clone",
      "source" => { "base_commit" => "baseSHA" },
      "provenance" => { "original_model" => producer, "execute_base_head" => head } }
  end

  def profile(id)
    HiveBench::Profile.new(id: id, harness: id.split("@").first, model: id.split("@").last,
                           bin: "x", headless_argv: ->(prompt:) { [prompt] })
  end

  def resolve(entry, profile, differ: FakeDiffer.new)
    [HiveBench::Reuse.resolver(differ: differ).call(entry, profile), differ]
  end

  def test_reuses_the_raw_execute_diff_for_the_matching_version
    out, differ = resolve(entry, profile("claude@opus-4.7"))

    assert_equal "RAW EXECUTE DIFF\n", out[:diff], "the incumbent is scored from its RAW execute output"
    assert_equal "claude-opus-4-7[1m]", out[:model_version]
    assert_equal({ repo: "/clone", base: "baseSHA", head: "execHEAD" }, differ.calls.first,
                 "diff is base..execute_base_head, never the merged reference")
  end

  def test_newer_version_of_same_agent_runs_fresh_not_reused
    out, = resolve(entry, profile("claude@opus-4.8"))

    assert_nil out, "claude-4.8 is a genuine new contestant — it must run fresh, not reuse 4.7"
  end

  def test_no_reuse_for_a_different_family
    out, = resolve(entry, profile("codex@gpt-5.5-xhigh"))

    assert_nil out, "a claude-produced task has no codex output to reuse"
  end

  def test_pi_never_reuses_it_is_the_fresh_challenger
    out, = resolve(entry, profile("pi@glm-5.2"))

    assert_nil out
  end

  def test_no_reuse_when_execute_head_is_missing
    out, = resolve(entry(head: nil), profile("claude@opus-4.7"))

    assert_nil out
  end

  def test_no_reuse_when_the_raw_diff_is_empty
    out, = resolve(entry, profile("claude@opus-4.7"), differ: FakeDiffer.new(diff: "   \n"))

    assert_nil out, "an empty recovered diff is not a scorable cell"
  end
end
