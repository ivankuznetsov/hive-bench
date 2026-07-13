# Publish the complete v2-ce preliminary evidence

Published the canonical 36-cell preliminary campaign as an auditable result
bundle under `runs/v2-ce/`. The bundle keeps the merged board plus every
per-cell result and final candidate patch, with a manifest that records
candidate/task identity, model version, byte size, and SHA-256 for each patch.

The repository's canonical secret scanner reported zero findings across all 72
published per-cell files. Raw model streams, target clones, Git databases,
credentials, and build logs remain untracked. The snapshot is explicitly
preliminary: one sample per Fable 5 / GPT-5.6 Sol judge-cell pair, Sol judging
at `xhigh`; the three-sample Sol-`ultra` replication remains follow-up work.
