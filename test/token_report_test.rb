# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "lib/token_report"

class TokenReportTest < Minitest::Test
  T = HiveBench::TokenReport

  def write_log(dir, name, lines)
    d = File.join(dir, ".hive-state", "logs", "task-x")
    FileUtils.mkdir_p(d)
    File.write(File.join(d, name), lines.join("\n"))
  end

  def test_attributes_claude_events_by_message_model
    Dir.mktmpdir do |dir|
      write_log(dir, "plan-1.log",
                ['[stream] {"message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":50,' \
                 '"cache_read_input_tokens":1000,"cache_creation_input_tokens":20}}}'])
      r = T.scan_cell(dir)

      assert_equal({ "input" => 100, "output" => 50, "cache_read" => 1000, "cache_write" => 20 },
                   r["claude-opus-4-8"])
    end
  end

  def test_codex_events_attribute_by_stage_and_uncache_input
    Dir.mktmpdir do |dir|
      # codex: no model id; input INCLUDES cached -> uncached input is 300.
      write_log(dir, "execute-impl-1.log",
                ['[stream] {"usage":{"input_tokens":1000,"cached_input_tokens":700,"output_tokens":40,"reasoning_output_tokens":10}}'])
      r = T.scan_cell(dir, stage_models: { execute: "gpt-5.5" })

      assert_equal({ "input" => 300, "output" => 40, "cache_read" => 700 }, r["gpt-5.5"].slice("input", "output", "cache_read"))
    end
  end

  def test_pi_events_use_camel_case_and_own_model
    Dir.mktmpdir do |dir|
      write_log(dir, "execute-impl-1.log",
                ['[stream] {"model":"z-ai/glm-5.2","usage":{"input":10,"output":5,"cacheRead":100,"cacheWrite":1}}'])
      r = T.scan_cell(dir)

      assert_equal({ "input" => 10, "output" => 5, "cache_read" => 100, "cache_write" => 1 }, r["z-ai/glm-5.2"])
    end
  end

  def test_mixed_candidate_splits_by_model
    Dir.mktmpdir do |dir|
      write_log(dir, "plan-1.log",
                ['[stream] {"message":{"model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":1,' \
                 '"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}'])
      write_log(dir, "execute-impl-1.log",
                ['[stream] {"usage":{"input_tokens":20,"cached_input_tokens":0,"output_tokens":2}}'])
      r = T.scan_cell(dir, stage_models: { execute: "gpt-5.5" })

      assert_equal 10, r["claude-opus-4-8"]["input"]
      assert_equal 20, r["gpt-5.5"]["input"]
    end
  end

  def test_price_totals_and_nil_on_unpriceable
    priced = T.price({ "claude-opus-4-8" => { "input" => 1_000_000, "output" => 0, "cache_read" => 0, "cache_write" => 0 },
                       "gpt-5.5" => { "input" => 1_000_000, "output" => 0, "cache_read" => 0, "cache_write" => 0 } })

    assert_in_delta 5.0, priced["claude-opus-4-8"]["cost_usd"]
    assert_in_delta 10.0, priced["_total"]["cost_usd"]
    assert_equal 2_000_000, priced["_total"]["tokens"]["input"]

    with_unknown = T.price({ "mystery" => { "input" => 5, "output" => 0, "cache_read" => 0, "cache_write" => 0 } })

    assert_nil with_unknown["_total"]["cost_usd"], "a partial total must not read as complete"
  end
end
