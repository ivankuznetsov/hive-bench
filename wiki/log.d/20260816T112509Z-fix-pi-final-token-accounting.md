# 2026-08-16 — Count only final Pi usage events

- Corrected `HiveDriver` and `TokenReport` so Pi-backed candidates count each
  assistant `message_end`. Pi's `message_update` and `turn_end` events repeat
  the same response usage and are not additional model calls.
- Added regression coverage with two realistic update/end/turn-end sequences,
  proving finalized responses accumulate while their copies do not.
- Reconstructed all six published GLM cells from their retained final events;
  the token and usual-tier cost corrections do not alter candidate patches,
  judge scores, or wall times.
- Marked the older `RESULTS.md` Pi-backed Kimi and mixed totals as unknown
  because their retained streams are not committed and cannot be corrected.
