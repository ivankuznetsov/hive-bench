# 2026-07-13 — Add serialized mixed-model follow-up workflows

- Added Sol xhigh plan → Terra xhigh execute, Fable 5 high plan → Grok 4.5
  xhigh execute, and Sol xhigh plan → Grok 4.5 xhigh execute candidate profiles.
- All three profiles use Sol xhigh as the sole production reviewer through
  Codex `ce-code-review`, keeping review policy fixed while planner/executor vary.
- Added stage-specific Codex model/effort pins and container shim propagation so
  Sol and Terra can occupy different stages even though both use Hive's `codex`
  agent profile.
- Kept the native bench campaign serial: one task walks one cell at a time; the
  campaign contract retains three Fable + Sol-ultra judge samples and adversarial
  deliberation.
- Synchronized the runtime into Hive's packaged `bench` workflow; GPT-5.6 cells
  select the Codex-0.144+ `sol` runner, which also contains Grok for mixed cells.
