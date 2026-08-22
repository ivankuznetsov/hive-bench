# Complete the Ox Alpha Pi and OpenCode comparison

- Finished all six Pi and all six OpenCode cells using OpenRouter
  `stealth/ox-alpha` at high reasoning with plan review disabled in both
  harnesses.
- Validated 12 distinct generated cells, zero pending, zero failed, and three
  Sol `ultra` samples on every row. Five rows also have three Fable samples;
  seven lack Fable scores because the Claude session cap was reached earlier.
- Retained separate six-cell results plus a canonical 12-cell combined result.
  Pi's Sol mean is 3.794; OpenCode's is 3.000.
- Confirmed the OpenCode run config mounted Compound Engineering, exposed its
  skills path, and generated all 33 CE commands.
- Recorded the recovery caveat: one pre-fix timeout lost the original Pi
  fix-review candidate and required fresh generation; later timeout recoveries
  preserved and reused the daemon and web-install artifacts successfully.
