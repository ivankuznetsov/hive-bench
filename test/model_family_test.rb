# frozen_string_literal: true

require "minitest/autorun"
require "lib/model_family"

class ModelFamilyTest < Minitest::Test
  MF = HiveBench::ModelFamily

  def test_maps_candidate_and_judge_ids_to_families
    assert_equal ["anthropic"], MF.families("all-opus-4.8", "claude-opus-4-8")
    assert_equal ["openai"], MF.families("all-codex", "gpt-5.5")
    assert_equal ["zhipu"], MF.families("pi@glm-5.2")
    assert_equal ["moonshot"], MF.families("kimi-k2.7")
  end

  def test_mixed_candidate_belongs_to_both_families
    fams = MF.families("opus-plan->codex-exec", "opus-plan/codex-exec")

    assert_includes fams, "anthropic"
    assert_includes fams, "openai"
  end

  def test_same_family_flags_self_judging
    assert MF.same_family?("opus-4.8", "all-opus-4.8", "claude-opus-4-8"),
           "opus judging an opus candidate is same-family"
    assert MF.same_family?("fable-5", "all-opus-4.8", "claude-opus-4-8"),
           "fable is anthropic-family — same family as an opus candidate"
    assert MF.same_family?("gpt-5.5-pro", "all-codex", "gpt-5.5")
    refute MF.same_family?("gpt-5.5-pro", "all-opus-4.8", "claude-opus-4-8")
    refute MF.same_family?("opus-4.8", "pi@glm-5.2", "glm-5.2")
  end

  def test_mixed_candidate_is_same_family_with_either_judge
    assert MF.same_family?("opus-4.8", "opus-plan->codex-exec")
    assert MF.same_family?("gpt-5.5-pro", "opus-plan->codex-exec")
  end

  def test_unknown_strings_are_no_family_and_never_match
    assert_empty MF.families("mystery-model-9000")
    refute MF.same_family?("opus-4.8", "mystery-model-9000")
  end
end
