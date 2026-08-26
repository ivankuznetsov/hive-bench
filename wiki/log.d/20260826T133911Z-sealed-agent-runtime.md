# Seal benchmark controller source from candidate models

- Audited the Ox Alpha Pi/OpenCode artifacts. No log or patch-overlap evidence
  showed an actual reference-solution lookup, but the candidate could read the
  mounted current Hive checkout and the image's installed `hive-cli` source.
  Older rows also retained future Git objects and ordinary GitHub egress.
- Split the runner gems into a root-only, exact-commit-labelled Hive control
  bundle and a uid-1000 candidate bundle with every `hive-cli` path removed.
- Added Pi and OpenCode privilege-dropping launchers, zeroed candidate Linux
  capabilities, omitted host runtime mounts in sealed mode, and failed closed
  on image/runtime SHA mismatch or unsupported candidate harnesses.
- Reconciled base-only depth-one checkouts and provider-only CONNECT egress into
  the canonical harness. Generation identity now binds all three isolation
  properties, preventing reuse of older artifacts under the sealed contract.
- Verified in a real container that root can run Hive 0.7.2 while the candidate
  uid cannot read the control bundle or `/proc/1/root`, cannot discover the
  `hive-cli` gem, retains ordinary dependencies, and has zero effective caps.
- Superseded every existing Ox Alpha Pi/OpenCode score pending sealed parallel
  replacement campaigns.
