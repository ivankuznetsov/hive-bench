# Resume Pi turns missing a finish reason

- Classified Pi's typed `Stream ended without finish_reason` terminal as a
  resumable transport failure.
- Identity verification, exact marker/log agreement, and auth/limit exclusions
  still gate the resume; the target is retained and the same model continues
  from its partial worktree.
