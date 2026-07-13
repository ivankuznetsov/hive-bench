# Align the native benchmark workflow with maintained campaigns

- Made `campaign.yml` declare the enabled judge backends, exact model ids,
  Codex reasoning effort, and judge sample count. Validation rejects unknown
  backends and model combinations that collapse to the same results key before
  any generation spend.
- Defaulted the example to Fable 5 plus GPT-5.6 Sol at `ultra`, with three
  independent samples per judge and cell.
- Persisted individual judge scores, reasons, sample counts, intervals, and
  reasoning-effort provenance; undersampled records are now repair targets.
- Switched v3 judging and deliberation to each candidate's generated plan.
- Added the adversarial deliberation round where judges argue against their own
  initial scores without changing the independent leaderboard score.
- Kept scheduling in Hive: deterministic cell order inside a campaign and
  normal daemon concurrency between separate workflow tasks.
- Expanded the no-cost workflow smoke and unit coverage for judge slate,
  sample-count, and effort invariants.
