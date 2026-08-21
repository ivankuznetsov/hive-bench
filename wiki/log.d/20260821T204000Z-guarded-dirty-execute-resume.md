## 2026-08-21: Recover benchmark execute residue through Hive guards

**Action:** Changed identity-verified `ERROR reason=dirty_worktree` resume to
invoke `hive worktree commit-residue` before clearing the exact marker. Resume
now rechecks the worktree and fails closed when Hive's ownership, task-lock,
scope, symlink, secret-content, signing, or commit guard rejects the residue.

**Action:** Generalized the exact Pi local version-probe timeout classifier from
the original 10-second value to any positive configured deadline while retaining
the full provider-specific marker message. This preserves partial work when a
loaded runner exceeds the newer bounded probe window without admitting model,
auth, or usage failures.

**Evidence:** `test/hive_resume_execute_test.rb` pins successful guarded residue
commit plus failure-without-clear behavior. `test/hive_driver_test.rb` pins a
30-second Pi preflight marker as resumable without replacing its artifact.

