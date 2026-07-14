# Use Hive's built-in benchmark workflow

- Removed the duplicate project workflow descriptor and stage instructions;
  Hive now owns the named `bench` workflow and its packaged prompts.
- Updated the no-cost smoke to load `Hive::Workflows::Registry.fetch(:bench)`,
  verify the packaged instructions, and prove `hive init --workflow bench`
  needs no `.hive-state/workflows` copy.
- Corrected four June-task corpus manifests that had inferred Haiku from Claude
  utility activity: their execute logs and Codex rollouts show GPT-5.5 via
  Codex implemented web-install, fix-tmux, fix-review, and daemon; Claude
  authored the plans.
- Documented that Honeycomb is not deployed and is not required.
- Scoped UsageDb provenance lookup to the `4-execute` stage so an unknown
  executor model cannot be misattributed to a later review or finalize model.
