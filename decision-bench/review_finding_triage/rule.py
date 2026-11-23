"""Truth table for the decomposed review_finding_triage variant.

decide(answers, facts) -> "auto_fix" | "resolved_no_fix" | "escalate" | "deferred"

answers: {question_name: P(yes)} for the nouls in questions.DECOMPOSED.
facts:   row["rule_facts"]: values Hive's code already knows, never asked of the model:
         triage_bias ("courageous"|"safetyist"), severity ("high"|"medium"|"low"|"nit"|"unspecified"),
         severity_gate_active, convergence_rules_active, verify_only (bools).
         If facts is None the rule assumes a pass-1 courageous review with no convergence rules.

Mirrors templates/triage_courageous.md.erb, templates/triage_safetyist.md.erb and
lib/hive/stages/review/convergence.rb (Convergence.triage_section takes precedence over bias).
Thresholds: yes >= 0.7, no <= 0.3, anything between is the unsettled band.
"""
YES = 0.7
NO = 0.3


def _p(answers, name):
    v = answers.get(name)
    if v is None:
        return 0.5  # a missing answer is treated as unsettled, never as "no"
    return float(v)


def decide(answers, facts=None):
    f = {"triage_bias": "courageous", "severity": "unspecified", "severity_gate_active": False,
         "convergence_rules_active": False, "verify_only": False}
    if facts and "rule_facts" in facts:  # the whole dataset row was passed
        facts = facts["rule_facts"]
    if facts:
        f.update({k: v for k, v in facts.items() if v is not None})
    p = lambda n: _p(answers, n)
    yes = lambda n: p(n) >= YES
    no = lambda n: p(n) <= NO
    unsettled = lambda n: NO < p(n) < YES

    # 1. Context answers it -> RESOLVED/NO-FIX (both biases).
    if yes("already_resolved_in_code") or yes("duplicate_of_earlier_finding") or yes("outside_plan_scope"):
        return "resolved_no_fix"
    # 2. Convergence rules (only exist from Hive #1597, 2026-11-03) take precedence over bias.
    if f["convergence_rules_active"]:
        if yes("release_evidence_only") or yes("negligible_or_implausible"):
            return "resolved_no_fix"
        if f["verify_only"] and not yes("concrete_evidence"):
            # Verify-only passes keep only unresolved/regressed findings; without concrete
            # evidence of a regression the finding is out of verify-only scope.
            return "resolved_no_fix"
    elif yes("release_evidence_only") and no("concrete_evidence"):
        # Pre-convergence prompts already resolved missing screenshots / evidence-collection limits.
        return "resolved_no_fix"
    # 3. Severity gate: only High findings with concrete evidence may be fixed.
    if f["severity_gate_active"]:
        if f["severity"] != "high":
            return "deferred"
        if not yes("concrete_evidence"):
            return "deferred"
    # 4. A genuine owner decision remains -> ESCALATE (both biases).
    if yes("needs_owner_decision"):
        return "escalate"
    if f["triage_bias"] == "safetyist":
        # Safetyist: auto-fix only truly mechanical items; escalate everything else unresolved.
        if yes("one_obvious_fix") and no("needs_owner_decision") and f["severity"] in ("nit", "low"):
            return "auto_fix"
        return "escalate"
    # Courageous (default): bias toward AUTO-FIX at ~70% confidence.
    if no("one_obvious_fix") and not no("needs_owner_decision"):
        # Several valid designs and the owner question is unsettled: subjective trade-off.
        return "escalate"
    if unsettled("needs_owner_decision") and unsettled("one_obvious_fix"):
        # "Low-confidence findings where you would classify differently on a re-read."
        return "escalate"
    return "auto_fix"


if __name__ == "__main__":
    import itertools
    names = ["release_evidence_only", "already_resolved_in_code", "duplicate_of_earlier_finding",
             "outside_plan_scope", "negligible_or_implausible", "concrete_evidence", "one_obvious_fix",
             "needs_owner_decision"]
    seen = set()
    for vals in itertools.product([0.1, 0.5, 0.9], repeat=len(names)):
        for facts in ({}, {"convergence_rules_active": True, "severity_gate_active": True, "severity": "high"},
                      {"convergence_rules_active": True, "severity_gate_active": True, "severity": "medium"},
                      {"convergence_rules_active": True, "verify_only": True},
                      {"triage_bias": "safetyist", "severity": "nit"}):
            out = decide(dict(zip(names, vals)), facts)
            assert out in ("auto_fix", "resolved_no_fix", "escalate", "deferred"), out
            seen.add(out)
    print("all", 3 ** len(names), "x 5 fact combinations map to an outcome:", sorted(seen))
