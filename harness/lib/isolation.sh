#!/usr/bin/env bash
# Runs a command inside an ephemeral, resource-capped hive-bench runner
# container. Fails CLOSED (exit 70) if Docker is unavailable or isolation
# cannot be established — a benchmark score is never produced from an
# un-isolated run (mirrors agent-reviewer-eval's posture).
#
# Usage:
#   hb_isolated <mode> <work_dir> <cmd...>
#     mode=gate  -> --network none, read-only except /work (no agent, no model)
#     mode=gen   -> egress restricted to the model API; agent CLIs+auth mounted ro
#
# Network note: true egress allowlisting on plain Docker needs a proxy/firewall
# (in CI, GitHub's runner egress firewall or StepSecurity Harden-Runner). v1
# enforces it there; locally, `gen` uses the default bridge and relies on fs
# isolation + caps. The `gate` mode's --network none is always enforced.
set -euo pipefail

HB_FAIL_ISOLATION=70

hb_isolated() {
  local mode="$1" work="$2"; shift 2
  command -v docker >/dev/null 2>&1 || { echo "hive-bench: docker unavailable — failing closed" >&2; exit "$HB_FAIL_ISOLATION"; }
  [ -d "$work" ] || { echo "hive-bench: work dir $work missing" >&2; exit "$HB_FAIL_ISOLATION"; }

  local net_args=()
  case "$mode" in
    gate) net_args=(--network none) ;;
    gen)  net_args=() ;;  # egress allowlist applied by the CI firewall layer
    *)    echo "hive-bench: unknown isolation mode '$mode'" >&2; exit "$HB_FAIL_ISOLATION" ;;
  esac

  docker run --rm \
    "${net_args[@]}" \
    --cpus "${HB_CPUS:-2}" --memory "${HB_MEMORY:-4g}" --pids-limit "${HB_PIDS:-512}" \
    --read-only --tmpfs /tmp \
    -v "$work:/work" \
    "${HB_RUNNER_IMAGE:-hive-bench-runner:latest}" \
    "$@"
}

# Allow sourcing (for tests) or direct invocation.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  hb_isolated "$@"
fi
