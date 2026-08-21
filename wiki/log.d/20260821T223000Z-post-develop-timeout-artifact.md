# Preserve paid execute artifacts across review timeouts

- When the outer Hive timeout fires after plan and develop completed, the
  harness now atomically restores `candidate-execute.patch` as the final
  candidate instead of recording an unscoreable timeout.
- The cell records `stage_timed_out: true` and `review_status: timed_out`, so
  review lift remains visibly absent while the trustworthy execute artifact can
  proceed to judging.
- Provenance-matched reruns recover the timeout snapshot before repository setup,
  preventing `setup_repo` from deleting paid work.
- Focused Hive driver coverage proves both first-pass promotion and no-rerun
  recovery.
