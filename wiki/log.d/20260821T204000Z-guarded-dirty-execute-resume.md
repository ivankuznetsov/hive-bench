## 2026-08-21: Recover benchmark execute residue through Hive guards

**Action:** Changed identity-verified `ERROR reason=dirty_worktree` resume to
invoke `hive worktree commit-residue` before clearing the exact marker. Resume
now rechecks the worktree and fails closed when Hive's ownership, task-lock,
scope, symlink, secret-content, signing, or commit guard rejects the residue.
The command receives the exact task-directory path so resolution stays scoped
to the mounted benchmark project rather than a global project with the same
slug or an unrelated default worktree root.

**Action:** Seeded a deterministic repository-local Git author identity during
target clone setup and again before guarded recovery of preserved dirty rows.
The runner deliberately does not mount an operator's global Git config, so
without this local identity CleanExit could validate safe residue but fail the
final commit before the cell reached a terminal generated state.

**Action:** Disabled the production filename scope allowlist in benchmark-only
Hive configs. Corpus tasks legitimately add paths such as `schemas/` and
`examples/`, and a tool-only model may leave those changes for CleanExit to
commit. The isolated clone boundary, staged-symlink rejection, and added-content
secret scan remain in force; only the repo-specific filename allowlist is
relaxed so the complete candidate diff is preserved for judging.

**Action:** Generalized the exact Pi local version-probe timeout classifier from
the original 10-second value to any positive configured deadline while retaining
the full provider-specific marker message. This preserves partial work when a
loaded runner exceeds the newer bounded probe window without admitting model,
auth, or usage failures.

**Evidence:** `test/hive_resume_execute_test.rb` pins successful guarded residue
commit plus failure-without-clear behavior. `test/hive_driver_test.rb` pins a
30-second Pi preflight marker as resumable without replacing its artifact.
