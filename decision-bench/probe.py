#!/usr/bin/env python3
"""One tiny synthetic call to confirm a provider's request/response shape.

    probe.py openai|jev

Sends a two-question request about a made-up support ticket (no project data)
through run_decisions.py's own payload builders and call functions, then prints
the raw response and the normalized answers. Keys come from the environment
and are never printed.
"""
import json
import sys
import time

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
import run_decisions as rd  # noqa: E402

ROW = {
    "id": "probe#direct",
    "variant": "direct",
    "state": {"ticket": {"subject": "Broken screen", "body": "My order arrived with a cracked screen. Please send a replacement."}},
    "questions": [
        {"name": "category", "type": "choice", "instructions": "Which kind of request is `ticket`?",
         "choices": [{"value": "damaged_item", "description": "The customer reports an item that arrived broken."},
                     {"value": "billing", "description": "The customer asks about a charge."}]},
        {"name": "wants_replacement", "type": "noul", "instructions": "Does `ticket` ask for a replacement item?",
         "criteria": {"true": "The customer asks for a new item to be sent.", "false": "The customer asks only for a refund or information."}},
    ],
}


def main():
    provider = sys.argv[1]
    model = rd.PROVIDERS[provider]["model"]
    payload = (rd.openai_payload if provider == "openai" else rd.jev_payload)(ROW, model)
    print("REQUEST", json.dumps(payload, indent=1))
    t = time.time()
    try:
        resp = rd.call_openai(payload, 60) if provider == "openai" else rd.call_jev(payload, 60)
    except rd.CallError as exc:
        print("ERROR", exc.status, str(exc)[:800])
        return 1
    print(f"LATENCY_MS {round((time.time() - t) * 1000)}")
    print("RESPONSE", json.dumps(resp, indent=1))
    answers, usage = (rd.normalize_openai if provider == "openai" else rd.normalize_jev)(resp, ROW)
    print("NORMALIZED", json.dumps(answers), json.dumps(usage))
    print("VERDICT", rd.verdict_for(ROW, answers, None))
    return 0


if __name__ == "__main__":
    sys.exit(main())
