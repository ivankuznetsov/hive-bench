<!-- AGENT_WORKING pid=1684087 started=2026-06-30T08:21:05Z -->

# Brainstorm: fix-review-stage-claude-stop-260629-26ed

## Round 1

### Q1. The seed offers two fix directions: (a) fix the stop-hook so it reliably writes the completion sentinel in tmux mode, and (b) make the review-fix phase tolerant — accept clean process exit + expected artifacts/commit as completion even when the hook signal is missing/late. Which do you want as the primary deliverable for this task?
- (a) only — find and fix the real signaling root cause; no tolerant fallback
- (b) only — add the tolerant fallback; treat root cause as a separate task
- both — fix signaling AND add the fallback as a safety net (recommended)
### A1.
Both. Primary deliverable should identify/fix the real tmux stop-hook signaling path where practical, and also add a tolerant fallback as a safety net. The failure mode has already stranded useful completed work, so a pure root-cause fix is not enough.

### Q2. For the tolerant path, define the exact predicate that means "completed successfully despite missing hook signal." Which conditions must ALL hold before we suppress REVIEW_ERROR? (e.g. agent_end "phase complete" logged AND process exited 0 AND a new commit exists since pass start AND expected review artifacts present). Please confirm the precise set, especially whether a new commit is required or just expected artifacts.
### A2.
Suppress `REVIEW_ERROR` only when all of these are true: Claude process exited 0; the stage wrapper observed/logged normal agent completion rather than crash/timeout; required review-fix artifacts for the pass exist and parse; the pass has either a new commit since pass start or explicit "no code changes needed / all findings already resolved" evidence in the review artifacts; the worktree is readable; and there is no unresolved escalation or missing-output marker. A new commit is required only when the pass claims it changed code. If the pass legitimately resolved with no code edits, artifacts plus explicit no-change evidence are acceptable. <!-- hive-bench: repo-state assertion, verify against the restored base -->

### Q3. Scope of the fallback: should it apply only to the review fix phase (`6-review-fix-pass`), or to every tmux-launched Claude phase that uses the same completion path (brainstorm, plan, work, and review's ci_fix/triage/browser_test wrappers)? The same control-plane code is shared, so a narrow fix may leave siblings exposed.
### A3.
Implement the completion predicate in the shared tmux Claude completion/control-plane path so every tmux-launched phase benefits, but gate the first acceptance tests around review fix because that is the observed production failure. Do not loosen real missing-output/crash/unreadable-tmux behavior in any phase.

### Q4. Recovery of the three already-stuck tasks (58/PR #622, 287/PR #623, 288/PR #624): is this task responsible for recovering them out of REVIEW_ERROR (e.g. a documented manual command or an automatic re-evaluation), or is it fix-forward only with a separate manual cleanup left to the operator?
### A4.
This task should include recovery guidance for the already-stuck tasks 58/PR #622, 287/PR #623, and 288/PR #624. Prefer automatic re-evaluation if the new predicate can safely prove the pass completed; otherwise document exact manual `hive markers clear ... && hive run ...` commands. Do not silently clear them without auditable evidence.

### Q5. The `claude.mode: headless` switch is the active mitigation. After this fix lands, should tmux mode become the default again, or should headless remain the recommended/default mode with tmux as opt-in? This affects what the docs say and whether reverting config is part of acceptance.
### A5.
Keep `claude.mode: headless` as the recommended mitigation until the fix is released and verified. After the fix, tmux may be supported again, but do not automatically revert local/operator config as part of this task. Docs should say headless remains the workaround for affected versions and tmux is safe only once the fix is present.

### Q6. When the fallback fires (hook signal absent but artifacts present), the seed asks for an explicit audit event/log. Should this be a non-error WARN-level event that lets the stage proceed to SUCCESS, or should it still mark the stage with a distinct non-terminal "completed-with-fallback" state so operators can audit/investigate later? What event name/marker do you want?
### A6.
Use a non-error WARN-level audit event and allow the stage to proceed to SUCCESS when the fallback predicate proves completion. Suggested event name: `claude_completion_fallback`. Include phase, pass, pid/session if available, expected sentinel path, missing signal reason, artifacts checked, commit/no-change evidence, and task slug. No new terminal marker is needed for the success path.

### Q7. Root-cause depth: do you require the actual cause of the missing/late hook signal to be identified and documented (timeout too short? hook script not writing the sentinel? tmux pane race? cleanup deleting the sentinel?), or is it acceptable to ship the tolerant fallback + tests now and leave root-cause confirmation as a follow-up note?
### A7.
Require enough root-cause investigation to document the most likely cause and the files/paths involved, especially `claude_launcher.rb`, `stop_hook_installer.rb`, `scripts/stop_hook.sh`, and review wrappers. Do not block shipping the fallback if the exact race cannot be reproduced deterministically, but leave a clear follow-up note if root cause is not fully proven.

## Requirements

### Actor & context
- Actor: the hive daemon running a Claude-backed stage in **tmux mode**, specifically the review-fix phase (`6-review-fix-pass`), via the shared completion/control-plane path in `claude_launcher.rb` + `stop_hook_installer.rb` + `scripts/stop_hook.sh`.
- Problem: when Claude finishes its work and the process exits cleanly (artifacts/commits produced) but the stop-hook completion sentinel is absent or late, the stage is wrongly marked `REVIEW_ERROR phase=fix reason=fix_failed pass=N message="claude stop hook did not signal completion"`, stranding completed work.

### Primary flow (dual deliverable)
- (a) Investigate and, where practical, fix the real tmux stop-hook signaling root cause (timeout too short / hook not writing sentinel / tmux pane race / cleanup deleting sentinel). Document the most likely cause and the files/paths involved even if not deterministically reproduced (leave a follow-up note if unproven).
- (b) Add a tolerant completion fallback in the **shared** tmux Claude completion path so all tmux-launched phases benefit; gate first acceptance tests on review-fix.

### Suppression predicate (ALL must hold to suppress REVIEW_ERROR)
- Claude process exited 0.
- Stage wrapper observed/logged normal agent completion (not crash/timeout).
- Required review-fix artifacts for the pass exist and parse.
- Either a new commit exists since pass start (required when the pass claims it changed code) OR explicit "no code changes needed / all findings already resolved" evidence is present in the review artifacts.
- Worktree is readable.
- No unresolved escalation and no missing-output marker.

### Strict-failure behavior preserved
- Real missing-output, crashed Claude, exit≠0, unreadable/gone tmux, or missing required artifacts must still produce the `REVIEW_ERROR` terminal marker.
- tmux cleanup still runs; stale sessions/settings do not accumulate.

### Audit / observability
- When the fallback fires, emit a non-error WARN-level event `claude_completion_fallback` and allow the stage to proceed to SUCCESS (no new terminal marker).
- Event payload: phase, pass, pid/session if available, expected sentinel path, missing-signal reason, artifacts checked, commit/no-change evidence, task slug.

### Recovery of stuck tasks
- Provide recovery for tasks 58/PR #622, 287/PR #623, 288/PR #624: prefer automatic re-evaluation when the new predicate can safely prove completion; otherwise document exact manual `hive markers clear … && hive run …` commands. Never silently clear without auditable evidence.

### Mode policy & docs
- `claude.mode: headless` remains the recommended workaround for affected versions; tmux is safe only once the fix is present. Do not auto-revert local/operator config as part of this task.
- Document the operator workaround and the recovery commands.

### Acceptance examples
- Tmux review-fix pass: process exits 0, expected artifacts + auto-commit exist, stop hook never signals → stage does NOT end in `REVIEW_ERROR`; `claude_completion_fallback` WARN event emitted; stage reaches SUCCESS.
- Tmux review-fix pass: missing required outputs / crashed Claude / unreadable tmux → still ends in `REVIEW_ERROR`.
- `stop_hook_installer` tests assert the exact sentinel/result file paths `ClaudeLauncher` expects.
- Review-stage test asserts the `claude stop hook did not signal completion` message path is reached only on genuine failure, not on clean-exit-with-artifacts.

<!-- COMPLETE -->
