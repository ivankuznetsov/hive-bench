# Dependencies

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
