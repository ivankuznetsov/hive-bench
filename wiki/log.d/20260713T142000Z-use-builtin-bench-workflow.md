# Use Hive's built-in benchmark workflow

- Removed the duplicate project workflow descriptor and stage instructions;
  Hive now owns the named `bench` workflow and its packaged prompts.
- Updated the no-cost smoke to load `Hive::Workflows::Registry.fetch(:bench)`,
  verify the packaged instructions, and prove `hive init --workflow bench`
  needs no `.hive-state/workflows` copy.
- Corrected the fix-tmux corpus provenance: Codex GPT-5.5 implemented the task;
  Claude authored the plan.
- Documented that Honeycomb is not deployed and is not required.
