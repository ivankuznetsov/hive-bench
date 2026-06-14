# frozen_string_literal: true

require "minitest/autorun"
require_relative "../validator/secret_scan"

class SecretScanTest < Minitest::Test
  S = HiveBench::SecretScan

  def test_flags_private_key
    refute_empty S.scan_text("-----BEGIN OPENSSH PRIVATE KEY-----\nbody\n")
  end

  def test_flags_github_and_openai_tokens
    assert(S.scan_text("token = ghp_#{"a" * 36}").any? { |f| f.label.include?("github") })
    assert(S.scan_text("key: sk-#{"b" * 40}").any? { |f| f.label.include?("openai") })
  end

  def test_flags_aws_and_generic_assignment
    assert(S.scan_text("AKIAIOSFODNN7EXAMPLE").any? { |f| f.label.include?("aws") })
    assert(S.scan_text('password = "hunter2hunter2"').any? { |f| f.label.include?("generic") })
  end

  def test_clean_text_has_no_findings
    assert_empty S.scan_text("def greet = 'hello world'\nputs greet\n")
  end

  def test_redacts_long_secret_lines
    f = S.scan_text("api_key = \"#{"x" * 60}\"").first

    refute_includes f.snippet, "x" * 60, "the raw secret must not be echoed in the finding"
  end

  def test_scan_files_skips_missing
    assert_empty S.scan_files(["/nope/does/not/exist"])
  end
end
