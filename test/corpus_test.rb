# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "yaml"
require "lib/corpus"

class CorpusTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("hb-corpus")
    write_entry("b-task")
    write_entry("a-task")
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def write_entry(task_id)
    dir = File.join(@root, task_id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "manifest.yml"),
               { "task_id" => task_id, "source" => { "base_commit" => "deadbeef" },
                 "spec" => { "plan" => "spec/plan.md" } }.to_yaml)
  end

  def test_loads_each_manifest_with_entry_dir_and_checkout_source
    entries = HiveBench::Corpus.load(root: @root, checkout_source: "/clones/hive")

    assert_equal 2, entries.size
    a = entries.find { |e| e["task_id"] == "a-task" }

    assert_equal File.join(@root, "a-task"), a["entry_dir"]
    assert_equal "/clones/hive", a["checkout_source"]
    assert_equal "deadbeef", a.dig("source", "base_commit"), "manifest fields are preserved"
  end

  def test_returns_entries_in_deterministic_order
    ids = HiveBench::Corpus.load(root: @root, checkout_source: "/x").map { |e| e["task_id"] }

    assert_equal %w[a-task b-task], ids, "glob order is sorted/stable"
  end

  def test_empty_corpus_yields_no_entries
    assert_empty HiveBench::Corpus.load(root: Dir.mktmpdir, checkout_source: "/x")
  end
end
