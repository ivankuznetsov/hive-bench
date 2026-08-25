# Dependencies

## Claude authentication

Fable judging and every Opus candidate use the host Claude Code session. Do
not rely on `claude auth status` alone: it reports `loggedIn: true` when an
expired access token is still present, even if the credentials contain no
refresh token. Verify the session with a small `claude -p` call before a paid
campaign and re-run `claude auth login` when it returns a structured 401.

Claude Code can put structured failures on stdout while leaving stderr empty.
`ClaudeJudge` therefore falls back to bounded stdout text in its nonzero-exit
diagnostic, so judge repair reports the authentication cause instead of
`claude judge exited 1:` with no explanation. Quota classification is narrower:
stderr uses the shared trusted limit parser, while stdout counts as quota
evidence only when it contains the standalone `usage`/`session` reset banner
(an optional `mise ... tools: claude@...` launcher line is ignored). Arbitrary
model prose on stdout is never allowed to schedule an automatic limit retry.

The Codex CLI can put its provider error after a long startup banner or echoed
judge prompt. `CodexJudge` classifies the complete stderr stream before
truncating diagnostics and prefixes usage walls with `limits_reached`. Keep
that marker at the front of the exception: the campaign's judge-backfill log is
intentionally bounded, and the Hive lane relies on the marker to schedule a
timed daemon retry instead of stopping at `WAITING`. Its per-call timeout is
3600 seconds; Sol at `ultra` may take more than 30 minutes on large diffs under
parallel load.

Every persisted judge record includes `reasoning_effort` and
`reasoning_effort_explicit`. The Codex-backed GPT-5.6-sol judge records its
explicit `xhigh` pin. Fable 5 and the legacy OpenRouter GPT-5.5-pro judge record
`unspecified` because their CLI/API invocations contain no effort parameter.

`HiveBench::AgentLimit.retry_after` converts an explicit Claude UTC reset hint
such as `resets 12am (UTC)` into the next matching boundary plus a one-minute
grace period. Benchmark workflows should pass only diagnostics produced during
the current lane attempt; missing, stale, malformed, or non-UTC hints retain
the conservative one-hour fallback.

## Runner and model routing

The selected `HB_RUNNER_IMAGE` must contain Hive and the candidate CLIs. The
installed 2026-08-25 harness uses that image's baked Hive runtime directly; it
does not overlay the host's active Hive source/gem home, set `RUBYLIB` to a host
runtime, or verify `HB_HIVE_VERSION` inside the container.

Candidate model and effort belong to Hive's provider-neutral `models:` stage
routes. The shared Agent CLI runtime renders provider-native flags for Claude,
Codex, Pi, and Grok. The generated per-cell Codex `config.toml` now contains only
Compound Engineering plugin registration and `/work` trust; it does not carry
candidate model/effort. The removed OpenCode/Ox Alpha path no longer needs the
OpenCode-specific runner, plugin preflight, model catalog, or probe-timeout
override.

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
arguments. The container wrapper now does only two Pi-specific jobs: activate
that extension and create a non-secret, non-empty `~/.pi/agent/auth.json`
descriptor when Hive's preflight needs one. Pi still consumes
`OPENROUTER_API_KEY` from the environment, while the exact model comes from
Hive's native route; no benchmark-local Pi launcher or provider model catalog is
mounted.

Pi reports cumulative usage repeatedly on `message_update`, `message_end`, and
`turn_end`. Only final assistant `message_end` records are billable responses.
The installed snapshot currently sums every usage-bearing event, so Pi token
and cost telemetry from it is not publishable until the final-event filter is
restored; see [[gaps]].
