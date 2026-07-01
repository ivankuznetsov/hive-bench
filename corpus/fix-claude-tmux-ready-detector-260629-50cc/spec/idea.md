---
slug: fix-claude-tmux-ready-detector-260629-50cc
created_at: 2026-06-29T09:34:24Z
original_text: |
  Fix Claude tmux ready detector and package wrapper
---

# fix-claude-tmux-ready-detector-260629-50cc

Fix two issues found while trying to run Hive 0.3.2 locally with Claude Code
2.1.179 in tmux mode.

## Incident

Task `add-local-hive-web-install-260629-f4ca` was blocked in
`2-brainstorm` with `claude_launch_failed`.

After installing the real agent plugins (`EveryInc/compound-engineering-plugin`
for Claude/Codex/Pi) and making `hive doctor` pass, the stage still failed
before Claude could run.

First failure:

- `hive run .../2-brainstorm/add-local-hive-web-install-260629-f4ca`
  created a tmux session that disappeared immediately.
- Hive reported:
  `could not inspect claude tmux session ... tmux capture-pane ... failed:
  can't find pane`.
- Root cause: the installed `hive-cli-0.3.2` gem did not contain
  `lib/hive/scripts/interactive_claude_wrapper.sh`, but
  `Hive::ClaudeLauncher.wrapper_command` builds an argv pointing at that
  script inside the gem. `bash <missing-file>` exits immediately, closing the
  tmux session before Hive can inspect it.

Second failure after restoring the wrapper locally:

- Claude Code stayed alive in tmux, but Hive never detected the idle prompt
  and timed out with:
  `claude interactive prompt did not become ready in tmux session ...`.
- Captured Claude Code 2.1.179 prompt shape:
  - The prompt line is `❯ Try "fix lint errors"` where the character after
    `❯` is a non-breaking space, not a normal ASCII space.
  - The bottom of the input box is now:
    1. separator line
    2. prompt/caret line
    3. separator line
    4. footer line: `⏵⏵ bypass permissions on ... ← for agents`
- Existing detector in `lib/hive/claude_launcher.rb` only checked the last
  two nonblank lines, so it saw the separator/footer and missed the caret
  line. It also used `\s` after `❯`, which did not match the non-breaking
  space observed in the tmux capture.

## Local workaround applied

These local changes made the blocked brainstorm task work:

- Copied `lib/hive/scripts/interactive_claude_wrapper.sh` from the source
  checkout into:
  `<REPO_ROOT>/share/hive/gems/gems/hive-cli-0.3.2/lib/hive/scripts/interactive_claude_wrapper.sh`
- Patched both the installed gem and source checkout:
  - `CLAUDE_READY_PROMPT_LINE` from
    `/\A❯(?:\s|\z)|\s❯\z/`
    to
    `/\A❯(?:\s|\u00A0|\z)|\s❯\z/`
  - `CLAUDE_PROMPT_TAIL_LINES` from `2` to `3`.

After that, Hive pasted the brainstorm prompt into Claude and the task moved
to `WAITING`.

## Desired fix

- Ensure release packaging includes
  `lib/hive/scripts/interactive_claude_wrapper.sh` in the `hive-cli` gem.
- Update Claude tmux ready detection to handle Claude Code 2.1.179's prompt:
  - non-breaking space after the `❯` caret;
  - separator/prompt/separator/footer layout at the bottom of the input box.
- Add or update focused tests so the detector accepts captured pane text from
  current Claude Code and still rejects permission/trust prompts and menu
  selections.
- Add a packaging/release test that fails if any script referenced by
  `ClaudeLauncher.wrapper_command` is missing from the built gem.

## Extra related finding

The new daemon-dispatched task for this idea was picked up automatically, but
it failed again because the running daemon/systemd path is still using
`/usr/bin/hive` / old 0.3.1 packaging, not the patched
`<REPO_ROOT>/bin/hive` 0.3.2 install. This is separate from the
detector bug, but it is relevant when validating the fix end-to-end.

## Acceptance

- On a clean install of Hive from the release gem, `hive run` in Claude tmux
  mode can start Claude, detect the idle prompt, paste the stage prompt, and
  reach a terminal marker.
- The built gem contains every script referenced by `ClaudeLauncher`.
- `hive doctor` remains green when the Compound Engineering plugin is
  installed.
- No manual copying into the installed gem is required.
- The reproduced task shape works:
  `hive run <REPO_ROOT>/.hive-state/stages/2-brainstorm/add-local-hive-web-install-260629-f4ca`
  reaches `WAITING` instead of `claude_launch_failed`.

<!-- WAITING -->
