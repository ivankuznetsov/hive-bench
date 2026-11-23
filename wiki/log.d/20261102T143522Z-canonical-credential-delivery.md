# Publish direct credential isolation through the canonical PR workflow (U4)

Prepared `fix/profile-credential-isolation-delivery` from current upstream main
`243ef7bb`, porting only the changes in `dce0f155`, `a09fd659`, `7383c88b`,
`f157ef79` and `8d562e14`. The original branch's unpublished benchmark-results
commits are excluded. The original dirty source checkout remains untouched.

The delivered `harness/lib/isolation.sh` and `isolation_exec.rb` each match
Hive's corrected packaged copy byte-for-byte. Files outside the original
credential-change set are unchanged from the upstream base.

Validation on the delivery branch:

- Default suite: 361 tests, 1900 assertions, zero failures/errors/skips.
- Named proof: 3 tests, 40 assertions, zero failures/errors/skips, including
  real Docker 29.9.2 and actual Bash 3.2.57/5.3.20. Each interpreter's nested
  credential matrix passed 15 tests/590 assertions. The pinned Alpine image
  and separate `sh -c` argv protocol are unchanged.
- Canonical RuboCop: seven files, no offenses. Explicit `.rubocop.yml` and
  `--ignore-parent-exclusion` prevent Hive's enclosing config from applying.
- ShellCheck 0.11.0 and `git diff --check` pass.

Tests used a temporary directory inside Hive's permitted worktree, with
`GIT_CEILING_DIRECTORIES` set to that directory. Without the ceiling,
`HiveResumeExecuteTest#test_dirty_worktree_reason_completes_clean_or_guardedly_committed_residue`
discovers the enclosing Hive repository after deleting its fixture's `.git`
and fails its final assertion (expected exit 5, actual 0). The bounded rerun
passed without product or test changes. Hosted canonical CI remains a separate
pending result until the PR's Ubuntu and macOS jobs run.
