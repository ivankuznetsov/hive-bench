# 2026-08-25 — Native model routing and production review slate

- Refreshed the installed bench runtime from source commits `90fef72` and
  `41315d5`. Candidate model/effort now flows through Hive's provider-neutral
  `models:` routes and shared Agent CLI runtime; container model shims,
  OpenCode-specific runtime/probe configuration, and the Pi/OpenCode Ox Alpha
  profiles were removed.
- Added four production-shaped candidates covering Grok-owned review, a fixed
  Sol+Grok panel, and fixed Sol+Opus 5 panels for an Opus-vs-Fable planner
  comparison. Reviewer-level model/effort pins prevent a planner route from
  leaking into a heterogeneous panel.
- Documented the narrower recovery contract: only identity-matched Codex
  `implementer_failed` transport disconnects resume in place. Review, Pi,
  provider-error, and dirty-residue resume paths are gone; outer timeout is
  always `timed_out`; the runner uses its baked Hive runtime and inherited Hive
  defaults rather than a host-runtime overlay. Plan execution no longer retries
  a markerless promotion with `hive run` or normalizes a null dependency.
- Provider-limit classification now scans only newly appended stream-log bytes
  for the current attempt. Codex judge calls allow 3600 seconds, Claude stdout
  quota detection trusts only the standalone reset banner, and deliberation
  emits task/candidate/judge-keyed failure events for both rounds.
- Recorded two refresh risks in [[gaps]]: the installed snapshot reintroduces
  Pi usage double-counting by removing the final-event filter, and the
  configured cross-project main wiki path was absent during this refresh.

Pages updated: [[architecture]], [[dependencies]], [[decisions]], [[findings]],
[[v3-workflow]], and [[gaps]]. Page coverage did not change, so [[index]] was
left untouched.
