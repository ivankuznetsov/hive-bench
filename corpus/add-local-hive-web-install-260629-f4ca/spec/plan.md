# Plan: add-local-hive-web-install-260629-f4ca

**Title:** feat: First-class local (non-Docker) install/run mode for the Hive web UI

**Origin:** `brainstorm.md` (this stage folder)

**Target repo:** hive (this repository). All paths below are repo-relative.

---

## Overview

Today Hive's web UI (`hive web`) is effectively a Docker/hivebox-only surface. <!-- hive-bench: repo-state assertion, verify against the restored base -->
Two facts make a local, gem-installed machine a second-class web citizen:

1. **`hive web` exits 1 outside Docker or a source checkout.** `lib/hive/commands/web.rb`
   resolves the Rails app from `HIVEBOX_WEB_APP_DIR` or `web/` next to `lib/`, and the gem
   deliberately does **not** package the Rails app (`web/`) — pinned by a gemspec test. A
   user who installed Hive from the rubygem/Homebrew/AUR channels has no `web/` directory,
   so the web UI cannot start at all.
2. **No single command provisions the local web mode.** The OpenClaw skill *simulates*
   `/hive setup` by orchestrating `hive daemon install` + `hive init` from outside the CLI;
   there is no first-class `hive setup` command, no managed web service, and no in-CLI <!-- hive-bench: repo-state assertion, verify against the restored base -->
   diagnostics that verify the full local dependency set (Ruby 3.4, git, tmux, gh, claude,
   codex, node/npm, qmd, the Rails bundle, SQLite).

This plan makes local web a first-class install/run mode **alongside** Docker (Docker is not
replaced). It operates on the user's real local Hive/XDG state and checked-out repos so the
TUI and web share one source of truth. It adds: a runtime diagnostics engine, a managed
local Rails-app bundle, a loopback-default auth posture with a non-loopback guard, a managed
web service (`hive web install` / `start`) parallel to the existing daemon service, a
daemon binary-consistency check surfaced and repairable from the web UI, and a single
`hive setup` orchestrator that ties it together. The daemon and web stay separate services.

The existing supervision machinery does most of the heavy lifting and should be reused, not
reinvented: `Hive::Commands::ServiceInstaller::Base` already resolves a stable binary path
(`resolved_binary`, with Homebrew/version-manager handling — the exact mechanism that
guards against `/usr/bin/hive` drift), writes platform-native units atomically with backups,
and exposes a non-mutating `service_state` probe. `hive daemon status --json` already reports
`service_installed` / `service_enabled` / `unit_path` / `pid`. The web tier already has
`/health` (liveness) and `/health?deep=1` (daemon-pidfile readiness).

### Plan depth

**Deep.** Cross-cutting (CLI commands, Rails app, service supervision, packaging/release,
docs), touches an external contract surface (a new packaged/fetched web bundle and new
service unit templates), and carries one genuine architecture fork (web-app delivery channel).

---

## Key Technical Decisions

- **KTD-1 — Managed local web app under `${XDG_DATA_HOME}/hive/web`, mirroring the qmd
  pattern.** The gem does not package `web/` (gemspec test pins this) and packaging it would
  bloat the gem and break that contract. Instead, treat the Rails app as a Hive-owned,
  version-pinned managed dependency installed under `Hive::Paths.data_home/web` and
  `bundle install`-ed there — exactly how qmd is managed under `data_home/qmd`. `hive web`
  resolves its app dir as: `HIVEBOX_WEB_APP_DIR` → managed `data_home/web` → source-checkout
  `web/`. See **Open Questions OQ-1** for the delivery channel (release asset vs. vendored in
  gem vs. checkout-only) — the recommended channel is a per-release tarball asset fetched and
  version-checked against the CLI, but this is the one fork that benefits from user
  confirmation before execution.
- **KTD-2 — Loopback no-auth via an explicit local-mode signal, not by weakening the owner
  gate globally.** `ApplicationController#require_login` already has a `Rails.env.local?`
  tokenless exemption seam. Add an explicit `web.local_loopback` posture (env-signaled from
  `hive web` when bind is loopback) that bypasses the owner gate **only** when the bind is a
  loopback address. Binding a non-loopback address keeps the GitHub owner-claim gate and is
  *refused at the CLI* unless an owner is configured or `--unsafe`/`--allow-public` is passed.
  The GitHub device-flow/owner-claim path stays intact for Docker/hivebox and opt-in local
  use.
- **KTD-3 — Web is a separate managed service, subclassing the shared installer.** Add a
  `Hive::Commands::Web::ServiceInstaller` subclass of `ServiceInstaller::Base` with
  `service_name = "hive-web"`, new templates `examples/systemd/hive-web.service` and
  `examples/launchd/hive-web.plist`, and `ExecStart=<resolved_binary> web`. Reusing
  `resolved_binary` gives the web service the same binary-consistency guarantee as the daemon.
  Daemon and web are never merged into one unit.
- **KTD-4 — Binary consistency is verified by comparing the installed unit's `ExecStart`
  binary + that binary's `--version` against the running CLI**, surfaced in
  `hive daemon status --json` and repairable via `hive daemon install --force`. The web UI
  reads the status envelope and exposes a Repair control routed through the existing dispatch
  path.
- **KTD-5 — `hive setup` composes existing commands in-process rather than shelling out.**
  It calls the diagnostics engine, the web-bundle bootstrap, `Daemon::ServiceInstaller`,
  `Web::ServiceInstaller`, and `Commands::Init`, with non-interactive defaults and a `--json`
  envelope, so it is testable and the OpenClaw skill can delegate to it instead of
  re-orchestrating.

---

## High-Level Design

```
hive setup  (U6 — orchestrator, --json)
│
├─ U1 diagnostics ── verify Ruby3.4/git/tmux/gh/claude/codex/node/npm/qmd/bundle/sqlite
│                     (bootstrap qmd + web bundle; emit exact fix commands for the rest)
├─ U2 web bundle ─── ensure managed Rails app at $XDG_DATA_HOME/hive/web + bundle install
├─ U4 web service ── Web::ServiceInstaller (hive-web.service / local.hive-web.plist)
│                     ExecStart=<resolved_binary> web        ─┐ separate
├─    daemon ─────── Daemon::ServiceInstaller (existing) ─────┘ services
│                     + U5 binary-consistency check
└─    enroll ─────── Commands::Init / daemon enable (project enrolled for dispatch)

hive web [--bind 127.0.0.1] [--port 4567]   (U2 app-dir resolution, U3 auth posture)
   foreground always works · loopback ⇒ no auth · non-loopback ⇒ owner/--unsafe required

web UI ── reads hive daemon status --json (service_installed/enabled, binary/version drift)
          shows daemon health · Repair button ⇒ daemon install --force via dispatch  (U5)
```

Binary path (`resolved_binary`, reused by both services):
`HIVE_INVOKED_BIN` wrapper → `$PROGRAM_NAME` if path-qualified → PATH `hive`/`hv` → gem
fallback. This is the existing anti-drift mechanism; the web service inherits it unchanged.

---

## Requirements Trace

Requirements derived from `brainstorm.md` (Scope / Flow / Acceptance examples). AE-IDs map
to the brainstorm's "Acceptance examples" bullets.

| ID | Requirement | Unit(s) |
|----|-------------|---------|
| R1 | First-class local (non-Docker) web mode, alongside Docker (not replacing it) | U2, U6, U7 |
| R2 | `hive setup` — full local setup (deps, web bundle, qmd, daemon service, enrollment, web) | U6 |
| R3 | `hive web` foreground always works, with or without a managed service | U2, U3 |
| R4 | `hive web install` / `hive web start` — managed web service lifecycle | U4 |
| R5 | Operate on real local Hive/XDG state + repos; TUI and web share one source of truth; no sandbox | U2, U6 |
| R6 | Default bind `127.0.0.1:4567`; loopback requires no auth by default | U3 |
| R7 | Non-loopback bind requires auth/owner flow or an explicit unsafe flag | U3 |
| R8 | Daemon installed + running with the **same binary/version** as the CLI; project enrolled; tasks auto-picked-up | U5, U6 |
| R9 | Daemon and web are **separate** services; not merged locally | U4 |
| R10 | Web surfaces daemon health and can repair/restart it; detect drifted/stale daemon | U5 |
| R11 | Linux + macOS first; Windows out of scope | U4, U7 |
| R12 | Diagnostics verify Ruby 3.4, git, tmux, gh, claude, codex, node/npm, qmd, Rails bundle, SQLite | U1 |
| R13 | May bootstrap Hive-owned deps (qmd, web bundle); must NOT silently install/auth external agent CLIs — diagnose + emit exact fix commands | U1, U2 |
| R14 | Mirror OpenClaw local UX: zero/low-config loopback, lifecycle commands, health checks, port handling, diagnostics | U4, U6 |
| AE1 | One setup command → web at `http://127.0.0.1:4567`, daemon same-binary, repo enrolled, TUI-created task appears + auto-runs; reverse also works | U6 (+ U1–U5) |
| AE2 | Shared source of truth: TUI/web changes mutually visible (same local state) | U2, U6 |
| AE3 | Binary consistency: running daemon binary/version matches CLI; drift detected + repairable | U5 |
| AE4 | Loopback default needs no auth; non-loopback without owner/unsafe flag is refused | U3 |
| AE5 | Missing authenticated claude/codex/gh → setup reports exact fix command, does not silently fix | U1 |
| AE6 | `hive web` foreground; `hive web install` + `start` register/start a managed service; daemon service ensured independently | U4, U6 |
| AE7 | Docker/hivebox path continues to work unchanged | U7 (regression guard) |

---

## Scope Boundaries

**In scope**

- New `hive setup` command and `hive web install`/`start`/`stop`/`status` subcommands.
- A managed local Rails app dir under `${XDG_DATA_HOME}/hive/web` plus its bootstrap/bundle.
- A runtime diagnostics engine covering the full local dependency set with exact fix commands.
- Loopback-default auth posture and a non-loopback CLI guard.
- A daemon binary/version-consistency check surfaced in `hive daemon status --json` and a
  web Repair control.
- A new `Web::ServiceInstaller` + systemd/launchd templates for the web service.
- Docs: a `hive setup` reference, a README local-mode section, and operating/architecture updates.

**Out of scope (non-goals)**

- Replacing or changing the Docker/hivebox install path (it must keep working — AE7).
- Windows support (R11).
- Silently installing or authenticating external agent CLIs (claude/codex/gh) — diagnostics
  only (R13).
- Changing the GitHub device-flow / owner-claim auth model itself (it stays for Docker and
  opt-in non-loopback local use).
- Multi-user/remote hardening beyond the loopback-vs-non-loopback guard.

**Deferred to follow-up work**

- A `hive setup --uninstall` / teardown verb symmetric to setup (initial scope is provision +
  validate; `hive uninstall` already exists for service teardown).
- Auto-update of the managed web bundle on `hive update` (initial scope ensures it on setup
  and on `hive web` when missing/stale; wiring it into `hive update` can follow).
- A richer web "Diagnostics" page beyond the daemon health/repair panel.

---

## Implementation Units

### U1. Local runtime diagnostics engine

**Goal:** Provide a single in-process check that verifies the full local dependency set and,
for anything Hive must not auto-fix, emits the exact command the user should run. This is the
"diagnose, don't silently fix external CLIs" backbone (R12, R13, AE5).

**Requirements:** R12, R13, AE5. **Dependencies:** none.

**Files:**
- `lib/hive/setup/diagnostics.rb` — new module: ordered checks for Ruby ≥ 3.4, git ≥ 2.40,
  tmux ≥ 3.0, authenticated `gh`, authenticated `claude` (≥ 2.1.118), `codex` (≥ 0.125.0),
  Node/npm, qmd, the managed Rails bundle, and SQLite (sqlite3 availability for the web app).
  Each check returns a typed result `{name, status: ok|missing|version_too_old|unauthenticated,
  detail, fix_command}`.
- `lib/hive/commands/doctor.rb` — reuse existing probes where present (tmux, qmd via
  `check_llm_wiki_qmd`, agent skills/auth via `agent_profiles`) so diagnostics and `hive doctor`
  share one source of truth; have diagnostics call into the same helpers rather than duplicating
  version logic.
- `lib/hive/agent_profiles/claude.rb`, `.../codex.rb` — reuse existing auth/version probes for
  the agent-CLI rows (read-only; no behavior change expected).
- `test/unit/setup/diagnostics_test.rb` — new.

**Approach:** A pure module with injectable command-runner and PATH so checks are unit-testable
without touching the host. Classify each dependency as **Hive-bootstrappable** (qmd, web bundle —
handled in U2/U6) vs **diagnose-only** (ruby/git/tmux/gh/claude/codex/node/npm/sqlite). For
diagnose-only failures, attach an exact `fix_command` string (e.g.
`gh auth login`, `claude setup-token`, `brew install tmux`) keyed off the detected
platform/install channel (`Hive::InstallChannel.detect`). Never run a fix; only report it.
Expose an aggregate `ok?` and a `--json` friendly array consumed by U6.

**Test scenarios:**
- Happy path: all deps present/authenticated/new-enough → aggregate `ok? == true`, no fix commands.
- Missing binary: `gh` absent → row `status: missing` with the platform-appropriate install fix command.
- Version too old: `tmux 2.9` → `status: version_too_old` naming the required `>= 3.0`.
- Unauthenticated: `gh` present but `gh auth status` non-zero → `status: unauthenticated` with `gh auth login`. Covers AE5.
- Unauthenticated agent CLI: `claude` present but no token → `status: unauthenticated` with `claude setup-token`; diagnostics does NOT attempt to authenticate. Covers AE5, R13.
- Ruby too old: interpreter 3.3 → `version_too_old` naming Ruby 3.4.
- Classification: qmd missing is marked Hive-bootstrappable (not a hard fix-command row), distinguishing it from diagnose-only deps. Covers R13.
- JSON shape: aggregate serializes to a stable array of `{name,status,detail,fix_command}` for U6.

**Verification:** `ruby -Itest test/unit/setup/diagnostics_test.rb` passes; on a host with a
deliberately unauthenticated `gh`, diagnostics reports the exact `gh auth login` command and
returns non-ok without modifying anything.

---

### U2. Managed local web app bundle + `hive web` app-dir resolution

**Goal:** Make `hive web` work on a gem-only install by resolving and, when absent,
bootstrapping a Hive-owned managed Rails app under `${XDG_DATA_HOME}/hive/web` and installing
its bundle — the central gap today (R1, R3, R5). Closes the "exits 1 outside Docker/checkout" <!-- hive-bench: repo-state assertion, verify against the restored base -->
hole.

**Requirements:** R1, R3, R5, R13. **Dependencies:** U1 (for the SQLite/bundle checks it reuses).

**Files:**
- `lib/hive/web/app_bundle.rb` — new: `ensure!` (provision managed app dir + `bundle install`),
  `app_dir`, `installed_version`, `stale?` (compare against `Hive::VERSION`), and `present?`.
  Provisioning channel per **OQ-1** (recommended: fetch the per-release web tarball into
  `Hive::Paths.data_home/web`, verify version, then `bundle install`).
- `lib/hive/commands/web.rb` — extend `rails_app_dir` to add the managed `data_home/web`
  candidate between `HIVEBOX_WEB_APP_DIR` and the source-checkout `web/`; when no candidate
  exists, call `AppBundle.ensure!` (or, if `--no-bootstrap`, exit with the exact bootstrap
  command instead of the current generic guidance).
- `lib/hive/paths.rb` — add a `web_app_home` helper (`data_home/web`) alongside the existing
  XDG helpers.
- `packaging/` + release workflow (per OQ-1) — if the release-asset channel is chosen, add the
  web-bundle packaging step to `.github/workflows/release.yml` and a `packaging/` build script;
  keep `test/unit/gemspec_test.rb`'s "gem does not package web/" invariant intact.
- `test/unit/web/app_bundle_test.rb` — new.
- `test/unit/web/web_command_test.rb` — extend existing tests for the new resolution order.

**Approach:** Keep `hive web`'s existing env wiring (`SECRET_KEY_BASE`, `HIVEBOX_STORAGE_DIR`
under `state_home/web-storage`, `BUNDLE_GEMFILE`) so local and Docker share the same storage
contract and therefore the same local state (R5/AE2). The only change to the launch path is
*where the app dir comes from* and a one-time bootstrap when it is missing. `AppBundle.ensure!`
is idempotent: present-and-fresh → no-op; absent or stale → provision + `bundle install`.
The managed dir is version-stamped so `hive web` after a CLI upgrade can detect a stale bundle.

**Test scenarios:**
- Happy path (managed present): `rails_app_dir` returns `data_home/web` when it contains
  `config/application.rb`; launch argv unchanged (`bin/rails server -b <bind> -p <port>`).
- Resolution order: `HIVEBOX_WEB_APP_DIR` wins over managed; managed wins over source `web/`.
- Bootstrap on absence: no app dir anywhere → `AppBundle.ensure!` is invoked; with
  `--no-bootstrap`, the command exits non-zero printing the exact bootstrap command (not a
  generic "run from Docker" message). Covers R3, R13.
- Idempotence: `ensure!` on a present, version-matching dir performs no fetch and no
  `bundle install`.
- Staleness: managed dir stamped with an older `Hive::VERSION` → `stale? == true` and a
  reinstall is triggered/flagged.
- Shared state: `HIVEBOX_STORAGE_DIR` still resolves under `state_home/web-storage` so the
  local web reads the same SQLite/state as before. Covers AE2.
- Gemspec invariant preserved: `test/unit/gemspec_test.rb` still asserts the gem ships no `web/`.

**Verification:** On a simulated gem-only layout (no source `web/`), `hive web` provisions the
managed app and serves `http://127.0.0.1:4567`; `test/unit/web/app_bundle_test.rb` and the
extended `web_command_test.rb` pass.

**Execution note:** Start from the existing `test/unit/web/web_command_test.rb` stub-app
pattern; add a failing test for the managed-dir resolution branch before changing `web.rb`.

---

### U3. Loopback-default auth posture + non-loopback CLI guard

**Goal:** On a loopback bind, require no auth by default; on a non-loopback bind, keep the
owner gate and refuse to start without a configured owner or an explicit unsafe flag (R6, R7,
AE4).

**Requirements:** R6, R7, AE4. **Dependencies:** U2 (web must be launchable locally to test this).

**Files:**
- `lib/hive/commands/web.rb` — classify the resolved bind as loopback (`127.0.0.0/8`, `::1`,
  `localhost`); when loopback, export a `HIVEBOX_LOCAL_LOOPBACK=1` signal into the Rails env;
  when non-loopback, refuse to start unless `web.github.owner` is set or `--unsafe`
  (a.k.a. `--allow-public`) is passed — replacing/augmenting the current warn-only
  `warn_on_public_bind`.
- `web/app/controllers/application_controller.rb` — in `require_login`, short-circuit the owner
  gate when the loopback-local signal is present AND the request arrived on a loopback
  interface (defense in depth: trust the signal only for loopback peers).
- `lib/hive/config.rb` — add a `web.local_loopback` default and document the `--unsafe` posture
  in the web config block.
- `web/test/integration/loopback_auth_test.rb` — new (Rails integration).
- `test/unit/web/web_command_test.rb` — extend for the CLI bind-guard branch.

**Approach:** Two layers. CLI layer decides policy (loopback ⇒ no-auth signal; non-loopback ⇒
owner-or-unsafe). App layer enforces it without weakening the existing owner gate for Docker:
the gate is bypassed only under the explicit loopback signal and a loopback peer address, so a
mis-set signal on a public bind still cannot expose the app. The GitHub device-flow/owner-claim
routes remain available for users who opt into non-loopback with `--unsafe` or a configured
owner.

**Test scenarios:**
- Loopback no-auth: bind `127.0.0.1`, signal present, request from loopback → `/` renders
  without login. Covers AE4, R6.
- Non-loopback refused: `hive web --bind 0.0.0.0` with no `web.github.owner` and no `--unsafe`
  → command exits non-zero with guidance; server never starts. Covers AE4, R7.
- Non-loopback allowed: `--unsafe` (or configured owner) → server starts and the owner gate
  stays active (no auto-bypass on a public bind).
- Defense in depth: loopback signal present but request peer is non-loopback → owner gate still
  enforced (signal alone does not bypass).
- IPv6 loopback: `::1` classified as loopback.
- Regression: with no loopback signal (Docker posture), `require_login` behaves exactly as
  today (owner gate, owner-claim, session eviction on owner change). Covers AE7. <!-- hive-bench: repo-state assertion, verify against the restored base -->

**Verification:** `web/test/integration/loopback_auth_test.rb` passes; `hive web --bind 0.0.0.0`
without owner/unsafe is refused; `hive web` on `127.0.0.1` serves the dashboard with no login.

---

### U4. Web managed service lifecycle (`hive web install` / `start` / `stop` / `status`)

**Goal:** Add an optional managed web service via systemd-user (Linux) / launchd (macOS),
parallel to and separate from the daemon service, while keeping foreground `hive web` always
working (R4, R9, R11, R14, AE6).

**Requirements:** R4, R9, R11, R14, AE6. **Dependencies:** U2 (the service execs `hive web`,
which must resolve the managed app), U3 (bind/auth policy applies to the serviced web too).

**Files:**
- `lib/hive/commands/web/service_installer.rb` — new: subclass of
  `Hive::Commands::ServiceInstaller::Base` with `service_name = "hive-web"`, `cli_label = "web"`,
  `target_path` (`~/.config/systemd/user/hive-web.service` / `~/Library/LaunchAgents/local.hive-web.plist`),
  and `render_systemd`/`render_launchd` that read the new templates and set
  `ExecStart=<resolved_binary> web`.
- `examples/systemd/hive-web.service` — new template (mirror `hive-daemon.service`:
  `Restart=on-failure`, `StartLimitBurst`/`StartLimitIntervalSec`, `Environment=HIVE_BIN=`,
  `Environment=PATH=` placeholder rewritten by `build_path_line`).
- `examples/launchd/hive-web.plist` — new template (mirror `hive-daemon.plist`, including the
  `/bin/sh` missing-binary precheck and `KeepAlive`).
- `lib/hive/commands/web.rb` — promote `web` to a subcommand group: `install [--force]`,
  `start [--detach]`, `stop`, `status [--json]`; bare `hive web` keeps the current foreground
  behavior. `status --json` reuses `Base#service_state`.
- `lib/hive/cli.rb` — register the new web subcommands.
- `lib/hive/commands/uninstall.rb` — include `hive-web` in service teardown alongside daemon/bot.
- `test/unit/commands/web/service_installer_test.rb` — new (mirror the daemon installer test).
- `test/integration/web_command_test.rb` — new integration test for install/start/stop/status
  argv and exit codes (mirror `test/integration/daemon_command_test.rb`).

**Approach:** Pure reuse of `ServiceInstaller::Base` — only the identity, paths, and rendered
templates differ. Because `render_systemd`/`render_launchd` call `resolved_binary`, the web
unit inherits the same anti-drift binary path as the daemon (R8 mechanism). Foreground
`hive web` is untouched, satisfying "must always work without a service" (R3/AE6). The daemon
and web are distinct `service_name`s and distinct units — never merged (R9).

**Test scenarios:**
- Install writes unit: `hive web install` writes `hive-web.service` with
  `ExecStart=<resolved_binary> web` and enables it; re-install without `--force` is refused as
  drift (Base contract); `--force` backs up and upgrades.
- Separate services: installing web does not modify the daemon unit, and vice versa. Covers R9.
- Binary path: rendered `ExecStart` uses `resolved_binary` (Homebrew/version-manager aware),
  not a bare `/usr/bin/hive`. Covers R8.
- macOS path: `target_path` resolves to `local.hive-web.plist`; launchd load/unload invoked on
  install/force per Base.
- Unsupported host: no systemd-user → unit written, autostart not enabled, exit 0 with the
  `autostart_unavailable` message (Base behavior). Covers R11 partial.
- `status --json`: emits `service_installed`/`service_enabled`/`unit_path` via `service_state`.
- Foreground still works: bare `hive web` runs without any installed service. Covers R3, AE6.
- `start --detach` vs foreground: detached returns control; foreground execs Rails.

**Verification:** `test/unit/commands/web/service_installer_test.rb` and
`test/integration/web_command_test.rb` pass; on Linux, `hive web install && hive web start`
brings up a `systemctl --user` service that serves the dashboard and survives logout.

---

### U5. Daemon binary-consistency check + web health surfacing & repair

**Goal:** Detect when the running/installed daemon's binary or version has drifted from the CLI,
surface it (CLI + web), and make it repairable from the web UI (R8, R10, AE3).

**Requirements:** R8, R10, AE3. **Dependencies:** existing daemon status; U4 not required but
shares the installer.

**Files:**
- `lib/hive/commands/daemon.rb` — extend the `status --json` envelope with
  `installed_binary` (the unit's `ExecStart` binary), `expected_binary` (`resolved_binary`),
  `installed_binary_version` (its `--version`), `cli_version` (`Hive::VERSION`), and a derived
  `binary_drift: none|path|version`.
- `lib/hive/commands/daemon/service_installer.rb` — add a read-only `installed_exec_binary`
  helper that parses the current unit's `ExecStart`/plist `<string>` so status can compare
  without rewriting.
- `lib/hive/web/dispatcher.rb` — add a `repair_daemon` action that enqueues
  `hive daemon install --force` through the existing guarded dispatch queue (same pattern as
  recovery), so the web tier never shells out directly.
- `web/app/controllers/` (status/daemon controller) + a daemon-health partial/view — render the
  daemon health panel from the status envelope (running, service_installed/enabled, drift) with
  a confirm-gated **Repair** button posting to the new route.
- `web/config/routes.rb` — add the daemon repair route.
- `test/unit/commands/daemon_test.rb` — extend for the drift fields.
- `web/test/integration/daemon_health_test.rb` — new.

**Approach:** Comparison is read-only and lives in the status path; repair reuses the daemon
installer's existing `--force` upgrade (which already restarts the unit so new `Environment=`/
`ExecStart` take effect). The web Repair control writes a dispatch request rather than executing,
preserving the web tier's "no direct privileged side effects" contract. "Same binary/version as
the CLI" (AE3) is concretely: `binary_drift == none` AND `installed_binary_version == cli_version`.

**Test scenarios:**
- No drift: unit `ExecStart` equals `resolved_binary` and versions match → `binary_drift: none`.
- Path drift: unit points at `/usr/bin/hive` while CLI resolves elsewhere → `binary_drift: path`.
  Covers AE3.
- Version drift: same path, older `--version` → `binary_drift: version`. Covers AE3, R8.
- Status without unit: no installed unit → `service_installed: false`, drift reported as
  not-applicable (no false "path drift").
- Web surfacing: a drifted status renders the health panel with a visible warning and a Repair
  button. Covers R10.
- Web repair: clicking Repair enqueues exactly `hive daemon install --force` via the dispatch
  queue (no direct exec); a guarded-failure does not promote a follow-up. Covers R10.
- Healthy hides repair affordance’s warning state (panel shows green).

**Verification:** `test/unit/commands/daemon_test.rb` and `web/test/integration/daemon_health_test.rb`
pass; with a hand-edited drifted unit, `hive daemon status --json` reports the drift and the web
Repair button enqueues the force reinstall.

---

### U6. `hive setup` orchestrator command

**Goal:** One command that provisions and validates the whole local web mode and leaves the
machine in the AE1 end state: web at `http://127.0.0.1:4567`, daemon running on the same binary,
repo enrolled, new tasks auto-dispatched (R2, R5, R8, R14, AE1).

**Requirements:** R2, R5, R8, R14, AE1. **Dependencies:** U1, U2, U4, U5; uses existing
`Daemon::ServiceInstaller` and `Commands::Init`.

**Files:**
- `lib/hive/commands/setup.rb` — new orchestrator: run diagnostics (U1) and stop early with a
  consolidated fix-command report if hard deps fail; bootstrap qmd + the web bundle (U2);
  ensure the daemon service (`Daemon::ServiceInstaller#install!`) and enroll the current project
  (`Commands::Init` / `daemon enable`); ensure/print the web launch (foreground command) and
  optionally install the web service (U4) on `--service`. `--json` envelope; `--yes`/
  non-interactive defaults; `--no-bootstrap` to diagnose-only.
- `lib/hive/cli.rb` — register `hive setup`.
- `openclaw/skills/hive/SKILL.md` — update guided setup to delegate to `hive setup` instead of
  re-orchestrating `daemon install` + `init` (keeps the OpenClaw UX, single source of truth).
- `wiki/commands/setup.md` — new command reference (covered in U7).
- `test/unit/commands/setup_test.rb` — new.
- `test/integration/setup_command_test.rb` — new (real subprocess, isolated `HIVE_HOME`).

**Approach:** Compose the in-process pieces with injectable collaborators so the orchestration
is unit-testable without touching the host; the integration test exercises the real
subprocess against an isolated `HIVE_HOME` and stub agent CLIs. Setup is **idempotent and
repairing**: re-running on a healthy machine is a no-op that re-verifies; on a drifted machine
it reinstalls the daemon with the same binary (R8) and re-bootstraps a stale web bundle.
Diagnose-only failures (gh/claude/codex unauthenticated) do not abort the bootstrap of
Hive-owned pieces, but the final report lists every exact fix command and the overall exit code
is non-zero so automation can branch (AE5).

**Test scenarios:**
- Happy path: all deps ok → diagnostics pass, web bundle ensured, daemon service installed +
  project enrolled, web launch reported; `--json` envelope marks each phase ok; exit 0.
  Covers AE1.
- Same-binary daemon: after setup the installed daemon unit's `ExecStart` equals
  `resolved_binary` (no `/usr/bin/hive` drift). Covers R8, AE1.
- Enrollment: the current project ends with `daemon.enabled: true` in
  `.hive-state/config.yml`. Covers AE1.
- Diagnose-only failure: unauthenticated `gh` → setup still bootstraps qmd/web bundle but the
  report includes `gh auth login`, and exit code is non-zero. Covers AE5, R13.
- Idempotence: second run on a healthy machine makes no destructive change and re-verifies green.
- `--service`: also installs the web managed service (U4); without it, only foreground web is
  ensured. Covers AE6.
- Shared state: setup does not create a sandbox dir; web + TUI resolve the same `state_home`.
  Covers R5, AE2.
- OpenClaw delegation: SKILL.md's `/hive setup` path invokes `hive setup` (documented contract).

**Verification:** `test/integration/setup_command_test.rb` passes; on a fresh isolated home
with stub agent CLIs, `hive setup` brings up web at `127.0.0.1:4567`, installs a same-binary
daemon, enrolls the repo, and a task created via `hive new` is dispatched by the daemon.

**Execution note:** Implement test-first against the `--json` phase envelope — it is the
contract both the integration test and the OpenClaw skill depend on.

---

### U7. Documentation: setup reference, README local mode, operating/architecture

**Goal:** Document the local web mode as first-class while keeping Docker documented as a
supported alternative (R1, R11, AE7).

**Requirements:** R1, R11, AE7. **Dependencies:** U1–U6 (document the shipped surface).

**Files:**
- `wiki/commands/setup.md` — new: `hive setup` reference (flags, `--json` envelope, exit codes,
  the diagnose-vs-bootstrap split, the AE1 end state).
- `wiki/commands/web.md` — extend for the new `web install`/`start`/`stop`/`status` subcommands,
  the managed app dir, and the loopback-vs-non-loopback auth posture.
- `wiki/commands/daemon.md` — document the new `status --json` drift fields and the web Repair path.
- `README.md` — add a "Local (non-Docker) web" section alongside the Docker/hivebox section;
  keep Docker as an explicit alternative (AE7).
- `wiki/operating.md` — autostart section: add the web service (systemd-user/launchd) next to
  the daemon; note Linux/macOS only (R11).
- `docs/architecture.md` — note the managed `${XDG_DATA_HOME}/hive/web` app dir and that local
  TUI + web share one state (R5).
- `install.md` — cross-link `hive setup` from the install flow.

**Approach:** Documentation only; mirror the existing wiki front-matter and section style.
Cross-link the new command from the existing daemon/web docs so operators discover it.

**Test scenarios:** `Test expectation: none — documentation only.` Validate via the repo's
existing docs/markdown lint and `hive wiki compile-log --check` if wiki fragments are touched.

**Verification:** Docs render; `README.md` shows both the local and Docker paths; a reader can
go from install → `hive setup` → running web without reading source.

---

## Risks

- **R-A — Web-app delivery channel (OQ-1) is unresolved and is the critical-path dependency for
  U2/U6.** If the release-asset approach is chosen, it adds a packaging + release-workflow change
  and a fetch-with-integrity-check path; checkout-only would not satisfy "first-class on a gem
  install." *Mitigation:* surface as an Open Question for user confirmation before U2 execution;
  default to the managed-release-asset channel with version pinning.
- **R-B — Loopback bypass must not become a public-bind hole.** A signal-only bypass risks
  exposing an unauthenticated app if mis-set on `0.0.0.0`. *Mitigation:* KTD-2's two-layer design
  (CLI policy + app-layer loopback-peer re-check); explicit non-loopback refusal; regression test
  that Docker's owner gate is unchanged (U3).
- **R-C — Bundle/version skew between the managed web app and the CLI** could surface confusing
  runtime errors after a CLI upgrade. *Mitigation:* version-stamp the managed dir and detect
  staleness in `hive web`/`hive setup` (U2); defer auto-update-on-`hive update` to follow-up.
- **R-D — `bundle install` for the Rails app needs a compatible Ruby + native SQLite toolchain**
  on the host, which a gem-only user may lack. *Mitigation:* U1 diagnostics check Ruby 3.4 and
  SQLite and emit exact fix commands before U2 attempts the bundle.
- **R-E — Service-manager variability** (WSL without systemd, minimal hosts, launchd quirks).
  *Mitigation:* reuse `ServiceInstaller::Base`'s already-handled `autostart_unavailable` /
  unsupported-host paths; foreground `hive web` always works as the fallback (R3).
- **R-F — Regressing the Docker/hivebox path** while refactoring `web.rb` and the auth gate.
  *Mitigation:* AE7 regression guard — keep existing `web/test/integration` owner-gate tests
  green and the `0.0.0.0` supervisor path intact; gemspec "no web/ in gem" invariant preserved.

---

## Open Questions

- **OQ-1 (recommend confirming before U2/U6 execution) — How should the Rails web app reach a
  gem-only local install?** The gem deliberately does not package `web/`.
  Options:
  - **(a) Managed release-asset tarball (recommended):** publish a `hive-web-<version>` bundle as
    a GitHub Release asset; `hive setup`/`hive web` fetch it into `${XDG_DATA_HOME}/hive/web`,
    verify it matches the CLI version, then `bundle install`. Mirrors the qmd model; keeps the
    gem slim and the gemspec invariant intact. Adds a release-workflow step.
  - **(b) Vendor `web/` into the gem:** simplest at runtime but breaks the gemspec "no web/"
    contract, bloats the gem, and ships Rails sources to every CLI user.
  - **(c) Source-checkout only:** no new delivery; but then local web is not first-class for
    gem/Homebrew/AUR users — fails R1/AE1 for the primary audience.
  This plan is written against (a). If you prefer (b) or (c), U2's packaging files and parts of
  U6 change accordingly.
- **OQ-2 — Should `hive setup` enroll the *current* directory's project by default, or prompt?**
  Plan assumes non-interactive enroll-current-project with a `--no-init` opt-out, matching the
  OpenClaw guided-setup defaults. Confirm if a prompt is preferred for interactive runs.

<!-- COMPLETE -->
