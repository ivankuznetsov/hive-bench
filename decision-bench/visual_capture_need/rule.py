"""Decision rule for visual_capture_need (decomposed variant).

Mirrors Hive::Artifacts::CapturePolicy (lib/hive/artifacts/capture_policy.rb):
capture is "required" when a user-visible (rendered UI) surface changed, and
"not_applicable" when nothing rendered changed. Hive fails closed when it cannot
prove the absence of user-visible change (evidence_incomplete -> required); the
`unsettled` verdict below is that case, and `decide_fail_closed` maps it to
`needs_capture` the way Hive does.

All questions are nouls: each answer is P(yes) in [0, 1].
"""

HI = 0.7
LO = 0.3

# Any one of these, if true, means a rendered screen changes.
VISUAL_SIGNALS = (
    "edits_rendered_ui_files",
    "edits_styles",
    "edits_client_side_behaviour",
    "changes_ui_copy",
    "server_change_alters_page_output",
)
# Either of these, if true, argues that nothing rendered changes.
NON_VISUAL_SIGNALS = (
    "only_non_ui_files",
    "effect_is_terminal_only",
)

VERDICTS = ("needs_capture", "no_capture", "unsettled")


def decide(answers: dict) -> str:
    """Truth table over noul probabilities.

    v = max over VISUAL_SIGNALS; n = max over NON_VISUAL_SIGNALS.

      v >= HI                      -> needs_capture   (a visual signal is settled yes)
      LO <= v < HI and n >= HI     -> no_capture      (visual doubt, but a settled non-visual reading)
      LO <= v < HI and n <  HI     -> unsettled       (visual doubt, nothing settles it)
      v <  LO and n >= LO          -> no_capture      (no visual signal; non-visual reading not denied)
      v <  LO and n <  LO          -> unsettled       (no visual signal, yet the change is also
                                                       judged neither non-UI-only nor terminal-only:
                                                       nothing fits)
    A missing answer counts as 0.5 (unsettled), so every input has an outcome.
    """
    v = max(float(answers.get(k, 0.5)) for k in VISUAL_SIGNALS)
    n = max(float(answers.get(k, 0.5)) for k in NON_VISUAL_SIGNALS)
    if v >= HI:
        return "needs_capture"
    if v >= LO:
        return "no_capture" if n >= HI else "unsettled"
    return "no_capture" if n >= LO else "unsettled"


def decide_fail_closed(answers: dict) -> str:
    """Hive's own policy: what it cannot prove invisible, it captures."""
    verdict = decide(answers)
    return "needs_capture" if verdict == "unsettled" else verdict


def direct_decide(p_yes: float) -> str:
    """Map the direct variant's single noul (needs_visual_capture) to a verdict."""
    if p_yes >= HI:
        return "needs_capture"
    if p_yes < LO:
        return "no_capture"
    return "unsettled"


if __name__ == "__main__":
    # Exhaustive check over the three bands for every question.
    import itertools

    names = VISUAL_SIGNALS + NON_VISUAL_SIGNALS
    seen = set()
    for combo in itertools.product((0.1, 0.5, 0.9), repeat=len(names)):
        out = decide(dict(zip(names, combo)))
        assert out in VERDICTS
        seen.add(out)
    assert decide({}) == "unsettled"
    print("all", 3 ** len(names), "band combinations decided; verdicts seen:", sorted(seen))
