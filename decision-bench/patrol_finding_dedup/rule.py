"""Decision rule for the `decomposed` variant of patrol_finding_dedup.

decide(answers) -> "same" | "different" (the labels.system / labels.adjudicated space).

Expected answers (all noul -> P(true) float, or {"probability": p} / {"true": p}):
  same_code_location, same_failure, same_cause, same_fix

Hive suppresses a finding judged "same", so a wrong "same" silently drops a real
finding while a wrong "different" only creates a duplicate that Patrol Fix semantic
admission can still merge later. The rule therefore needs positive evidence for "same"
and resolves the unsettled band to "different".
Thresholds: >= 0.7 yes, <= 0.3 no. Every combination has an outcome.
"""

YES = 0.7
NO = 0.3


def _p(value):
    if value is None:
        return 0.5
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, dict):
        for key in ("probability", "p", "true", "yes"):
            if key in value:
                return float(value[key])
    raise ValueError(f"cannot read noul answer: {value!r}")


def decide(answers, state=None):
    location = _p(answers.get("same_code_location"))
    failure = _p(answers.get("same_failure"))
    cause = _p(answers.get("same_cause"))
    fix = _p(answers.get("same_fix"))

    # The known fix would resolve the new finding and they share a cause or symptom.
    if fix >= YES and (cause >= YES or failure >= YES):
        return "same"
    # Same mistake in the same code, even if the recommended fixes are worded apart.
    if cause >= YES and location >= YES:
        return "same"
    # Clear negatives.
    if fix <= NO:
        return "different"
    if cause <= NO and failure <= NO:
        return "different"
    # Unsettled: require three clear yeses, otherwise keep the finding.
    yes = sum(1 for p in (location, failure, cause, fix) if p >= YES)
    return "same" if yes >= 3 else "different"


if __name__ == "__main__":
    import itertools

    grid = [0.1, 0.5, 0.9]
    seen = {decide({"same_code_location": a, "same_failure": b, "same_cause": c, "same_fix": d})
            for a, b, c, d in itertools.product(grid, grid, grid, grid)}
    assert seen == {"same", "different"}, seen
    print("ok: grid covers", sorted(seen))
