# 2026-07-09 — v3 bench workflow descriptor

- Documented branch `v3-bench-as-hive-workflow-260709-b3nc`: the `bench`
  custom hive workflow (`inbox -> extract -> generate -> judge -> publish ->
  done`) as canonical repo files plus an installed `.hive-state/workflows`
  copy for hive's loader.
- Added `campaign.yml.example` coverage as the pre-registration contract for
  one campaign per task folder.
- Added the no-cost smoke coverage: parse both descriptor copies, check drift,
  validate the campaign example, advance a throwaway task through all stages,
  and verify the generate-stage missing-campaign gate.
- Recorded operator flow, WAITING plus `touch <state_file>` retry semantics,
  and remaining manual pieces in [[v3-workflow]] and [[gaps]].
