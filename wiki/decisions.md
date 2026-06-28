# Decisions

Methodology decisions and the reasoning. See [[findings]] for evidence, [[architecture]] for
how they're implemented.

- **Drive real hive, don't imitate it** (the v2 pivot). v1's reimplemented planner measured a
  toy workflow; the gap between real `/ce-plan` and the toy planner was ~2 judge points. Use
  hive exactly, with different model settings.
- **Full workflow incl. review** is the target — but v2 ships **plan+execute first**; the
  review chain (`open-pr` needs gh-stub, `review` needs CI + reviewer personas) is the next
  phase. Sequencing chosen to land a correct result fast.
- **Judge against the reference PR** (reference-PROVIDED), as a SIGNAL with an absolute rubric
  ("does this accomplish the task," not "how close to the gold"). v1 used reference-withheld;
  v2 flips it on.
- **Seed the frozen brainstorm** (the recorded human Q&A) for every candidate, then run
  plan→execute. Fair, deterministic, same task. The brainstorm is the scope authority.
- **Hive-in-container** for isolation (real hive runs agents on the host with skip-perms; we
  add the isolation ourselves).
- **Dual independent judge** = opus-4.8 (local claude CLI) + gpt-5.5-pro (OpenRouter),
  cross-family; gpt-5.5-pro is the de-anchored headline (stricter, but agrees on ordering).
- **Cost is API-equivalent at usual-tier rates**, computed from token counts (the CLIs report
  tokens even on subscription). Closed models priced at gpt-5.5 `$5/$30/$0.50` and opus-4.8
  `$5/$25/$0.50` per M — NOT the fast tier.
- **Don't add a `/ce-plan` variance hack.** A correct brainstorm usually (2/3) yields a clean
  full-scope plan; the minimal fork is the exception. (Considered: auto-answering open
  questions, multi-seed, seeding human answers — all rejected per maintainer guidance.)
