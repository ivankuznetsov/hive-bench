# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "verify_models"

class VerifyModelsTest < Minitest::Test
  def write_log(root, cell_dir, name, models)
    dir = File.join(root, "task-x", cell_dir, "target", ".hive-state", "logs", "task-x")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, name), models.map { |m| %({"model":"#{m}"}) }.join("\n"))
  end

  def test_clean_when_stages_ran_the_claimed_model
    Dir.mktmpdir do |root|
      write_log(root, "all_opus_4_8", "plan.log", %w[claude-opus-4-8 claude-opus-4-8])
      findings, checked = HiveBench::VerifyModels.scan([root])

      assert_equal 1, checked
      assert_empty findings
    end
  end

  def test_cli_utility_models_are_not_violations
    Dir.mktmpdir do |root|
      # haiku alongside the pinned implementer = the CLI's internal subtasks
      write_log(root, "all_opus_4_8", "plan.log", %w[claude-opus-4-8 claude-haiku-4-5-20251001])
      findings, = HiveBench::VerifyModels.scan([root])

      assert_empty findings, "CLI utility calls (haiku) must not read as violations"
    end
  end

  def test_flags_an_unclaimed_substantive_model
    Dir.mktmpdir do |root|
      write_log(root, "all_glm_5_2", "execute.log", %w[moonshotai/kimi-k2.7-code])
      findings, = HiveBench::VerifyModels.scan([root])

      assert_equal 1, findings.size
      assert_match(/kimi/, findings.first.seen.join)
    end
  end

  def test_utility_only_logs_are_skipped_not_counted
    Dir.mktmpdir do |root|
      write_log(root, "all_opus_4_8", "probe.log", %w[claude-haiku-4-5-20251001])
      findings, checked = HiveBench::VerifyModels.scan([root])

      assert_equal 0, checked
      assert_empty findings
    end
  end
end
