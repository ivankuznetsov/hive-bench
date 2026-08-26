# Add Ox Alpha max and recover OpenCode usage telemetry

- Registered `all-ox-alpha@max` as a separate Pi-only candidate with explicit
  `openrouter/stealth/ox-alpha:max` routes for plan, execute, and review. Plan
  review remains disabled under the same benchmark-local grant as the high run.
- Added a structured OpenCode telemetry fallback from each cell's
  `.hb/hive-home/usage.db`. Hive's redacted OpenCode logs remain unchanged; the
  benchmark uses the normalized database rows only when no stream-token
  evidence exists.
- Added focused candidate, database-accounting, and driver integration tests.
  The full 335-test benchmark suite passes. The paid six-cell max campaign and
  historical OpenCode publication backfill remain live follow-through work.
