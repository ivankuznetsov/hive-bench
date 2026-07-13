# 2026-07-11 — isolate forced-plan bookkeeping from runtime locks

- `hive_stages.sh` now force-completes a WAITING plan by staging and committing
  only `plan.md`, rather than sweeping the entire Hive state checkout with
  `git add -A`.
- This prevents transient `.lock` deletion and `.commit-lock` creation from
  aborting a completed generation before candidate diff capture.
- Added a real-Git regression that keeps both lock changes dirty while proving
  the plan-only commit succeeds.
