"""Decomposed plan_review_level rule: map atomic answers to skip/standard/mandatory.

Mirrors Hive::PlanReview::Policy.computed_level (lib/hive/plan_review/policy.rb:75):
  mandatory  if any mandatory category matches or a declared file is a protected path
  skip       if PlanSignals#skip_eligible? (no category, no uncertainty, tests explicit,
             rollback explicit, one production area, 1..5 declared files)
  standard   otherwise
The language judgments come from the model (nouls, P(yes) in [0, 1]); everything
code already knows comes from `facts` (row["rule_facts"], a copy of row["meta"]["code_facts"];
passing the whole row also works).

Bands: P >= 0.7 yes, P < 0.3 no, otherwise unsettled. An unsettled sensitive-area
answer is treated as a match (fail closed): Hive levels are raise-only, so doubt
about a sensitive area must not lower the review. An unsettled skip prerequisite
blocks skip (standard). A missing answer counts as unsettled.

Usage:  decide(answers, facts)  ->  "skip" | "standard" | "mandatory"
        decide_with_trace(answers, facts) -> (verdict, reason)
"""

YES = 0.7
NO = 0.3

CATEGORY_QUESTIONS = (
    "changes_auth_secrets_permissions",
    "changes_stored_data_or_schema",
    "changes_public_interface",
    "changes_concurrency_recovery_ownership",
    "changes_build_release_supply_chain",
)
SKIP_QUESTIONS = ("names_test_scenarios", "states_rollback_path")


def band(p):
    if p is None:
        return "unsettled"
    p = float(p)
    if p >= YES:
        return "yes"
    if p < NO:
        return "no"
    return "unsettled"


def decide_with_trace(answers, facts=None):
    answers = answers or {}
    facts = facts or {}
    if "rule_facts" in facts:  # the whole dataset row was passed
        facts = facts["rule_facts"] or {}
    if facts.get("protected_paths_touched"):
        return "mandatory", "code: declares a protected path"
    cats = {q: band(answers.get(q)) for q in CATEGORY_QUESTIONS}
    hits = [q for q, b in cats.items() if b == "yes"]
    if hits:
        return "mandatory", "sensitive area: " + ",".join(hits)
    doubt = [q for q, b in cats.items() if b == "unsettled"]
    if doubt:
        return "mandatory", "unsettled sensitive area (fail closed): " + ",".join(doubt)
    # Every category is a clear no. Skip needs every prerequisite.
    n = facts.get("declared_file_count")
    code_ok = (
        isinstance(n, int) and 1 <= n <= 5
        and facts.get("production_area_count") == 1
        and bool(facts.get("declares_test_files"))
        and not facts.get("plan_parse_uncertain")
    )
    if not code_ok:
        return "standard", "code: skip prerequisites fail (file count, areas, test files or parse)"
    skip = {q: band(answers.get(q)) for q in SKIP_QUESTIONS}
    if all(b == "yes" for b in skip.values()):
        return "skip", "no sensitive area; all skip prerequisites hold"
    return "standard", "skip prerequisite not clearly met: " + ",".join(q for q, b in skip.items() if b != "yes")


def decide(answers, facts=None):
    return decide_with_trace(answers, facts)[0]


if __name__ == "__main__":
    # Exhaustive band check: every combination yields a verdict.
    import itertools
    probes = (0.05, 0.5, 0.95, None)
    fact_sets = [
        {},
        {"protected_paths_touched": ["Gemfile"]},
        {"declared_file_count": 3, "production_area_count": 1, "declares_test_files": True},
        {"declared_file_count": 3, "production_area_count": 1, "declares_test_files": True, "plan_parse_uncertain": True},
        {"declared_file_count": 9, "production_area_count": 1, "declares_test_files": True},
    ]
    seen = set()
    names = CATEGORY_QUESTIONS + SKIP_QUESTIONS
    for facts in fact_sets:
        for combo in itertools.product(probes, repeat=len(names)):
            v = decide(dict(zip(names, combo)), facts)
            assert v in ("skip", "standard", "mandatory")
            seen.add(v)
    assert decide({q: 0.05 for q in CATEGORY_QUESTIONS} | {q: 0.95 for q in SKIP_QUESTIONS}, fact_sets[2]) == "skip"
    assert decide({q: 0.05 for q in CATEGORY_QUESTIONS} | {"names_test_scenarios": 0.5, "states_rollback_path": 0.95}, fact_sets[2]) == "standard"
    assert decide({q: 0.05 for q in CATEGORY_QUESTIONS} | {"changes_public_interface": 0.5}, {}) == "mandatory"
    print("ok", sorted(seen))
