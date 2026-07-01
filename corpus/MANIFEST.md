# hive-bench v1 corpus

The frozen task set a benchmark pass runs against. v1 is **curating** — this
file is the curation target and the source of truth for what's in the set and
how it's balanced.

## Targets (v1)

- **Size:** ~30–40 tasks. Enough for per-agent stability; small enough that a
  6-cell × N fresh pass is affordable.
- **Minimum gated fraction:** ≥ 60% of tasks must carry a real, curated gate
  (`fail_to_pass` populated, `needs_curation: false`). The rest are the *judged*
  subset. The leaderboard publishes the actual gated:judged split so the
  "objective floor" is never overstated.
- **Spread (best-effort within a Ruby/CLI-weighted corpus):** mix task *type*
  (bugfix / feature / refactor / test/docs), *size* (one-file → multi-file), and
  whatever *language* diversity the source repos offer. The published
  distribution states the real mix — the claim is scoped to it (see
  `/bench/methodology`).

## Curation workflow

1. Extract a candidate: `ruby harness/extract.rb --task-dir <9-done task> --repo <owner/name> --repo-path <clone>`
   (or `hive bench submit <slug>` from hive).
2. Curate the gate: fill `gate/gate.yml` (`install_cmd`, `test_cmd`,
   `fail_to_pass`, `pass_to_pass`) and flip `needs_curation: false`. Verify the
   reference reproduces — the validator (`validator/validate.rb`) requires the
   gold patch to pass its own gate.
3. Record the entry in the table below.

## Entries

| task_id | repo | type | gate | notes |
|---------|------|------|------|-------|
| add-i-key-with-legend-260522-ca28 | ivankuznetsov/hive | feature | needs curation | seed; reference verified to apply at base |
| figure-out-way-to-install-260513-4a0a | ivankuznetsov/hive | feature | needs curation | seed; reference verified to apply at base |
| add-local-hive-web-install-260629-f4ca | ivankuznetsov/hive | feature | needs curation | PR #622; validator ACCEPT (judged) |
| fix-claude-tmux-ready-detector-260629-50cc | ivankuznetsov/hive | bugfix | needs curation | PR #623; validator ACCEPT (judged) |
| fix-review-stage-claude-stop-260629-26ed | ivankuznetsov/hive | bugfix | needs curation | PR #625; validator ACCEPT (judged) |
| make-the-hive-daemon-automatically-260629-223d | ivankuznetsov/hive | feature | needs curation | PR #624; validator ACCEPT (judged) |

_(Curation in progress — gates not yet filled, so all entries are currently in
the judged subset. PRs #623/#624/#625 add unit tests, so they are the best
F2P-gate candidates.)_

**Extracted but rejected (2026-07-01):** the three `update-the-openclaw-hive-skill-260630-*`
tasks (PRs #632/#633/#635). Their brainstorms quote the exact guidance lines the
reference PR adds — a candidate-visible answer leak (inherent to
content-specified docs tasks: the spec IS the content, so execution collapses to
transcription). The validator rejects them; revisit only if a docs-task policy
with disclosure is written. Older done tasks predating the 2026-06-26
`.hive-state` re-bootstrap are unrecoverable (state history was reset).

## Open review findings — resolve before the first real gated pass

A `/pr-review-toolkit:review-pr` pass (2026-06-14) drove a round of clear-cut
fixes; these remain and matter for curation:

1. **Gate must positively observe FAIL_TO_PASS (highest priority).** Today
   `TestResultParser#test_outcome` treats a test name *absent* from the failure
   list as passing — so a FAIL_TO_PASS test that never ran (typo, deleted, not
   collected) is scored as a pass, and a green-but-empty run can clear the
   objective floor. **Curation rule:** every gated `test_cmd` MUST emit per-test
   results (run verbose, e.g. `rake test TESTOPTS=-v`), and the gate should be
   hardened to require each F2P name to appear in the *passed* set, erroring
   otherwise. Until that enforcement lands, a curator must manually confirm the
   F2P test actually executes in the reference run.
2. **CI trust boundary.** `validate-submission.yml` runs the *submission's*
   validator/harness/Dockerfile on the runner host. Controls keep blast radius
   to read-only compute (no secrets, `contents:read`, label gate), but before
   relying on it, run the validator/harness from a trusted ref and apply only
   the PR's `corpus/**`.
3. **Leaderboard summary fields.** `_includes/bench/leaderboard.html` reads
   top-level `status`/`gated_total`/`judged_total` that `Score#results` does not
   emit — add them (or compute in Liquid) before the first real `results.json`.
4. **`gen`-mode isolation fails open.** `harness/lib/isolation.sh` gen mode
   applies no egress restriction and doesn't verify the CI firewall is present;
   the CLI/auth bind-mount three comments describe isn't implemented. Make gen
   refuse to run unless egress enforcement is explicitly signalled.
