<!-- AGENT_WORKING pid=1900665 started=2026-05-13T21:26:35Z -->

## Round 1

### Q1. What exactly is "hive" from a packaging point of view today — is it a single CLI binary, a collection of shell/ruby/python scripts under `~/Dev/hive/`, a set of markdown templates + Claude Code skills, or some combination? List the actual artifacts a user needs on disk for `hive` to work end-to-end.
### A1.
collection of scripts with a daemon with a cli/tui
### Q2. Which install channels do you want to support in v1 of this "simple package", and is there a primary one? Options: Homebrew tap (mac + linuxbrew), `curl ... | bash` one-liner, native packages (deb/rpm/AUR), language package managers (gem / pipx / cargo / npm), Nix/Flake, manual `git clone` script. Pick the must-haves vs nice-to-haves.
### A2.
brew, aur, bash one liner, install as prompt (prompt that i give to claude and it install the best way)
### Q3. What is the canonical "installed" layout on a user's machine after a fresh install — i.e. where do binaries, the meta-pipeline assets (stage templates, prompts, agents), the per-user state (`~/.hive-state/...`), and config (e.g. model/provider) each live? Should it follow XDG (`~/.local/bin`, `~/.config/hive`, `~/.local/share/hive`, `~/.cache/hive`) or stay at the current `~/Dev/hive/` convention?
### A3.
stick to best practives 
### Q4. What are the hard runtime dependencies that the installer must check for / install, and what is the policy when they are missing? Candidates: `git`, `bash`, `python3` (which minimum?), `ruby` (which minimum?), `claude` CLI (Claude Code), `gh`, `jq`. Should the installer auto-install them, just warn, or hard-fail?
### A4.
you check yourself 
### Q5. Should there be one single command surface (`hive`) that users invoke, or do you also want global slash-command integration with Claude Code (e.g. `/hive` in `~/.claude/commands/`)? If both — how does the install step register slash-commands without clobbering user customizations?
### A5.
claude install is separate as a hive skill for claude / codex / pi / openclawd channel 
### Q6. What's the update story you want? Pinned releases (e.g. `brew upgrade hive`, semver tags) vs rolling/main-tracking vs both via channels (stable/edge)? And do you want a `hive self-update` subcommand so users don't have to remember the channel-specific command?
### A6.
pinned releases, with hive update 
### Q7. How should per-project initialization work after global install — is there a `hive init` that scaffolds the project's `.hive/` directory and Claude Code commands, or does the pipeline create everything lazily on first `/hive` invocation? Where does first-run config (provider keys, model choices) get collected?
### A7.
hive init. first run config stick to best practices
### Q8. What does "uninstall cleanly" look like — only remove the binary, or also remove `~/.config/hive`, `~/.hive-state`, project-level `.hive/` directories, and any Claude Code slash-commands hive registered? Should state ever be preserved on uninstall by default?
### A8.
we need to ask user about it i think 
### Q9. Which platforms are tier-1 (must work on day one), tier-2 (best-effort), and tier-3 (explicitly out-of-scope) for v1? E.g. macOS arm64, macOS x86_64, Ubuntu 22.04+, Debian 12+, Arch, Fedora 40+, Alpine, WSL2, NixOS, BSDs.
### A9.
macOS arm, ubunti 22.04, Arch first 
### Q10. What signals "v1 is done" — give 2–3 concrete acceptance scenarios. Example shape: "On a clean macOS arm64, `brew install hive/tap/hive && hive init && /hive 'add login form'` works end-to-end with no manual file copying." What are yours?
### A10.
for me the same but for arch as well, also i can give prompt to claude and it will install the best way for my sistem 

## Round 2

### Q11. What language(s) is hive actually implemented in today, and what's the language of the daemon vs the CLI/TUI? This drives packaging fundamentally — a Ruby gem + bash, a single Go/Rust binary, or a Python project (pipx) all have very different brew/AUR/one-liner recipes. Please name each piece (daemon, CLI, TUI) with its runtime.
### A11.
you can check the code (ruby, it's ruby)
### Q12. Where does hive's source / release artifacts live (or will live) — a public GitHub repo with tagged releases and prebuilt tarballs, a private repo, just `main` branch installs? The brew formula, AUR PKGBUILD, and `curl | bash` script all need a stable download URL and signed/checksummed releases. Confirm: github.com/<owner>/hive with GitHub Releases as the canonical artifact source?
### A12.
public github repo with tagged releases 
### Q13. The daemon — should the installer also register it as a background service (launchd on macOS, systemd user unit on Linux), or is it expected to be started on demand by the CLI/TUI? If autostart: should that be on by default after `hive init`, opt-in via a flag, or never (user does it manually)?
### A13.
yes it should register as a service 
### Q14. "Install as a prompt the user gives Claude" — flesh this out. Is this (a) a published prompt snippet the user copy-pastes into Claude Code, (b) a Claude Code skill / `~/.claude/skills/hive-installer/` that's distributed separately, or (c) an MCP server? And what is its job exactly — detect the OS and run the right native installer (brew/aur/bash), or do the install itself end-to-end from scratch?
### A14.
published ready to use prompt, tracks os, select best way to install, verify it works, helps user to setup project 
### Q15. The "hive skill for claude / codex / pi / openclawd" channel — is this one cross-tool skill package or per-tool packages? After `hive init` in a project, who is responsible for writing slash-commands / skills into `~/.claude/commands/`, `~/.codex/...`, etc. — the global `hive` install, the per-project `hive init`, or this separate skill package?
### A15.
separate skills package i think installable via existing approved agents path 
### Q16. Binary / command naming and conflicts: do you want the user-facing command to be exactly `hive`? Note `hive` collides with Apache Hive on some dev machines. Are you OK with that risk, or do you want a fallback name (`hivectl`, `hv`) when a conflict is detected? Same question for the AUR package name (`hive` vs `hive-bin` vs `hive-git`).
### A16.
hive-bin for arch package, if hive conflicting we can use hv 
### Q17. Versioning + release cadence: semver from v0.1.0 with GitHub Releases as the single source of truth? Do you want `hive update` to (a) just shell out to the channel's native updater (`brew upgrade`, `yay -Syu hive`, re-run the bash one-liner) or (b) download and swap the binary itself in-place? The latter conflicts badly with brew/AUR-managed installs.
### A17.
a 
### Q18. Uninstall confirmation prompts — what's the granularity? One yes/no for "remove everything", or separate prompts for: (1) binaries, (2) global config `~/.config/hive`, (3) global state `~/.hive-state`, (4) per-project `.hive/` directories under known roots, (5) Claude/Codex slash-commands? Should `hive uninstall --purge` exist for non-interactive CI use?
### A18.
only project related content -- don't lose the work done, also skills removed separately in agents 

## Round 3

### Q19. Ruby distribution strategy — since hive is Ruby, what runtime does the installed package assume? Options: (a) require the user's system Ruby (which minimum, 3.2+?), (b) ship a vendored Ruby (mruby/ruby-packer/Tebako) so `hive` runs as a self-contained binary, (c) install via `gem install hive` under the hood. This decision propagates: brew formula style (`depends_on "ruby"` vs bottled binary), AUR package type (`hive-bin` only makes sense if we ship a real binary), and the bash one-liner's complexity. Pick one primary path.
### A19.
what is the best practices
### Q20. Homebrew distribution — own tap (`brew install rabata/hive/hive`) or attempt homebrew-core inclusion? Tap is much faster to ship and we control releases; core has stricter rules and review latency but higher trust. Confirm: start with own tap under your GitHub org for v1, revisit core later?
### A20.
tap and code later 
### Q21. Service autostart default — when `hive init` (or post-install hook) registers the daemon with launchd/systemd-user, should it (a) be enabled and started immediately by default, (b) installed but disabled, requiring `hive daemon start` to activate, or (c) prompt the user during init? Same answer for both macOS launchd and Linux systemd --user?
### A21.
c 
### Q22. "Prompt installer" acceptance — what does success look like operationally? A single markdown prompt at e.g. `install.md` in the repo (or pinned gist URL) that the user pastes into Claude/Codex/etc. The prompt is considered correct when it: detects OS, picks brew/aur/bash, runs it, runs `hive --version` to verify, then runs `hive init` in the cwd. Do you also want it to install the separate skills package, or is that a follow-up step the user takes manually?
### A22.
if it can do it properly (via marketplace not copy-pastes) yes we need to install skills 
### Q23. Skills package distribution channel — "installable via existing approved agents path" — concretely, which paths are in scope for v1? Claude Code (`~/.claude/skills/`), Codex CLI (`~/.codex/skills/` or wherever), and which else? Is the skills package a separate GitHub repo (`hive-skills`) with its own release artifacts, a subfolder in the main hive repo, or a published thing on a registry (npm/gem)? Who is responsible for installing it — the user, or does `hive` have a `hive skills install <agent>` command?
### A23.
use claude add marketplace and same for pi and codex 

## Requirements

### Actor
- Developer on macOS arm64, Ubuntu 22.04+, or Arch Linux who wants to install the `hive` meta-pipeline as a single, idiomatic package and use it across multiple projects.
- AI coding agent (Claude Code, Codex, Pi) acting on behalf of the user when invoked via the published "install prompt".

### Source of truth
- Public GitHub repo with tagged semver releases (start at v0.1.0); GitHub Releases is the canonical artifact source for every channel.
- Hive itself is implemented in Ruby (daemon + CLI/TUI), so the release pipeline must produce a self-contained, vendored-Ruby binary (e.g. Tebako/ruby-packer) per tier-1 target to keep brew/AUR/bash-one-liner installs uniform and runtime-free.

### Install channels (v1)
- **Homebrew tap** under the project's GitHub org (`brew install <org>/hive/hive`); revisit homebrew-core later.
- **AUR** package `hive-bin` (prebuilt binary), with `hive-git` left for later.
- **Bash one-liner** `curl -fsSL <release-url>/install.sh | bash` that detects OS/arch and drops the right binary under XDG paths.
- **Prompt installer** — a single published markdown prompt the user pastes into Claude/Codex/Pi; it detects OS, picks brew/aur/bash, runs the install, verifies `hive --version`, prompts to run `hive init`, and (when the host agent supports a marketplace, not copy-paste) also installs the separate skills package.

### Skills package (separate distribution)
- Distributed as a separate package installed via each agent's native marketplace flow (Claude Code "add marketplace", and the Pi / Codex equivalents).
- Never installed by the core `hive` binary install; only optionally installed by the prompt installer when a real marketplace mechanism exists.

### On-disk layout (XDG best practices)
- Binary: `~/.local/bin/hive` (or `/opt/homebrew/bin/hive` when installed via brew).
- Config: `~/.config/hive/` (provider keys, model choices, defaults).
- Shared assets (stage templates, prompts, agents): `~/.local/share/hive/`.
- State (per-user, per-project tracking): `~/.local/state/hive/` (matches the current `~/.hive-state/...` convention but XDG-correct).
- Cache: `~/.cache/hive/`.
- Project-level scaffold: `.hive/` inside the project, created by `hive init`.

### Runtime dependencies
- Installer detects required tools (`git`, `bash`, `claude`, `gh`, `jq`) and reports missing ones with actionable install hints rather than silently auto-installing them.
- Because hive ships a vendored Ruby, no system Ruby is required on the user's machine for tier-1 channels.

### Command surface
- One user-facing binary: `hive` (fallback `hv` automatically chosen when a conflicting `hive` is already on `PATH`, e.g. Apache Hive). The AUR package is always named `hive-bin` regardless.
- Subcommands required for v1: `hive init`, `hive update`, `hive uninstall`, `hive daemon {start,stop,status}`, `hive --version`.

### Daemon / service
- `hive init` registers the daemon as a launchd agent on macOS and a `systemd --user` unit on Linux.
- On registration, `hive init` **prompts** the user whether to enable + start it now (option c — same prompt on both platforms); never autostarts silently and never installs-disabled-by-default.

### First-run / per-project init
- `hive init` scaffolds the project `.hive/` directory, registers the daemon (with the prompt above), and collects first-run config (provider, model) into `~/.config/hive/config.yml` using XDG defaults.
- Slash-commands / Claude skills are *not* written by `hive init` — those come through the separate skills package via the agent's marketplace.

### Update story
- Pinned semver releases only; no rolling channel in v1.
- `hive update` shells out to the channel's native updater (`brew upgrade`, `yay -Syu hive-bin`, or re-runs the bash one-liner) — never swaps the binary in place, to avoid corrupting brew/AUR-managed installs.

### Uninstall
- `hive uninstall` only ever removes project-related hive content and the binary's registrations; it never deletes user work or completed pipeline state by default.
- The user is prompted before any project-scoped cleanup; skills are removed through the agent marketplace, not by this command.
- A non-interactive `--purge` flag may exist for CI but still preserves accumulated work artifacts.

### Platform tiers (v1)
- **Tier-1 (must work day one):** macOS arm64, Ubuntu 22.04+, Arch Linux.
- **Tier-2 (best effort):** macOS x86_64, Debian 12+, Fedora 40+, WSL2.
- **Tier-3 (out of scope v1):** Alpine, NixOS, BSDs.

### Acceptance scenarios
- **A. macOS arm64 / Homebrew:** On a clean macOS arm64, `brew install <org>/hive/hive && hive init && hive --version` succeeds; the daemon registers as a launchd agent, `hive init` prompts about autostart, and a project-scoped `.hive/` is created in the cwd. No system Ruby was installed.
- **B. Arch / AUR:** On a clean Arch box, `yay -S hive-bin && hive init` succeeds with the daemon registered as a `systemd --user` unit, `hive init` prompts about autostart, and `hive update` later upgrades via `yay -Syu hive-bin` (not in-place swap).
- **C. Prompt installer:** On any tier-1 OS, pasting the published install prompt into Claude Code triggers OS detection, picks the right channel (brew/aur/bash), runs it, verifies `hive --version`, runs `hive init`, and — when invoked from a marketplace-aware agent — also installs the hive skills package via that marketplace. The same prompt also works in Codex/Pi without modification.
- **D. Clean uninstall preserves work:** `hive uninstall` on any tier-1 OS removes the binary and daemon registration and prompts before touching `.hive/` content; previously completed pipeline outputs under `~/.local/state/hive/` and project-level work are retained unless the user explicitly opts in.

<!-- COMPLETE -->
