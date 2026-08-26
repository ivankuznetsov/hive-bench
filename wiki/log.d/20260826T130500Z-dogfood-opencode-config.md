# Repair dogfood runtime resolution and OpenCode config validation

- Removed the unsupported `agents.opencode.isolation` field that stopped all
  OpenCode benchmark cells before model invocation.
- Kept OS and network isolation in the disposable runner, exact-base clone, and
  provider-only proxy while preserving the explicit scoped `Bash(*)` grant.
- Resolve dogfood wrapper invocations to their inherited, commit-verified
  immutable deployment instead of the wrapper or mutable current pointer.
