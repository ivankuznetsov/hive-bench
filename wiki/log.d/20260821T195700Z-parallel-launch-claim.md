# Extend benchmark worker launch claims under parallel load

- Set `attempt_launch_timeout_sec: 300` in every generated candidate config.
- A six-way OpenCode launch under host swap pressure reproduced the 30-second
  production claim expiring before the detached execute worker could claim it;
  Hive recorded `launch_handoff_failed` with `launch claim deadline expired`
  and no model process started.
- The claim remains finite and separate from each stage/model wall-clock
  timeout.
