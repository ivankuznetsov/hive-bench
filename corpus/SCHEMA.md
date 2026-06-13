# Corpus entry format (`hive-bench-corpus-entry` v1)

Each corpus entry is one **frozen, reproducible task instance**, modeled on the
SWE-bench instance shape but sourced from a completed hive task. The layout:

    corpus/<task-id>/
      manifest.yml        # the contract below
      spec/
        idea.md           # normalized: absolute paths -> <REPO_ROOT>, state assertions flagged
        brainstorm.md     # (same)
        plan.md           # the frozen plan the candidate executes
      reference.patch     # the merged-PR diff — HELD OUT from candidates (answer key)
      gate/
        gate.yml          # objective test gate (hand-curated in v1)

## What the candidate sees vs. what is held out

The candidate agent is given **only `spec/`** (the idea, brainstorm, and plan).
It must never see `reference.patch` or the grading tests — those are the answer
key. The harness enforces this at run time; the format enforces it by keeping
them in separate files the runner mounts separately.

## `manifest.yml`

```yaml
schema: hive-bench-corpus-entry
schema_version: 1
task_id: <hive task slug>

source:
  repo: <owner/name>              # the repo the task was completed in
  base_commit: <sha>             # worktree.yml:execute_base_head — the replay anchor
  reference_pr: <number>         # pr.md:pr_number — the merged solution
  reference_pr_url: <url>

spec:
  idea: spec/idea.md
  brainstorm: spec/brainstorm.md  # omitted (null) if the task had none
  plan: spec/plan.md
  normalized: true
  normalization:                 # what SpecNormalizer changed (provenance)
    rewritten_paths: <int>
    flagged_assertions: <int>

reference:
  patch: reference.patch
  sha256: <hex>                  # integrity check on the held-out answer key
  held_out: true

gate:
  spec: gate/gate.yml

provenance:
  extracted_from: <task folder, repo-relative>
  extracted_at: <iso8601 utc>
  original_model: <model string | "unknown">   # from hive UsageDb execute row, best-effort
  plan_authorship: <agent | "unknown">          # who authored the frozen plan (bias disclosure)
  attestation: <string>                          # submitter's right-to-publish statement

publish:                          # per-entry publish flags (R: per-task choice of what's published)
  include_diff: true              # may the reference.patch appear in the public repo?
  include_spec: true
```

## `gate/gate.yml`

The objective gate (scoring tier 1). Hand-curated per task in v1; extraction
writes a skeleton with `needs_curation: true`.

```yaml
needs_curation: true             # flip to false once a human fills + verifies the gate
install_cmd: <string | null>     # e.g. "bundle install"
test_cmd: <string | null>        # e.g. "bundle exec rake test"
fail_to_pass: []                 # test IDs that must flip fail -> pass with the change
pass_to_pass: []                 # regression guard: must stay green
```

A task with `needs_curation: true` or empty `fail_to_pass` is **gate-ineligible**
and scored judge-only (the "judged" subset). Curation either fills the gate
(moves it to the "gated" subset) or leaves it judged.
