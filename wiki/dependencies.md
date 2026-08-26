# Dependencies

## Agent CLI runtime

The bundle includes `agent-cli-runtime ~> 0.1.0`, published from Hive's
monorepo. `HiveBench::Profile#preflight` delegates deterministic local
prerequisite discovery to it: executable presence, bounded version probing,
the package-owned minimum version, and recognized authentication
configuration for Claude, Codex, Pi, and Grok.

This is deliberately not a live provider-health check. A configured credential
may still be expired, rate-limited, or unable to reach the provider. Keep the
paid Claude probe below and HiveBench's benchmark-specific Grok credential
validation before campaigns. HiveBench also retains ownership of model and
effort pins, container mounts, network policy, retries, and result
classification.

## Claude authentication

Fable judging and every Opus candidate use the host Claude Code session. Do
not rely on `claude auth status` alone: it reports `loggedIn: true` when an
expired access token is still present, even if the credentials contain no
refresh token. Verify the session with a small `claude -p` call before a paid
campaign and re-run `claude auth login` when it returns a structured 401.

Claude Code can put that structured failure on stdout while leaving stderr
empty. `ClaudeJudge` therefore falls back to bounded stdout text in its
nonzero-exit diagnostic, so judge repair reports the authentication cause
instead of `claude judge exited 1:` with no explanation.

The Codex CLI can put its provider error after a long startup banner or echoed
judge prompt. `CodexJudge` classifies the complete stderr stream before
truncating diagnostics and prefixes usage walls with `limits_reached`. Keep
that marker at the front of the exception: the campaign's judge-backfill log is
intentionally bounded, and the Hive lane relies on the marker to schedule a
timed daemon retry instead of stopping at `WAITING`.

Every persisted judge record includes `reasoning_effort` and
`reasoning_effort_explicit`. The Codex-backed GPT-5.6-sol judge records its
explicit `xhigh` pin. Fable 5 and the legacy OpenRouter GPT-5.5-pro judge record
`unspecified` because their CLI/API invocations contain no effort parameter.

`HiveBench::AgentLimit.retry_after` converts an explicit Claude UTC reset hint
such as `resets 12am (UTC)` into the next matching boundary plus a one-minute
grace period. Benchmark workflows should pass only diagnostics produced during
the current lane attempt; missing, stale, malformed, or non-UTC hints retain
the conservative one-hour fallback.

## Grok authentication

`all-grok-4.5` uses a benchmark-specific OIDC login. Create it once without
touching the operator's normal Grok login:

```bash
install -d -m 700 ~/.local/state/hive-bench/grok-auth
GROK_AUTH_PATH="$HOME/.local/state/hive-bench/grok-auth/auth.json" grok login
```

The auth directory can be overridden with `HB_GROK_AUTH_DIR`. Generation
containers keep `~/.grok` ephemeral and mount only this directory read-write at
`~/.grok-auth`, with `GROK_AUTH_PATH` selecting its `auth.json`. That gives all
parallel Grok cells one refresh-token chain and one adjacent `auth.json.lock`,
while sessions, configuration, and leader state remain isolated per cell.
The runner also creates an ephemeral `~/.grok/auth.json` symlink because Hive
0.3.6 checks that legacy path before launching Grok even when
`GROK_AUTH_PATH` is set. The symlink is a preflight compatibility view, not a
second credential copy or lock domain.

Do not copy `~/.grok/auth.json` into the benchmark directory: OIDC refresh
tokens rotate, so two copies with independent lock files can invalidate each
other and cause either the host CLI or the benchmark to appear logged out.

## Pi and GLM tool streaming

Pi drives `all-glm-5.2` through OpenRouter. GLM tool arguments are buffered by
default, so a large `write` call can produce no stream traffic long enough for
OpenRouter's upstream idle timeout to close an otherwise healthy response. Pi
cells load `harness/lib/pi_tool_stream.ts`, which adds GLM's provider-specific
`tool_stream: true` request field for `z-ai/glm-5.2` only. This changes the
transport framing, not the candidate model, prompt, tools, or generated tool
arguments.

## Ox Alpha through Pi and OpenCode

The single-family `all-ox-alpha@high` candidate routes plan, execute, and
review through Pi as `openrouter/stealth/ox-alpha:high`. A separate
`all-ox-alpha@max` row pins `openrouter/stealth/ox-alpha:max` across those same
three stages. The explicit suffixes are part of each candidate identity rather
than relying on the provider default. The runner mounts a minimal Pi OpenRouter
catalog and writes the existing `OPENROUTER_API_KEY` into Pi's ephemeral native
auth store without persisting or printing it.

`all-ox-alpha-opencode@high` runs the same three stages as
`openrouter/stealth/ox-alpha` with OpenCode variant `high`. It uses the separate
`hive-bench-runner:opencode` image with OpenCode `1.18.18` and Compound
Engineering `3.22.4` at `/opt/compound-engineering`. Before Hive starts, the
stage script verifies the local plugin config, the required plan/work/review
commands, and an exact 33-workflow CE inventory. The OpenCode profile is
hermetic, declares the Ox Alpha capability locally, and receives only the named
`OPENROUTER_API_KEY` credential. Its scoped tool policy grants read, write,
edit, and explicitly qualified `Bash(*)`, matching Pi's ability to run tests
and repository diagnostics inside the disposable candidate container. The
exact-base checkout and provider-only egress proxy, not an OpenCode shell
handicap, enforce benchmark containment.

Both candidates serialize `plan_review.enabled: false` and require the
process-local `HIVE_BENCH_ALLOW_DISABLED_PLAN_REVIEW=1` grant. No critique
model is inserted before execution, keeping Pi and OpenCode on the same
historical benchmark contract. Fable and Sol are judges only and run after a
candidate patch is generated.

Hive intentionally redacts OpenCode provider events from stage logs, but writes
normalized per-session usage into the cell-local SQLite store at
`.hb/hive-home/usage.db`. The benchmark has a direct `sqlite3` dependency and
uses those OpenCode rows when the raw log scan has no token evidence. Database
cache-read values take precedence over the legacy `cached` alias so one session
cannot be counted twice.

The exact Hive runtime mount also puts that checkout's
`components/agent-cli-runtime/lib` and `lib` directories first on `RUBYLIB`.
Invoking the mounted `bin/hive` directly would otherwise resolve the
host-installed component gem, silently bypassing component changes in the
selected checkout even though Hive's own source came from the mount.
