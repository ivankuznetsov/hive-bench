# Brainstorm: add-i-key-with-legend-260522-ca28

**Seed idea:** add i key with legend here

**Context from screenshot (`assets/bug-1.png`):** Hive TUI legend bar at bottom of screen showing existing bindings: `[Tab] switch  [Enter] action  [n] new  [/] filter  [?] help  [q] quit`. The selected card header reads `we-need-to-collect-artifacts-260514-402f`.

## Round 1

### Q1. What action should the `[i]` key trigger? Best guess: open a detail / inspect view for the currently selected card (showing full idea text, history, logs, file paths). Is that right, or do you mean something else (e.g. "info" popup, edit idea, etc.)?
### A1.

### Q2. Where exactly should the `[i]` entry appear in the legend bar? Suggested placement: between `[?] help` and `[q] quit` → `… [?] help  [i] info  [q] quit`. Or do you want it nearer the action keys, e.g. right after `[Enter] action`?
### A2.

### Q3. What label text should follow `[i]` in the legend? Candidates: `info`, `inspect`, `details`, `view`. Which word do you want?
### A3.

### Q4. What surface should the `i` action open the details into? Options: (a) full-screen modal view inside the TUI, (b) split pane on the right, (c) shell out to `$PAGER`/`less` with rendered markdown, (d) just print to stderr and exit. Pick one.
### A4.

### Q5. Which fields/content should the detail view show for a card? Minimum guess: slug, stage, created_at, full idea text, path to working dir, last log file. Anything else (round history, brainstorm.md contents, recent commits)?
### A5.

### Q6. Should `[i]` work on every stage's card (1-inbox, 2-brainstorm, 3-plan, 4-execute) the same way, or behave differently per stage (e.g. show plan.md in 3-plan, execute log in 4-execute)?
### A6.

### Q7. How does the user close the detail view and return to the list? Suggested: any of `q`, `Esc`, or `i` again. Confirm preferred keys.
### A7.

### Q8. Acceptance: when I press `i` on a card in the main TUI, ____ happens, and the legend bar visibly shows `[i] <label>`. Please complete the blank, and add any "must not" rules (e.g. "must not block the UI", "must not require network").
### A8.

## Round 2

Round 1 came back with no answers filled in. Before I freeze a requirements doc, I want to confirm I'm not building the wrong thing. I'll proceed on the defaults below unless you override any of them in the answer slots — empty answer = accept the default.

### Q1. Default bundle — does this match what you want, or do you want to override specific items?

Defaults I'll lock in if you leave A1 blank:

- **Trigger:** `[i]` on a selected card in the main TUI list.
- **Action:** open a read-only detail/info view of that card.
- **Legend label:** `[i] info`, placed between `[?] help` and `[q] quit`.
- **Surface:** full-screen modal panel inside the TUI (no shell-out, no external pager).
- **Content shown:** slug, stage, created_at, full original idea text, working-dir path, path of latest log file. Stage-specific extras: `brainstorm.md` in 2-brainstorm, `plan.md` in 3-plan, latest execute log tail in 4-execute, none in 1-inbox.
- **Close keys:** any of `q`, `Esc`, or `i` again returns to the list.
- **Non-goals:** no editing, no network, no blocking the UI thread, no changes to existing keybindings.
- **Acceptance:** pressing `i` on any card in any stage opens the detail view within one render frame; legend bar visibly shows `[i] info`; closing returns to the same selected card.

Override any line above by replacing it in A1, or write "accept all" to lock the defaults.

### A1.

### Q2. Anything I should explicitly **not** include in scope for this change (e.g. don't touch the help screen, don't change other keybindings, don't add scrolling inside the detail view yet)? Default: scope is limited to (a) adding the `i` keybinding, (b) adding the legend entry, (c) rendering the detail view described above — nothing else.
### A2.

## Requirements

Round 1 and Round 2 were both left without explicit answers. Per Round 2's stated rule ("empty answer = accept the default"), the defaults are locked in below.

### Actor
- A hive TUI user navigating the main card list (any stage: 1-inbox, 2-brainstorm, 3-plan, 4-execute).

### Trigger & flow
- User selects a card with arrow keys / `Tab`.
- User presses `i`.
- TUI opens a full-screen, read-only **info panel** showing details for the selected card.
- User presses `q`, `Esc`, or `i` again → panel closes, focus returns to the same selected card in the list.
- Legend bar at bottom permanently shows a new `[i] info` entry, placed between `[?] help` and `[q] quit`:
  `[Tab] switch  [Enter] action  [n] new  [/] filter  [?] help  [i] info  [q] quit`

### Content rendered in the info panel
- Common to every stage:
  - `slug`
  - current `stage` (1-inbox / 2-brainstorm / 3-plan / 4-execute)
  - `created_at` (from idea.md frontmatter)
  - full `original_text` / idea body
  - absolute path to the card's working dir under `.hive-state/stages/<stage>/<slug>/`
  - absolute path to the latest log file for this card (most recent file under `.hive-state/logs/<slug>/`)
- Stage-specific extras:
  - 1-inbox: nothing extra
  - 2-brainstorm: rendered `brainstorm.md` contents
  - 3-plan: rendered `plan.md` contents
  - 4-execute: tail of the latest execute log file

### Non-goals (explicitly out of scope)
- No editing of idea / brainstorm / plan files from the panel.
- No changes to any existing keybindings (`Tab`, `Enter`, `n`, `/`, `?`, `q`).
- No network calls, no git ops, no file mutations triggered by opening the panel.
- No scrolling inside the panel beyond what fits on screen for this iteration (overflow may be truncated with a `…` indicator; full scrolling can be a follow-up).
- No changes to the `?` help screen content in this change.

### Acceptance examples
- **A1 — legend visible:** Launching the TUI on any non-empty stage shows the bottom legend bar including the exact substring `[i] info` between `[?] help` and `[q] quit`.
- **A2 — open on 2-brainstorm card:** With a 2-brainstorm card selected, pressing `i` opens an info panel that shows the slug, stage `2-brainstorm`, created_at, original idea text, working-dir path, latest log path, and the rendered contents of that card's `brainstorm.md`.
- **A3 — open on 4-execute card:** With a 4-execute card selected, pressing `i` shows the common fields plus a tail of the latest execute log file.
- **A4 — open on 1-inbox card:** With a 1-inbox card selected, pressing `i` shows only the common fields; no stage-specific extras section is rendered.
- **A5 — close paths:** From the open info panel, pressing `q` closes it; from a fresh open, pressing `Esc` closes it; from a fresh open, pressing `i` closes it. After every close path, the previously selected card remains selected in the list.
- **A6 — no side effects:** Opening and closing the info panel for any card does not modify any file on disk and does not change the card's stage.
- **A7 — read-only:** Inside the info panel, typing characters other than `q`, `Esc`, or `i` does not edit or navigate; the panel stays open (any unmapped key is a no-op).

<!-- COMPLETE -->
