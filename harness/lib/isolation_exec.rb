# frozen_string_literal: true

require "open3"

module HiveBench
  # Bridges the Gate's `exec` seam to the real isolated runner (isolation.sh).
  # Gate-mode commands run with --network none. Kept tiny and separate so the
  # Gate stays pure/testable and only the edge touches Docker.
  module IsolationExec
    module_function

    SCRIPT = File.expand_path("isolation.sh", __dir__)

    # Returns an exec proc: ->(cmd:, work_dir:) => { output:, ok: }
    def gate_exec
      lambda do |cmd:, work_dir:|
        out, status = Open3.capture2e("bash", SCRIPT, "gate", work_dir, cmd)
        { output: out, ok: status.success? }
      end
    end
  end
end
