#!/usr/bin/env bash
# Runs a command inside an ephemeral, resource-capped hive-bench runner
# container. Fails CLOSED (exit 70) if Docker is unavailable or isolation
# cannot be established — a benchmark score is never produced from an
# un-isolated run (mirrors agent-reviewer-eval's posture).
#
# Usage:
#   hb_isolated <mode> <work_dir> <cmd...>
#     mode=gate  -> --network none, read-only except /work (no agent, no model)
#     mode=gen   -> egress allowed to the model API; HOME points at the tmpfs and
#                   provider credentials present in the env are forwarded.
#
# Network note: true egress allowlisting on plain Docker needs a proxy/firewall
# (in CI, GitHub's runner egress firewall or StepSecurity Harden-Runner). v1
# enforces it there; locally, `gen` uses the default bridge and relies on the
# read-only rootfs, dropped Linux capabilities (--cap-drop ALL,
# no-new-privileges), and resource caps. gen does NOT silently fail open: the operator must set
# HB_ALLOW_EGRESS=1 to acknowledge the run permits outbound network (review
# finding #4). The `gate` mode's --network none is always enforced.
set -euo pipefail

HB_FAIL_ISOLATION=70

hb_isolated() {
  local mode="$1" work="$2"; shift 2
  command -v docker >/dev/null 2>&1 || { echo "hive-bench: docker unavailable — failing closed" >&2; exit "$HB_FAIL_ISOLATION"; }
  [ -d "$work" ] || { echo "hive-bench: work dir $work missing" >&2; exit "$HB_FAIL_ISOLATION"; }
  # `docker run -v` needs an absolute source; the caller may pass a relative path.
  work="$(cd "$work" && pwd)" || { echo "hive-bench: cannot resolve work dir $work — failing closed" >&2; exit "$HB_FAIL_ISOLATION"; }

  local net_args=() env_args=() mount_args=()
  case "$mode" in
    gate)
      net_args=(--network none)
      ;;
    gen)
      # Egress must be explicitly acknowledged — we never fail open silently.
      [ "${HB_ALLOW_EGRESS:-}" = "1" ] || {
        echo "hive-bench: gen mode requires HB_ALLOW_EGRESS=1 to permit model-API egress — failing closed" >&2
        exit "$HB_FAIL_ISOLATION"
      }
      net_args=()  # default bridge; egress allowlist applied by the CI firewall layer
      # Under --read-only the agent CLI's HOME must be writable; point it at the tmpfs.
      env_args=(-e HOME=/tmp)
      # Forward provider credentials that are present (the value is never echoed).
      local k
      for k in OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY; do
        [ -n "${!k:-}" ] && env_args+=(-e "$k")
      done
      # claude cells need their OAuth creds: mount the host file read-only into
      # the runner's HOME. The path comes from the harness, never baked into the image.
      [ -n "${HB_CLAUDE_AUTH:-}" ] && mount_args+=(-v "${HB_CLAUDE_AUTH}:/tmp/.claude/.credentials.json:ro")
      ;;
    *)
      echo "hive-bench: unknown isolation mode '$mode'" >&2; exit "$HB_FAIL_ISOLATION" ;;
  esac

  docker run --rm \
    "${net_args[@]}" \
    "${env_args[@]}" \
    "${mount_args[@]}" \
    --cap-drop ALL --security-opt no-new-privileges \
    --cpus "${HB_CPUS:-8}" --memory "${HB_MEMORY:-16g}" --pids-limit "${HB_PIDS:-4096}" \
    --read-only --tmpfs /tmp \
    -v "$work:/work" \
    "${HB_RUNNER_IMAGE:-hive-bench-runner:latest}" \
    "$@"
}

# Allow sourcing (for tests) or direct invocation.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  hb_isolated "$@"
fi
