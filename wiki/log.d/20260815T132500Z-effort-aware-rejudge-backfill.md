# Make rejudge backfill effort-aware

- Changed `rejudge.rb --only-missing` to require both the configured sample
  count and, when pinned, the configured reasoning effort before reusing an
  existing judge record.
- Added regression coverage proving an `xhigh` Codex record is rejudged when a
  campaign requires `ultra`, while judges without an effort pin remain
  sample-count based.
- Fresh replacement records now take the invocation effort before they merge
  with untouched incumbents; rejudge no longer applies an effort override to
  the whole output and falsely relabels skipped judges.
- Judge-effort keys are normalized for library callers, and legacy incumbents
  regain missing provenance fields without overwriting stored values.
- An end-to-end `rejudge_cell` regression proves a wrong-effort judge is
  replaced while a satisfied judge is left unchanged.
- This aligns retry selection with judge-stage validation and prevents a retry
  loop that repeatedly skips a record validation must reject.
