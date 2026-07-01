# Plan: fix-claude-tmux-ready-detector

## Overview

Two coupled defects break `hive run` in Claude tmux mode on a clean release-gem install with Claude Code 2.1.179:

1. **Packaging.** `hive.gemspec` ships `spec.files = Dir["lib/**/*.rb", ...]` — `.rb` only. The shell scripts `ClaudeLauncher` depends on (`lib/hive/scripts/interactive_claude_wrapper.sh`, referenced at `claude_launcher.rb:471`, and `lib/hive/scripts/stop_hook.sh`, referenced via `StopHookInstaller::HOOK_PATH` at `stop_hook_installer.rb:7` and installed from `ClaudeLauncher.with_shared_session`) are never packaged. `bash <missing-file>` exits instantly, the tmux session dies, and Hive reports `claude_launch_failed` / "can't find pane". This confirms brainstorm A4 — root cause is the gemspec file glob, not `.gitignore`.

2. **Detection.** Once the wrapper exists, the 2.1.179 idle prompt is not recognized. The caret uses a non-breaking space after `❯`, and the input box ends with separator / caret / separator / footer. The current detector (`claude_ready_prompt?`) narrows the pane to the last `CLAUDE_PROMPT_CONTEXT_LINES = 4` nonblank lines, then scans only the last `CLAUDE_PROMPT_TAIL_LINES = 3` for `CLAUDE_READY_PROMPT_LINE = /\A❯(?:\s| |\z)|\s❯\z/`. This is brittle: the window is too shallow and footer-distance-coupled, and only ` ` (not the full `\p{Zs}` separator class) is tolerated, and only after a *start* caret — not before an *end* caret.

The work delivers: a gemspec/build file-list fix, a built-gem packaging guard that enumerates every script `ClaudeLauncher` touches, a version-tolerant ready detector, and focused detector regression + rejection tests. Publishing a new `hive-cli` version and fixing daemon/systemd binary drift are explicitly out of scope (brainstorm A5/A6).

## Requirements Trace

| Req (from brainstorm) | Addressed by |
| --- | --- |
| Package `lib/hive/scripts/**/*.sh` (and any script referenced by `ClaudeLauncher`) into the gem (A4, Scope IN) | U1 |
| Built-gem packaging guard: build real `.gem` in CI, assert every script referenced by `ClaudeLauncher` is inside it; enumerate all references, future-proof (A3) | U2 |
| Lighter unit check that `spec.files` includes the script glob (A3) | U1 (extends `gemspec_test.rb`) |
| Version-tolerant detector: scan last 8–12 nonblank lines, tolerate `\p{Zs}`/ASCII/NBSP/EOL after `❯`, keep trailing `❯` form, no fixed footer offset (A1, Detector behavior) | U3 |
| Include exact 2.1.179 shape as a regression case but don't hardcode footer offset (A1) | U3 + U4 |
| Hand-authored fixtures: 2.1.179 ready (NBSP, separator/caret/separator/footer) + prior ready shape (A2) | U4 |
| Rejection fixtures: permission, trust, menu states must NOT read as ready (A2) | U4 |
| Source changes + tests only; no publish; built-gem verification so a release build would pass (A6) | U1–U4 (no version bump / no publish) |
| Daemon/systemd binary drift: document as e2e validation note only, no code fix (A5) | U5 |
| Acceptance: reproduced task `.../2-brainstorm/add-local-hive-web-install-260629-f4ca` reaches `WAITING`; `hive doctor` stays green | U5 (validation notes) |

## Scope Boundaries

**IN**
- `hive.gemspec` file-list fix so all `lib/hive/scripts/**/*.sh` ship.
- Unit assertion in `test/unit/gemspec_test.rb` that the script glob is present.
- New built-gem guard that builds the real artifact and asserts every `ClaudeLauncher`-referenced script is inside it.
- Version-tolerant rewrite of the ready detector in `lib/hive/claude_launcher.rb`.
- Hand-authored detector regression + rejection tests/fixtures.
- A documented end-to-end validation note (manual repro steps, daemon-drift caveat).

**OUT**
- Cutting/publishing `hive-cli` 0.3.3 or bumping `Hive::VERSION` (separate release step — A6).
- Fixing `/usr/bin/hive` 0.3.1 vs `~/.local/bin/hive` 0.3.2 daemon/systemd drift (A5) — documented only.
- Any change outside the detector + packaging surface (no refactor of `prepare_claude_session!` flow, trust/permission handling, or tmux runner beyond what detection needs).

## Implementation Units

### U1 — Package the launcher scripts in the gem
- **Goal:** Every script `ClaudeLauncher` shells out to is present in the built gem, so `bash <wrapper>` runs instead of exiting instantly.
- **Files:** `hive.gemspec`; `test/unit/gemspec_test.rb`.
- **Approach:**
  - In `spec.files`, add an explicit glob for the scripts directory: `"lib/hive/scripts/**/*.sh"` (alongside the existing `"lib/**/*.rb"`). Prefer the narrow `**/*.sh` over a broad `lib/hive/scripts/**/*` so editor/backup cruft is not packaged; both currently-shipped scripts (`interactive_claude_wrapper.sh`, `stop_hook.sh`) are `.sh`. <!-- hive-bench: repo-state assertion, verify against the restored base -->
  - Add a unit test `test_gem_package_includes_launcher_scripts` asserting `spec.files` includes both `lib/hive/scripts/interactive_claude_wrapper.sh` and `lib/hive/scripts/stop_hook.sh` (load via `Gem::Specification.load(GEMSPEC_PATH)`, matching the existing pattern in the file).
- **Test scenarios:**
  - `spec.files` includes the two known scripts.
  - (Negative, cheap) `spec.files` still excludes the web app — existing test stays green, confirming the glob didn't over-broaden.
- **Verification:** `rake test` (unit) green; `gem build hive.gemspec` then `tar -tf` / `gem contents`-style inspection shows the scripts (covered formally by U2).

### U2 — Built-gem packaging guard (enumerated, future-proof)
- **Goal:** A release-representative test that builds the actual `.gem` and fails if *any* script referenced by `ClaudeLauncher` is missing from the packaged artifact — so a future script can't silently drop out (A3).
- **Files:** new `test/integration/gem_package_scripts_test.rb` (integration tier so the default `rake test` FileList picks it up; it shells out to `gem build`, which is heavier than a pure unit test).
- **Approach:**
  - Enumerate the script references rather than hardcoding one path. Derive the list from the code so new references are caught:
    - `Hive::ClaudeLauncher` direct reference: `lib/hive/scripts/interactive_claude_wrapper.sh` (the `wrapper_command` path).
    - `Hive::StopHookInstaller::HOOK_PATH` → `lib/hive/scripts/stop_hook.sh`, reachable from `ClaudeLauncher.with_shared_session`.
  - Concretely: grep `lib/hive/claude_launcher.rb` and `lib/hive/stop_hook_installer.rb` for `scripts/...\.sh` literals and `File.expand_path("scripts/..."` patterns, collect the basenames, and assert each appears in the packaged gem. This keeps the guard "enumerate all references, future-proof": a newly added `scripts/foo.sh` reference is discovered by the grep and must then be packaged.
  - Build into a tmp dir: `gem build hive.gemspec` (or `Gem::Package.build(Gem::Specification.load(...))`) and read the entry list via `Gem::Package.new(path).spec.files` or by unpacking. Skip/build-guard if `gem` is unavailable in the runner (use Minitest `skip` with a clear message rather than a hard failure on environments without a build chain).
  - Assert: every enumerated script basename resolves to a packaged path under `lib/hive/scripts/`.
- **Test scenarios:**
  - Built gem contains `interactive_claude_wrapper.sh` and `stop_hook.sh`.
  - Guard would fail if a referenced script were absent (validate the enumeration logic against a synthetic missing entry, or assert the enumerated set is non-empty and each maps to a real source file before checking the gem — so an empty/over-narrow enumeration can't pass vacuously).
- **Verification:** `rake test` runs it; in CI it runs on the same runner that already does `gem build hive.gemspec` (`release.yml`). Confirm it is part of the default suite FileList (`test/{unit,integration,babysitter}/**/*_test.rb`).

### U3 — Version-tolerant ready detector
- **Goal:** Recognize the 2.1.179 idle prompt (NBSP after `❯`; separator/caret/separator/footer) and tolerate future Claude TUI tweaks, without misreading permission/trust/menu states or mid-output carets as ready.
- **Files:** `lib/hive/claude_launcher.rb` (`claude_ready_prompt?`, `current_prompt_text`, and the `CLAUDE_READY_PROMPT_LINE` / `CLAUDE_PROMPT_TAIL_LINES` / `CLAUDE_PROMPT_CONTEXT_LINES` constants).
- **Approach:**
  - **Whitespace tolerance.** Broaden `CLAUDE_READY_PROMPT_LINE` from ` `-only to the full Unicode separator class on *both* sides of the caret: start form `\A❯(?:[\p{Zs}\s]|\z)` and end form `(?:[\p{Zs}\s])❯\z` (so an NBSP or narrow-no-break-space *before* an end caret also matches). Keep the bare-caret (`\A❯\z`) and menu-exclusion (`CLAUDE_MENU_OPTION_LINE`) behavior. Note: Ruby `String#strip` does **not** remove `\p{Zs}` (e.g. NBSP), so a stripped caret line retains its NBSP and the regex must account for it — do not rely on `strip` to normalize separators.
  - **Wider scan window, content-anchored (no fixed footer offset).** Raise the window to ~8–12 nonblank lines (set `CLAUDE_PROMPT_TAIL_LINES`/`CLAUDE_PROMPT_CONTEXT_LINES` to cover 8–12; reconcile the two constants so the context slice isn't narrower than the scan). Rather than "caret must be within the last N lines" (a fixed footer-distance rule that breaks when the footer grows), find the **last** caret-matching line in the window and accept it as ready **iff every line below it (to the pane end) is chrome**: a footer hint (`for agents`, `⏵⏵ bypass permissions …`), a box/separator rule (runs of `─ ━ │ ┄ ┈ ?───…` box-drawing/dash glyphs), or blank/whitespace-only. This drops the fixed-distance dependency (any number of chrome lines may follow the caret) while still rejecting a caret with real output below it.
  - **Keep the negative guards unchanged and first:** trust markers (`CLAUDE_TRUST_PROMPT_MARKERS`), permission marker (`CLAUDE_PERMISSION_PROMPT_MARKER`), and the positive banner/footer gate (`CLAUDE_READY_BANNER_MARKER` || `CLAUDE_READY_FOOTER_MARKER`). Misreading a trust/permission prompt as ready is the dangerous case (per the existing code comment) — these stay as hard `return false`s.
  - **Preserve scrollback rejection:** keep `current_prompt_text`'s anchoring to the last banner / last blank line so a stale caret separated from the live box by a blank line (`rejects_stale_prompt_marker_in_scrollback`) still does not count. The wider window applies *within* the current input region, not across the whole scrollback.
  - Update the constant doc comments to record the 2.1.179 shape and the chrome-aware rule, and to state explicitly that footer distance is not assumed.
- **Test scenarios:** (assert/refute via the public `Hive::ClaudeLauncher.claude_ready_prompt?`)
  - ACCEPT: 2.1.179 ready pane — separator / `<cwd> <git>  ❯` with NBSP / separator / `⏵⏵ … for agents` footer.
  - ACCEPT: prior shapes still pass — last-nonblank `❯ Try …`, end-caret + single hint footer, footer-only when banner scrolled out, bare `❯`.
  - REJECT: permission prompt (`Do you want to …`), trust prompt (`Quick safety check` + `Yes, I trust this folder`), numbered menu (`❯ 1.`) with and without a footer.
  - REJECT: caret embedded mid-line (Claude's own output); caret with real non-chrome output below it (`running build step 1/2`); stale caret in scrollback separated by a blank line.
- **Verification:** `rake test` green including every existing `test_claude_ready_prompt_*` (no regressions) plus the new 2.1.179 cases; `rake coverage` 100%-line gate holds for the touched methods.

### U4 — Detector regression + rejection fixtures and tests
- **Goal:** Lock the 2.1.179 behavior and the rejection invariants with hand-authored fixtures from the incident (A2).
- **Files:** `test/unit/claude_launcher_test.rb` (inline pane strings, matching the existing `test_claude_ready_prompt_*` style). Optionally add raw-capture fixture files under `test/fixtures/` later, but do not block on them (A2).
- **Approach:**
  - Add named tests for each scenario in U3, using the exact incident shape: non-breaking space (` `) after `❯`, and the separator/caret/separator/footer layout. Include a comment citing Claude Code 2.1.179 and the incident, mirroring the existing dated comments.
  - Add the "prior ready shape" as an explicit regression test so the widened window doesn't silently change pre-2.1.179 behavior.
  - Add/keep rejection tests for permission, trust, and menu states (with and without a footer line beneath).
- **Test scenarios:** as enumerated in U3 (this unit is where they're authored).
- **Verification:** `rake test` green; deliberately reverting the U3 change should turn the new 2.1.179 acceptance test(s) red (the test actually guards the fix).

### U5 — End-to-end validation + daemon-drift documentation note
- **Goal:** Record how to validate the fix end-to-end and capture the out-of-scope daemon/systemd drift as a note only (A5), so the next stage and the operator know the manual checks.
- **Files:** validation notes captured in the execute stage's deliverable (e.g. PR description / a short note under `docs/` if the repo convention calls for it) — **no** detector/daemon code change here.
- **Approach (documented steps, run in execute/validation, not in this plan stage):**
  - Build the gem locally, install into a sandbox `GEM_HOME`, and run `hive run <REPO_ROOT>/.hive-state/stages/2-brainstorm/add-local-hive-web-install-260629-f4ca` in Claude tmux mode; confirm it reaches `WAITING` (not `claude_launch_failed`) with no manual copying into the installed gem.
  - Confirm `hive doctor` stays green with the Compound Engineering plugin installed.
  - Note the daemon binary drift (`/usr/bin/hive` 0.3.1 vs `~/.local/bin/hive` 0.3.2) as a known, separate issue for the local-setup/daemon-auto-retry work — call out that an operator may need to ensure the daemon picks up the patched install when testing.
- **Test scenarios:** manual/e2e only (the automated guards are U1–U4).
- **Verification:** the reproduced task advances past launch; doctor green. These are acceptance checks, not unit tests.

## Risks

- **R1 — Widening the scan window regresses existing rejection tests.** `rejects_caret_above_the_input_box_tail` (caret with build output below) and `rejects_stale_prompt_marker_in_scrollback` (caret + blank + later output) currently pass *because* the window is shallow. A naive bump to 8–12 lines would flip them green-to-red (false "ready"). Mitigation: the chrome-aware rule in U3 (caret ready only if all lines below it are footer/separator/blank) plus retaining `current_prompt_text`'s blank/banner anchoring. **This is the central design decision — see Open Questions Q1.** <!-- hive-bench: repo-state assertion, verify against the restored base -->
- **R2 — Over-broad separator/chrome matching.** Treating any line below the caret as "chrome" would let a stale caret with trailing output read as ready. Keep the chrome predicate tight (explicit footer markers + box-drawing/dash glyphs + whitespace-only), and cover it with the negative tests in U4.
- **R3 — Built-gem guard flakiness / environment.** `gem build` may be slow or unavailable on some runners. Mitigation: `skip` cleanly when `gem` is absent, keep the lighter `spec.files` unit check (U1) as the always-on signal, and ensure the guard is non-vacuous (enumeration asserted non-empty and source-resolvable before checking the artifact).
- **R4 — `\p{Zs}` vs `\s` interaction and `strip`.** Ruby `\s` is ASCII-only by default and `String#strip` leaves `\p{Zs}` (NBSP) in place; an incorrect combination could either miss NBSP or accidentally accept a mid-line caret. Mitigation: explicit `[\p{Zs}\s]` classes anchored with `\A`/`\z`, plus the embedded-caret rejection test.
- **R5 — Coverage gate.** The repo enforces a 100%-line coverage gate (`rake coverage`). New branches in the detector and the guard must be exercised by U4/U2 tests or the gate fails. Mitigation: author tests alongside each new branch.
- **R6 — Scope creep into the launch flow.** Touching `prepare_claude_session!` / trust handling beyond detection risks unrelated regressions. Mitigation: keep changes confined to `claude_ready_prompt?`, `current_prompt_text`, and the related constants.

## Open Questions

- **Q1 (design — needs confirmation).** The brainstorm asks to "scan the last 8–12 nonblank lines" and "not depend on a fixed footer distance," but two existing tests (`rejects_caret_above_the_input_box_tail`, `rejects_stale_prompt_marker_in_scrollback`) rely on a shallow window to reject a caret that has real output/scrollback below it. This plan proposes the **chrome-aware** rule (U3/R1): widen the search to find the caret, but only accept it when every line below it is footer/separator/blank — preserving those rejections. Confirm this is the intended behavior. The alternative (a plain N-line window that accepts the last caret regardless of what's below it) is simpler but would relax those two rejection guarantees — please confirm you do **not** want that.
- **Q2.** For the packaging glob (U1), confirm the narrow `lib/hive/scripts/**/*.sh` is acceptable (vs. a broader `lib/hive/scripts/**/*` that would also ship any future non-`.sh` asset placed there). Default in this plan: narrow `**/*.sh`.

<!-- COMPLETE -->
