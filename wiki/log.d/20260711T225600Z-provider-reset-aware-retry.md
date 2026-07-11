# Align provider retries with explicit UTC reset hints

- Added a narrow parser for Claude's `resets <time> (UTC)` session-limit hint.
- Retry timestamps use the next stated boundary plus one minute; absent or
  non-UTC hints continue to use the one-hour fallback.
- This keeps Hive as the sole lane dispatcher while avoiding an extra cooldown
  when a generic one-hour retry lands just before the provider reset.
