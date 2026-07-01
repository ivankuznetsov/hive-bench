## Round 1

### Q1. Scope of recoverable reasons — which marker reasons should be eligible for auto-retry in v1? The seed names `implementer_failed` (Codex 401 auth) and `claude_launch_failed` (launcher/binary). Is the intent a fixed allowlist of specific reasons, or a broader "transient" category? Please list the exact marker reasons you want covered now, and any you explicitly want excluded.
### A1.
Use a fixed v1 allowlist, not a broad transient category. Include `implementer_failed` only when diagnostics/logs classify it as Codex auth failure (401 missing bearer/basic auth) and `claude_launch_failed` only when the launcher/wrapper/readiness health probe now passes. Exclude business-logic failures, test failures, review findings, merge conflicts, dirty-worktree failures, unknown `exit_code=1`, and any marker without a recognized diagnostic signature.

### Q2. Health-probe mapping — each recoverable reason needs a probe that must pass before retry. Can you confirm the probe per reason? e.g. Codex auth → `codex login status` logged-in AND a `codex exec` smoke test; Claude launcher → ready-detector/current-binary check AND `hive doctor` green. Should `hive doctor` green be a universal precondition for every auto-retry, or only for the launcher case?
### A2.
Codex auth recovery requires both `codex login status` showing logged in and a tiny `codex exec` smoke test succeeding in the same environment the daemon will use. Claude launcher recovery requires the wrapper file to exist in the active install, the ready detector fixtures/check to pass, the active daemon binary/version to match the CLI, and `hive doctor` green for required agent skills. A lightweight doctor/agent-health pass should be a universal precondition before any auto-retry.

### Q3. Probe execution model — how should the daemon run these probes? Options: (a) shell out to the real `hive doctor` / `codex` CLIs, (b) reuse in-process health-check functions, (c) a mix. What timeout and failure handling do you want if a probe itself hangs or errors (treat as "not healthy" and skip retry, presumably)? Any concern about probe cost/frequency on the daemon loop?
### A3.
Use a mix: prefer in-process helpers for Hive-owned checks, shell out for external CLIs (`codex`, `claude`, `gh`) because auth and runtime behavior live there. Every probe must have a short timeout (10-30s depending on command), capture stderr/stdout into audit logs, and treat timeout/error as "not healthy, do not retry." Cache probe results per daemon tick/reason so parked markers do not create noisy repeated CLI calls.

### Q4. Trigger & cadence — when should the daemon evaluate parked recoverable markers? On every daemon tick, on a slower dedicated interval, or only when a health-signal change is detected (e.g. binary version changed, config/env changed)? What concretely counts as a "changed health signal" that justifies re-probing a previously-failing marker?
### A4.
Evaluate recoverable parked markers on daemon ticks, but throttle per task/reason. Re-probe when a health signal changes: daemon binary path/version/fingerprint, relevant config/env, plugin/skill inventory, Codex login state, wrapper file mtime, or a manual marker-clear/retry-related event. Periodic low-frequency re-probe is acceptable as a fallback, but not every 30s for expensive probes.

### Q5. Retry limits & backoff — what are the desired numbers? e.g. max N auto-retries per task per reason, exponential backoff schedule, and the rule that a retry is only allowed when the health signal has changed since the last failed attempt (vs. allowing periodic re-probe even without a detected change). What should happen when the limit is exhausted — park permanently and require manual `hive markers clear`?
### A5.
Allow at most 2 auto-retries per task per marker reason. Require a changed health signal since the last failed attempt before retrying again. Use backoff such as immediate after first healthy signal, then 30 minutes after a second healthy signal. After exhaustion, park permanently on the marker and require manual `hive markers clear`.

### Q6. "Don't discard user work" guard — what defines a marker where retry is unsafe? How does the daemon detect partial/uncommitted work or in-progress artifacts that a retry would overwrite? Is the safe rule simply "only auto-retry failures that produced no committed stage output / left the worktree clean," or do you have a more specific signal?
### A6.
Only auto-retry when the failed stage did not produce terminal success output and the relevant work area is safe. For execute, require the worktree to be clean or only contain Hive/agent-generated files known to be safe for that stage, with no uncommitted user edits. For brainstorm/plan launcher failures, require no answered user content would be overwritten. When uncertain, do not auto-retry.

### Q7. What "auto-retry" does mechanically — should it be equivalent to `hive markers clear` followed by re-enqueueing the stage from the start, or a resume? Does the task re-run the same stage (e.g. 4-execute) from scratch? Should it behave identically to a manual clear+retry so the rest of the pipeline is unchanged?
### A7.
Make auto-retry mechanically equivalent to manual `hive markers clear` plus re-enqueueing/running the same stage from the start. Do not invent a special resume path in v1. The rest of the pipeline should see the same state transitions and markers as a manual recovery.

### Q8. Audit & observability — where should auto-retry events be recorded (events.jsonl, daemon log, both)? What fields do you want per event (task slug, reason, probe results, attempt count, decision rationale, timestamp)? Should there also be an event when a marker is evaluated but NOT retried (and why)?
### A8.
Record decisions in both the task `events.jsonl` and daemon log. Include task slug/id, stage, marker id, reason, probe names/results, health-signal fingerprint, auto-retry attempt count, action taken, and rationale. Also record negative decisions at a throttled rate, e.g. "not retried: codex smoke failed" or "not retried: unknown reason."

### Q9. Opt-in & configuration — should auto-retry be on by default for all tasks/repos, or gated behind a config flag? Do you want per-reason or per-repo tuning of limits/backoff, and a global kill-switch to disable it entirely?
### A9.
Enable by default only for the v1 allowlisted recoveries, with a global config kill-switch such as `daemon.auto_retry.enabled: false`. Add per-reason limits/backoff config later if needed, but keep v1 conservative and hardcoded enough to be safe.

### Q10. Acceptance criteria — beyond the two named tests (Codex auth recovery, Claude launcher recovery), what end-to-end outcomes define "done"? e.g. "task 58-style auth failure auto-clears within one probe cycle after `codex exec` smoke-tests green, with an audit event, and never auto-clears an unknown business-logic failure." Please state the concrete pass/fail scenarios you'd check.
### A10.
Done means: a task 58-style Codex auth failure auto-clears and retries within one daemon/probe cycle after `codex login status` and a smoke test pass; a task 287-style Claude launcher failure auto-clears only after wrapper/detector/doctor checks pass; both cases emit audit events; unknown `implementer_failed` remains parked; repeated failures respect retry limits/backoff; dirty worktrees or ambiguous partial outputs are not retried.

## Requirements

**Actor:** Hive daemon (background loop), acting on parked tasks that hold a terminal error marker. Manual `hive markers clear` remains the fallback/escape hatch.

**Goal:** Automatically clear and retry tasks parked on a *known recoverable* error marker once the underlying dependency is verified healthy again — without ever touching unknown errors, business-logic failures, or markers where retry could discard user work.

### Scope (v1 allowlist — fixed, not a broad "transient" category)
- `implementer_failed` **only** when diagnostics classify it as a Codex auth failure (401 missing bearer/basic auth).
- `claude_launch_failed` **only** when the launcher/wrapper/readiness health probe now passes.
- Explicitly excluded: business-logic failures, test failures, review findings, merge conflicts, dirty-worktree failures, unknown `exit_code=1`, and any marker without a recognized diagnostic signature.

### Health probes (must pass before retry)
- **Universal precondition:** a lightweight `hive doctor` / agent-health pass for required agent skills.
- **Codex auth recovery:** `codex login status` shows logged in AND a tiny `codex exec` smoke test succeeds in the same environment the daemon will use.
- **Claude launcher recovery:** wrapper file exists in the active install + ready-detector check/fixtures pass + active daemon binary/version matches the CLI + `hive doctor` green.

### Probe execution model
- Mix: in-process helpers for Hive-owned checks; shell out for external CLIs (`codex`, `claude`, `gh`) where auth/runtime behavior lives.
- Each probe has a short timeout (10–30s by command); capture stdout/stderr into audit logs.
- Timeout or error ⇒ treat as "not healthy, do not retry."
- Cache probe results per daemon tick/reason to avoid noisy repeated CLI calls for parked markers.

### Trigger & cadence
- Evaluate recoverable parked markers on daemon ticks, throttled per task/reason.
- Re-probe when a **health signal changes**: daemon binary path/version/fingerprint, relevant config/env, plugin/skill inventory, Codex login state, wrapper file mtime, or a manual marker-clear/retry event.
- Low-frequency periodic re-probe allowed as a fallback (not every 30s for expensive probes).

### Retry limits & backoff
- Max **2 auto-retries** per task per marker reason.
- A changed health signal since the last failed attempt is required before retrying again.
- Backoff: immediate after first healthy signal, then 30 minutes after a second healthy signal.
- On exhaustion: park permanently on the marker; require manual `hive markers clear`.

### Safety guard — never discard user work
- Auto-retry only when the failed stage produced no terminal success output and the work area is safe.
- Execute stage: worktree must be clean or contain only Hive/agent-generated files known safe for that stage; no uncommitted user edits.
- Brainstorm/plan launcher failures: no answered user content would be overwritten.
- When uncertain: do not auto-retry.

### Mechanics
- Auto-retry is equivalent to manual `hive markers clear` + re-enqueue/run the same stage from the start. No special resume path in v1.
- Rest of the pipeline sees the same state transitions/markers as a manual recovery.

### Audit & observability
- Record decisions in both task `events.jsonl` and the daemon log.
- Fields: task slug/id, stage, marker id, reason, probe names/results, health-signal fingerprint, auto-retry attempt count, action taken, rationale, timestamp.
- Also record negative (not-retried) decisions at a throttled rate (e.g. "not retried: codex smoke failed", "not retried: unknown reason").

### Config
- Enabled by default for v1 allowlisted recoveries only.
- Global kill-switch: `daemon.auto_retry.enabled: false`.
- Per-reason limits/backoff config deferred; v1 stays conservative and hardcoded enough to be safe.

### Acceptance examples
- ✅ Task-58-style Codex auth `implementer_failed` auto-clears and retries within one daemon/probe cycle after `codex login status` + smoke test pass, emitting an audit event.
- ✅ Task-287-style `claude_launch_failed` auto-clears only after wrapper/detector/binary-version/doctor checks pass, emitting an audit event.
- ✅ Unknown `implementer_failed` (no recognized signature) remains parked — no auto-clear.
- ✅ Repeated failures respect the 2-retry limit and backoff; exhausted tasks park permanently for manual clear.
- ✅ Dirty worktree or ambiguous partial output ⇒ not retried.
- ✅ Probe hang/error ⇒ treated as not healthy ⇒ not retried.
- ✅ Kill-switch off ⇒ no auto-retry behavior at all.

<!-- COMPLETE -->
