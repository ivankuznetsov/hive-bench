# frozen_string_literal: true

require "minitest/autorun"

class BuildRunnerTest < Minitest::Test
  def setup
    @script = File.read(File.expand_path("../harness/build_runner.sh", __dir__))
  end

  def test_builds_default_and_opencode_tags_in_one_image_build
    assert_includes @script, 'IMAGE_TAG="${IMAGE_TAG:-hive-bench-runner:latest}"'
    assert_includes @script,
                    'OPENCODE_IMAGE_TAG="${OPENCODE_IMAGE_TAG:-hive-bench-runner:opencode}"'
    assert_includes @script, 'image_tag_args+=(-t "$OPENCODE_IMAGE_TAG")'
    assert_includes @script,
                    'docker build -f Dockerfile.runner "${image_tag_args[@]}"'
  end
end
