"""Truth table for the decomposed task_workflow_routing variant.

decide(answers) -> "express" | "standard" | "full"
explain(answers) -> {"verdict", "settled", "path", "bands", "size"}

`answers` maps question name -> probability of yes for each Noul (OpenAI
`predicate`), and `expected_size` -> one of:
  * a level label ("tiny" ... "very_large"),
  * a dict {label: probability},
  * a float position in [0, 1] (0 = tiny, 1 = very_large).
A missing or refused answer counts as unsettled. Noul bands use TypeSafe's
starting thresholds: yes >= 0.7, no <= 0.3, unsettled in between.

Profiles (see README.md for the Hive knobs behind each):
  express  - no brainstorm, standard plan review without the adversarial leg,
             one reviewer and one fix pass, cheaper planning/review models.
  standard - brainstorm auto-answered with recommended defaults, standard plan
             review, two reviewers and up to two fix passes.
  full     - today's coding workflow.

Rules, in order:
  FULL when any of
    F1 the idea leaves an owner-only product or policy decision open;
    F2 the expected size is very_large;
    F3 two or more risk areas (access control, stored data, public contract)
       are touched and the size is at least medium;
    F4 several subsystems must change together and the size is at least large;
    F5 the idea is not fully specified and it touches a risk area or the size
       is at least large.
  EXPRESS when every gate below holds (all settled):
    no owner decision, fully specified, no access-control change, no stored-data
    change, a single subsystem, and one of
      E1 no program code changes and size at most medium;
      E2 size at most small;
      E3 a narrow bug fix at a named location, size at most medium, and no
         public-contract change.
  STANDARD otherwise.
Unsettled answers never trigger FULL and never satisfy an EXPRESS gate, so they
fall to STANDARD; `settled` is False whenever an unsettled answer could have
changed the verdict, so a deployment can defer to a reasoning model there.
"""

YES, NO = 0.7, 0.3
SIZE_LEVELS = ("tiny", "small", "medium", "large", "very_large")
NOULS = (
    "touches_access_control", "changes_stored_data", "changes_public_contract",
    "spans_multiple_subsystems", "fully_specified", "narrow_bug_fix_at_named_location",
    "no_program_code", "needs_owner_decision",
)
QUESTION_NAMES = NOULS + ("expected_size",)


def band(p):
    if p is None:
        return "U"
    try:
        p = float(p)
    except (TypeError, ValueError):
        return "U"
    return "Y" if p >= YES else ("N" if p <= NO else "U")


def size_of(value):
    """-> (index 0..4 or None, settled: bool)."""
    if value is None:
        return None, False
    if isinstance(value, str):
        return (SIZE_LEVELS.index(value), True) if value in SIZE_LEVELS else (None, False)
    if isinstance(value, dict):
        probs = {k: float(v) for k, v in value.items() if k in SIZE_LEVELS and v is not None}
        total = sum(probs.values())
        if total <= 0:
            return None, False
        exp = sum(SIZE_LEVELS.index(k) * v for k, v in probs.items()) / total
        top = max(probs.values()) / total
        return int(round(exp)), top >= 0.5
    try:
        pos = float(value)
    except (TypeError, ValueError):
        return None, False
    pos = min(max(pos, 0.0), 1.0)
    return int(round(pos * (len(SIZE_LEVELS) - 1))), True


def explain(answers):
    b = {n: band(answers.get(n)) for n in NOULS}
    s, s_settled = size_of(answers.get("expected_size"))
    risks = [b["touches_access_control"], b["changes_stored_data"], b["changes_public_contract"]]
    risk_y = sum(1 for r in risks if r == "Y")
    risk_u = sum(1 for r in risks if r == "U")

    def ge(k):  # size >= level k ; None when size unknown
        return None if s is None else s >= k

    def out(verdict, path, settled):
        return {"verdict": verdict, "path": path, "settled": settled, "bands": b,
                "size": None if s is None else SIZE_LEVELS[s], "size_settled": s_settled}

    # ---- FULL triggers (settled yes only)
    full_paths = []
    if b["needs_owner_decision"] == "Y":
        full_paths.append("F1_owner_decision")
    if s == 4:
        full_paths.append("F2_very_large")
    if risk_y >= 2 and ge(2):
        full_paths.append("F3_two_risk_areas")
    if b["spans_multiple_subsystems"] == "Y" and ge(3):
        full_paths.append("F4_multi_subsystem_large")
    if b["fully_specified"] == "N" and (risk_y >= 1 or ge(3)):
        full_paths.append("F5_underspecified_risky")
    if full_paths:
        return out("full", "+".join(full_paths), s_settled or "F1_owner_decision" in full_paths)

    # Could an unsettled answer have produced FULL?
    full_possible = (
        b["needs_owner_decision"] == "U" or s is None or not s_settled or
        (risk_y + risk_u >= 2 and (s is None or s >= 2) and risk_u > 0) or
        (b["spans_multiple_subsystems"] == "U" and (s is None or s >= 3)) or
        (b["fully_specified"] == "U" and (risk_y >= 1 or (s is not None and s >= 3))) or
        (b["fully_specified"] == "N" and risk_u > 0)
    )

    # ---- EXPRESS gates (settled values only)
    gates = {
        "no_owner_decision": b["needs_owner_decision"] == "N",
        "fully_specified": b["fully_specified"] == "Y",
        "no_access_control": b["touches_access_control"] == "N",
        "no_stored_data": b["changes_stored_data"] == "N",
        "single_subsystem": b["spans_multiple_subsystems"] == "N",
    }
    e1 = b["no_program_code"] == "Y" and s is not None and s <= 2
    e2 = s is not None and s <= 1
    e3 = (b["narrow_bug_fix_at_named_location"] == "Y" and s is not None and s <= 2 and
          b["changes_public_contract"] == "N")
    if all(gates.values()) and (e1 or e2 or e3):
        path = "express_" + ("E1_no_code" if e1 else "E2_small" if e2 else "E3_narrow_fix")
        return out("express", path, s_settled)

    # Could an unsettled answer have produced EXPRESS?
    gate_u = [k for k, v in gates.items() if not v and {
        "no_owner_decision": b["needs_owner_decision"], "fully_specified": b["fully_specified"],
        "no_access_control": b["touches_access_control"], "no_stored_data": b["changes_stored_data"],
        "single_subsystem": b["spans_multiple_subsystems"]}[k] == "U"]
    gate_hard_fail = [k for k, v in gates.items() if not v and k not in gate_u]
    sub_u = (b["no_program_code"] == "U" or b["narrow_bug_fix_at_named_location"] == "U" or
             b["changes_public_contract"] == "U" or s is None or not s_settled)
    express_possible = not gate_hard_fail and (gate_u or sub_u)
    return out("standard", "standard_default", not (full_possible or express_possible))


def decide(answers):
    return explain(answers)["verdict"]


if __name__ == "__main__":
    # Exhaustive check: every Y/N/U/missing combination of the 8 Nouls times every
    # size form (5 labels, a flat distribution, missing) yields a valid verdict.
    import itertools
    probs = {"Y": 0.9, "N": 0.1, "U": 0.5, "missing": None}
    sizes = list(SIZE_LEVELS) + [{k: 0.2 for k in SIZE_LEVELS}, None]
    counts, n = {}, 0
    for combo in itertools.product(probs, repeat=len(NOULS)):
        base = {q: probs[c] for q, c in zip(NOULS, combo) if probs[c] is not None}
        for sz in sizes:
            a = dict(base)
            if sz is not None:
                a["expected_size"] = sz
            e = explain(a)
            assert e["verdict"] in ("express", "standard", "full"), e
            counts[(e["verdict"], e["settled"])] = counts.get((e["verdict"], e["settled"]), 0) + 1
            n += 1
    # Spot checks
    docs = {"touches_access_control": 0.05, "changes_stored_data": 0.05, "changes_public_contract": 0.1,
            "spans_multiple_subsystems": 0.1, "fully_specified": 0.9, "narrow_bug_fix_at_named_location": 0.1,
            "no_program_code": 0.95, "needs_owner_decision": 0.05, "expected_size": "small"}
    assert decide(docs) == "express"
    assert decide({**docs, "needs_owner_decision": 0.9}) == "full"
    assert decide({**docs, "no_program_code": 0.1, "expected_size": "medium"}) == "standard"
    assert decide({**docs, "expected_size": "very_large"}) == "full"
    assert decide({}) == "standard" and not explain({})["settled"]
    print(f"ok: {n} combinations", sorted(counts.items()))
