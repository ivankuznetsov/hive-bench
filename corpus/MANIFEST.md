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

_(Curation in progress — gates not yet filled, so both seeds are currently in
the judged subset.)_
