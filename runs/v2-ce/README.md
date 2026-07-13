# v2-ce preliminary evidence

This directory is the auditable publication of the completed preliminary
campaign: six candidates across six frozen Hive tasks (36 generated and judged
cells).

- `results.json` is the canonical merged result used for the published board.
- Every `<candidate>--<task>/results.json` is the corresponding per-cell result.
- Every published `target/candidate.patch` is the final implementation diff
  that the blind judges scored.
- `manifest.json` maps all 36 cells to those files and pins every patch by
  SHA-256.

The preliminary board uses one score sample per judge and cell. Its current
full-coverage judges are Fable 5 (reasoning effort not exposed by the provider)
and GPT-5.6 Sol at `xhigh`; a few preserved GPT-5.5 Pro scores are historical
supplemental evidence, not a third full leaderboard. These cells have
`no_gate` because the final rejudge intentionally removed the earlier
reference-internal gate overlays.

Raw provider streams, copied target repositories, Git object databases, auth
material, and build logs are not published. They are large operational
artifacts and are not needed to reproduce the score-to-patch audit. Before
publication, the 36 per-cell result files and 36 patches passed the repository's
canonical secret scanner with zero findings.

The planned replication campaign (three samples, Fable 5 plus GPT-5.6 Sol at
`ultra`, with adversarial judge self-critique) is follow-up evidence. It does
not rewrite this preliminary snapshot.
