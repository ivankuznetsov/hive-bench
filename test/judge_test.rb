# frozen_string_literal: true

require "minitest/autorun"
require "judge"

class JudgeTest < Minitest::Test
  # A judge_fn that returns a fixed score (optionally varying by seed).
  def fixed(score)
    lambda { |prompt:, seed:|
      _ = [prompt, seed]
      { score: score, reason: "ok" }
    }
  end

  def varying(scores_by_seed)
    lambda { |prompt:, seed:|
      _ = prompt
      { score: scores_by_seed.fetch(seed), reason: "ok" }
    }
  end

  # --- Covers AE4: blinding ---

  def test_prompt_never_contains_agent_identity
    j = HiveBench::Judge.new(judge_fn: fixed(8), seeds: 1)
    prompt = j.render(plan: "do X", candidate_diff: "+code", reference: "+ref")
    # The judge only ever sees plan/diff/reference — the caller passes no agent id,
    # and the rubric forbids guessing.
    refute_match(/claude|codex|pi@|opus|gpt-5/i, prompt, "judge prompt must not reveal the contestant")
    assert_includes prompt, "do X"
    assert_includes prompt, "+code"
  end

  def test_rubric_instructs_verbosity_neutrality_and_absolute_scoring
    prompt = HiveBench::Judge.new(judge_fn: fixed(5), seeds: 1).render(plan: "p", candidate_diff: "d", reference: nil)

    assert_match(/ignore verbosity/i, prompt)
    assert_match(/absolute rubric/i, prompt)
  end

  # --- stability across seeds ---

  def test_aggregates_mean_and_spread_across_seeds
    j = HiveBench::Judge.new(judge_fn: varying({ 1 => 6.0, 2 => 8.0, 3 => 7.0 }), seeds: 3)
    r = j.call(plan: "p", candidate_diff: "d", reference: "ref")

    assert_in_delta 7.0, r.mean, 0.001
    assert_equal [6.0, 8.0, 7.0], r.scores
    assert_operator r.stddev, :>, 0, "varying seed scores must produce a non-zero spread"
  end

  def test_identical_seeds_give_zero_spread_and_tight_interval
    r = HiveBench::Judge.new(judge_fn: fixed(9), seeds: 4).call(plan: "p", candidate_diff: "d")

    assert_in_delta(9.0, r.mean)
    assert_in_delta(0.0, r.stddev)
    assert_equal [9.0, 9.0], r.interval
  end

  def test_clamps_out_of_range_and_garbage_scores
    r = HiveBench::Judge.new(judge_fn: lambda { |prompt:, seed:|
      _ = [prompt, seed]
      { score: 99 }
    }, seeds: 1).call(plan: "p", candidate_diff: "d")

    assert_in_delta(10.0, r.mean, 0.001, "scores are clamped to the 0..10 rubric")
  end

  # --- reference-withheld ablation (R24) ---

  def test_reference_withheld_flag_and_prompt
    j = HiveBench::Judge.new(judge_fn: fixed(7), seeds: 1)
    withheld = j.call(plan: "p", candidate_diff: "d", reference: nil)

    assert withheld.reference_withheld, "nil reference is the ablation variant"

    prompt = j.render(plan: "p", candidate_diff: "d", reference: nil)

    assert_match(/No reference provided/i, prompt)
  end

  # --- tie detection (overlapping intervals) ---

  def test_overlapping_intervals_are_ties
    a = HiveBench::Judge.new(judge_fn: varying({ 1 => 7.0, 2 => 8.0, 3 => 7.5 }), seeds: 3).call(plan: "p", candidate_diff: "d")
    b = HiveBench::Judge.new(judge_fn: varying({ 1 => 7.5, 2 => 8.5, 3 => 8.0 }), seeds: 3).call(plan: "p", candidate_diff: "d")

    assert a.ties_with?(b), "overlapping judge intervals must read as a tie"
  end

  def test_seeds_must_be_positive
    assert_raises(ArgumentError) { HiveBench::Judge.new(judge_fn: fixed(5), seeds: 0) }
  end

  # A real diff carries backslashes (regex literals, escapes, Windows paths).
  # The 2-arg gsub would interpret \0/\1/\\ as backreferences; block-form must not.
  def test_render_preserves_backslash_sequences_in_diff_and_plan
    diff = "+re = /\\d+\\s/\n+path = \"C:\\\\tmp\"\n+echo \\0 and \\1"
    plan = "Match \\1 then \\\\."
    prompt = HiveBench::Judge.new(judge_fn: fixed(5), seeds: 1).render(plan: plan, candidate_diff: diff, reference: nil)

    assert_includes prompt, diff, "the candidate diff must reach the judge byte-for-byte"
    assert_includes prompt, plan, "the plan must reach the judge byte-for-byte"
    refute_includes prompt, "{{CANDIDATE}}", "no placeholder may survive (backreference \\0 must not re-inject it)"
  end
end
