# 2026-07-09 — bench workflow follow-up refresh

- `3-generate` now records nonzero harness commands and still inspects the
  campaign results before deciding whether to park at WAITING.
- `5-publish` now summarizes the merged `agents` schema directly: cross-family
  means, judged cells, gate pass rate, fresh/reused provenance, and total cost.
- The no-cost workflow smoke now requires `hive` before loading the descriptor
  parser. [[v3-workflow]] and [[gaps]] were refreshed to match the current
  workflow coverage and remaining uncertainty.
