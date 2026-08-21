# Resume recoverable Pi and cleaned execute attempts

- Extended identity-verified execute resume to Pi's exact terminal
  `JSON error injected into SSE stream` and upstream-idle-timeout evidence.
  Authentication, usage limits, and ordinary implementation errors still fail
  closed.
- Reuse Hive's `dirty_worktree` execute marker only after the container proves
  the clean-exit hook left the owned worktree clean. This preserves the
  residual auto-commit instead of regenerating a paid cell from its base commit.
- Kept exact marker-id/reason matching, generation identity, committed-plan
  reuse, and `execute_resumed` telemetry mandatory.
