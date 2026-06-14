# Contributing a task to hive-bench

A corpus task is a frozen, reproducible instance (see `corpus/SCHEMA.md`). The
easiest path, if you use hive, is to let it build the entry for you:

    hive bench submit <task-slug>     # extracts a completed task + opens the PR

To add one by hand, open a PR adding `corpus/<task-id>/` with `manifest.yml`,
`spec/` (idea/brainstorm/plan), a held-out `reference.patch`, and `gate/gate.yml`.

## What the validator checks (and why it's safe)

Every submission is validated in CI. The validation job runs your declared
build/test command, so — by design — it runs with **no repository secrets**, a
read-only token, and only after a maintainer applies the `safe-to-validate`
label (the GitHub Security Lab two-workflow pattern). An entry is **accepted**
only if it:

1. **Reproduces** — for a gated entry, the held-out `reference.patch` applied at
   `base_commit` must pass the task's own `gate` (FAIL_TO_PASS flips,
   PASS_TO_PASS holds). A no-gate entry joins the *judged* subset instead.
2. **Doesn't leak** — the reference solution must not appear in the
   candidate-visible `spec/`.
3. **Is clean** — no secrets/PII in the diff, fixtures, spec, or telemetry.
4. **Is provenanced** — `provenance.attestation` states your right to publish
   the included repo state. Diffs sourced from private repos are reviewed for
   third-party-authored commits before first publication.

Contested content can be removed via the project's takedown procedure, which
includes git-history scrubbing — file deletion alone does not erase public
history.
