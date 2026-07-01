---
slug: fix-review-stage-claude-stop-260629-26ed
created_at: 2026-06-29T16:56:54Z
original_text: |
  Fix review-stage Claude stop-hook completion failures that leave otherwise completed review fix passes in REVIEW_ERROR. Evidence from 2026-06-29: tasks 58 (PR #622), 287 (PR #623), and 288 (PR #624) all reached 6-review; reviewers and triage ran; fix pass ran for hours, produced artifacts/commits, then ended with REVIEW_ERROR phase=fix reason=fix_failed pass=1 message='claude stop hook did not signal completion'. For tasks 58 and 287 escalations show no user questions and all findings auto-fixed/resolved. Task 288 had one escalation answered: daemon-global health gate is OK for v1. Desired source fix: make the review fix phase robust to Claude stop-hook/completion signal failures when the agent process already completed and expected artifacts/commits exist, or fix the hook signaling itself. Add tests/fixtures covering review fix pass clean completion, stop-hook timeout/non-signal behavior, and ensuring real failed review fixes still surface as REVIEW_ERROR. Also document/manual recovery guidance as needed.
---

# fix-review-stage-claude-stop-260629-26ed

Fix review-stage Claude stop-hook completion failures that leave otherwise completed review fix passes in REVIEW_ERROR. Evidence from 2026-06-29: tasks 58 (PR #622), 287 (PR #623), and 288 (PR #624) all reached 6-review; reviewers and triage ran; fix pass ran for hours, produced artifacts/commits, then ended with REVIEW_ERROR phase=fix reason=fix_failed pass=1 message='claude stop hook did not signal completion'. For tasks 58 and 287 escalations show no user questions and all findings auto-fixed/resolved. Task 288 had one escalation answered: daemon-global health gate is OK for v1. Desired source fix: make the review fix phase robust to Claude stop-hook/completion signal failures when the agent process already completed and expected artifacts/commits exist, or fix the hook signaling itself. Add tests/fixtures covering review fix pass clean completion, stop-hook timeout/non-signal behavior, and ensuring real failed review fixes still surface as REVIEW_ERROR. Also document/manual recovery guidance as needed.

## Runtime details to preserve in brainstorm/plan

This is specifically a tmux-mode Claude completion-signal/control-plane bug, not just a generic review failure. The local mitigation applied on 2026-06-29 was to switch `.hive-state/config.yml` from:

```yaml
claude:
  mode: tmux
```

to:

```yaml
claude:
  mode: headless
```

That avoids the interactive tmux wrapper path for future Claude-backed stages, but the source fix should make tmux mode reliable again.

Observed failure pattern:

- A Claude-backed review fix phase runs for a long time and appears to complete useful work.
- Hive records `agent_end phase=fix pass=01 phase complete`.
- In at least task 288, Hive also recorded `clean_exit_auto_committed` with a new commit and changed wiki/docs files.
- Immediately after that, Hive writes `REVIEW_ERROR phase=fix reason=fix_failed pass=1 message="claude stop hook did not signal completion"`.
- The result is a terminal review marker even though the review/fix content appears complete.

Concrete affected tasks:

- Task 58 / PR #622 `add-local-hive-web-install-260629-f4ca`: `6-review`, `REVIEW_ERROR`, no user questions in `reviews/escalations-01.md`.
- Task 287 / PR #623 `fix-claude-tmux-ready-detector-260629-50cc`: `6-review`, `REVIEW_ERROR`, no user questions in `reviews/escalations-01.md`.
- Task 288 / PR #624 `make-the-hive-daemon-automatically-260629-223d`: `6-review`, `REVIEW_ERROR`, one escalation answered by user: daemon-global health gate is OK for v1.

Likely source areas to inspect:

- `lib/hive/claude_launcher.rb`
  - `send_prompt_and_wait!`
  - `spawn_claude_with_tmux_marker!`
  - `wait_for_terminal_marker`
  - stop/result signal file paths and cleanup
  - tmux session-gone and pane-unreadable marker paths
- `lib/hive/stop_hook_installer.rb`
- `lib/hive/scripts/stop_hook.sh`
- Review launch sites in `lib/hive/stages/review.rb`, especially the fix phase around `6-review-fix-pass`.
- Review phase wrappers in `lib/hive/stages/review/ci_fix.rb`, `triage.rb`, and `browser_test.rb` for consistent tmux completion handling.
- Existing tests:
  - `test/unit/claude_launcher_test.rb`
  - `test/unit/stop_hook_installer_test.rb`
  - `test/integration/run_brainstorm_tmux_test.rb`
  - review integration/unit tests under `test/integration/run_review_test.rb` and `test/unit/stages/review/*`.

Desired fix shape:

- Fix the actual stop-hook signaling if the hook is not writing the expected result/done sentinel in tmux review-fix runs.
- If the agent process exits cleanly and the expected review-fix artifacts/auto-commit exist, do not convert the stage to `REVIEW_ERROR` solely because the stop-hook signal was absent or late.
- Preserve strict failure behavior when Claude exits/crashes before producing required outputs, when tmux becomes unreadable, or when expected review artifacts are missing.
- Ensure tmux cleanup still happens and stale sessions/settings do not accumulate.
- If the answer is to fallback from a missing stop-hook signal to another completion signal, emit an explicit audit event/log message so the operator can see that fallback happened.

Acceptance criteria:

- Add a regression test that models a tmux Claude review-fix pass where the process exits cleanly and expected outputs/auto-commit exist but the stop hook does not signal; the review stage should not end in `REVIEW_ERROR` purely for missing hook signal.
- Add a test that a real missing-output / crashed / unreadable tmux case still produces an error marker.
- Add or update `stop_hook_installer` tests for the exact sentinel/result files expected by `ClaudeLauncher`.
- Add a review-stage test around the three real markers' message: `claude stop hook did not signal completion`.
- Document the operator workaround: switch `claude.mode` to `headless` until the tmux completion-signal bug is fixed.

<!-- WAITING -->
