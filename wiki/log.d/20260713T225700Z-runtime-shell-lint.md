---
title: Runtime shell lint compatibility
type: change
date: 2026-07-13
---

- Parse optional runner-image build arguments into a Bash array before passing
  them to Docker, avoiding implicit word splitting.
- Inventory mounted Codex and Pi skill directories with `find` instead of
  parsing `ls`, keeping the canonical harness synchronized with Hive's
  packaged runtime snapshot.
