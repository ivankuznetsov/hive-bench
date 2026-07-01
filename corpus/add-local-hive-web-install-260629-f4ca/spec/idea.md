---
slug: add-local-hive-web-install-260629-f4ca
created_at: 2026-06-29T08:23:29Z
original_text: |
  Add local Hive web install/run mode alongside Docker
---

# add-local-hive-web-install-260629-f4ca

Add local Hive web install/run mode alongside Docker

Request details:

- Add a first-class local web mode for Hive so the same pipeline can be accessed via both the TUI and the web UI.
- Keep Docker/hivebox as one supported install/run method.
- Add another supported local runtime path, similar in spirit to how OpenClaw/OpenClawd runs locally without requiring Docker.
- In the local runtime path, the Hive daemon should work by default so newly created tasks are picked up automatically.

<!-- WAITING -->
