# Add native Ox Alpha Pi and OpenCode benchmark support

- Registered separate `all-ox-alpha@high` Pi and
  `all-ox-alpha-opencode@high` OpenCode candidates with the same high reasoning
  tier across plan, execute, and review.
- Moved model selection to Hive's provider-neutral stage routes, mounted the
  exact selected Hive runtime per cell, and recorded its version in generation
  identity. The mounted checkout's Hive and Agent CLI Runtime libraries now
  precede installed gems, so component fixes cannot be silently bypassed.
- Added the pinned OpenCode runner, hermetic Ox Alpha capability declaration,
  local Compound Engineering package, and a fail-closed 33-workflow CE gate.
  The image builder now applies both Pi/default and OpenCode tags in one build,
  avoiding a manual retagging prerequisite on clean hosts.
- Disabled plan review for both harnesses under Hive's explicit benchmark-only
  grant and continued a successful markerless plan promotion through the native
  `hive run` action before execution.
- Restricted provider-limit classification to trusted harness/stage channels,
  normalized only a literal null plan dependency, and removed failed zero-byte
  patch sentinels. A nonzero native plan result now stops before develop even
  when the failed stage left a partial `plan.md` artifact.
- Focused config, driver, stage, and Hive lifecycle tests pass. Paid parallel
  generation and Fable/Sol judge completion remain live evidence, not a result
  claimed by this fragment.
