# frozen_string_literal: true

require "minitest/autorun"
require "yaml"

class ValidateSubmissionWorkflowTest < Minitest::Test
  def setup
    path = File.expand_path("../.github/workflows/validate-submission.yml", __dir__)
    @workflow = YAML.load_file(path, aliases: true)
    @pull_request = @workflow.fetch(true).fetch("pull_request") # Psych parses the YAML 1.1 `on` key as true.
    @job = @workflow.fetch("jobs").fetch("validate")
    @steps = @job.fetch("steps")
  end

  def test_requires_a_fresh_safe_label_event
    assert_equal ["labeled"], @pull_request.fetch("types")
    refute @pull_request.key?("paths"), "label authorization must not depend on GitHub's truncated path filter"
    assert_equal "github.event.label.name == 'safe-to-validate'", @job.fetch("if")
  end

  def test_executes_validation_code_from_the_immutable_base_checkout
    trusted_checkout = @steps.find { |step| step["name"] == "Check out trusted hive-bench validation code" }
    submission_checkout = @steps.find { |step| step["name"] == "Check out submitted PR data" }
    build = @steps.find { |step| step["name"] == "Build the no-network runner image" }
    validate = @steps.find { |step| step["name"] == "Validate changed corpus entries" }

    assert_equal "${{ github.event.pull_request.base.sha }}", trusted_checkout.dig("with", "ref")
    refute trusted_checkout.dig("with", "path"), "trusted code must own the workspace root"
    assert_equal "${{ github.event.pull_request.head.sha }}", submission_checkout.dig("with", "ref")
    assert_equal ".ci/submission", submission_checkout.dig("with", "path")
    assert_equal 0, submission_checkout.dig("with", "fetch-depth")
    assert_equal "harness/build_runner.sh", build.fetch("run")
    assert_equal "4", validate.dig("env", "HB_CPUS")
    assert_includes validate.fetch("run"), 'validator/cli.rb "$SUBMISSION/$entry"'
    refute_includes validate.fetch("run"), '"$SUBMISSION/harness/build_runner.sh"'
    assert_includes validate.fetch("run"), "-- 'corpus/*/**'"
    refute_includes validate.fetch("run"), "'corpus/*/manifest.yml'"
    assert_includes validate.fetch("run"), "mapfile -d '' changed_paths"
    assert_includes validate.fetch("run"), 'find "$SUBMISSION/corpus" -type l'
  end
end
