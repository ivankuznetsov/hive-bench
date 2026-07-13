# Resume interrupted Codex execute turns

- Added identity-verified in-place recovery for Hive tasks parked at
  `4-execute` after a terminal Codex model-transport disconnect.
- The resume path clears only the matching `implementer_failed` marker, reuses
  the existing plan/worktree, and records `execute_resumed` telemetry.
- Authentication, usage-limit, provenance-mismatch, and ordinary implementation
  failures remain ineligible for automatic resume.
- Review-only provider limits now preserve the trustworthy execute fallback as
  generated; plan/execute limits continue to park the cell even when the stage
  wrapper consequently exits nonzero.
