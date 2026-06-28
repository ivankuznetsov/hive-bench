# Log

Reverse-chronological work log. Add fragments under `wiki/log.d/` and compile here.

## 2026-06-27 — v2: drive real hive

- Pivoted from v1 (imitate hive) to v2 (drive REAL hive) after v1 showed the toy planner was
  the wrong measurement — real `/ce-plan` was worth ~2 judge points. See [[findings]].
- Built the v2 driver: `hive_driver.rb`, `hive_config.rb`, `hive_stages.sh`, `candidates.rb`,
  `hive_run.rb`; baked hive into `Dockerfile.runner`. Committed `100314b`.
- Solved the container integration through a long bring-up (Stage A/B): non-root, writable
  `.claude` tmpfs (the Bash-tool bug), `/ce-plan` plugin resolution, worktree off base_commit,
  telemetry from hive's logs. See [[architecture]].
- **Proven:** all-opus-4.8 → real `/ce-plan` (15-unit plan) + execute (1300-line diff matching
  the reference file-set), judged vs gold: opus 7.5–8.0 / gpt 4.0 (add-i-key),
  7.0 / 2.0 (figure-out-install). Resolved the `/ce-plan` scope variance as 2/3-good.
- Set up this wiki + `HANDOFF.md` for cross-machine continuation.

## 2026-06-25/26 — v1: dual-judge corpus×slate pass

- Ran the v1 corpus × slate (frozen-plan exec, from-idea self-plan, handoffs, raw incumbent)
  with the dual judge (opus-4.8 + gpt-5.5-pro). Published v1 `RESULTS.md` + token-based costs.
- Findings that motivated v2: the refined `/ce-plan` plan beats from-idea by ~2 gpt-points;
  the brainstorm carries scope; cost inverts (closed models pricier at API rates); judge
  calibration (opus generous, gpt strict, agree on ordering). See [[findings]].
- Fixes: new-files capture, vendored-tree excludes, per-judge fail-soft, judge max_tokens cap.
