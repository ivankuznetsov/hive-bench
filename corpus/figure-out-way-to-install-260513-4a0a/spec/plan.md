<!-- AGENT_WORKING pid=3180453 started=2026-05-14T13:46:42Z -->

# Plan: figure-out-way-to-install-260513-4a0a

## Overview

Ship hive v0.1.0 as a real installable package across the tier-1 platforms (macOS arm64, Ubuntu 22.04+, Arch Linux) via four channels: a Homebrew tap, an AUR `hive-bin` package, a `curl | bash` one-liner, and a published "prompt installer" markdown that lets Claude Code / Codex / Pi pick the right channel. The release artifact is a self-contained, vendored-Ruby binary built per tier-1 target — no system Ruby required on the user's machine.

Per-project state (`.hive-state/` inside a project) stays exactly where it is today; per-user state migrates to XDG paths (`~/.config/hive`, `~/.local/share/hive`, `~/.local/state/hive`, `~/.cache/hive`). `hive init` registers the daemon as a launchd agent (macOS) or `systemd --user` unit (Linux) and prompts the user whether to enable+start now (brainstorm option c — same prompt on both platforms). `hive update` delegates to the user's channel-native updater (never swaps the binary in place). `hive uninstall` removes the binary's registrations and prompts before touching project-scoped content, with the explicit invariant that no completed pipeline work is destroyed by default. <!-- hive-bench: repo-state assertion, verify against the restored base -->

The skills package (a separate distribution consumed via each agent's marketplace) is **out of scope** for this plan beyond referencing the per-agent install commands from the prompt installer.

## Requirements Trace

| Requirement (from `brainstorm.md`) | Implementation Unit |
|---|---|
| Public GitHub repo + tagged semver releases as canonical artifact source | U1 |
| Self-contained vendored-Ruby binary per tier-1 target | U1 (validated by U1.0 spike) |
| Homebrew tap under project org (`brew install <org>/hive/hive`) | U3 |
| AUR `hive-bin` (prebuilt binary) | U4 |
| `curl … \| bash` one-liner with OS/arch detect → XDG drop | U2 |
| Prompt installer (markdown) that detects OS, picks channel, verifies, runs `hive init`, optionally installs skills via marketplace | U7 |
| Skills package distributed only via agent marketplaces, never by core install | U7 reference + U8 docs; **shipping the skills package itself is out of scope** |
| XDG layout for binary/config/state/cache/share | U5 |
| Runtime-dep detection (`git`, `bash`, `claude`, `gh`, `jq`) with actionable hints, no auto-install | U2 + U5 (`hive doctor` already exists) |
| `hive` user-facing binary; `hv` fallback when `hive` conflicts (Apache Hive); AUR always `hive-bin` | U5 + U2/U3/U4 collision detection |
| Required v1 subcommands: `hive init`, `hive update`, `hive uninstall`, `hive daemon {start,stop,status}`, `hive --version` | U5 (new: `update`, `uninstall`); existing `init`, `daemon`, `--version` |
| `hive init` registers daemon (launchd / systemd-user) with autostart **prompt** (option c) | U6 |
| `hive init` collects first-run config (provider, model) into `~/.config/hive/config.yml` | U5 + U6 |
| Pinned semver releases only; `hive update` delegates to the native updater per channel | U5 + U9 channel marker |
| `hive uninstall` removes binary + daemon registration; prompts before touching `.hive/`; preserves accumulated work; `--purge` for CI still preserves user work artifacts | U5 |
| Tier-1: macOS arm64, Ubuntu 22.04+, Arch; tier-2 best-effort; tier-3 out | U1 build matrix + U10 docs |
| Acceptance A (brew end-to-end) | U3 |
| Acceptance B (AUR end-to-end + `hive update` via `yay`) | U4 + U5 + U9 |
| Acceptance C (prompt installer end-to-end on each tier-1 OS × agent) | U7 |
| Acceptance D (clean uninstall preserves work) | U5 |

## Scope Boundaries

**In scope (v1):**

- Tag `v0.1.0` and produce a GitHub Release with prebuilt binaries for `darwin-arm64`, `linux-x86_64-gnu`, `linux-aarch64-gnu`, plus checksums and a cosign keyless signature.
- Author the bash one-liner (`install.sh`), Homebrew formula (own tap), AUR `hive-bin` PKGBUILD, and the prompt-installer markdown (`install.md`).
- Add `hive update`, `hive uninstall`, an `hv` fallback wrapper, an install-channel marker, and XDG path migration to the CLI.
- Extend `hive init` to install + (with prompt) start the platform-appropriate daemon service unit.
- Document tier-1 vs tier-2 vs tier-3, plus the Apache Hive name collision, in `wiki/operating.md` and `README.md`.

**Out of scope (v1) — explicit:**

- **Shipping the skills package itself.** A separate repo with its own release flow. This plan only references per-agent marketplace install commands.
- **Homebrew-core submission.** Own tap only; revisit after the tap is stable.
- **`hive-git` AUR variant.** Only `hive-bin` ships in v1.
- **Tier-2 prebuilt binaries** (macOS x86_64, Debian 12+, Fedora 40+, WSL2). Best-effort means the bash one-liner is allowed to attempt those targets via a closest-match tarball; no dedicated brew bottle / AUR `-bin` row is shipped for them.
- **Tier-3 (Alpine, NixOS, BSD).** Bash installer exits with a clear "unsupported platform" message.
- **In-place binary self-update.** `hive update` only delegates to the native channel updater.
- **macOS code-signing / notarization** beyond `xattr -d com.apple.quarantine` instructions. Notarization is a v0.2 follow-up.
- **Rolling / edge channel.** Only pinned semver releases.
- **Migration tooling** to move existing `~/Dev/hive` clone state into XDG paths. New users get XDG; existing dev installs keep working unchanged.

**Open assumptions (carried into Risks):**

- Tebako can package the current Gemfile (`bubbletea-ruby 0.1.4` + `lipgloss-ruby 0.2.2` are FFI / native-extension gems pinned exactly). Validated by U1.0 spike **before** any release infrastructure work; fallback is `ruby-packer`, then a fat-tarball-plus-vendored-Ruby strategy.
- The GitHub org for the tap is `ivankuznetsov` (matches `git remote -v`). If a different org name is preferred for the `homebrew-hive` repo, U3 swaps the URL only.

## Implementation Units

### U1.0 — Spike: validate Tebako packs the current Gemfile (½ day)

**Goal:** before any release pipeline work, confirm a single-file binary can be produced on the tier-1 OSes for hive's current Gemfile. The high-risk dependencies are `bubbletea-ruby` 0.1.4 and `lipgloss-ruby` 0.2.2 — both ship native FFI bindings, and bubbletea is pinned exactly because hive's `PasteAwareRunner` reads its private superclass ivars. If Tebako fails, the fallback is `ruby-packer`; if that fails too, a fat-tarball strategy (vendored Ruby + gems + a thin `hive` wrapper).

**Files:**
- `packaging/spike/tebako-build.sh` (spike-only; deleted after decision)
- New ADR in `wiki/decisions.md` recording the chosen packaging strategy.

**Approach:**
1. Run `tebako press` against the repo on macOS arm64 and on a `linux/amd64` GitHub Actions runner.
2. Smoke the produced binary: `./hive --version`, `./hive doctor`, `./hive tui` (boot + Esc).
3. If Tebako fails on the FFI gems, repeat with `ruby-packer`. If both fail, fall back to the fat-tarball strategy.

**Test scenarios:**
- `tebako press` succeeds on macOS arm64 and linux x86_64.
- `./hive --version` prints `0.1.0`.
- `./hive tui` boots and renders the dashboard (manual smoke; the bubbletea FFI is the highest-risk piece).
- Binary size ≤ ~50 MB (informational, not a gate).

**Verification:** ADR committed before U1 starts. If Tebako fails, the rest of U1 retargets the chosen fallback; downstream units stay valid because they only depend on "the release has a runnable `hive` artifact per target."

---

### U1 — Release infrastructure: GitHub Actions + signed tarballs

**Goal:** On every `v*.*.*` tag, produce a GitHub Release whose assets include `hive-<version>-<target>.tar.gz` for `darwin-arm64`, `linux-x86_64-gnu`, `linux-aarch64-gnu`, plus `SHA256SUMS` and `SHA256SUMS.sig` (cosign keyless / OIDC). Every channel (`install.sh`, brew, AUR) consumes the same checksums for verification.

**Files:**
- `.github/workflows/release.yml` (new)
- `Rakefile` — new task `build:release[<target>]`
- `packaging/build/<target>.sh` per-target helper scripts
- `lib/hive.rb` — `Hive::VERSION` remains the single source of truth (the release workflow reads it via a one-liner that requires `hive` and prints `Hive::VERSION`)

**Approach:**
- Trigger: `on: push: tags: ['v*.*.*']`.
- Matrix builds: `macos-15` (arm64), `ubuntu-24.04` (x86_64), `ubuntu-24.04-arm` (aarch64).
- Each job: install Ruby 3.4 via `ruby/setup-ruby@v1`, install the U1.0-chosen packager (Tebako / ruby-packer / fat-tarball), run `rake build:release[<target>]`, attach `hive-<version>-<target>.tar.gz` to the draft release.
- A final `release-finalize` job concatenates SHA256 sums, signs `SHA256SUMS` with cosign keyless (`id-token: write`), and publishes the release as non-draft.
- Tarball contents: `hive` (binary), `LICENSE`, `README.md`, `share/hive/` (templates, agents, prompts under `lib/hive/...`-derived assets and `templates/`), `wiki/` (operating docs).

**Test scenarios:**
- Pre-release tag `v0.1.0-rc.0` produces three tarballs + `SHA256SUMS` + `SHA256SUMS.sig`.
- `sha256sum --check SHA256SUMS` passes against the downloaded tarballs.
- `cosign verify-blob --certificate-identity '<workflow-identity>' SHA256SUMS` succeeds.
- The build is reproducible enough that two consecutive runs on the same SHA produce binaries with matching `hive --version` (not byte-identical — Tebako embeds timestamps — but the version envelope matches).

**Verification:** A dry-run `v0.1.0-rc.0` release lands in GitHub Releases with all expected assets; verifying signatures passes against the workflow's keyless identity.

---

### U2 — Bash one-liner installer (`install.sh`)

**Goal:** A single script downloadable from `https://raw.githubusercontent.com/<org>/hive/main/install.sh` (and re-attached to each release) that detects OS/arch, downloads the matching tarball, verifies the SHA256, extracts to `~/.local/share/hive/<version>/`, symlinks the binary to `~/.local/bin/hive`, writes a channel marker, runs a runtime-dep preflight, and prints next steps.

**Files:**
- `install.sh` (new, at repo root)
- `wiki/operating.md` — new "Install: bash one-liner" subsection

**Approach:**
- Detect platform with `uname -s` / `uname -m`; map to `darwin-arm64`, `linux-x86_64-gnu`, `linux-aarch64-gnu`. Tier-3 (Alpine via musl detection, NixOS, BSD) exits with `unsupported platform — see <wiki link> for tier-2 guidance`.
- Resolve target version: env override `HIVE_VERSION=v0.1.0` or fetch latest from the GitHub Releases API (`curl -fsSL https://api.github.com/repos/<org>/hive/releases/latest`).
- Download the tarball + `SHA256SUMS`; verify with `sha256sum` (Linux) or `shasum -a 256` (macOS); abort with non-zero exit and a clear message on mismatch.
- Extract to `${XDG_DATA_HOME:-$HOME/.local/share}/hive/<version>/`; symlink `${XDG_BIN_HOME:-$HOME/.local/bin}/hive` → that path's `bin/hive`.
- Write channel marker: `${XDG_DATA_HOME:-$HOME/.local/share}/hive/install-channel` containing the literal string `bash`.
- Detect `hive` PATH collision: if `command -v hive` resolves to anything outside our install dir, also symlink `hv` → the installed binary and print a single highly-visible warning naming the colliding path.
- macOS quarantine: run `xattr -d com.apple.quarantine "<extracted dir>/bin/hive"` (ignoring failure if the xattr isn't present).
- Preflight runtime deps (`git`, `bash`, `claude`, `gh`, `jq`): warn (not fail) with platform-specific install hints (`brew install …` / `apt install …` / `pacman -S …`). Never auto-install.
- Print next steps pointing at `hive --version`, `hive init`, and `install.md` (U7) for the skills marketplace step.
- Flags: `--dry-run` (print resolved actions, exit 0), `--prefix=<dir>` (override XDG_DATA_HOME for this install), `--version=<tag>` (alias for env override).

**Test scenarios:**
- macOS arm64 clean VM: `curl … | bash` → `hive --version` prints `0.1.0`.
- Ubuntu 22.04 clean container: same.
- Arch clean container: same.
- Corrupt tarball fixture: SHA256 mismatch aborts with exit ≠ 0 and a clear message.
- PATH collision: pre-place a script called `hive` in `/usr/local/bin/`; installer creates `hv` symlink + prints warning.
- Tier-3 (Alpine via `docker run alpine`): script exits non-zero with "unsupported platform".
- `--dry-run`: prints the would-be actions without touching disk; exits 0.

**Verification:** `shellcheck install.sh` clean; a `.github/workflows/install-smoke.yml` exercises the script against the three tier-1 platforms (macOS, Ubuntu, Arch via container) on every push to `main`.

---

### U3 — Homebrew tap

**Goal:** A separate public repo `<org>/homebrew-hive` containing `Formula/hive.rb`. After `brew tap <org>/hive`, `brew install hive` installs the prebuilt darwin-arm64 tarball from the GitHub Release.

**Files (in `<org>/homebrew-hive` — separate repo):**
- `Formula/hive.rb` (new)
- `README.md` describing tap + install
- `.github/workflows/bump.yml` — auto-bumps formula on new upstream tag (driven by a `repository_dispatch` from the main repo's `release-finalize` job)

**Files (in main hive repo):**
- `packaging/homebrew/hive.rb.erb` — formula template rendered by the release pipeline
- `wiki/operating.md` — install section adds `brew install <org>/hive/hive`

**Approach:**
- Formula declares `url` → darwin-arm64 tarball, `sha256` from release `SHA256SUMS`. (linux-x86_64 / linux-aarch64 are documented but **not** delivered via brew in v1; Linux users prefer AUR or the bash one-liner.)
- `def install`: extract tarball, `bin.install "hive"`, `share.install Dir["share/hive/*"]`.
- `post_install`: write `<HOMEBREW_PREFIX>/share/hive/install-channel` containing `brew`.
- `caveats`: print "run `hive init` to scaffold a project; the daemon is registered then, not now. If `hive` is shadowed by Apache Hive, run as `hv`."
- No `service` block in v1: daemon registration is a `hive init` concern (option c prompt). Documented as a deliberate non-feature.
- Tap-repo bump workflow: the main repo's `release-finalize` job fires `repository_dispatch` at `<org>/homebrew-hive` with the new version + sha256; that repo's workflow opens an auto-merging PR.

**Test scenarios:**
- Clean macOS arm64 VM: `brew tap <org>/hive && brew install hive && hive --version` succeeds.
- Subsequent `brew upgrade hive` (after a `v0.1.1` release) installs the new bottle.
- `brew uninstall hive` removes the binary; project `.hive-state/` content is untouched (cross-checks U5's uninstall invariant).

**Verification:** `brew audit --strict --online <org>/hive/hive` passes; the end-to-end install scenario in `wiki/operating.md` is reproduced on a fresh macOS VM (manual for v1).

---

### U4 — AUR `hive-bin` package

**Goal:** Publish `hive-bin` to the AUR. `yay -S hive-bin` works on a clean Arch box; `yay -Syu hive-bin` upgrades to the latest tagged release.

**Files (in main hive repo):**
- `packaging/aur/PKGBUILD.template` (new) — rendered per release
- `packaging/aur/.SRCINFO.template`
- `packaging/aur/hive.install` (post-install / upgrade / remove pacman hooks)

**Approach:**
- `pkgname=hive-bin`, `provides=('hive')`, `conflicts=('hive' 'apache-hive')` — the second guards the Apache Hive collision cleanly via pacman's conflict resolution.
- `source=()` references the GitHub Release tarball (`x86_64` and `aarch64` rows); `sha256sums=()` from `SHA256SUMS`.
- `package()`: install `hive` → `$pkgdir/usr/bin/hive`, templates → `$pkgdir/usr/share/hive/`, LICENSE → `$pkgdir/usr/share/licenses/hive-bin/LICENSE`, channel marker → `$pkgdir/usr/share/hive/install-channel` containing `aur`.
- `.install` hook on first install: prints "Run `hive init` in a project to scaffold + register the systemd-user daemon." Does **not** install the systemd unit globally — `hive init` installs into `~/.config/systemd/user/` per option c.
- Update flow: the main repo's `release-finalize` job pushes a refreshed `PKGBUILD` + `.SRCINFO` to the AUR repo over SSH using a dedicated AUR account key stored as a GitHub Actions secret.

**Test scenarios:**
- Clean Arch container (`archlinux:latest`): install `yay`, run `yay -S hive-bin`, verify `hive --version`.
- Pre-existing `apache-hive` installed: `pacman` refuses without `--overwrite`; user must remove `apache-hive` or accept the `conflicts=` resolution. Documented; the `hv` fallback (U5) is unavailable in this case because pacman blocks the install — note this limitation explicitly in `wiki/operating.md`.
- Upgrade: bump `pkgver` to `0.1.1` → `yay -Syu hive-bin` upgrades.

**Verification:** `namcap PKGBUILD` and `namcap .SRCINFO` clean; `makepkg -si` succeeds in a fresh Arch container in CI.

---

### U5 — `hive` CLI: XDG paths, `update`, `uninstall`, `hv` fallback, install-channel marker

**Goal:** Migrate per-user paths to XDG, add `hive update` and `hive uninstall` commands, add an `hv` fallback wrapper that all installers can drop when a `hive` PATH collision is detected, and have every channel write a `install-channel` marker that `hive update` reads.

**Files:**
- `lib/hive/paths.rb` (new) — XDG resolver: `config_home`, `data_home`, `state_home`, `cache_home`, `bin_home`, each with `XDG_*` env-var precedence and platform defaults.
- `lib/hive/install_channel.rb` (new) — reads/writes the marker file. Values: `brew`, `aur`, `bash`, `dev`. Detection order: `<data_home>/hive/install-channel` → `<HOMEBREW_PREFIX>/share/hive/install-channel` → `/usr/share/hive/install-channel` → `dev` fallback (when the binary is invoked from a git clone with no marker).
- `lib/hive/commands/update.rb` (new) — registered as the `update` Thor subcommand.
- `lib/hive/commands/uninstall.rb` (new) — registered as the `uninstall` Thor subcommand.
- `lib/hive/cli.rb` — wire the two new commands into Thor; preserve the existing `--version` short-circuit in `bin/hive`.
- `bin/hv` (new, OPTIONAL) — thin shell wrapper that hands off to the resolved `hive` binary. Only installed by the bash installer when a collision is detected; brew formula installs it as a same-cellar symlink; AUR's `conflicts=` resolution typically prevents the need (see U4).
- `lib/hive/config.rb` — audit for any existing per-user write paths (`Hive::Config.registered_projects` and any other state files). Re-point through `Hive::Paths`. Add a one-time migration shim: if the legacy path exists AND the new path doesn't, move it.

**Approach (per-piece):**

*XDG migration:*
- `Hive::Paths.config_home` → `${XDG_CONFIG_HOME:-$HOME/.config}/hive`
- `Hive::Paths.data_home` → `${XDG_DATA_HOME:-$HOME/.local/share}/hive`
- `Hive::Paths.state_home` → `${XDG_STATE_HOME:-$HOME/.local/state}/hive`
- `Hive::Paths.cache_home` → `${XDG_CACHE_HOME:-$HOME/.cache}/hive`
- Per-project `.hive-state/` inside each project is **untouched** — that is project-local and lives next to the user's code, not under `$HOME`.

*`hive update`:*
- Reads `install-channel` marker. For `brew`: hands off to `brew upgrade <org>/hive/hive` via `Process.spawn` then `Process.exec`. For `aur`: detect `yay` or `paru` (whichever resolves on PATH first) and hand off to `yay -Syu hive-bin`; error if neither helper is present with a clear "install yay or paru, or re-run the bash one-liner". For `bash`: hand off to `bash -c "curl -fsSL <install-url> | bash"`. For `dev`: print "you're running from a git clone — run `git pull && bundle install` instead" and exit 0.
- Never modifies the binary in place. Never falls back across channels — wrong inference would corrupt a brew install if `hive update` shelled to `yay`.
- `--dry-run` prints the chosen command without executing.

*`hive uninstall`:*
- Default flow (interactive):
  1. Always: stop + deregister the daemon (`launchctl unload ~/Library/LaunchAgents/local.hive-daemon.plist` on macOS, `systemctl --user disable --now hive-daemon` on Linux). Skip cleanly if the unit isn't installed.
  2. Always: remove `~/.config/hive/`, `~/.cache/hive/`, and `~/.local/share/hive/<version>/`.
  3. **Prompt** before any project-scoped cleanup. Default: leave `.hive-state/` content alone in every registered project.
  4. **Never** touch `~/.local/state/hive/` (accumulated work artifacts) and never touch per-project `.hive-state/` content without an explicit `y` at the prompt.
  5. Does NOT remove the binary itself — refer the user to the channel-native uninstall (`brew uninstall hive`, `yay -R hive-bin`, or removing the symlink for bash).
- `--purge` (non-interactive, for CI): same as default, but skip prompts. Still preserves `~/.local/state/hive/` and per-project `.hive-state/` unless `--force-purge-state` is also passed (deliberately the only way to destroy accumulated work).
- Skills are never touched; uninstall prints "skills are managed by your agent's marketplace; remove with `claude plugin remove …` / `codex plugin remove …` / `pi remove …`."

*`hv` fallback wrapper:*
- All three installers detect collision via `command -v hive` resolving to a path other than the one they just installed. When detected, drop a `hv` symlink or shell wrapper next to `hive` (bash: `~/.local/bin/hv`; brew: cellar symlink; AUR: relies on `conflicts=` resolution instead, see U4). The installer prints one warning naming the colliding `hive`.

**Test scenarios:**
- Minitest: `Hive::Paths` respects `XDG_*` env vars and falls back to platform defaults.
- Minitest: `Hive::InstallChannel` reads/writes marker; rejects unknown values; detection order is correct under all four conditions.
- Minitest: `hive update` with `marker=brew` invokes `brew upgrade …` (stub the process call); with `marker=aur` + `yay` on PATH invokes `yay`; with `marker=aur` + neither yay nor paru errors out non-zero with EX_UNAVAILABLE (69).
- Minitest: `hive uninstall` removes `~/.config/hive/` but leaves `~/.local/state/hive/projects/*` intact (work-preservation invariant).
- Minitest: `hive uninstall --purge` still leaves `~/.local/state/hive/projects/*` intact.
- Minitest: legacy-path migration shim — pre-create `~/.hive-state/registry.yml` (legacy), invoke `Hive::Config`, assert the new XDG path now has the file and the old path is gone.
- Existing `hive init` tests continue to pass after the path migration (re-point to `Hive::Paths.config_home`).

**Verification:** `bundle exec rake test` and `bundle exec rubocop` clean; manual smoke on macOS + Arch confirming the four XDG dirs are created and no `~/.hive-state/` for per-user data on a fresh install.

---

### U6 — `hive init`: daemon-registration-with-prompt (option c)

**Goal:** Extend `hive init` so that, after the existing project scaffold, it (1) writes the platform-appropriate daemon unit to the per-user location, (2) prompts the user "Enable and start the hive daemon now? [y/N]", (3) on yes runs `launchctl load …` / `systemctl --user enable --now hive-daemon`, on no leaves the unit on disk disabled. Same prompt text on both platforms.

**Files:**
- `lib/hive/commands/init.rb` — append a `register_daemon_service!` step after `print_summary` and before `run_init_preflight!`.
- `lib/hive/commands/daemon/service_installer.rb` (new) — platform-detecting installer with `macos!` / `linux!` methods that render from the existing example unit files, substituting the real binary path.
- `lib/hive/commands/init/prompts.rb` — append the autostart question to the existing prompt flow.
- `examples/launchd/hive-daemon.plist` and `examples/systemd/hive-daemon.service` — repurpose as install templates. Their `YOU` / `%h` placeholder substitution moves into `ServiceInstaller`. The original files stay in `examples/` (sample copy-paste path is still valid for users who want to do it manually).

**Approach:**
- Platform detection via `RbConfig::CONFIG['host_os']` (`darwin*` → macos; `linux*` → linux; anything else → tier-3 path below).
- macOS: render plist → `~/Library/LaunchAgents/local.hive-daemon.plist`. Binary path resolved via `File.realpath(which("hive"))` so a rbenv/asdf/mise/brew shim is followed to its real target (launchd has no shell rc to read; absolute real path is required — see the existing example's RESPAWN-LOOP CIRCUIT-BREAKER doc).
- Linux: render unit → `~/.config/systemd/user/hive-daemon.service`. Same realpath resolution.
- Prompt the user; record decision in `~/.config/hive/config.yml` as `daemon.autostart: true|false` for idempotent re-runs.
- Idempotency guard: if the unit file already exists AND its rendered content matches what we would write now, skip the write. If it exists and the content has drifted (user-customized), warn and skip overwrite — never clobber user changes.
- WSL2 best-effort: if `systemctl --user` is unavailable (older WSL without systemd), write the unit anyway and print "systemd not detected; enable systemd in WSL or run `hive daemon start` manually." Exit 0.
- Tier-3 (BSD): emit "daemon autostart not supported on this platform; run `hive daemon start` manually." Exit 0.

**Test scenarios:**
- macOS path (`RbConfig` stubbed to `darwin23`), mocked `launchctl`: plist rendered, user says `y` → `launchctl load` invoked.
- Linux path, mocked `systemctl`: unit rendered, user says `n` → no `systemctl enable` call, unit stays on disk disabled.
- Re-run `hive init --force` against a hand-edited unit file: warn, skip overwrite, continue.
- Re-run `hive init` with no drift: silent skip on the unit write, prompt still re-asked (so user can flip autostart later).
- WSL2 without systemd: unit written, start skipped, exit 0.
- BSD path: friendly skip message, exit 0.

**Verification:** `bundle exec rake test` covers all flows above using the existing `StringIO`-driven `Prompts` injection point (already used by `Hive::Commands::Init`). Manual smoke on real macOS + Arch confirms the daemon actually starts.

---

### U7 — Prompt installer (`install.md`)

**Goal:** A markdown file at the repo root + linked from the GitHub Release that the user pastes into Claude Code / Codex / Pi. The agent (a) detects host OS via shell, (b) picks the channel (brew on macOS, AUR helper on Arch, bash one-liner otherwise), (c) runs it, (d) verifies `hive --version`, (e) offers to run `hive init` in the current project, (f) when the agent host supports a marketplace (Claude Code → `claude plugin install …`, Codex → `codex plugin install …`, Pi → `pi install …`), also offers to install the hive skills marketplace.

**Files:**
- `install.md` (new, at repo root)
- `wiki/operating.md` — section pointing at it.

**Approach:**
- Single markdown prompt, ≤ 200 lines, structured as: goal → detect OS → channel decision tree → verify → init offer → optional skills install → final report.
- Embeds the exact channel commands so the agent doesn't have to guess. References `install.sh` URL pinned to a release tag (the user is told they can override via `HIVE_VERSION=`).
- Marketplace install lines are conditional: "if you are Claude Code, run X; if Codex, run Y; if Pi, run Z; otherwise tell the user how to install skills manually." If the skills repo doesn't exist yet at v0.1.0 ship time, the prompt states "skills package — coming soon at <URL>" and skips the marketplace step (acceptance C still passes, see U8).
- Idempotent: re-running on an already-installed system reports "already installed, version X" and exits without redoing work.
- The prompt **never auto-installs runtime deps** — it reports missing `git` / `gh` / `jq` / `claude` and asks the user to run platform-specific install commands.

**Test scenarios (all manual, no CI gate — agent-driven is non-deterministic):**
- Paste prompt into Claude Code on macOS arm64: channel = brew, install succeeds, `hive --version` reported, `hive init` offered, skills install offered.
- Paste prompt into Codex CLI on Arch: channel = AUR, install succeeds, skills install offered via `codex plugin install …`.
- Paste prompt into Pi on Ubuntu 22.04: channel = bash, install succeeds, skills install offered via `pi install …`.
- Paste prompt twice on the same machine: second run reports "already installed, current version: X" and exits.

**Verification:** End-to-end manual run on each of the three tier-1 OS × agent combinations above before tagging `v0.1.0`. Outcome is recorded in `wiki/decisions.md` (acceptance evidence).

---

### U8 — Skills package marketplace integration (reference only)

**Goal:** Document in `install.md` (U7) and `wiki/operating.md` the **command** each marketplace-aware agent uses to install the hive skills package. The hive skills package itself is a separate repo / separate plan.

**Files:**
- `wiki/operating.md` — table listing each agent's marketplace command.
- `install.md` — same commands embedded.

**Approach:**
- Plan only records command strings, not the package contents. Example shape: `claude plugin install <org>/hive-skills` (real URL set when the skills repo lands).
- If the skills repo doesn't exist yet by `v0.1.0` ship time, both files state "skills package — coming soon, link will be published at `<URL>`". Acceptance scenario C still passes because the prompt installer treats skills as optional and reports success on the core install.

**Test scenarios:** N/A — content-only.

**Verification:** doc review during the 5-review stage.

---

### U9 — Channel-marker write at install time

**Goal:** Make sure every channel installer writes the `install-channel` marker so `hive update` (U5) has a non-heuristic signal.

**Files:**
- `install.sh` (U2): writes `<data_home>/hive/install-channel` = `bash`.
- Homebrew formula (U3) `post_install`: writes `<HOMEBREW_PREFIX>/share/hive/install-channel` = `brew`.
- AUR PKGBUILD (U4) `package()`: writes `/usr/share/hive/install-channel` = `aur`.
- Running from a git clone with no marker: `Hive::InstallChannel.detect` falls back to `dev`.

**Approach:** Trivial in each installer; `Hive::InstallChannel.detect` uses the detection order specified in U5.

**Test scenarios:**
- All three installers, after a clean run, produce a marker readable by `hive update --dry-run`.
- `hive update --dry-run` from a git clone reports `channel: dev; suggested action: git pull`.

**Verification:** Covered by the integration tests in U2 / U3 / U4.

---

### U10 — Docs + tier matrix in `wiki/operating.md` and `README.md`

**Goal:** A single canonical install section in `wiki/operating.md` listing all four channels and the tier matrix; replace the current `Install` block in `README.md` with a short summary that links there and to `install.md`.

**Files:**
- `wiki/operating.md` — new "Install" subsection.
- `README.md` — replace the current `## Install` block.
- `CHANGELOG.md` — entry under "Added — Install channels" in `## [Unreleased]`.

**Approach:** Straight prose + tables. Tier-1 vs tier-2 vs tier-3 unambiguous; call out "Apache Hive collision → use `hv`"; cross-link `install.md`.

**Test scenarios:** N/A.

**Verification:** doc review during 5-review.

---

## Risks

1. **Tebako fails on the pinned native-FFI gems** (`bubbletea-ruby` 0.1.4, `lipgloss-ruby` 0.2.2). Bubbletea is pinned exactly because `Hive::Tui::PasteAwareRunner` reads private superclass ivars — even a patch bump could silently break it.
   - **Mitigation:** U1.0 spike validates this before any release-pipeline work. Fallback path is `ruby-packer`, then a fat-tarball strategy (vendored Ruby + gems + thin `hive` wrapper). If the chosen strategy requires a runtime Ruby on the user's machine, the brew formula gains `depends_on "ruby@3.4"` and the AUR package switches from `hive-bin` to `hive` (script-based). The brainstorm's "stick to best practices" answer reconciles cleanly with either outcome.

2. **Apache Hive PATH collision** is more common than the brainstorm's "if `hive` conflicting we can use `hv`" treats it.
   - **Mitigation:** all three installers detect and drop `hv`; AUR uses `conflicts=('hive' 'apache-hive')` for a clean pacman refusal (with `hv` unavailable in that case, as called out in U4). The fallback is documented in `wiki/operating.md` and `install.md`.

3. **`hive update` cannot detect channel when the user moved the binary** (e.g. cp'd the brew bottle into `/usr/local/bin/`).
   - **Mitigation:** prefer the explicit marker file (set by every installer at install time); fall back to path-based inference; fall back to a clear error message. Never guess across channels — a wrong inference would `yay -Syu hive-bin` on a brew install and corrupt it.

4. **macOS Gatekeeper / quarantine xattr** blocks the binary when downloaded via the bash one-liner.
   - **Mitigation:** the installer runs `xattr -d com.apple.quarantine` on the unpacked binary on macOS. Notarization is documented as a v0.2 follow-up.

5. **launchd absolute-path requirement** breaks when `which hive` points at a brew shim or asdf/mise shim.
   - **Mitigation:** `ServiceInstaller` resolves the real path via `File.realpath(which("hive"))`. The existing `examples/launchd/hive-daemon.plist`'s `[ -x "$0" ] || exit 0` circuit-breaker already prevents a respawn loop on a bad path, so even a stale plist on disk degrades gracefully.

6. **AUR maintainer expectations** (responsiveness, namcap cleanliness, no upstream URL drift).
   - **Mitigation:** dedicated `aur-publish` job in `release.yml` using a service AUR account's SSH key (GH Actions secret); CI runs `namcap PKGBUILD .SRCINFO` before push; release-finalize fails non-fatally on a publish error so the GitHub Release still ships and the AUR push can be retried.

7. **`curl … | bash` security posture.**
   - **Mitigation:** `install.sh` lives at a pinned `raw.githubusercontent.com` URL; the tarball it downloads is SHA256-verified against the release's signed `SHA256SUMS`. A `--dry-run` flag prints the would-be actions without executing. The `curl -fsSL … -o install.sh && bash install.sh` two-step pattern is documented as the recommended path for users who want to inspect first.

8. **Prompt installer (U7) is non-deterministic.** Agents may misidentify OS or skip steps.
   - **Mitigation:** the prompt explicitly tells the agent to run `hive --version` as the success gate and to either confirm success or hand back to the user on failure. No CI for this surface; manual run per tier-1 × agent combo before tag.

9. **Legacy per-user state migration.** If `Hive::Config.registered_projects` (or any other current path) actually writes outside the project's `.hive-state/` today (e.g. to `~/.hive-state/registry.yml`), users upgrading to v0.1.0 will lose that registry when paths move to XDG. <!-- hive-bench: repo-state assertion, verify against the restored base -->
   - **Mitigation:** during U5 implementation, audit `Hive::Config` and any other per-user write sites. If found, add a one-time migration shim in `Hive::Paths.ensure_migrated!` (called once at CLI boot): "if legacy path exists AND current does not, move it." Idempotent on every CLI start.

10. **Skills package timing.** Acceptance scenario C asks the prompt installer to install skills via the marketplace, but the skills package is a separate repo not yet built.
    - **Mitigation:** Acceptance C is graded "passes if skills marketplace URL is wired; passes-with-note if skills repo is still TBD at `v0.1.0` ship". The plan never blocks on skills.

11. **GitHub Releases API rate limit** hit by the bash installer's "fetch latest version" call.
    - **Mitigation:** the installer accepts `HIVE_VERSION=` env override, falls through unauthenticated to the API once (60 req/h per IP — adequate for normal use), and surfaces a clear "set HIVE_VERSION=vX.Y.Z to skip the API call" hint on 403.

12. **Build matrix divergence** between platforms (Tebako's macOS output uses `dlopen`-style native gem loading; the Linux output may use `dlmopen`). Two platforms could ship subtly different binaries.
    - **Mitigation:** every binary is smoke-tested in CI (`./hive --version`, `./hive doctor`, `./hive tui` headless boot) before being attached to the release; mismatched behavior fails the release workflow.

<!-- COMPLETE -->
