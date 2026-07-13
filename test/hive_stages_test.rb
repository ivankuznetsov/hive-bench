# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

class HiveStagesTest < Minitest::Test
  SCRIPT = File.expand_path("../harness/lib/hive_stages.sh", __dir__)

  def test_grok_auth_path_is_linked_for_hive_preflight
    Dir.mktmpdir("hb-grok-preflight") do |root|
      home = File.join(root, "home")
      auth = File.join(root, "shared-auth", "auth.json")
      FileUtils.mkdir_p(File.dirname(auth))
      File.write(auth, '{"scope":{"key":"access","refresh_token":"refresh"}}')

      _out, err, status = run_grok_preflight(home:, auth:)

      assert_predicate status, :success?, err

      link = File.join(home, ".grok", "auth.json")

      assert_predicate File.lstat(link), :symlink?, "Hive 0.3.6 preflight needs ~/.grok/auth.json"
      assert_equal auth, File.readlink(link)
    end
  end

  def test_grok_auth_preflight_fails_when_credential_disappears
    Dir.mktmpdir("hb-grok-preflight") do |root|
      home = File.join(root, "home")
      auth = File.join(root, "missing", "auth.json")

      _out, err, status = run_grok_preflight(home:, auth:)

      refute_predicate status, :success?
      assert_includes err, "HB_ERROR grok_auth_preflight missing credential: #{auth}"
    end
  end

  def test_grok_auth_preflight_fails_when_legacy_directory_cannot_be_created
    Dir.mktmpdir("hb-grok-preflight") do |root|
      home = File.join(root, "home")
      auth = File.join(root, "shared-auth", "auth.json")
      FileUtils.mkdir_p([home, File.dirname(auth)])
      File.write(auth, '{"scope":{"key":"access","refresh_token":"refresh"}}')
      File.write(File.join(home, ".grok"), "not a directory")

      _out, err, status = run_grok_preflight(home:, auth:)

      refute_predicate status, :success?
      assert_includes err, "HB_ERROR grok_auth_preflight cannot create #{home}/.grok"
    end
  end

  private

  def run_grok_preflight(home:, auth:)
    script = File.read(SCRIPT)
    block = script[/# BEGIN grok-auth-preflight\n(.*?)# END grok-auth-preflight/m, 1]

    refute_nil block, "hive_stages.sh must expose the Grok preflight compatibility block"

    Open3.capture3({ "HOME" => home, "GROK_AUTH_PATH" => auth }, "bash", "-c", block)
  end
end
