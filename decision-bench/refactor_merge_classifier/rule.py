"""Decision rule for the `decomposed` variant of refactor_merge_classifier.

decide(answers) maps the atomic TypeSafe answers to Hive's verdict: "feature" or "skip".

Expected answers (by question name):
  adds_new_capability, extends_existing_feature, primarily_bug_fix, maintenance_only:
      noul -> P(true) as a float, or {"probability": p} / {"true": p, "false": q}
  architecture_footprint:
      score -> a level label ("none" | "local" | "moderate" | "broad"), or a
      {label: probability} distribution (the top label is used)

Thresholds follow the TypeSafe default band: >= 0.7 yes, <= 0.3 no, otherwise unsettled.
Every combination of answers has an outcome; the unsettled band has its own row.
"""

YES = 0.7
NO = 0.3
LEVELS = ["none", "local", "moderate", "broad"]


def _p(value):
    if value is None:
        return 0.5  # a missing answer is treated as unsettled, never as "no"
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, dict):
        for key in ("probability", "p", "true", "yes"):
            if key in value:
                return float(value[key])
    raise ValueError(f"cannot read noul answer: {value!r}")


def _level(value):
    if value is None:
        return "moderate"
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        if "label" in value:
            return value["label"]
        dist = value.get("distribution", value)
        return max(dist, key=dist.get)
    raise ValueError(f"cannot read score answer: {value!r}")


def decide(answers, state=None):
    new_cap = _p(answers.get("adds_new_capability"))
    extends = _p(answers.get("extends_existing_feature"))
    bug_fix = _p(answers.get("primarily_bug_fix"))
    maintenance = _p(answers.get("maintenance_only"))
    footprint = _level(answers.get("architecture_footprint"))

    # No production structure, or clearly maintenance: nothing for Architecture Patrol.
    if footprint == "none" or maintenance >= YES:
        return "skip"

    feature_signal = max(new_cap, extends)
    if feature_signal >= YES:
        if bug_fix >= YES:
            # A fix that also adds behavior: patrol only when it reshapes structure.
            return "feature" if footprint in ("moderate", "broad") else "skip"
        return "feature"
    if feature_signal <= NO:
        return "skip"

    # Unsettled band (0.3, 0.7): fall back to the structural footprint.
    if bug_fix >= YES:
        return "skip"
    return "feature" if footprint == "broad" else "skip"


if __name__ == "__main__":
    import itertools

    grid = [0.1, 0.5, 0.9]
    seen = set()
    for a, b, c, d, lvl in itertools.product(grid, grid, grid, grid, LEVELS):
        seen.add(decide({
            "adds_new_capability": a, "extends_existing_feature": b,
            "primarily_bug_fix": c, "maintenance_only": d, "architecture_footprint": lvl,
        }))
    assert seen == {"feature", "skip"}, seen
    print("ok: every grid combination maps to", sorted(seen))
