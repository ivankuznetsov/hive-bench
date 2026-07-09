# 2026-07-09 — v3 workflow fragment refresh

- Inspected v3-bench-as-hive-workflow-260709-b3nc's workflow-refresh commit.
  The diff is changelog-only: it adds the `bench workflow review fix pass 1`
  fragment, removes the later duplicate refresh fragment, and touches the
  compiled `wiki/log.md` (left for the post-commit compiler here).
- Rechecked the branch's `workflows/bench/{generate,judge,publish}.md`,
  `campaign.yml.example`, `harness/merge_results.rb`, and
  `tmp/bench-workflow-smoke.sh`. The main wiki's [[v3-workflow]] and [[gaps]]
  already describe the verified state: per-cell results merge into the
  campaign-root `results.json`, bought/walled cells are not regenerated,
  judge/publish use guarded extraction and scratch files, and smoke coverage
  remains no-cost/stubbed rather than a real paid campaign run.
- No page coverage changed, so [[index]] needed no new page entry.
