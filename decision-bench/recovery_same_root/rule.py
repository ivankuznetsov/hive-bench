"""recovery_same_root — decomposed variant truth table.

decide(answers, state=None) -> True | False | "unsure"

True  = the current failure is the same root failure as the previous one
False = different root failure
"unsure" = escalate (keep today's fingerprint counter, or ask an LLM); score
           it as an abstention.

`answers` maps question name -> P(yes):
  same_error          the two failures report the same error, ignoring ids/timestamps
  current_specific    current_failure names a specific cause (not a bare code)
  previous_specific   previous_failure names a specific cause (not a bare code)
  same_subsystem      both failures come from the same subsystem
Thresholds: >= 0.7 yes, <= 0.3 no, otherwise unsettled.
"""

YES = 0.7
NO = 0.3


def _band(p):
    if p is None:
        return "unsettled"
    if p >= YES:
        return "yes"
    if p <= NO:
        return "no"
    return "unsettled"


def decide(answers, state=None):
    same = _band(answers.get("same_error"))
    cur = _band(answers.get("current_specific"))
    prev = _band(answers.get("previous_specific"))
    subsystem = _band(answers.get("same_subsystem"))

    if same == "yes":
        # Two identical bare codes ("exit_code", "all_failed", a CI attempt
        # count) do not show what failed; leave that to the existing counter.
        if cur == "no" and prev == "no":
            return "unsure"
        return True
    if same == "no":
        return False
    # same_error unsettled
    if subsystem == "no":
        return False
    return "unsure"


if __name__ == "__main__":
    import itertools
    names = ["same_error", "current_specific", "previous_specific", "same_subsystem"]
    seen = set()
    for combo in itertools.product([0.1, 0.5, 0.9, None], repeat=4):
        seen.add(decide(dict(zip(names, combo))))
    print(seen)
