"""Decision rule for the `decomposed` variant of patrol_fix_semantic_admission.

decide(answers, state=None) -> "same_root:<task slug>" | "distinct" | "insufficient_evidence"
(the same string space as labels.system.verdict; compare coarse routes by splitting on ":").

Expected answers (by question name):
  same_defect_in_any_task, same_code_in_any_task, finding_is_concrete:
      noul -> P(true) float, or {"probability": p} / {"true": p}
  matching_task:
      choice -> the chosen task slug, or a {slug: probability} distribution (top slug used).
      Its options are row-specific: the slugs of that row's `candidates`.
state (optional): the row's state; only `candidate_coverage.partial` is read. Passing it
lets code apply Hive's "partial context cannot justify an answer" rule; without it the
rule assumes the candidate list was complete.

Thresholds: >= 0.7 yes, <= 0.3 no, otherwise unsettled. Every combination has an outcome.
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


def _top(value):
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        if "value" in value:
            return value["value"]
        dist = value.get("distribution", value)
        return max(dist, key=dist.get) if dist else None
    raise ValueError(f"cannot read choice answer: {value!r}")


def decide(answers, state=None):
    same_defect = _p(answers.get("same_defect_in_any_task"))
    same_code = _p(answers.get("same_code_in_any_task"))
    concrete = _p(answers.get("finding_is_concrete"))
    match = _top(answers.get("matching_task"))
    partial = bool(((state or {}).get("candidate_coverage") or {}).get("partial"))

    # A finding too vague to compare cannot be routed either way.
    if concrete <= NO:
        return "insufficient_evidence"
    if same_defect >= YES:
        return f"same_root:{match}" if match else "insufficient_evidence"
    if same_defect <= NO:
        return "distinct"
    # Unsettled same-defect judgment.
    if same_code >= YES:
        return "insufficient_evidence"  # same code, unclear whether the same cause
    if partial:
        return "insufficient_evidence"  # unseen tasks could hold the match
    return "distinct"


if __name__ == "__main__":
    import itertools

    grid = [0.1, 0.5, 0.9]
    seen = set()
    for a, b, c, partial in itertools.product(grid, grid, grid, (False, True)):
        out = decide(
            {"same_defect_in_any_task": a, "same_code_in_any_task": b,
             "finding_is_concrete": c, "matching_task": {"task-a": 0.8, "task-b": 0.2}},
            {"candidate_coverage": {"partial": partial}},
        )
        seen.add(out.split(":")[0])
    assert seen == {"same_root", "distinct", "insufficient_evidence"}, seen
    print("ok: grid covers", sorted(seen))
