# Adopt agent-cli-runtime for local CLI preflight

- Added the public `agent-cli-runtime ~> 0.1.0` gem as a runtime dependency.
- Replaced HiveBench's duplicate executable discovery, version parsing and
  floors, and auth-configuration checks with an adapter over
  `AgentCliRuntime.probe`.
- Kept benchmark-specific model commands, auth mounts, live credential
  validation, orchestration, and result policy inside HiveBench.
- Added adapter tests plus a real local fake-binary/auth integration test; no
  paid provider call is made.
