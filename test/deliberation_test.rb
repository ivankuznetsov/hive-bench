# frozen_string_literal: true

require "minitest/autorun"
require "lib/deliberation"

class DeliberationTest < Minitest::Test
  # Judge stubs record every prompt; round is inferred from seed (1 or 2).
  def make_fn(name, initial:, final:, log:)
    lambda do |prompt:, seed:|
      log << { judge: name, seed: seed, prompt: prompt }
      seed == 1 ? initial : final
    end
  end

  def delib(log, strict_final: { score: 5.0, reason: "held", discussion: "checked their claim; diff lacks the test" },
            lenient_final: { score: 6.0, reason: "conceded the missing test", discussion: "they are right" })
    HiveBench::Deliberation.new(judge_fns: {
                                  "lenient" => make_fn("lenient", initial: { score: 8.0, reason: "complete work" },
                                                                  final: lenient_final, log: log),
                                  "strict" => make_fn("strict", initial: { score: 5.0, reason: "no tests added" },
                                                                final: strict_final, log: log)
                                })
  end

  def test_two_rounds_share_verdicts_and_record_revision
    log = []
    v = delib(log).call(plan: "add a panel", candidate_diff: "diff --git a/x b/x", reference: "ref diff")

    assert_equal 4, log.size, "2 judges x 2 rounds"
    assert_in_delta 8.0, v["lenient"].initial
    assert_in_delta 6.0, v["lenient"].final
    assert_predicate v["lenient"], :revised?
    assert_in_delta(-2.0, v["lenient"].delta)
    refute_predicate v["strict"], :revised?, "strict held its score"
    assert_equal "checked their claim; diff lacks the test", v["strict"].discussion
  end

  def test_round_two_prompt_contains_other_verdict_but_never_judge_names
    log = []
    delib(log).call(plan: "p", candidate_diff: "d", reference: nil)
    r2 = log.select { |l| l[:seed] == 2 }
    lenient_r2 = r2.find { |l| l[:judge] == "lenient" }[:prompt]

    assert_includes lenient_r2, "score: 8.0", "own initial verdict is shown"
    assert_includes lenient_r2, "no tests added", "the other referee's reason is shown"
    assert_includes lenient_r2, "referee-B", "others are anonymized"
    refute_includes lenient_r2, "strict", "judge names must never leak into the discussion"
    refute_includes lenient_r2, "lenient"
    assert_includes lenient_r2, "strongest evidence-based case that your own"
    assert_includes lenient_r2, "initial score is wrong"
  end

  def test_round_one_failure_sits_the_judge_out
    log = []
    fns = {
      "ok" => make_fn("ok", initial: { score: 7.0, reason: "r" }, final: { score: 7.0, reason: "r" }, log: log),
      "broken" => lambda { |prompt:, seed:|
        _ = [prompt, seed]
        raise "judge down"
      }
    }
    v = capture_io { @out = HiveBench::Deliberation.new(judge_fns: fns).call(plan: "p", candidate_diff: "d") } && @out

    assert_empty v, "one surviving judge has nobody to discuss with"
  end

  def test_round_two_failure_keeps_initial_with_nil_final
    log = []
    fns = {
      "ok" => make_fn("ok", initial: { score: 7.0, reason: "r" }, final: { score: 7.5, reason: "r2" }, log: log),
      "flaky" => lambda do |prompt:, seed:|
        raise "402" if seed == 2

        log << { judge: "flaky", seed: seed, prompt: prompt }
        { score: 3.0, reason: "weak" }
      end
    }
    v = capture_io { @out = HiveBench::Deliberation.new(judge_fns: fns).call(plan: "p", candidate_diff: "d") } && @out

    assert_in_delta 3.0, v["flaky"].initial
    assert_nil v["flaky"].final
    refute_predicate v["flaky"], :revised?
  end

  def test_requires_two_judges
    assert_raises(ArgumentError) { HiveBench::Deliberation.new(judge_fns: { "solo" => ->(*) {} }) }
  end
end
