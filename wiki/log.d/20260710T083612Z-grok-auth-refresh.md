# Grok benchmark containers can persist automatic authentication refresh

Grok candidate cells now use a separately authenticated benchmark credential
directory. Mounting only that directory read-write lets the CLI atomically
replace `auth.json` and coordinate through `auth.json.lock`, while each cell's
sessions, config, and leader state stay in a fresh `~/.grok` tmpfs. The
operator's normal refresh-token chain is neither copied nor mounted.

The driver regression tests require the isolated writable auth mount, the
`GROK_AUTH_PATH` override, and a trusted mode-0600 credential. This fixes the
live failure where authorization succeeded but ended with `Failed to save
credentials: Operation not permitted`, without duplicating a rotating refresh
token across independent lock domains.
