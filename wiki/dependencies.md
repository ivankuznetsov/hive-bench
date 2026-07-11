# Dependencies

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
