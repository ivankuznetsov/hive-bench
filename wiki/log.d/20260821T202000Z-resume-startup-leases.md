# Refresh startup leases for resumed benchmark cells

- Added the same finite 300-second first-heartbeat window as the existing
  parallel launch-claim window.
- Identity-verified execute and review resumes now refresh both startup timer
  keys in legacy candidate configs and commit that config-only state change.
- Candidate routing, model selection, reasoning effort, and task artifacts are
  not rewritten during resume.
