# fix-claude-tmux-ready-detector

## Round 1

### Q1. Detector robustness: should the fix target Claude Code 2.1.179's exact prompt shape, or aim for a version-tolerant detector?
The incident gives a specific layout (non-breaking space after `❯`; separator / caret / separator / footer at the bottom). We can either (a) hardcode the new layout — bump `CLAUDE_PROMPT_TAIL_LINES` to 3 and add ` ` — matching what you already patched, or (b) make detection look for the caret line anywhere in the last N lines and tolerate any whitespace (`\p{Zs}`/`[\s ]`) so future Claude tweaks don't re-break it. Which do you want, and how many tail lines should the scan window cover?
### A1.
Use a version-tolerant detector. The incident fix should include the exact Claude Code 2.1.179 shape, but the production detector should scan the last 8-12 nonblank lines for a prompt/caret line and tolerate Unicode separator whitespace, including NBSP. Avoid depending on a fixed footer distance.

### Q2. What is the authoritative regression fixture? Do you have raw `tmux capture-pane` dumps from Claude Code 2.1.179 (ready prompt, plus the permission/trust/menu states that must still be rejected) we can commit as test fixtures, or should the detector tests be hand-authored from the shapes described in the incident?
### A2.
Use hand-authored fixtures from the incident for the initial regression tests, because the observed shapes are known: ready prompt with NBSP after `❯`, separator/prompt/separator/footer, plus the previous ready shape. Add rejection fixtures for permission/trust/menu states. If raw tmux captures are later available, add them as higher-fidelity fixtures, but do not block this fix on them.

### Q3. Packaging guard scope: the new test should "fail if any script referenced by `ClaudeLauncher.wrapper_command` is missing from the built gem." Should this assert against the actually-built `.gem` artifact (build it in CI, inspect contents), or is it enough to assert the gemspec's `files`/`spec.files` globs include `lib/hive/scripts/**/*.sh`? And should the guard enumerate every script reference in `ClaudeLauncher` (future-proof) or just the wrapper?
### A3.
Assert against the actually built gem artifact in CI. Keep a unit-level check of `spec.files`, but the release guard should build the `.gem` and inspect that every script referenced by `ClaudeLauncher` exists in the packaged artifact. Enumerate all script references, not just the current wrapper, so future scripts cannot be missed.

### Q4. Root cause of the missing script: was `interactive_claude_wrapper.sh` excluded because the gemspec `files` list doesn't glob `lib/hive/scripts/`, because of a `.gitignore`/build-ignore rule, or some other reason? Knowing this determines whether the fix is a one-line gemspec change or something broader. If you know, what was it?
### A4.
Treat the root cause as the gemspec/build file list missing `lib/hive/scripts/**/*.sh` unless implementation proves otherwise. The fix should add that glob or equivalent explicit files, then pin it with the built-gem inspection test.

### Q5. Scope boundary on the daemon/systemd finding: the idea explicitly calls the `/usr/bin/hive` 0.3.1-vs-`~/.local/bin/hive` 0.3.2 mismatch "separate from the detector bug." Should this task (a) ignore it entirely, (b) document it for end-to-end validation only, or (c) include a fix (e.g. daemon picking up the correct install / version pinning)? 
### A5.
Do not fix daemon/systemd binary drift in this detector task. Document it as an end-to-end validation note only. The actual drift/recovery behavior belongs in the separate local setup / daemon auto-retry work.

### Q6. Release mechanics: does landing this fix require cutting a new `hive-cli` version (e.g. 0.3.3) and republishing the gem, or is the deliverable just the source changes + tests, with release handled separately? The acceptance criterion "on a clean install of Hive from the release gem ..." implies a rebuilt/republished gem — confirm whether that rebuild+publish is in scope here.
### A6.
Deliver source changes and tests in this task. Add a local built-gem verification test so a release build would pass, but publishing a new `hive-cli` version is a separate release step. The expected release vehicle would be a patch release such as 0.3.3.

## Requirements

### Actor
- Hive operator running `hive run` against a `2-brainstorm` (or any) stage in Claude tmux mode, on a clean install of the `hive-cli` release gem with Claude Code 2.1.179 and the Compound Engineering plugin installed.

### Problem (two coupled defects)
- Packaging: `Hive::ClaudeLauncher.wrapper_command` points at `lib/hive/scripts/interactive_claude_wrapper.sh`, but the built gem omits it. `bash <missing-file>` exits instantly, killing the tmux session before Hive can inspect it → `claude_launch_failed` / "can't find pane".
- Detection: after the wrapper is present, the Claude Code 2.1.179 idle prompt is not recognized. The caret line uses a non-breaking space (` `) after `❯`, and the input box now ends with separator / caret / separator / footer, so a detector that only inspects the last two nonblank lines and matches `\s` after `❯` misses the caret and times out with "claude interactive prompt did not become ready".

### Flow (desired)
1. Operator installs Hive from the release gem (no manual file copying).
2. `hive run <stage>` launches the wrapper script from inside the gem; the tmux session stays alive.
3. The ready detector scans the last 8–12 nonblank lines of the captured pane for a caret/prompt line, tolerating Unicode separator whitespace (including NBSP) after `❯`, without depending on a fixed footer distance.
4. Detector recognizes the idle prompt, Hive pastes the stage prompt, and the task advances to `WAITING` / reaches a terminal marker.

### Scope
- IN: gemspec/build file-list fix so `lib/hive/scripts/**/*.sh` (and any script referenced by `ClaudeLauncher`) is packaged; version-tolerant ready detector; focused detector tests; built-gem packaging guard; source changes + tests for a future 0.3.3 patch release.
- OUT: cutting/publishing the new `hive-cli` version (separate release step); fixing daemon/systemd binary drift (`/usr/bin/hive` 0.3.1 vs `~/.local/bin/hive` 0.3.2) — document as an end-to-end validation note only.

### Detector behavior
- Scan the last ~8–12 nonblank lines (not just the last two) for the caret/prompt line.
- Match `❯` followed by any Unicode separator whitespace (`\p{Zs}`), ASCII space, NBSP (` `), or end-of-line; keep the trailing `❯` form too.
- Include the exact Claude Code 2.1.179 shape as a regression case, but do not hardcode the footer offset.

### Test strategy
- Hand-authored fixtures from the incident for initial regression: (a) 2.1.179 ready prompt (NBSP after `❯`, separator/caret/separator/footer layout); (b) prior ready shape. Add raw `tmux capture-pane` dumps later if available, but do not block on them.
- Rejection fixtures: permission prompt, trust prompt, and menu selection states must NOT be detected as ready.
- Packaging guard: build the actual `.gem` artifact in CI and assert every script referenced by `ClaudeLauncher` exists inside it (enumerate all references, future-proof). Keep a lighter unit check that `spec.files` includes the script glob.

### Acceptance examples
- Clean install from the release gem: `hive run` in Claude tmux mode starts Claude, detects the idle prompt, pastes the stage prompt, and reaches a terminal marker — with no manual copying into the installed gem.
- The built gem contains every script referenced by `ClaudeLauncher` (packaging guard passes).
- Detector accepts the captured 2.1.179 ready pane and still rejects permission/trust/menu states.
- Reproduced task: `hive run <REPO_ROOT>/.hive-state/stages/2-brainstorm/add-local-hive-web-install-260629-f4ca` reaches `WAITING` instead of `claude_launch_failed`.
- `hive doctor` stays green with the Compound Engineering plugin installed.

<!-- COMPLETE -->
