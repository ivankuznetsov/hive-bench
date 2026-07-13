---
title: Record judge reasoning effort in benchmark results
date: 2026-07-12
---

- New and rejudged `results.json` cells include `reasoning_effort` and
  `reasoning_effort_explicit` on every judge record.
- GPT-5.6-sol is recorded as explicitly `xhigh`; Fable 5, legacy GPT-5.5-pro,
  and unknown judge IDs are recorded as `unspecified` rather than assigning an
  unverified provider default.
- Added a metadata-only annotator for existing result artifacts. It does not
  invoke judges or change scores.
