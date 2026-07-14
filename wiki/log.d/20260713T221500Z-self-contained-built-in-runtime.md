---
title: Self-contained built-in benchmark runtime
type: change
date: 2026-07-13
---

- The Hive package now owns a versioned copy of the maintained harness,
  `Dockerfile.runner`, `.dockerignore`, and `campaign.yml.example`.
- `hive init --workflow bench` installs that snapshot under
  `.hive-state/bench-runtime`, removing the separate hive-bench checkout from
  the local campaign path.
- The hive-bench repository remains canonical for public corpus submissions,
  published evidence, methodology, and future runtime synchronization.
