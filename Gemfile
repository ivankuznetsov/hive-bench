# frozen_string_literal: true

source "https://rubygems.org"

ruby "~> 3.4"

gem "agent-cli-runtime", "~> 0.1.0"

# Stdlib-first by design — the harness shells out to git/agent CLIs and uses
# YAML/JSON from the standard library. Agent CLI prerequisite probing is shared
# with Hive through agent-cli-runtime. Dev/test tooling only below.
group :development, :test do
  gem "minitest", "~> 5.25"
  gem "rake", "~> 13.2"
  gem "rubocop", "~> 1.68", require: false
  gem "rubocop-minitest", "~> 0.36", require: false
end
