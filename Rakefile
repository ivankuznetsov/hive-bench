# frozen_string_literal: true

require "rake/testtask"

BENCH_ISOLATION_PROOF_TEST = "test/isolation_proof_test.rb"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "harness"
  t.test_files = FileList["test/**/*_test.rb"].exclude(BENCH_ISOLATION_PROOF_TEST)
  t.warning = false
end

Rake::TestTask.new("test:bench_isolation_proof") do |t|
  t.libs << "test" << "harness"
  t.test_files = FileList[BENCH_ISOLATION_PROOF_TEST]
  t.warning = false
  t.description = "Prove credential isolation with actual Bash versions and Docker when available"
end

task default: :test
