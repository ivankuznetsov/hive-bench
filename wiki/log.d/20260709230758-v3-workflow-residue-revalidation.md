# 2026-07-09 — v3 workflow residue revalidation

- Revalidated the global wiki after
  v3-bench-as-hive-workflow-260709-b3nc's wiki-only residual cleanup. Kept the
  broader generate-stage coverage in [[v3-workflow]] and [[gaps]] because the
  branch's canonical `workflows/bench/generate.md` still implements those
  guards, retry protections, and atomic campaign-root merge semantics.
- Recorded a newly verified gap: the committed
  `.hive-state/workflows/bench/generate.md` copy predates the canonical generate
  stage, so the no-cost smoke exits at its initial copy-drift assertion before
  exercising scenario coverage. The installed copy must be refreshed and the
  smoke rerun before it can be treated as green.
- Page coverage did not change, so [[index]] remains current. `wiki/log.md` was
  left for the post-commit compiler.
