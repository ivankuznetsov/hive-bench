# Grok benchmark auth is visible to Hive's legacy preflight

Hive 0.3.6 checks only `~/.grok/auth.json` before it launches the Grok agent.
After the benchmark moved its canonical refreshable credential to
`GROK_AUTH_PATH`, Hive returned a successful no-agent plan transition and the
harness surfaced `execute_failed` without ever starting Grok.

The in-container stage shim now exposes a symlink from the legacy path inside
the per-cell tmpfs to the canonical benchmark auth file. A regression test
executes that exact shell block and verifies the link target. Missing
credentials or symlink-setup failures now stop with an explicit `HB_ERROR`
instead of falling through to Hive's opaque no-agent result. This preserves a
single credential and refresh-lock domain while satisfying the older Hive
preflight.
