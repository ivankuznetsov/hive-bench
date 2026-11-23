"""Truth table for the decomposed plan_review_decision_triage variant.

decide(answers) -> "keep_gate" | "auto_apply"
explain(answers) -> {"verdict", "settled", "confidence", "path", "bands"}

`answers` maps question name -> probability of yes (a Noul / OpenAI predicate).
A missing or refused answer counts as unsettled. Bands use TypeSafe's starting
thresholds: yes >= 0.7, no <= 0.3, unsettled in between.

The table mirrors Hive's decision-triage prompt
(templates/plan_review_decision_triage_prompt.md.erb):
  * a mistaken or already-satisfied finding stays automatic;
  * an owner-only decision, or an open choice the plan explicitly leaves
    unanswered, keeps the gate (manual);
  * a correction that adds scope or changes relied-on behaviour beyond what
    the plan requires keeps the gate (gated_auto);
  * a correction that carries out an existing requirement is automatic, even
    if high risk;
  * when no gate signal is present and the owner is not needed, it is automatic.
Every other combination is unsettled: the verdict is keep_gate (Hive never
accepts risk on the owner's behalf) and settled=False, so a deployment would
defer to the LLM triage instead of acting.
"""

YES, NO = 0.7, 0.3

QUESTION_NAMES = (
    "plan_requires_outcome", "already_addressed", "adds_scope", "changes_relied_on_behaviour",
    "several_materially_different_fixes", "owner_decision_needed", "plan_leaves_question_open",
)


def band(p):
    if p is None:
        return "U"
    return "Y" if p >= YES else ("N" if p <= NO else "U")


def _certainty(answers, names):
    vals = [answers.get(n) for n in names]
    vals = [max(v, 1 - v) for v in vals if v is not None]
    return round(min(vals), 4) if vals else 0.5


def explain(answers):
    b = {n: band(answers.get(n)) for n in QUESTION_NAMES}
    req, done, scope, behav = b["plan_requires_outcome"], b["already_addressed"], b["adds_scope"], b["changes_relied_on_behaviour"]
    several, owner, open_q = b["several_materially_different_fixes"], b["owner_decision_needed"], b["plan_leaves_question_open"]

    def out(verdict, settled, path, used):
        return {"verdict": verdict, "settled": settled, "path": path,
                "confidence": _certainty(answers, used) if settled else 0.5, "bands": b}

    if done == "Y" and scope != "Y":
        return out("auto_apply", True, "already_addressed", ["already_addressed", "adds_scope"])
    if owner == "Y":
        return out("keep_gate", True, "owner_decision_needed", ["owner_decision_needed"])
    if several == "Y" and open_q == "Y":
        return out("keep_gate", True, "open_choice_left_by_plan", ["several_materially_different_fixes", "plan_leaves_question_open"])
    if scope == "Y" and req != "Y":
        return out("keep_gate", True, "adds_scope_beyond_plan", ["adds_scope", "plan_requires_outcome"])
    if behav == "Y" and req != "Y":
        return out("keep_gate", True, "changes_relied_on_behaviour_beyond_plan", ["changes_relied_on_behaviour", "plan_requires_outcome"])
    if req == "Y":
        return out("auto_apply", True, "plan_requires_outcome", ["plan_requires_outcome", "owner_decision_needed"])
    if owner == "N" and scope == "N" and (several == "N" or open_q == "N"):
        used = ["owner_decision_needed", "adds_scope", "several_materially_different_fixes" if several == "N" else "plan_leaves_question_open"]
        return out("auto_apply", True, "no_gate_signal", used)
    return out("keep_gate", False, "unsettled_default_keep_gate", [])


def decide(answers):
    return explain(answers)["verdict"]


if __name__ == "__main__":
    # Exhaustive check: every Y/N/U combination (including missing answers) has an outcome.
    import itertools
    probs = {"Y": 0.9, "N": 0.1, "U": 0.5, "missing": None}
    counts = {}
    for combo in itertools.product(probs, repeat=len(QUESTION_NAMES)):
        ans = {n: probs[c] for n, c in zip(QUESTION_NAMES, combo) if probs[c] is not None}
        r = explain(ans)
        assert r["verdict"] in ("keep_gate", "auto_apply")
        counts[(r["verdict"], r["settled"])] = counts.get((r["verdict"], r["settled"]), 0) + 1
    print(f"{4 ** len(QUESTION_NAMES)} combinations, all decided:", counts)
