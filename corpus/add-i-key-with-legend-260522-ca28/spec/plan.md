# Plan: add-i-key-with-legend-260522-ca28

## Overview

Hive's TUI already binds `i` in grid mode to `OpenIdeaPreview`, but the current implementation renders only a 6-row bottom strip of the task's `original_text`, dismisses on **any** keystroke, and is **not advertised in the bottom footer hint** (`[Tab] switch  [Enter] action  [n] new  [/] filter  [?] help  [q] quit`). The brainstorm asks to make `i` a first-class affordance:

1. Add `[i] info` to the footer hint between `[?] help` and `[q] quit` so the binding is discoverable without opening the `?` overlay.
2. Replace the bottom-strip preview with a **full-screen, read-only info panel** that shows the common task identity (slug, stage, `created_at`, full original idea text, working-dir path, latest log path) plus **stage-specific** extras (rendered `brainstorm.md` in `2-brainstorm`, rendered `plan.md` in `3-plan`, tail of the latest execute log in `4-execute`, nothing extra in `1-inbox`).
3. Tighten the close-key surface so **only** `q`, `Esc`, or `i` again dismiss the panel; any other key is a no-op (today every key dismisses, which makes the panel hostile to accidental keystrokes). <!-- hive-bench: repo-state assertion, verify against the restored base -->
4. Keep the existing `:idea_preview` mode symbol and the existing `OpenIdeaPreview` / `Back` message contract — the change is content + layout + close-key gating, not a new mode.

This is an **expansion** of an existing affordance, not a new mode. We keep one mode symbol, one message family, one folder of view code; we add fields to `Model`, broaden the side-effect handler that opens the panel, and replace the `IdeaPreview` view's body. The legend string change is one line. Close-key gating is one method in `KeyMap`.

## Requirements Trace

Each acceptance bullet from `brainstorm.md` maps to one or more implementation units below:

| Requirement (brainstorm) | Implementation Unit(s) |
| --- | --- |
| A1 — legend shows `[i] info` between `[?] help` and `[q] quit` | IU1 |
| A2 — `2-brainstorm` card: common fields + rendered `brainstorm.md` | IU2, IU3, IU4 |
| A3 — `4-execute` card: common fields + tail of latest execute log | IU2, IU3, IU4 |
| A4 — `1-inbox` card: common fields, no extras | IU2, IU3, IU4 |
| A5 — close on `q`, `Esc`, or `i` again; returns to same selected card | IU5 |
| A6 — open/close does not mutate any file or stage | IU2, IU4 (read-only side-effect path) |
| A7 — unmapped keys are a no-op inside the panel | IU5 |
| Legend label exactly `[i] info` between `[?] help` and `[q] quit` | IU1 |
| Working-dir path (absolute, under `.hive-state/stages/<stage>/<slug>/`) | IU2, IU4 |
| Latest log path (most recent file under `.hive-state/logs/<slug>/`) | IU2, IU4 |
| `created_at` sourced from `idea.md` frontmatter | IU4 |
| Stage-specific extras gating by `row.stage` | IU3, IU4 |
| No editing, no network, no scrolling, no help-screen change | Scope Boundaries |
| Help overlay description for `i` reflects the new behaviour | IU5 |

## Scope Boundaries

**In scope**

- One-line footer-hint string change in `Hive::Tui::BubbleModel#footer_hint`.
- A new `Model` info-panel state bundle (replaces `idea_preview_text` / `idea_preview_slug` or augments it — see IU2).
- Side-effect handler `BubbleModel#open_idea_preview` rewritten to gather all common + stage-specific content at open time (one read pass per file; no polling).
- `Views::IdeaPreview` rewritten from a 6-row bottom strip into a full-screen panel renderer that fills the available area (no scrolling; oversize content is truncated with a trailing `…`).
- `KeyMap#idea_preview_message` tightened from "any key → BACK" to "q/Esc/i → BACK; everything else → NOOP".
- `Help::BINDINGS` entry for `i` updated to describe the new behaviour and the `:idea_preview` mode entry updated to list the explicit close keys.
- Unit tests for: legend string, footer hint width, KeyMap close-key gating, view rendering per stage, side-effect handler for each stage, help-overlay BINDINGS contents.
- Test factories for `Row` / `Snapshot` get a `created_at` source path via `idea.md` (same path the existing `open_idea_preview` already uses).

**Explicitly out of scope (deferred or refused)**

- No new keybinding constants, no `i`-mode-switch from any sub-mode other than grid (the panel only opens from `:grid`).
- No editing affordance, no `$EDITOR` shell-out, no markdown-to-ANSI rendering library — `brainstorm.md` / `plan.md` are shown as plain UTF-8 with newline-wrap and width-truncate, same as `IdeaPreview`'s existing `wrap_text` helper.
- No scrolling inside the panel; oversize content is truncated with `…` (brainstorm A1 default and Q2 default — already locked in).
- No changes to the `?` help overlay layout, just the existing `BINDINGS` text.
- No changes to any other keybinding (`Tab`, `Enter`, `n`, `/`, `?`, `q`, `o`, `s`, verb keys).
- No git ops, no network calls, no file mutations.
- No new logging — read-only browse.
- No change to the `compose_idea_preview_view`'s `prompt_footer` wrapping: it still uses `compose_two_pane_view(footer: …)`, so the footer hint line remains visible above the panel (we just rewrite what `prompt_footer` is fed for `:idea_preview` so it occupies the full footer area, not just the 6-row strip).
  - **Caveat:** if a full-screen panel cannot be expressed cleanly through `compose_two_pane_view(footer:)`, IU3 may add a dedicated `compose_info_panel_view` that renders the panel **in place of** the two-pane layout. See IU3 for the decision.
- No change to `legacy_stage_dirs` / `legacy_migrate_command` surfacing — those stay in `ProjectsPane`.
- No change to `OpenTaskFolder` (`o`) — it remains the editor-shell-out browse path, distinct from the in-TUI info panel.

## Implementation Units

### IU1 — Add `[i] info` to the bottom footer hint

**Goal**: The static bottom legend line, rendered in `:grid` mode (and on the `default_footer` fallback in every sub-mode that uses it), shows `[i] info` between `[?] help` and `[q] quit`.

**Files**

- `lib/hive/tui/bubble_model.rb` (single `footer_hint` method, line ~3100)
- `test/unit/tui/bubble_model_test.rb` (or wherever `footer_hint` is asserted; add a test if none exists)

**Approach**

- Change `footer_hint` to return `"[Tab] switch  [Enter] action  [n] new  [/] filter  [?] help  [i] info  [q] quit"`.
- Two spaces between groups, mirroring the existing separator (the existing string uses `  ` — verify byte-for-byte by re-checking the literal before edit).
- No conditional logic — the binding always exists in grid mode and the legend should always show it. Sub-modes already replace the footer (`prompt_footer`), so this string only renders when `default_footer` is called. <!-- hive-bench: repo-state assertion, verify against the restored base -->
- Mind the `Views::Format.truncate(line, usable_width)` clamp in `default_footer` — the new string is 7 chars longer (76 → 83 cols), so terminals between 76–82 cols that previously fit the full hint will start truncating the `q] quit` tail. This is acceptable (the help overlay still lists `[q] quit`), but the truncate behaviour should be re-asserted in a test so a future change doesn't accidentally clip `[i] info` instead.

**Test scenarios**

- `footer_hint` returns the literal new string (exact-string assertion, including separator widths).
- The substring `[i] info` appears between `[?] help` and `[q] quit` and not adjacent to any other label (regex check).
- `default_footer` at `cols=120` renders the full hint and includes `[i] info`.
- `default_footer` at `cols=70` truncates from the right (i.e., `[i] info` survives if `[?] help` survives — order is preserved); add an assertion that the truncation point doesn't fall in the middle of the `[i] info` token at typical breakpoints (≥80 cols). A snapshot-style fixed-width assertion is fine here; behaviour on `cols<70` is already governed by `Model::TWO_PANE_MIN_COLS` and is out of scope.

**Verification**

- `bin/rake test TEST=test/unit/tui/bubble_model_test.rb` passes.
- `bin/hive tui` (manual smoke) at ≥80 cols visually shows `[i] info` in the bottom strip when the grid is focused.

---

### IU2 — Extend `Model` with info-panel state fields

**Goal**: `Hive::Tui::Model` can carry the data the info panel needs without the view doing I/O. Open-time the side-effect handler populates the fields; close-time `apply_back` clears them.

**Files**

- `lib/hive/tui/model.rb`
- `test/unit/tui/model_test.rb`
- `test/unit/tui/update_test.rb` (back-from-`:idea_preview` already exists; extend to cover new fields)

**Approach**

Add new fields to the `Data.define` (keep the existing `idea_preview_text` / `idea_preview_slug` for the existing test surface — they will be **subsumed** by a structured `InfoPanelState` record but kept as convenience readers for the renderer):

```ruby
:info_panel_state  # Hive::Tui::Model::InfoPanelState or nil — :idea_preview mode only
```

Define `Model::InfoPanelState`:

```ruby
Model::InfoPanelState = Data.define(
  :slug,             # String
  :stage,            # String — "1-inbox" / "2-brainstorm" / "3-plan" / "4-execute"
  :created_at,       # String or nil — verbatim from idea.md frontmatter
  :original_text,    # String — capped to NEW_IDEA_BUFFER_MAX_CHARS
  :folder_path,      # String — absolute, under .hive-state/stages/<stage>/<slug>/
  :latest_log_path,  # String or nil — absolute path of most recent file under .hive-state/logs/<slug>/
  :stage_extra       # String or nil — rendered brainstorm.md / plan.md / execute-log tail / nil
)
```

- `idea_preview_text` and `idea_preview_slug` get a default of `nil` and are deprecated in favour of `info_panel_state` — keep them for one release so out-of-tree forks don't break, but the new view reads from `info_panel_state`. (Document in the `Model` doc-comment that they're vestigial.) **Decision point**: if `idea_preview_text` / `idea_preview_slug` are only read by the existing view and tests, we can delete them outright. Grep on first commit; if no third-party callers, drop them and update the existing view tests in one pass.
- `apply_back` clears `info_panel_state` (and `idea_preview_text` / `idea_preview_slug` if retained).
- `Model.initial` adds `info_panel_state: nil`.

**Test scenarios**

- `Model.initial.info_panel_state` is `nil`.
- `apply_back` on a `mode: :idea_preview` model with a populated `info_panel_state` returns `mode: :grid` with `info_panel_state: nil`.
- `InfoPanelState.new(...)` round-trips its fields and is frozen.
- The existing `apply_back` test for `:idea_preview` still passes (i.e., we don't break the `idea_preview_text` / `idea_preview_slug` clear semantics).

**Verification**

- `bin/rake test TEST=test/unit/tui/model_test.rb` passes.
- `bin/rake test TEST=test/unit/tui/update_test.rb` passes.

---

### IU3 — Rewrite `Views::IdeaPreview` as a full-screen info panel

**Goal**: A new full-screen layout that fills the terminal (minus the bottom footer hint line), shows the common identity block + the stage-specific extras block + a close hint, and read-only-truncates oversize content.

**Files**

- `lib/hive/tui/views/idea_preview.rb` (rewrite body; keep file name and module path so requires don't churn)
- `test/unit/tui/views/idea_preview_test.rb` (rewrite to cover new layout)
- `lib/hive/tui/bubble_model.rb` — adjust `compose_idea_preview_view` to render the panel as the main body (in place of the two-pane grid), not as a footer strip.

**Approach**

- The view reads `model.info_panel_state` and renders a vertically-stacked layout:

  ```
  Info: <slug>                                           [stage: 2-brainstorm]
  ─────────────────────────────────────────────────────────────
  created_at:  2026-05-22T22:40:00Z
  folder:      <REPO_ROOT>/.hive-state/stages/2-brainstorm/<slug>/
  latest log:  <REPO_ROOT>/.hive-state/logs/<slug>/<file>

  Original idea
  ─────────────
  <wrapped original_text>

  brainstorm.md                              # only on :2-brainstorm
  ─────────────
  <wrapped brainstorm.md>

                                            press q / Esc / i to close
  ```

- The header / divider / footer hint use `Styles::HINT` (existing); the rest is plain text padded to `model.cols` and chunked with `Format.truncate`.
- Available row count = `model.rows - 1` (reserve one line for the bottom `[Tab] switch  …  [i] info  [q] quit` legend below the panel).
  - **Decision (single source of truth)**: `compose_idea_preview_view` invokes the new panel as the **body** and lets `default_footer` render the legend below it. The previous `prompt_footer(IdeaPreview.render(...))` call is replaced with a body-only composition: `Lipgloss.join_vertical(Lipgloss::TOP, Views::IdeaPreview.render(@hive_model, width: usable, height: panel_height), default_footer(usable))`. This keeps the bottom legend line and the footer-hint logic in IU1 reachable without the panel "owning" the footer.
- The view computes line counts before truncating: if the combined common + extras content exceeds available rows, the **stage_extra block** is truncated last, with a `…` indicator on the final visible line. The common identity block always fits (it's six small lines plus headers).
- Stage-specific extras are sourced from `info_panel_state.stage_extra` — the view does **not** know about stages directly. The handler in IU4 decides what to put in `stage_extra` based on `row.stage`.
- Reuse `wrap_text` / `chunk_buffer` / `truncate` helpers already in this file. Keep `DISMISS_HINT` but change its text to `"press q / Esc / i to close"`.

**Test scenarios**

- Renders the `Info: <slug>` header and the stage tag.
- Renders all common fields with the labels `created_at`, `folder`, `latest log`.
- Renders the `Original idea` section with the wrapped text.
- On `:2-brainstorm` stage_extra populated → renders `brainstorm.md` section.
- On `:3-plan` stage_extra populated → renders `plan.md` section.
- On `:4-execute` stage_extra populated → renders an `execute log` section.
- On `:1-inbox` stage_extra `nil` → no extras section rendered.
- Renders the close hint `"press q / Esc / i to close"` as the final visible line.
- Truncates lines to `width`.
- Truncates the extras block (not the common block) when content overflows `height`.
- Renders gracefully on `info_panel_state: nil` (returns an empty string or a single-line placeholder — pick one, document, test).

**Verification**

- `bin/rake test TEST=test/unit/tui/views/idea_preview_test.rb` passes.
- `bin/rake test TEST=test/unit/tui/bubble_model_test.rb` passes (composition test).
- `bin/hive tui` manual smoke on a card from each of the 4 stages.

---

### IU4 — Rewrite `BubbleModel#open_idea_preview` to gather all fields

**Goal**: When `OpenIdeaPreview` arrives, the side-effect handler reads `idea.md`, computes the working-dir path, finds the latest log file, and reads the stage-specific extra. It returns a Model with `mode: :idea_preview` and a fully populated `info_panel_state`.

**Files**

- `lib/hive/tui/bubble_model.rb` (`open_idea_preview` ≈ line 1611)
- `test/unit/tui/bubble_model_test.rb` (the `open_idea_preview` test exists; rewrite to cover all four stages)

**Approach**

- Pseudocode:

  ```ruby
  def open_idea_preview(row)
    return [ flashed("no idea for #{row.slug}"), nil ] if row.folder.to_s.empty?

    idea_path = File.join(row.folder, "idea.md")
    return [ flashed("no idea.md for #{row.slug}"), nil ] unless File.exist?(idea_path)

    data = idea_frontmatter(File.read(idea_path))
    original_text = data["original_text"].to_s
    if original_text.empty?
      return [ flashed("idea has no original_text for #{row.slug}"), nil ]
    end

    capped_text = original_text[0, Hive::Tui::Model::NEW_IDEA_BUFFER_MAX_CHARS]
    state = Hive::Tui::Model::InfoPanelState.new(
      slug:            row.slug,
      stage:           row.stage,
      created_at:      data["created_at"]&.to_s,
      original_text:   capped_text,
      folder_path:     File.expand_path(row.folder),
      latest_log_path: latest_log_for(row.slug),
      stage_extra:     stage_extra_for(row)
    )
    [ @hive_model.with(mode: :idea_preview, info_panel_state: state), nil ]
  rescue Errno::ENOENT, Errno::EACCES, Psych::Exception
    [ flashed("could not read idea for #{row.slug}"), nil ]
  end
  ```

- `latest_log_for(slug)` finds the most-recently-mtime'd file under `.hive-state/logs/<slug>/`. Use `Dir.glob` + `File.mtime`; return `nil` if the directory is missing or empty. The base path comes from `Hive::Paths` (look up the existing helper rather than hardcode `.hive-state/logs`). **Action**: grep `Hive::Paths` for `logs_root` or `logs_dir`; use the existing API if present, otherwise add a tiny helper in the same file (do not introduce a new public API on `Paths` for this change).
- `stage_extra_for(row)` switches on `row.stage`:
  - `"1-inbox"` → `nil`
  - `"2-brainstorm"` → `read_capped(File.join(row.folder, "brainstorm.md"))` or `nil` if missing.
  - `"3-plan"` → `read_capped(File.join(row.folder, "plan.md"))` or `nil` if missing.
  - `"4-execute"` → `tail_capped(latest_execute_log_for(row.slug))` or `nil` if no log.
  - Unknown stage → `nil` (safe fallback).
- `read_capped(path)` reads up to `NEW_IDEA_BUFFER_MAX_CHARS` bytes; `tail_capped(path)` reads the last N bytes (use a small constant like `4 * 1024` — explicit in the file, not pulled from a config). Missing file returns `nil`. **Note**: the brainstorm doesn't specify the tail size; pick a value that fits in a typical terminal screen (e.g., 32 lines worth ≈ 4KB). Document the choice in a one-line comment in code.
- All I/O is rescued with the same `ENOENT/EACCES/Psych::Exception` net the existing code uses; failures fall through to `nil` for the extra and never raise.
- The handler must **not** mutate any file, must **not** call git, must **not** spawn any subprocess — pure read of `idea.md` + `brainstorm.md` / `plan.md` / latest log file.

**Test scenarios**

- 1-inbox row: opens with `stage_extra: nil`, common fields populated.
- 2-brainstorm row with `brainstorm.md`: opens with `stage_extra` = file contents.
- 2-brainstorm row without `brainstorm.md`: opens with `stage_extra: nil` (no flash, no error).
- 3-plan row with `plan.md`: opens with `stage_extra` = file contents.
- 4-execute row with a log file: opens with `stage_extra` = tail of latest log.
- 4-execute row without any log: opens with `latest_log_path: nil` AND `stage_extra: nil`.
- Missing `idea.md`: flashes "no idea.md for <slug>", no mode change.
- `idea.md` with no `original_text`: flashes the existing message.
- Unreadable `brainstorm.md` (Errno::EACCES): opens with `stage_extra: nil`, no flash for the extra (the panel still shows the common fields).
- `row.folder` empty/nil: flashes the existing "no idea" message.
- `created_at` from `idea.md` frontmatter is propagated verbatim (string).
- The side-effect handler does not write any file (assert via Tempdir + mtime snapshot before/after).

**Verification**

- `bin/rake test TEST=test/unit/tui/bubble_model_test.rb` passes.
- Manual smoke in `bin/hive tui` against a project with cards in all four stages.

---

### IU5 — Tighten KeyMap close-keys + update Help BINDINGS

**Goal**: Inside `:idea_preview` mode only `q`, `Esc`, or `i` close the panel; every other key is a no-op. Help screen `BINDINGS` reflects the new behaviour.

**Files**

- `lib/hive/tui/key_map.rb` (`idea_preview_message`, line ~362)
- `lib/hive/tui/help.rb` (`:grid` `i` entry; `:idea_preview` entry)
- `test/unit/tui/key_map_test.rb`
- `test/unit/tui/help_test.rb`

**Approach**

```ruby
def idea_preview_message(key:, row:) # rubocop:disable Lint/UnusedMethodArgument
  return Messages::BACK if ESCAPE_KEYS.include?(key) || key == "q" || key == "i"

  Messages::NOOP
end
```

- Update `Help::BINDINGS`:
  - `{ mode: :grid, key: "i", action: :open_idea_preview, description: "open the info panel for the focused task (slug, stage, created_at, folder, latest log, original idea, and stage-specific brainstorm.md / plan.md / execute log tail)" }`
  - `{ mode: :idea_preview, key: "q",   action: :back, description: "close the info panel and return to grid" }`
  - `{ mode: :idea_preview, key: "Esc", action: :back, description: "close the info panel and return to grid" }`
  - `{ mode: :idea_preview, key: "i",   action: :back, description: "close the info panel (toggle off — same key that opens it)" }`
  - Remove the old `{ mode: :idea_preview, key: "any", action: :back, ... }` entry.

**Test scenarios**

- `KeyMap.message_for(mode: :idea_preview, key: "q", row: row)` → `Messages::BACK`.
- `KeyMap.message_for(mode: :idea_preview, key: :key_escape, row: row)` → `Messages::BACK`.
- `KeyMap.message_for(mode: :idea_preview, key: "\e", row: row)` → `Messages::BACK`.
- `KeyMap.message_for(mode: :idea_preview, key: "i", row: row)` → `Messages::BACK`.
- `KeyMap.message_for(mode: :idea_preview, key: "x", row: row)` → `Messages::NOOP` (was `BACK` before).
- `KeyMap.message_for(mode: :idea_preview, key: :key_enter, row: row)` → `Messages::NOOP`.
- After `Back` from `:idea_preview`, the previously selected `cursor` is preserved (covered in IU2's `apply_back` test).
- `Help::BINDINGS` contains the three `:idea_preview` entries and **does not** contain a `key: "any"` entry.
- The `:grid` `i` entry's description includes the words `info panel` (anchor for documentation drift).

**Verification**

- `bin/rake test TEST=test/unit/tui/key_map_test.rb` passes.
- `bin/rake test TEST=test/unit/tui/help_test.rb` passes.
- Manual smoke: pressing random letters inside the panel does nothing; pressing `q`, `Esc`, or `i` closes it; selected card remains highlighted after close.

---

### IU6 — End-to-end TUI smoke test (optional, deferred if no `tui-e2e` harness exists)

**Goal**: A single integration test that opens the TUI, navigates to a `2-brainstorm` card, presses `i`, asserts the panel shows the brainstorm.md content, presses `q`, asserts the cursor is back on the same card.

**Files**

- `test/e2e/tui_info_panel_test.rb` (only if a comparable e2e harness exists — check `bin/hive-e2e`, `test/e2e/`)

**Approach**

- **Action**: grep for `test/e2e` and `bin/hive-e2e` to decide whether to write this. If the TUI has no end-to-end harness, skip IU6 and rely on the unit tests in IU1–IU5 (rationale: unit tests already cover key-map, view, side-effect handler, model, and help).

**Test scenarios**

- See goal above; details depend on harness shape.

**Verification**

- Pass `bin/hive-e2e` (or equivalent) if implemented; otherwise omit.

## Risks

- **R1: Footer truncation at 76–82 cols** — the new hint is 7 chars longer. Terminals just above `TWO_PANE_MIN_COLS=70` will truncate from the right tail. Mitigation: IU1 explicitly tests the truncation behaviour at a chosen breakpoint. Acceptable because the help overlay still lists `[q] quit`.
- **R2: Full-screen panel composition fights `compose_two_pane_view`** — the existing helper expects a footer strip, not a body-replacing surface. IU3 commits to swapping the call site (`Lipgloss.join_vertical(panel, default_footer)`) rather than threading a "use full body" flag. Mitigation already specified in IU3.
- **R3: `created_at` field may be absent in older `idea.md` files** — `data["created_at"]&.to_s` returns `""` or `nil`; view shows `(unknown)` or omits the line. Test the missing case (IU4).
- **R4: `Hive::Paths` may not expose a logs-dir helper** — IU4 calls out a grep before implementation. If absent, a private helper inside `BubbleModel` is fine; do not add a public Paths API for this change.
- **R5: `idea_preview_text` / `idea_preview_slug` are still referenced by out-of-tree code** — local grep before deleting (IU2 decision). If retained, mark as `# @deprecated` and mirror them off `info_panel_state` on open.
- **R6: `stage_extra` content can be very large (`plan.md` can be several KB)** — capped to `NEW_IDEA_BUFFER_MAX_CHARS` for full files, and to a small byte window for the execute-log tail. The view truncates the rendered text with `…`. No scrolling planned for this iteration.
- **R7: `latest_log_for(slug)` race against an actively-writing daemon process** — `File.mtime` may flip between `Dir.glob` and `File.mtime`. Mitigation: rescue `Errno::ENOENT` from the mtime sort and fall back to "any file" if all candidates raced. Worst case: `latest_log_path` is `nil` for one render cycle. Acceptable.
- **R8: Existing tests that assert `idea_preview_text` / `idea_preview_slug` will fail if we delete them** — explicitly part of IU2's "rewrite the existing test surface" work.
- **R9: Read-only invariant** — every new file path opened by `open_idea_preview` must be opened with `File.read`, never `File.open(..., "w")`. IU4's test asserts mtimes are unchanged.

<!-- COMPLETE -->
