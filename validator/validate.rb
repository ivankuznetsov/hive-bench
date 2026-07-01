# frozen_string_literal: true

require "yaml"
require "digest"
require_relative "secret_scan"

module HiveBench
  # The submission acceptance gate (R4–R7, R20). A corpus entry is accepted only
  # if it is structurally complete, leak-free, secret-free, provenanced, and —
  # for gated entries — REPRODUCIBLE: the held-out reference, applied at the base
  # commit, must pass the task's own gate. A judged-subset entry (no gate) skips
  # the reproducibility check but must still clear every other check.
  #
  # The gate run is a seam so the same logic runs in the validator CI (inside the
  # isolated runner) and in tests (offline).
  class Validator
    Result = Data.define(:ok, :subset, :failures, :warnings) do
      def to_s
        head = ok ? "ACCEPT (#{subset})" : "REJECT:\n#{failures.map { |f| "  - #{f}" }.join("\n")}"
        warnings.empty? ? head : "#{head}\n#{warnings.map { |w| "  ~ #{w}" }.join("\n")}"
      end
    end

    # gate_runner: ->(entry:, gate_spec:, candidate_patch:, work_dir:) => Gate::Result
    def initialize(gate_runner:, secret_scan: SecretScan)
      @gate_runner = gate_runner
      @secret_scan = secret_scan
    end

    def call(entry_dir:, work_dir:)
      failures = []
      warnings = []
      manifest = load_manifest(entry_dir, failures)
      return reject(failures) unless manifest

      structural(entry_dir, manifest, failures)
      reference_integrity(entry_dir, manifest, failures)
      no_leak(entry_dir, manifest, failures, warnings)
      provenance(manifest, failures)
      secrets(entry_dir, manifest, failures)
      gate_spec = load_gate(entry_dir, failures)

      subset = reproducibility(entry_dir, manifest, gate_spec, work_dir, failures)
      Result.new(ok: failures.empty?, subset: subset, failures: failures, warnings: warnings)
    end

    private

    def load_manifest(entry_dir, failures)
      path = File.join(entry_dir, "manifest.yml")
      return failures.push("manifest.yml missing") && nil unless File.file?(path)

      YAML.safe_load_file(path)
    rescue StandardError => e
      failures.push("manifest.yml unparseable: #{e.message}")
      nil
    end

    def structural(entry_dir, manifest, failures)
      failures << "manifest.schema must be hive-bench-corpus-entry" unless manifest["schema"] == "hive-bench-corpus-entry"
      failures << "manifest.source.base_commit missing" if manifest.dig("source", "base_commit").to_s.empty?
      failures << "manifest.source.repo missing" if manifest.dig("source", "repo").to_s.empty?
      plan = manifest.dig("spec", "plan")
      failures << "spec.plan missing" if plan.to_s.empty?
      failures << "spec/plan.md not present" if plan && !File.file?(File.join(entry_dir, plan))
      failures << "reference.patch not present" unless File.file?(File.join(entry_dir, "reference.patch"))
    end

    def reference_integrity(entry_dir, manifest, failures)
      patch_path = File.join(entry_dir, "reference.patch")
      return unless File.file?(patch_path)

      declared = manifest.dig("reference", "sha256")
      actual = Digest::SHA256.hexdigest(File.read(patch_path))
      failures << "reference.patch sha256 mismatch (manifest says #{declared}, file is #{actual})" if declared && declared != actual
    end

    # The reference solution must never appear in the CANDIDATE-VISIBLE spec —
    # under v2 that is idea + brainstorm (+assets): hive re-plans from there, so
    # a leak in them hands the candidate the answer -> REJECT. plan.md is judge
    # context only (the candidate never sees it), and a detailed plan
    # legitimately quotes the code it prescribes — overlap there is a WARNING
    # (it matters again if a frozen-plan replay mode returns).
    def no_leak(entry_dir, manifest, failures, warnings)
      patch_path = File.join(entry_dir, "reference.patch")
      return unless File.file?(patch_path)

      added = File.read(patch_path).each_line.select { |l| l.start_with?("+") && !l.start_with?("+++") }
                                             .map { |l| l[1..].strip }.reject { |l| l.length < 12 }
      return if added.empty?

      visible = %w[idea brainstorm].filter_map { |k| manifest.dig("spec", k) }
                                   .map { |rel| File.expand_path(File.join(entry_dir, rel)) }
      Dir.glob(File.join(entry_dir, "spec", "*")).each do |f|
        next unless File.file?(f)

        leaked = added.count { |line| File.read(f).include?(line) }
        next if leaked < 3

        if visible.include?(File.expand_path(f))
          failures << "reference solution leaks into #{File.basename(f)} (#{leaked} added lines present)"
        else
          warnings << "reference overlaps judge-only #{File.basename(f)} (#{leaked} added lines — " \
                      "fine for v2 self-plan; blocks any frozen-plan replay)"
        end
      end
    end

    def provenance(manifest, failures)
      att = manifest.dig("provenance", "attestation").to_s.strip
      failures << "provenance.attestation missing (submitter must attest right to publish)" if att.empty?
    end

    def secrets(entry_dir, _manifest, failures)
      targets = [File.join(entry_dir, "reference.patch"), File.join(entry_dir, "manifest.yml")] +
                Dir.glob(File.join(entry_dir, "spec", "*")) +
                Dir.glob(File.join(entry_dir, "**", "*.jsonl"))
      found = @secret_scan.scan_files(targets.uniq)
      found.each { |f| failures << "secret/PII: #{f.label} (line #{f.line})" }
    end

    def load_gate(entry_dir, failures)
      path = File.join(entry_dir, "gate", "gate.yml")
      return nil unless File.file?(path)

      YAML.safe_load_file(path)
    rescue StandardError => e
      failures << "gate/gate.yml unparseable: #{e.message}"
      nil
    end

    # Returns the subset ("gated"/"judged"). For a gated entry, the reference
    # MUST reproduce (apply at base + pass the gate); otherwise the gate is a
    # fiction and the entry is rejected.
    def reproducibility(entry_dir, manifest, gate_spec, work_dir, failures)
      return "judged" if gate_spec.nil? || gate_spec["needs_curation"] || Array(gate_spec["fail_to_pass"]).empty?

      entry = manifest.merge("entry_dir" => entry_dir,
                             "checkout_source" => clone_source(manifest.dig("source", "repo")))
      patch = File.read(File.join(entry_dir, "reference.patch"))
      res = @gate_runner.call(entry: entry, gate_spec: gate_spec, candidate_patch: patch, work_dir: work_dir)
      unless res.status == :pass
        failures << "reference does not reproduce: gate returned #{res.status} (#{res.reason}); " \
                    "a gated entry's gold patch must pass its own gate"
      end
      "gated"
    end

    # GitRestore#restore runs `git clone <source>`; a bare "owner/repo" slug is
    # treated by git as a local path and fails. Expand a slug to its public
    # GitHub clone URL; pass through anything that's already a URL or local path.
    def clone_source(repo)
      r = repo.to_s
      return r if r.empty? || r.include?("://") || r.start_with?("git@") || File.exist?(r)

      "https://github.com/#{r}.git"
    end

    def reject(failures)
      Result.new(ok: false, subset: nil, failures: failures, warnings: [])
    end
  end
end
