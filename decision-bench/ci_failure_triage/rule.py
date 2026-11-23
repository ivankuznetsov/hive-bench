"""ci_failure_triage — decomposed variant truth table.

decide(answers, state=None) -> defect_from_diff | flaky_or_infra |
  environment_or_billing | merge_conflict | unknown | unsure

`answers` maps question name -> P(yes):
  account_blocked              jobs did not run because of billing/spending/account limits
  merge_blocked                merge conflict / branch not mergeable with base
  setup_or_dependency_problem  missing tool/package/browser, failed setup script, dependency advisory
  infra_symptom                runner/network/download/OOM/service-start/cancellation symptom
  deterministic_error          test assertion, compile/type/lint error, coverage gate, code exception
  touches_diff                 the failing test/file/check relates to a file in diff.files
  timing_dependent             timeout, duration budget, race, wall-clock check
Thresholds: >= 0.7 yes, <= 0.3 no, otherwise unsettled. "unsure" = escalate;
score it as an abstention. "unknown" = the evidence was read and nothing fits.
"""

YES = 0.7
NO = 0.3
NAMES = ("account_blocked", "merge_blocked", "setup_or_dependency_problem", "infra_symptom",
         "deterministic_error", "touches_diff", "timing_dependent")


def _band(p):
    if p is None:
        return "unsettled"
    if p >= YES:
        return "yes"
    if p <= NO:
        return "no"
    return "unsettled"


def decide(answers, state=None):
    b = {k: _band(answers.get(k)) for k in NAMES}
    code_in_diff = b["deterministic_error"] == "yes" and b["touches_diff"] == "yes"

    # No code fix in this branch can repair these; route to the operator.
    if b["account_blocked"] == "yes":
        return "environment_or_billing"
    if b["merge_blocked"] == "yes":
        return "merge_conflict"
    if b["setup_or_dependency_problem"] == "yes" and not code_in_diff:
        return "environment_or_billing"

    if b["deterministic_error"] == "yes":
        if b["timing_dependent"] == "yes":
            # A timing assertion fails without a code defect on a slow runner;
            # call it a defect only when it is about changed code.
            return "defect_from_diff" if b["touches_diff"] == "yes" else "flaky_or_infra"
        if b["touches_diff"] == "yes":
            return "defect_from_diff"
        if b["touches_diff"] == "no":
            # A real error outside the diff: base breakage or an indirect
            # effect; triage cannot pin it on this change.
            return "flaky_or_infra" if b["infra_symptom"] == "yes" else "unknown"
        return "unsure"

    if b["infra_symptom"] == "yes" or b["timing_dependent"] == "yes":
        return "flaky_or_infra"

    if any(v == "unsettled" for v in b.values()):
        return "unsure"
    return "unknown"


if __name__ == "__main__":
    import itertools
    seen = set()
    for combo in itertools.product([0.1, 0.5, 0.9], repeat=len(NAMES)):
        seen.add(decide(dict(zip(NAMES, combo))))
    print(sorted(seen))
