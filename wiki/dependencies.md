# Dependencies

Confirmed dependencies and local assumptions for `hive-bench`.

## Runtime

- Ruby 3.4 plus the bundle in `Gemfile`.
- Docker for generation containers and no-network gate containers.
- A local clone of hive, passed as `HIVE_SRC` for `harness/build_runner.sh` and
  `--source` for `harness/hive_run.rb`.
- `hive-bench-runner:latest` by default. Grok cells currently require a
  grok-enabled runner image (`HB_RUNNER_IMAGE=hive-bench-runner:grok`) until the
  pinned runner includes hive's grok support.

## Agent CLIs And Auth

- `claude` authenticated on the host. The driver requires
  `~/.claude/.credentials.json`, `~/.claude/settings.json`, and
  `~/.claude/plugins`; commands are mounted if `~/.claude/commands` exists.
- `codex` authenticated on the host via `~/.codex/auth.json`. The driver
  generates a per-cell `~/.codex/config.toml` inside the container instead of
  mounting the operator's config.
- `pi` for OpenRouter-backed open-model runs. `OPENROUTER_API_KEY` is forwarded
  when pi is used, and the harness injects per-stage pi model pins through
  `HB_PI_MODEL_<STAGE>`.
- `grok` authenticated through `~/.grok/auth.json` for `all-grok-4.5` cells.
  The harness injects `HB_GROK_MODEL` and `HB_GROK_EFFORT`.

## External Services

- OpenRouter for `gpt-5.5-pro` judging and pi-backed glm/kimi candidates.
- Claude/Fable through the claude CLI for fable judging and claude candidates.
- Provider limits are expected operational events; the harness classifies walls
  as `limit_hit`/pending rather than failed cells.

## Local Skill/Plugin Inputs

- Claude `/ce-plan` resolves from the mounted claude plugins/commands.
- Codex and pi Compound Engineering skills are mounted read-only from the host
  and linked into writable CLI home directories inside the container.

## Isolation Controls

- Generation containers are resource-capped and need model API egress; optional
  `HB_GEN_NETWORK` can attach them to an allowlisted Docker network.
- Gate containers run without network and require verbose per-test output so
  every declared gate test is positively observed.
