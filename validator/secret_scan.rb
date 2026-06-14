# frozen_string_literal: true

module HiveBench
  # Pattern-based secret/PII scan, the hard pre-merge gate (R20) that stops a
  # corpus entry from carrying credentials into the public repo. This portable
  # pattern set has no external dependency, so the gate ALWAYS runs — never
  # silently skipped because a tool is missing. (A dedicated scanner like
  # gitleaks could be layered on top later; R20 names it only as an example.)
  #
  # Biased toward catching: a false positive is a one-line review; a missed
  # secret is published and must be rotated. Scans diffs, fixtures, specs, and
  # reused telemetry alike (JSON/JSONL included).
  module SecretScan
    module_function

    Finding = Data.define(:label, :line, :snippet)

    PATTERNS = {
      "private key" => /-----BEGIN (?:RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----/,
      "github token" => /\bgh[pousr]_[A-Za-z0-9]{20,}\b/,
      "openai key" => /\bsk-(?:proj-)?[A-Za-z0-9]{20,}\b/,
      "anthropic key" => /\bsk-ant-[A-Za-z0-9-]{20,}\b/,
      "aws access key" => /\bAKIA[0-9A-Z]{16}\b/,
      "slack token" => /\bxox[baprs]-[0-9A-Za-z-]{10,}\b/,
      "google api key" => /\bAIza[0-9A-Za-z_-]{30,}\b/,
      "generic api key assignment" => /\b(?:api[_-]?key|secret|password|token)\b\s*[:=]\s*["'][^"'\s]{12,}["']/i,
      # Require a real hostname shape (label + dot + reserved suffix), so prose
      # words like "local", "internal", "corp" don't trip the gate — only
      # `db.internal`, `printer.local:8080`, `host.corp` do.
      "private hostname" => /\b[a-z0-9][\w-]*\.(?:internal|corp|intranet|local)\b(?::\d+)?/i
    }.freeze

    # Scan one string; returns an array of Finding.
    def scan_text(text, source: nil)
      findings = []
      (text || "").each_line.with_index do |line, i|
        PATTERNS.each do |label, re|
          next unless line.match?(re)

          findings << Finding.new(label: "#{label}#{" in #{source}" if source}", line: i + 1, snippet: redact(line.strip))
        end
      end
      findings
    end

    # Scan a list of file paths; missing files are skipped (caller decides if
    # absence is itself a failure).
    def scan_files(paths)
      paths.flat_map do |path|
        next [] unless File.file?(path)

        scan_text(File.read(path), source: File.basename(path))
      end
    end

    # Don't echo the secret back into logs — show only enough to locate it.
    def redact(line)
      return line if line.length <= 40

      "#{line[0, 24]}…#{line[-8..]}"
    end
  end
end
