"""provider_failure_class — decomposed variant truth table.

decide(answers, state=None) -> one of
  quota_or_usage_limit | transient_rate_limit | model_unsupported |
  auth_or_credentials | network_transient | merge_conflict |
  tool_permission_denied | agent_crashed | other_or_healthy | unsure

`answers` maps question name -> P(yes) for the eight nouls in dataset.jsonl.
`state` is the row's state object; code reads only facts Hive already knows
exactly (run.exit_code, run.timed_out) instead of asking the model for them.

Thresholds: >= 0.7 is yes, <= 0.3 is no, anything between is unsettled.
"unsure" means "escalate" (fall back to today's regex or an LLM); runners
should score it as an abstention, not as a class.
"""

YES = 0.7
NO = 0.3

# Highest priority first. Model refusal and auth are operator-owned and never
# heal on retry, so they outrank a quota line that may sit next to them (Hive's
# handle_exit also checks model_unsupported before limits). Quota outranks a
# 429 throttle because an exhausted window also arrives as HTTP 429.
PRIORITY = [
    ("model_refused", "model_unsupported"),
    ("auth_failed", "auth_or_credentials"),
    ("quota_exhausted", "quota_or_usage_limit"),
    ("rate_throttled", "transient_rate_limit"),
    ("git_conflict", "merge_conflict"),
    ("tool_blocked", "tool_permission_denied"),
    ("network_failed", "network_transient"),
]

# Exit statuses that mean the CLI was terminated by a signal (shell 128+N and
# Ruby's negative Process::Status form): SIGABRT, SIGKILL, SIGSEGV, SIGTERM.
SIGNAL_EXITS = {-6, -9, -11, -15, 134, 137, 139, 143}


def _band(p):
    if p is None:
        return "unsettled"
    if p >= YES:
        return "yes"
    if p <= NO:
        return "no"
    return "unsettled"


def decide(answers, state=None):
    run = (state or {}).get("run", {}) if isinstance(state, dict) else {}
    exit_code = run.get("exit_code")
    timed_out = bool(run.get("timed_out"))

    # Hive's own deadline killed the run: a timeout, not a provider failure.
    if timed_out:
        return "other_or_healthy"

    finished = _band(answers.get("finished_normally"))
    bands = {q: _band(answers.get(q)) for q, _ in PRIORITY}

    # The agent completed its work after any earlier error: the run is healthy.
    if finished == "yes":
        return "other_or_healthy"

    for q, cls in PRIORITY:
        if bands[q] == "yes":
            return cls

    if any(b == "unsettled" for b in bands.values()) or finished == "unsettled":
        return "unsure"

    # No failure signal in the text, finished_normally is "no".
    if exit_code in SIGNAL_EXITS:
        return "agent_crashed"
    return "other_or_healthy"


if __name__ == "__main__":
    # Every combination of the 8 nouls in {no, unsettled, yes} x signal exit
    # yes/no x timed_out yes/no has an outcome; enumerate to prove totality.
    import itertools
    names = ["finished_normally"] + [q for q, _ in PRIORITY]
    seen = set()
    for combo in itertools.product([0.1, 0.5, 0.9], repeat=len(names)):
        for ec in (0, 1, 143, None):
            for to in (False, True):
                v = decide(dict(zip(names, combo)), {"run": {"exit_code": ec, "timed_out": to}})
                assert v, (combo, ec, to)
                seen.add(v)
    print(sorted(seen))
