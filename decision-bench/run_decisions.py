#!/usr/bin/env python3
"""Run a decision-eval dataset through a decision-model API, then report.

    run_decisions.py run    --point <point> --provider openai|jev [--split dev|test|all]
                            [--variant direct|decomposed|both] [--cases N] [--limit ROWS]
                            [--ids ID,...] [--max-usd 5] [--workers 4] [--dry-run]
                            [--results-dir DIR]
    run_decisions.py report --point <point> --provider openai|jev [--split ...] [--variant ...]

Reads <point>/dataset.jsonl, or <point>/dataset.jsonl.xz when no plain copy exists
(FORMAT.md rev. 2). Each row's questions are bundled into ONE request with the
row's JSON-object state sent as structured data. Results are appended to
results/<point>/results-<provider>.jsonl (override the directory with
--results-dir) keyed by row id, with the exact request payload, the raw response,
latency, usage and cost. A row whose latest result has no error is skipped on
rerun, so the published results act as a cache: rerunning a point sends nothing
unless you point --results-dir at an empty directory. A failed call is recorded
as an error and never becomes an answer. Decomposed rows get their verdict from
<point>/rule.py (`explain(answers)` if present, else `decide(answers)`).

Keys come only from the environment (OPENAI_API_KEY, TYPESAFE_API_KEY) and are
never written to disk or printed.

Providers
  openai: OpenAI Decisions API (`client.decisions.create`, openai-python >= 3.26),
          model gpt-6-luna. Noul -> predicate (criteria folded into instructions:
          predicates take no criteria field); choice -> choices[{value,description}];
          score -> levels[{label,description}]. State -> a user message with one
          `input_json` part. A choice with a single option (the API requires >= 2) is
          not sent: its answer is forced and recorded with confidence 1.0, which is
          what Jev returns for the same question.
  jev:    TypeSafe System One HTTP API, POST https://api.typesafe.ai/v1/systemone
          (https://api.typesafe.ai/openapi.json v0.2.0, read 2026-11-22). Body
          {model, state, questions:{name:{type, instructions, criteria}}}; noul
          criteria {true,false}; choice criteria {value: description}; score
          criteria [level descriptions]. Answers keyed by name; usage.input_tokens.
"""
import inspect
import argparse
import collections
import importlib.util
import json
import lzma
import math
import os
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS_DIR = os.path.join(HERE, "results")

PROVIDERS = {
    "openai": {
        "model": "gpt-6-luna",
        # USD per 1M tokens, from developers.openai.com/api/docs/pricing (Standard,
        # short context) as read 2026-11-22. Override with --usd-in/--usd-out.
        "usd_in": 0.10, "usd_cached_in": 0.01, "usd_out": 0.50,
    },
    "jev": {
        "model": "jev-1.14.0",  # pinned; jev-latest aliases it as of 2026-10-14
        "url": "https://api.typesafe.ai/v1/systemone",
        # docs.typesafe.ai/go/models: $0.042 per Mtok input, output free.
        "usd_in": 0.042, "usd_cached_in": 0.042, "usd_out": 0.0,
        # Per-question context limit is 32k tokens; above that the long-context header is needed.
        "long_context_tokens": 30000,
    },
}
RETRYABLE = {408, 409, 429, 500, 502, 503, 504}


class CallError(Exception):
    def __init__(self, msg, status=None, retryable=False):
        super().__init__(msg)
        self.status = status
        self.retryable = retryable


# ---------------------------------------------------------------- payloads
def noul_text(q):
    crit = q.get("criteria") or {}
    parts = [q["instructions"]]
    if crit.get("true"):
        parts.append(f"Yes means: {crit['true']}")
    if crit.get("false"):
        parts.append(f"No means: {crit['false']}")
    return "\n".join(parts)


def forced_choice(q):
    """A choice question with exactly one option has a forced answer."""
    return q["type"] == "choice" and len(q["choices"]) == 1


def forced_answers(row):
    out = {}
    for q in row["questions"]:
        if forced_choice(q):
            v = str(q["choices"][0]["value"])
            out[q["name"]] = {"type": "choice", "choice": v, "confidence": 1.0, "probabilities": {v: 1.0},
                              "forced": True}
    return out


def openai_payload(row, model):
    state = row["state"]
    if isinstance(state, str):
        inp = state
    else:
        inp = [{"type": "message", "role": "user", "content": [{"type": "input_json", "data": state}]}]
    questions = []
    for q in row["questions"]:
        t = q["type"]
        if forced_choice(q):
            continue  # the Decisions API rejects choices with fewer than 2 options
        if t == "noul":
            questions.append({"type": "predicate", "name": q["name"], "instructions": noul_text(q)})
        elif t == "choice":
            questions.append({"type": "choice", "name": q["name"], "instructions": q["instructions"],
                              "choices": [{"value": c["value"], "description": c.get("description", "")} for c in q["choices"]]})
        elif t == "score":
            questions.append({"type": "score", "name": q["name"], "instructions": q["instructions"],
                              "levels": [{"label": l["label"], "description": l.get("description", "")} for l in q["levels"]]})
        else:
            raise ValueError(f"unknown question type {t}")
    return {"model": model, "input": inp, "questions": questions}


def jev_payload(row, model):
    questions = {}
    for q in row["questions"]:
        t = q["type"]
        if t == "noul":
            body = {"type": "noul", "instructions": q["instructions"]}
            if q.get("criteria"):
                body["criteria"] = {k: q["criteria"][k] for k in ("true", "false") if q["criteria"].get(k)}
        elif t == "choice":
            body = {"type": "choice", "instructions": q["instructions"],
                    "criteria": {c["value"]: c.get("description") or None for c in q["choices"]}}
        elif t == "score":
            body = {"type": "score", "instructions": q["instructions"],
                    "criteria": [f"{l['label']}: {l['description']}" if l.get("description") else l["label"] for l in q["levels"]]}
        else:
            raise ValueError(f"unknown question type {t}")
        questions[q["name"]] = body
    return {"model": model, "state": row["state"], "questions": questions}


# ---------------------------------------------------------------- calls
def call_openai(payload, timeout):
    try:
        import openai
    except ImportError as exc:
        raise CallError(f"openai SDK not importable: {exc}")
    if not os.environ.get("OPENAI_API_KEY"):
        raise CallError("OPENAI_API_KEY is not set")
    client = _openai_client(openai, timeout)
    try:
        resp = client.decisions.create(**payload)
    except openai.APIStatusError as exc:
        raise CallError(f"HTTP {exc.status_code}: {str(exc)[:500]}", exc.status_code, exc.status_code in RETRYABLE)
    except (openai.APIConnectionError, openai.APITimeoutError) as exc:
        raise CallError(f"connection: {str(exc)[:300]}", None, True)
    return resp.model_dump(mode="json")


_clients = {}
_clients_lock = threading.Lock()


def _openai_client(openai, timeout):
    with _clients_lock:
        if "openai" not in _clients:
            # SDK-level retries off: this runner owns retries so every attempt is counted.
            _clients["openai"] = openai.OpenAI(max_retries=0, timeout=timeout)
        return _clients["openai"]


def call_jev(payload, timeout, long_context=False):
    key = os.environ.get("TYPESAFE_API_KEY")
    if not key:
        raise CallError("TYPESAFE_API_KEY is not set")
    headers = {"Authorization": f"Bearer {key}", "Content-Type": "application/json", "Accept": "application/json"}
    if long_context:
        headers["TypeSafe-Danger-Zone-Long-Context"] = "true"
    req = urllib.request.Request(PROVIDERS["jev"]["url"], data=json.dumps(payload).encode(), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")[:800]
        raise CallError(f"HTTP {exc.code}: {body}", exc.code, exc.code in RETRYABLE)
    except (urllib.error.URLError, TimeoutError, ConnectionError) as exc:
        raise CallError(f"connection: {exc}", None, True)


# ---------------------------------------------------------------- answers
def normalize_openai(resp, row):
    by_name = {}
    sent = [q for q in row["questions"] if not forced_choice(q)]
    for i, a in enumerate(resp.get("answers") or []):
        name = a.get("name") or sent[i]["name"]
        t = a.get("type")
        if t == "predicate":
            by_name[name] = {"type": "noul", "p": a["probability"]}
        elif t == "choice":
            by_name[name] = {"type": "choice", "choice": a["choice"], "confidence": a["confidence"],
                             "probabilities": {str(p["value"]): p["probability"] for p in a.get("probabilities") or []}}
        elif t == "score":
            by_name[name] = {"type": "score", "score": a["score"], "confidence": a["confidence"],
                             "probabilities": {p["label"]: p["probability"] for p in a.get("probabilities") or []}}
        else:
            by_name[name] = {"type": "refusal"}
    by_name.update(forced_answers(row))
    u = resp.get("usage") or {}
    usage = {"input_tokens": u.get("input_tokens", 0), "output_tokens": u.get("output_tokens", 0),
             "cached_tokens": (u.get("input_tokens_details") or {}).get("cached_tokens", 0)}
    return by_name, usage


def normalize_jev(resp, row):
    by_name = {}
    for name, a in (resp.get("answers") or {}).items():
        t = a.get("type")
        if t == "noul":
            by_name[name] = {"type": "noul", "p": a["noul"]}
        elif t == "choice":
            by_name[name] = {"type": "choice", "choice": a["choice"], "confidence": a["confidence"],
                             "probabilities": a.get("probabilities") or {}}
        elif t == "score":
            by_name[name] = {"type": "score", "score": a["score"], "confidence": a["confidence"],
                             "probabilities": a.get("probabilities") or {}}
        else:
            by_name[name] = {"type": t or "unknown"}
    u = resp.get("usage") or {}
    usage = {"input_tokens": u.get("input_tokens", 0), "output_tokens": u.get("output_tokens", 0), "cached_tokens": 0}
    return by_name, usage


def load_rule(point):
    path = os.path.join(HERE, point, "rule.py")
    if not os.path.exists(path):
        return None
    spec = importlib.util.spec_from_file_location(f"rule_{point}", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def verdict_for(row, answers, rule):
    """Return (verdict, confidence, settled, path) or raise CallError if unusable."""
    if row.get("variant") == "decomposed":
        if rule is None:
            raise CallError("decomposed row but no rule.py for this point")
        # Rules read nouls as floats, choices as {"value", "distribution"} and
        # scores as {"label", "distribution"}; some also take a second argument
        # (row["rule_facts"] when present, else the row's state).
        probs = {}
        for n, a in answers.items():
            if a.get("type") == "noul":
                probs[n] = a["p"]
            elif a.get("type") == "choice":
                probs[n] = {"value": a["choice"], "distribution": a.get("probabilities") or {}}
            elif a.get("type") == "score":
                probs[n] = {"label": a["score"], "distribution": a.get("probabilities") or {}}
        if hasattr(rule, "explain"):
            r = rule.explain(probs)
            return r["verdict"], r.get("confidence"), r.get("settled"), r.get("path")
        if len(inspect.signature(rule.decide).parameters) >= 2:
            extra = row["rule_facts"] if "rule_facts" in row else row.get("state")
            return rule.decide(probs, extra), None, None, None
        return rule.decide(probs), None, None, None
    q = row["questions"][0]
    a = answers.get(q["name"])
    if not a or a.get("type") == "refusal":
        raise CallError(f"no usable answer for {q['name']}: {a}")
    if a["type"] == "choice":
        return a["choice"], a["confidence"], None, None
    if a["type"] == "noul":
        return a["p"] >= 0.5, max(a["p"], 1 - a["p"]), None, None
    return a.get("score"), a.get("confidence"), None, None


def cost_usd(provider, usage, prices):
    cached = usage.get("cached_tokens", 0)
    fresh = max(0, usage.get("input_tokens", 0) - cached)
    return (fresh * prices["usd_in"] + cached * prices["usd_cached_in"] + usage.get("output_tokens", 0) * prices["usd_out"]) / 1e6


# ---------------------------------------------------------------- dataset / cache
def load_dataset(point):
    plain = os.path.join(HERE, point, "dataset.jsonl")
    if os.path.exists(plain):
        with open(plain, encoding="utf-8") as fh:
            return [json.loads(l) for l in fh]
    with lzma.open(plain + ".xz", "rt", encoding="utf-8") as fh:
        return [json.loads(l) for l in fh]


def results_path(point, provider):
    return os.path.join(RESULTS_DIR, point, f"results-{provider}.jsonl")


def load_results(point, provider):
    latest = {}
    path = results_path(point, provider)
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                r = json.loads(line)
                latest[r["id"]] = r
    return latest


def select(rows, args):
    out = [r for r in rows if args.split == "all" or r.get("split") == args.split]
    if args.variant != "both":
        out = [r for r in out if r.get("variant", "direct") == args.variant]
    if args.ids:
        wanted = set(args.ids.split(","))
        out = [r for r in out if r["id"] in wanted or r["id"].split("#")[0] in wanted]
    if args.cases:
        keep, seen = [], []
        for r in out:
            base = r["id"].split("#")[0]
            if base not in seen:
                if len(seen) >= args.cases:
                    continue
                seen.append(base)
            keep.append(r)
        out = keep
    if args.limit:
        out = out[: args.limit]
    return out


# ---------------------------------------------------------------- run
def run(args):
    prov = dict(PROVIDERS[args.provider])
    if args.usd_in is not None:
        prov["usd_in"] = prov["usd_cached_in"] = args.usd_in
    if args.usd_out is not None:
        prov["usd_out"] = args.usd_out
    model = args.model or prov["model"]
    rows = select(load_dataset(args.point), args)
    done = load_results(args.point, args.provider)
    todo = [r for r in rows if not (r["id"] in done and done[r["id"]].get("error") is None)]
    rule = load_rule(args.point)
    build = openai_payload if args.provider == "openai" else jev_payload
    payloads = {r["id"]: build(r, model) for r in todo}
    est_tokens = {i: math.ceil(len(json.dumps(p, ensure_ascii=False)) / 4) for i, p in payloads.items()}
    est_total = sum(est_tokens[i] * prov["usd_in"] / 1e6 + 20 * len(r["questions"]) * prov["usd_out"] / 1e6 for i, r in zip(payloads, todo))
    print(f"{args.provider}/{model}: {len(rows)} selected, {len(rows) - len(todo)} cached, {len(todo)} to send; "
          f"estimated ${est_total:.4f} (cap ${args.max_usd})", file=sys.stderr)
    if est_total > args.max_usd:
        print("projected spend exceeds --max-usd; nothing sent", file=sys.stderr)
        return 2
    if args.dry_run:
        for r in todo[:1]:
            print(json.dumps(payloads[r["id"]], indent=1, ensure_ascii=False)[:3000])
        return 0
    lock = threading.Lock()
    spent = [0.0]
    stop = [False]
    os.makedirs(os.path.dirname(results_path(args.point, args.provider)), exist_ok=True)
    out_fh = open(results_path(args.point, args.provider), "a", encoding="utf-8")

    def one(row):
        if stop[0]:
            return None
        payload = payloads[row["id"]]
        attempts, err, resp, started, latency = 0, None, None, None, None
        long_ctx = args.provider == "jev" and est_tokens[row["id"]] > prov["long_context_tokens"]
        while True:
            attempts += 1
            started = time.time()
            try:
                if args.provider == "openai":
                    resp = call_openai(payload, args.timeout)
                else:
                    resp = call_jev(payload, args.timeout, long_ctx)
                latency = time.time() - started
                err = None
                break
            except CallError as exc:
                latency = time.time() - started
                err = exc
                # chars/4 underestimates JSON-heavy states by up to 2x, so a payload under the
                # header threshold can still exceed Jev's 32k per-question limit: retry it once
                # with the long-context header instead of recording an error.
                if (args.provider == "jev" and not long_ctx and exc.status == 400
                        and "max_tokens_exceeded" in str(exc)):
                    long_ctx = True
                    continue
                if exc.retryable and attempts < args.retries:
                    time.sleep(min(60, 2 ** attempts))
                    continue
                break
        rec = {"id": row["id"], "point": args.point, "variant": row.get("variant"), "provider": args.provider,
               "model_requested": model, "request": payload, "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "attempts": attempts, "latency_ms": round(latency * 1000) if latency is not None else None,
               "long_context": long_ctx}
        if err is None:
            answers, usage = (normalize_openai if args.provider == "openai" else normalize_jev)(resp, row)
            rec.update({"response": resp, "model": resp.get("model"), "answers": answers, "usage": usage,
                        "cost_usd": round(cost_usd(args.provider, usage, prov), 8)})
            try:
                verdict, conf, settled, path = verdict_for(row, answers, rule)
                rec.update({"verdict": verdict, "confidence": conf, "settled": settled, "rule_path": path, "error": None})
            except CallError as exc:
                rec.update({"verdict": None, "error": f"answer: {exc}"})
        else:
            rec.update({"response": None, "answers": None, "usage": None, "cost_usd": 0.0, "verdict": None,
                        "error": str(err), "http_status": err.status})
        with lock:
            spent[0] += rec["cost_usd"] or 0.0
            out_fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
            out_fh.flush()
            if spent[0] > args.max_usd:
                stop[0] = True
        return rec

    results = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futs = [pool.submit(one, r) for r in todo]
        for i, f in enumerate(as_completed(futs), 1):
            rec = f.result()
            if rec is None:
                continue
            results.append(rec)
            if i % 10 == 0 or i == len(futs):
                errs = sum(1 for r in results if r["error"])
                print(f"  {i}/{len(futs)} done, {errs} errors, ${spent[0]:.4f}", file=sys.stderr)
            # Re-project after real costs arrive.
            done_cost = [r["cost_usd"] for r in results if r["cost_usd"]]
            if done_cost and len(done_cost) >= 5:
                proj = spent[0] + statistics.mean(done_cost) * (len(todo) - len(results))
                if proj > args.max_usd and not stop[0]:
                    stop[0] = True
                    print(f"projected ${proj:.2f} exceeds cap; stopping", file=sys.stderr)
    out_fh.close()
    errs = [r for r in results if r["error"]]
    print(f"sent {len(results)}, errors {len(errs)}, spent ${spent[0]:.4f}", file=sys.stderr)
    for r in errs[:5]:
        print(f"  ERROR {r['id']}: {r['error'][:300]}", file=sys.stderr)
    return 1 if errs else 0


# ---------------------------------------------------------------- report
def kappa(pairs, labels):
    n = len(pairs)
    if not n:
        return None
    po = sum(1 for a, b in pairs if a == b) / n
    pe = sum((sum(1 for a, _ in pairs if a == l) / n) * (sum(1 for _, b in pairs if b == l) / n) for l in labels)
    return round((po - pe) / (1 - pe), 4) if pe < 1 else None


def agreement(pairs, labels):
    if not pairs:
        return {"n": 0}
    cm = {t: {p: 0 for p in labels} for t in labels}
    for t, p in pairs:
        cm.setdefault(t, {}).setdefault(p, 0)
        cm[t][p] += 1
    return {"n": len(pairs), "accuracy": round(sum(1 for t, p in pairs if t == p) / len(pairs), 4),
            "kappa": kappa(pairs, labels), "confusion(true->pred)": cm}


def report(args):
    rows = {r["id"]: r for r in select(load_dataset(args.point), args)}
    res = {i: r for i, r in load_results(args.point, args.provider).items() if i in rows}
    labels = sorted({r["labels"]["system"]["verdict"] for r in rows.values()})
    out = {"point": args.point, "provider": args.provider, "selected_rows": len(rows), "results": len(res)}
    for variant in sorted({r.get("variant", "direct") for r in rows.values()}):
        rs = [r for i, r in res.items() if rows[i].get("variant", "direct") == variant]
        ok = [r for r in rs if not r["error"]]
        sec = {"answered": len(ok), "errors": len(rs) - len(ok)}
        sys_pairs = [(rows[r["id"]]["labels"]["system"]["verdict"], r["verdict"]) for r in ok]
        out_pairs = [(rows[r["id"]]["labels"]["outcome"]["verdict"], r["verdict"]) for r in ok if "outcome" in rows[r["id"]]["labels"]]
        sec["vs_system"] = agreement(sys_pairs, labels)
        sec["vs_outcome"] = agreement(out_pairs, labels)
        llm_vs_outcome = [(rows[r["id"]]["labels"]["outcome"]["verdict"], rows[r["id"]]["labels"]["system"]["verdict"])
                          for r in ok if "outcome" in rows[r["id"]]["labels"]]
        sec["system_llm_vs_outcome_same_rows"] = agreement(llm_vs_outcome, labels)
        for thr in (0.8, 0.9):
            conf = [r for r in ok if r.get("confidence") is not None and r["confidence"] >= thr and r.get("settled") is not False]
            cp = [(rows[r["id"]]["labels"]["system"]["verdict"], r["verdict"]) for r in conf]
            co = [(rows[r["id"]]["labels"]["outcome"]["verdict"], r["verdict"]) for r in conf if "outcome" in rows[r["id"]]["labels"]]
            sec[f"conf>={thr}"] = {"coverage": round(len(conf) / len(ok), 4) if ok else None,
                                   "n": len(conf), "acc_vs_system": agreement(cp, labels).get("accuracy"),
                                   "n_outcome": len(co), "acc_vs_outcome": agreement(co, labels).get("accuracy")}
        if variant == "decomposed":
            settled = [r for r in ok if r.get("settled")]
            sec["settled"] = {"coverage": round(len(settled) / len(ok), 4) if ok else None,
                              "acc_vs_system": agreement([(rows[r["id"]]["labels"]["system"]["verdict"], r["verdict"]) for r in settled], labels).get("accuracy"),
                              "paths": dict(collections.Counter(r.get("rule_path") for r in ok))}
        lat = sorted(r["latency_ms"] for r in ok if r.get("latency_ms") is not None)
        if lat:
            sec["latency_ms"] = {"p50": lat[len(lat) // 2], "p95": lat[min(len(lat) - 1, math.ceil(0.95 * len(lat)) - 1)], "max": lat[-1]}
        sec["cost_usd"] = round(sum(r.get("cost_usd") or 0 for r in ok), 6)
        sec["input_tokens"] = sum((r.get("usage") or {}).get("input_tokens", 0) for r in ok)
        sec["disagreements"] = [
            {"id": r["id"], "system": rows[r["id"]]["labels"]["system"]["verdict"],
             "outcome": rows[r["id"]]["labels"].get("outcome", {}).get("verdict"),
             "pred": r["verdict"], "confidence": r.get("confidence"), "rule_path": r.get("rule_path")}
            for r in ok if r["verdict"] != rows[r["id"]]["labels"]["system"]["verdict"]][:15]
        out[variant] = sec
    path = os.path.join(RESULTS_DIR, args.point, f"runner-report-{args.provider}.json")
    with open(path, "w") as fh:
        json.dump(out, fh, indent=1)
    print(json.dumps(out, indent=1))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["run", "report"])
    ap.add_argument("--point", required=True)
    ap.add_argument("--provider", choices=sorted(PROVIDERS), required=True)
    ap.add_argument("--model")
    ap.add_argument("--split", choices=["dev", "test", "all"], default="dev")
    ap.add_argument("--variant", choices=["direct", "decomposed", "both"], default="both")
    ap.add_argument("--cases", type=int, help="first N distinct cases (all selected variants of each)")
    ap.add_argument("--limit", type=int, help="first N rows after other filters")
    ap.add_argument("--ids", help="comma-separated row ids or case ids")
    ap.add_argument("--max-usd", type=float, default=5.0)
    ap.add_argument("--usd-in", type=float)
    ap.add_argument("--usd-out", type=float)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--retries", type=int, default=5)
    ap.add_argument("--timeout", type=float, default=120.0)
    ap.add_argument("--dry-run", action="store_true", help="print one payload, send nothing")
    ap.add_argument("--results-dir", help="where results/<point>/results-<provider>.jsonl live (default: ./results)")
    args = ap.parse_args(argv)
    if args.results_dir:
        global RESULTS_DIR
        RESULTS_DIR = os.path.abspath(args.results_dir)
    return run(args) if args.command == "run" else report(args)


if __name__ == "__main__":
    sys.exit(main())
