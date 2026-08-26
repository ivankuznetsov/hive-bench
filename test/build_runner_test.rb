# frozen_string_literal: true

require "minitest/autorun"

class BuildRunnerTest < Minitest::Test
  def setup
    @script = File.read(File.expand_path("../harness/build_runner.sh", __dir__))
    @dockerfile = File.read(File.expand_path("../Dockerfile.runner", __dir__))
  end

  def test_builds_default_and_opencode_tags_in_one_image_build
    assert_includes @script, 'IMAGE_TAG="${IMAGE_TAG:-hive-bench-runner:latest}"'
    assert_includes @script,
                    'OPENCODE_IMAGE_TAG="${OPENCODE_IMAGE_TAG:-hive-bench-runner:opencode}"'
    assert_includes @script, 'image_tag_args+=(-t "$OPENCODE_IMAGE_TAG")'
    assert_includes @script,
                    'docker build -f Dockerfile.runner --build-arg "HIVE_BUILD_SHA=$full_rev"'
  end

  def test_separates_root_only_hive_control_bundle_from_candidate_gems
    assert_includes @dockerfile, "mv /usr/local/bundle /opt/hb/control-bundle"
    assert_includes @dockerfile, "rm -rf /usr/local/bundle/gems/hive-cli-*"
    assert_includes @dockerfile, "chmod -R go-rwx /opt/hb/control-bundle"
    assert_includes @dockerfile, 'io.hive.bench.hive-build-sha="${HIVE_BUILD_SHA}"'
    assert_includes @dockerfile, 'io.hive.bench.runtime-visibility="sealed-control-bundle-v1"'
  end
end
