# Recover generated benchmark artifacts after result failures

- Hardened Hive stream telemetry parsing for valid events whose `message` is a
  string rather than a usage object.
- Made v2 retries reuse a non-empty `candidate.patch` when the persisted Hive
  stage transcript proves the cell completed plan and develop successfully and
  persisted task/base/candidate identity matches. Legacy artifacts require an
  explicit unverified-recovery opt-in; `--no-reuse-existing-artifacts` opts into
  a fresh generation. Provenance mismatches fail without deleting the saved run.
- Preserved generated cell records when every judge fails, with the missing
  scores represented by an empty `judges` map and the retry reason retained in
  `pending` or `failed`.
- Added regressions for Codex error events, artifact reuse/incomplete-artifact
  rejection, and all-judge outages.
