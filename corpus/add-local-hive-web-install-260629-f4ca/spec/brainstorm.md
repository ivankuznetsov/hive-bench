# Brainstorm: add-local-hive-web-install-260629-f4ca

Add a first-class local (non-Docker) install/run mode for the Hive web UI,
alongside the existing Docker/hivebox path, so the same pipeline is reachable
from both the TUI and the web UI, with the daemon picking up new tasks by
default.

## Round 1

### Q1. There is already a `hive web` command serving the Rails app and a `hive daemon` that runs per-user by default. Concretely, what is *new* in this idea — a one-shot installer/command that provisions the local web mode (deps + service + daemon), a long-running supervised service definition, or mainly documentation/packaging that ties existing pieces together? What command(s) should a user run to get it?
### A1.
Make local web a first-class install/run mode, not just docs. Add a setup path
that provisions and validates the Hive CLI, Rails web bundle, qmd, daemon
service, project enrollment, and web launch/service. Commands should probably
be `hive setup` for full local setup, `hive web` for foreground web, and
`hive web install` / `hive web start` for managed service lifecycle.

### Q2. What is the canonical state/data model in local mode? Docker's hivebox isolates everything under `/data`. Should local mode operate directly on the user's real home/XDG paths, existing `hive` config, and their actual checked-out repos (so TUI and web share one source of truth), or maintain a separate sandboxed data dir like Docker does?
### A2.
Use the user's real local Hive/XDG state and checked-out repos. TUI and web
should share one source of truth. Docker keeps `/data`; local mode should not
create a separate sandbox by default.

### Q3. How should authentication/ownership work locally? Docker's hivebox uses GitHub device-flow with a first-login-claims-owner model on a loopback bind. For a local single-user machine, do we (a) require no auth at all on loopback, (b) reuse the same GitHub claim/owner flow, or (c) make it configurable? What is the default bind address and port?
### A3.
Default bind should be `127.0.0.1:4567`. For loopback, no auth by default is
acceptable for local single-user usage. If binding non-loopback, require an
auth/owner flow or an explicit unsafe flag. GitHub claim flow can remain
Docker/hivebox-oriented or optional.

### Q4. "The daemon should work by default so newly created tasks are picked up automatically." The README says the per-user daemon is already enabled by default and `hive init .` enrolls a project for dispatch. What is the gap today in the local web path — is the daemon not being installed/started, not enrolled, not surfaced in the web UI, or something else? What does "works by default" mean as an acceptance test?
### A4.
Acceptance: after setup, daemon is installed/running with the same Hive
binary/version as the CLI, the project is enrolled, and a new task created
from TUI or web gets picked up automatically. Current gap: daemon/systemd can
drift to `/usr/bin/hive`, old versions, or not be surfaced/repairable from
web.

### Q5. What platforms must local mode support, and what is the dependency story? Prereqs today include Ruby 3.4, git, tmux, Node/npm, and authenticated `claude`/`codex`/`gh`. Should the local web installer verify/bootstrap these (and the Rails app's bundle + SQLite), or assume a standard Hive install is already present? Linux + macOS only, or Windows too?
### A5.
Support Linux and macOS first. Installer verifies Ruby 3.4, git, tmux, gh,
claude, codex, Node/npm/qmd, Rails bundle, and SQLite. It can bootstrap
Hive-owned deps like qmd and the web bundle, but should not silently install or
authenticate external agent CLIs; it should diagnose and give exact fix
commands.

### Q6. How should the local web service be supervised and started? Options: reuse the existing systemd-user (Linux) / launchd (macOS) machinery to register the web server as a managed service that autostarts, vs. a foreground `hive web` the user runs manually, vs. both (manual run + optional install-as-service). Should the web server and the daemon be one service or two?
### A6.
Keep daemon and web as separate services. Manual foreground `hive web` should
always work. Add optional managed web service via systemd-user/launchd. Setup
should ensure daemon service too. Do not merge daemon and web into one service
locally.

### Q7. What is the relationship to the OpenClaw/OpenClawd local pattern referenced in the idea (there is an `openclaw/` path in the repo)? Are there specific behaviors from that runtime — e.g. zero-config local launch, lifecycle commands, port handling, update flow — that you want mirrored here, or is it only directional inspiration?
### A7.
Mirror the local UX pattern: zero/low-config local loopback server, clear
lifecycle commands, health checks, port handling, local browser/control
surface, and diagnostics. It is directional inspiration, not a requirement to
copy OpenClaw internals.

### Q8. What is the definition of done / acceptance scenario? For example: "On a fresh machine with Hive installed, running `<command>` brings up the web UI at `http://localhost:<port>` and an enabled daemon; creating a task in the TUI makes it appear in the web UI and start executing automatically without any further setup." Please confirm or correct the concrete end-to-end scenario you want to pass.
### A8.
On a fresh supported local machine, after installing Hive, running one setup
command brings up web at `http://127.0.0.1:4567`, ensures daemon is running
with the same binary, enrolls the repo, and a task created in TUI appears in
web and starts automatically. Docker/hivebox remains an alternative install/run
path, not replaced.

## Requirements

### Actors
- **Local single-user operator** — installs and runs Hive on their own
  Linux/macOS machine; uses both the TUI and the web UI against one shared
  state.
- **Hive daemon** — per-user background process that picks up enrolled
  projects' new tasks and dispatches them automatically.
- **Local web service** — the Rails app served at the loopback address,
  optionally supervised as a managed service.

### Scope
- Add a first-class **local (non-Docker) install/run mode** for Hive web,
  alongside the existing Docker/hivebox path (Docker remains supported, not
  replaced).
- Local mode is more than docs: a setup path that provisions and validates the
  Hive CLI, Rails web bundle, qmd, daemon service, project enrollment, and web
  launch/service.
- Mirror the OpenClaw/OpenClawd local UX pattern (zero/low-config loopback
  server, clear lifecycle commands, health checks, port handling, diagnostics)
  as directional inspiration — not a copy of internals.

### Flow
- **Commands**
  - `hive setup` — full local setup: provision + validate deps, web bundle,
    qmd, daemon service, project enrollment, web launch.
  - `hive web` — run web in the foreground; must always work without a service.
  - `hive web install` / `hive web start` — managed web service lifecycle.
- **State / data model**
  - Operate directly on the user's real local Hive/XDG state, existing `hive`
    config, and actual checked-out repos. TUI and web share one source of
    truth. No separate sandbox dir by default (Docker keeps its `/data`).
- **Networking / auth**
  - Default bind `127.0.0.1:4567`.
  - On loopback: no auth required by default for single-user use.
  - On non-loopback bind: require an auth/owner flow or an explicit unsafe
    flag. GitHub claim/owner flow stays Docker/hivebox-oriented or optional.
- **Daemon**
  - Setup ensures the daemon is installed and running using the **same Hive
    binary/version as the CLI** (guard against systemd drift to `/usr/bin/hive`
    or stale versions); the project is enrolled.
  - Daemon and web are **separate services**; do not merge them locally.
  - Web should surface daemon health and be able to repair/restart it.
- **Supervision**
  - Manual foreground `hive web` always works.
  - Optional managed services via systemd-user (Linux) / launchd (macOS) for
    both web and daemon.
- **Platforms & dependencies**
  - Linux and macOS first; Windows out of scope.
  - Installer verifies: Ruby 3.4, git, tmux, gh, claude, codex, Node/npm, qmd,
    Rails bundle, SQLite.
  - May bootstrap Hive-owned deps (qmd, web bundle); must **not** silently
    install or authenticate external agent CLIs — instead diagnose and emit
    exact fix commands.

### Acceptance examples
- **End-to-end (definition of done):** On a fresh supported local machine with
  Hive installed, running one setup command brings up the web UI at
  `http://127.0.0.1:4567`, ensures the daemon is running with the same binary
  as the CLI, and enrolls the repo. A task created in the TUI appears in the
  web UI and starts executing automatically with no further setup; the reverse
  (created in web) also works.
- **Shared source of truth:** A task or config change made via the TUI is
  immediately visible in the web UI and vice versa, because both read the
  same local Hive/XDG state and repos.
- **Binary consistency:** After setup, the running daemon's Hive binary/version
  matches the CLI's; a drifted/stale daemon is detected and repairable.
- **Loopback default:** Binding to `127.0.0.1:4567` requires no auth; binding
  to a non-loopback address without an auth/owner flow or unsafe flag is
  refused.
- **Dependency diagnostics:** On a machine missing an authenticated `claude`,
  `codex`, or `gh`, setup does not silently fix it but reports the exact
  command(s) the user must run.
- **Service lifecycle:** `hive web` runs in the foreground; `hive web install`
  + `hive web start` register and start a managed web service; the daemon
  service is ensured independently.
- **Docker unaffected:** The Docker/hivebox install/run path continues to work
  as an alternative.

<!-- COMPLETE -->
