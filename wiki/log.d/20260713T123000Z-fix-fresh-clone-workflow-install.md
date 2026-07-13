# Fix native benchmark workflow installation on a fresh clone

- Removed the checked-in `.hive-state/workflows/bench*` copy. `.hive-state` is
  created as a Hive-managed Git worktree, and pre-populating it in the main
  checkout made `hive init` fail with `already exists` on a fresh clone.
- Kept `workflows/bench.yml` and `workflows/bench/` as the canonical sources.
- Documented and smoke-tested the correct order: initialize the project, copy
  the canonical files into the state worktree, commit them there, then create a
  task with `--workflow bench`.
