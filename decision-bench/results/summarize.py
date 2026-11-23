#!/usr/bin/env python3
"""Score the runner caches; write results/<point>/report-<provider>.json and results/SUMMARY.md.

    summarize.py [--data DIR] [--caches DIR [--strip-request]] [--annotations DIR] [--findings FILE]

Paths (the defaults fit the published layout, with this script in results/):
  --data DIR      <point>/dataset.jsonl or <point>/dataset.jsonl.xz; these rows are in scope.
                  Default: the directory above results/.
  results/<point>/results-<provider>.jsonl
                  the runner caches that get scored (one record per call, latest per id wins).
  --caches DIR    first import caches from DIR/<point>/results-<provider>.jsonl: records for
                  in-scope ids are copied into results/<point>/, records for other ids are
                  counted as billed but never scored. --strip-request drops each record's
                  `request` (the payload; rebuildable from the dataset and run_decisions.py).
                  Billing totals are kept in results/billing.json for later runs without it.
  --annotations DIR
                  gold.jsonl and agreement.json. Default: annotations/ next to results/.
  --findings FILE markdown placed at the top of SUMMARY.md as the headline findings.

Scoring differs from run_decisions.py's `report` in six deliberate ways:
  * direct noul verdicts (True/False) are mapped onto the label space where the
    labels are strings (patrol_finding_dedup, visual_capture_need);
  * a null outcome verdict counts as "no outcome", not as a class;
  * outcome vocabularies that are not verdicts (provider_failure_class: retry fate)
    are not scored as accuracy; a grounded healthy-run check is reported instead;
  * rule abstentions ("unsure", "unsettled") count as wrong in all-rows accuracy
    and as not decisive; visual_capture_need's "unsettled" is mapped fail-closed to
    needs_capture, as its rule.py `decide_fail_closed` (and Hive) does;
  * decisive subsets: direct choice/score confidence >= 0.8 (A) / >= 0.9 (B);
    direct noul p <= 0.3 or >= 0.7 (A) / <= 0.1 or >= 0.9 (B); decomposed A = rule
    settled (no abstention, settled != False), B = A and every component answer
    decisive (noul outside 0.3-0.7, choice/score confidence >= 0.8);
  * `gold` (Claude∩Neon) is annotations/gold.jsonl: adjudicated cases on which a second,
    blind annotator gave the same label. Both variants of a case share its gold label.
"""
import argparse
import collections
import json
import lzma
import math
import os

OUT = os.path.dirname(os.path.abspath(__file__))
PROVIDERS = ("openai", "jev")
VARIANTS = ("direct", "decomposed")
NOUL_MAP = {"patrol_finding_dedup": {True: "same", False: "different"},
            "visual_capture_need": {True: "needs_capture", False: "no_capture"}}
ABSTAIN = {"unsure", "unsettled"}
NON_VERDICT_OUTCOME = {"provider_failure_class"}
GOLD = {}  # point -> {case id (no #variant): gold verdict in the labels' vocabulary}


def open_text(path):
    return lzma.open(path, "rt", encoding="utf-8") if path.endswith(".xz") else open(path, encoding="utf-8")


def load_jsonl(path):
    with open_text(path) as fh:
        return [json.loads(l) for l in fh if l.strip()]


def dataset_path(data, point):
    for name in ("dataset.jsonl", "dataset.jsonl.xz"):
        p = os.path.join(data, point, name)
        if os.path.isfile(p):
            return p
    return None


def write_private(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.chmod(path, 0o600)


def kappa(pairs):
    n = len(pairs)
    if not n:
        return None
    cats = {a for a, _ in pairs} | {b for _, b in pairs}
    po = sum(1 for a, b in pairs if a == b) / n
    ca = collections.Counter(a for a, _ in pairs)
    cb = collections.Counter(b for _, b in pairs)
    pe = sum(ca[c] / n * cb[c] / n for c in cats)
    return None if pe >= 1 else (po - pe) / (1 - pe)


def agree(pairs):
    if not pairs:
        return {"n": 0, "accuracy": None, "kappa": None}
    k = kappa(pairs)
    return {"n": len(pairs), "accuracy": round(sum(a == b for a, b in pairs) / len(pairs), 4),
            "kappa": None if k is None else round(k, 4)}


def confusion(pairs):
    cm = collections.defaultdict(collections.Counter)
    for t, p in pairs:
        cm[str(t)][str(p)] += 1
    return {t: dict(c) for t, c in cm.items()}


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, max(0, math.ceil(q * len(xs)) - 1))] if xs else None


def gold_labels(point, row):
    lab = row["labels"]
    out = {"system": lab["system"]["verdict"]}
    o = lab.get("outcome", {}).get("verdict")
    if o is not None and point not in NON_VERDICT_OUTCOME:
        out["outcome"] = o
    if lab.get("adjudicated", {}).get("verdict") is not None:
        out["adjudicated"] = lab["adjudicated"]["verdict"]
    if lab.get("llm_inference", {}).get("verdict") is not None:
        out["llm_inference"] = lab["llm_inference"]["verdict"]
    case = row["id"].split("#")[0]
    if case in GOLD.get(point, {}):
        out["gold"] = GOLD[point][case]
    return out


def load_gold(annotations):
    path = os.path.join(annotations, "gold.jsonl")
    if not os.path.exists(path):
        return
    for g in load_jsonl(path):
        # gold_label is in the direct question's vocabulary (true/false for nouls);
        # gold_label_adjudicated_vocab, where present, is in the labels' vocabulary.
        GOLD.setdefault(g["point"], {})[g["id"].split("#")[0]] = g.get("gold_label_adjudicated_vocab", g["gold_label"])


def answer_decisive(a, strict=False):
    if a is None:
        return False
    t = a.get("type")
    if t == "noul":
        p = a["p"]
        lo, hi = (0.1, 0.9) if strict else (0.3, 0.7)
        return p <= lo or p >= hi
    if t in ("choice", "score"):
        return (a.get("confidence") or 0) >= (0.9 if strict else 0.8)
    return False


def interpret(point, row, rec):
    """-> dict(pred, settled, decA, decB) for one successful record."""
    v = rec["verdict"]
    variant = row.get("variant", "direct")
    if variant == "direct":
        if isinstance(v, bool) and point in NOUL_MAP:
            v = NOUL_MAP[point][v]
        a = (rec.get("answers") or {}).get(row["questions"][0]["name"])
        return {"pred": v, "settled": True, "decA": answer_decisive(a), "decB": answer_decisive(a, strict=True)}
    settled = rec.get("settled")
    settled = (v not in ABSTAIN) if settled is None else (bool(settled) and v not in ABSTAIN)
    if point == "visual_capture_need" and v == "unsettled":
        v = "needs_capture"
    comps = all(answer_decisive(a) for a in (rec.get("answers") or {}).values())
    return {"pred": v, "settled": settled, "decA": settled, "decB": settled and comps}


def section(point, rows, recs):
    """Metrics for one (provider, variant, split) slice."""
    ok, errs, missing = [], 0, 0
    for r in rows:
        rec = recs.get(r["id"])
        if rec is None:
            missing += 1
        elif rec.get("error"):
            errs += 1
        else:
            ok.append((r, rec, interpret(point, r, rec)))
    s = {"rows": len(rows), "answered": len(ok), "errors": errs, "not_run": missing}
    for g in ("system", "outcome", "adjudicated", "gold", "llm_inference"):
        pairs = [(gold_labels(point, r)[g], it["pred"]) for r, _, it in ok if g in gold_labels(point, r)]
        if pairs:
            s[f"vs_{g}"] = agree(pairs)
            s[f"vs_{g}"]["confusion(true->pred)"] = confusion(pairs)
    for key in ("decA", "decB"):
        sub = [(r, it) for r, _, it in ok if it[key]]
        d = {"coverage": round(len(sub) / len(ok), 4) if ok else None, "n": len(sub)}
        for g in ("system", "outcome", "adjudicated", "gold"):
            pairs = [(gold_labels(point, r)[g], it["pred"]) for r, it in sub if g in gold_labels(point, r)]
            d[f"acc_{g}"] = agree(pairs)["accuracy"]
            d[f"n_{g}"] = len(pairs)
        s[key] = d
    if point == "patrol_fix_semantic_admission":
        s["vs_system_coarse_route"] = agree([(gold_labels(point, r)["system"].split(":")[0], str(it["pred"]).split(":")[0]) for r, _, it in ok])
    if point == "provider_failure_class":
        healthy = [(r, it) for r, _, it in ok if r["labels"].get("outcome", {}).get("verdict") == "run_completed_normally"]
        s["healthy_run_check"] = {
            "n": len(healthy),
            "pred_other_or_healthy": round(sum(it["pred"] == "other_or_healthy" for _, it in healthy) / len(healthy), 4) if healthy else None,
            "system_other_or_healthy": round(sum(r["labels"]["system"]["verdict"] == "other_or_healthy" for r, _ in healthy) / len(healthy), 4) if healthy else None}
        s["pred_x_outcome"] = confusion([(r["labels"].get("outcome", {}).get("verdict"), it["pred"]) for r, _, it in ok])
    lat = [rec["latency_ms"] for _, rec, _ in ok if rec.get("latency_ms") is not None]
    s["latency_ms"] = {"p50": pct(lat, 0.5), "p95": pct(lat, 0.95), "max": max(lat) if lat else None}
    s["cost_usd"] = round(sum(rec.get("cost_usd") or 0 for _, rec, _ in ok), 6)
    s["input_tokens"] = sum((rec.get("usage") or {}).get("input_tokens", 0) for _, rec, _ in ok)
    s["verdict_dist"] = dict(collections.Counter(str(it["pred"]) for _, _, it in ok))
    return s


def incumbent(point, rows):
    """System label (and llm_inference where present) vs outcome / adjudicated / gold on the same rows."""
    out = {}
    for inc in ("system", "llm_inference"):
        for g in ("outcome", "adjudicated", "gold"):
            pairs = [(gold_labels(point, r)[g], gold_labels(point, r)[inc]) for r in rows
                     if g in gold_labels(point, r) and inc in gold_labels(point, r)]
            if pairs:
                out.setdefault(inc, {})[f"vs_{g}"] = agree(pairs)
    return out


def fmt_ak(m):
    if not m or not m.get("n"):
        return "-"
    k = "-" if m.get("kappa") is None else f"{m['kappa']:.2f}"
    return f"{m['accuracy']:.3f} / {k} ({m['n']})"


def fmt_acc(m):
    return "-" if not m or not m.get("n") else f"{m['accuracy']:.3f}"


def fmt_dec(d, gold):
    if not d or d.get("coverage") is None:
        return "-"
    a = "-" if d["acc_system"] is None else f"{d['acc_system']:.3f}"
    g = "" if not gold or d.get(f"n_{gold}", 0) == 0 or d.get(f"acc_{gold}") is None else f", {d[f'acc_{gold}']:.3f}g"
    return f"{d['coverage']:.2f} → {a}{g}"


def short_state(state, n=260):
    s = json.dumps(state, ensure_ascii=False) if not isinstance(state, str) else state
    s = " ".join(s.split()).replace("`", "'").replace("|", "/")
    return s[:n] + ("…" if len(s) > n else "")


def pick_examples(point, rows_by_id, results, gold):
    """Up to 3 test-split disagreements: models beat incumbent, models wrong, providers split."""
    cands = []
    for rid, row in rows_by_id.items():
        if row.get("variant") != "direct" or row.get("split") != "test":
            continue
        base = rid.split("#")[0]
        preds = {}
        for prov in PROVIDERS:
            for var in VARIANTS:
                rec = results[prov].get(f"{base}#{var}")
                vrow = rows_by_id.get(f"{base}#{var}")
                if rec and not rec.get("error") and vrow:
                    preds[(prov, var)] = interpret(point, vrow, rec)["pred"]
        if ("openai", "direct") not in preds or ("jev", "direct") not in preds:
            continue
        gl = gold_labels(point, row)
        sysv, g = gl["system"], gl.get(gold) if gold else None
        od, jd = preds[("openai", "direct")], preds[("jev", "direct")]
        kind = None
        if g is not None and od == jd == g != sysv:
            kind = "models_beat_incumbent"
        elif g is not None and od == jd != g and g == sysv:
            kind = "models_wrong"
        elif od != jd:
            kind = "providers_split"
        elif od == jd != sysv:
            kind = "models_vs_system"
        if kind:
            cands.append((kind, base, sysv, g, preds, row["state"]))
    chosen, seen = [], set()
    for want in ("models_beat_incumbent", "models_wrong", "providers_split", "models_vs_system"):
        for c in cands:
            if c[0] == want and c[0] not in seen:
                chosen.append(c)
                seen.add(c[0])
                break
        if len(chosen) == 3:
            break
    return chosen


def import_caches(caches, points, scope, strip_request):
    """Copy in-scope cache records into results/<point>/; return billing totals per provider."""
    billing = {p: {"billed": 0.0, "excluded_billed": 0.0, "excluded_rows": 0} for p in PROVIDERS}
    for point in points:
        os.makedirs(os.path.join(OUT, point), mode=0o700, exist_ok=True)
        for prov in PROVIDERS:
            src = os.path.join(caches, point, f"results-{prov}.jsonl")
            lines = load_jsonl(src) if os.path.exists(src) else []
            keep, foreign = [], set()
            for l in lines:
                billing[prov]["billed"] += l.get("cost_usd") or 0
                if l["id"] in scope[point]:
                    if strip_request:
                        l.pop("request", None)
                    keep.append(l)
                else:
                    foreign.add(l["id"])
                    billing[prov]["excluded_billed"] += l.get("cost_usd") or 0
            billing[prov]["excluded_rows"] += len(foreign)
            write_private(os.path.join(OUT, point, f"results-{prov}.jsonl"),
                          "".join(json.dumps(l, ensure_ascii=False) + "\n" for l in keep))
    for p in PROVIDERS:
        billing[p] = {k: round(v, 6) if isinstance(v, float) else v for k, v in billing[p].items()}
    write_private(os.path.join(OUT, "billing.json"), json.dumps(billing, indent=1) + "\n")
    return billing


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=os.path.normpath(os.path.join(OUT, "..")))
    ap.add_argument("--caches")
    ap.add_argument("--strip-request", action="store_true")
    ap.add_argument("--annotations", default=os.path.normpath(os.path.join(OUT, "..", "annotations")))
    ap.add_argument("--findings")
    args = ap.parse_args()
    load_gold(args.annotations)
    points = sorted(p for p in os.listdir(args.data) if dataset_path(args.data, p))
    datasets = {p: load_jsonl(dataset_path(args.data, p)) for p in points}
    scope = {p: {r["id"] for r in rows} for p, rows in datasets.items()}
    if args.caches:
        billing = import_caches(args.caches, points, scope, args.strip_request)
    else:
        bpath = os.path.join(OUT, "billing.json")
        billing = json.load(open(bpath)) if os.path.exists(bpath) else None
    totals = {p: {"in_scope": 0.0, "calls": 0, "errors_final": 0, "lat": collections.defaultdict(list),
                  "rows": collections.Counter(), "cost": collections.Counter()} for p in PROVIDERS}
    md_points, dev_md, board, board_nogold = [], [], [], []
    for point in points:
        rows = datasets[point]
        rows_by_id = {r["id"]: r for r in rows}
        results = {}
        for prov in PROVIDERS:
            src = os.path.join(OUT, point, f"results-{prov}.jsonl")
            keep = [l for l in (load_jsonl(src) if os.path.exists(src) else []) if l["id"] in rows_by_id]
            totals[prov]["in_scope"] += sum(l.get("cost_usd") or 0 for l in keep)
            totals[prov]["calls"] += len(keep)
            latest = {}
            for l in keep:
                latest[l["id"]] = l
            totals[prov]["errors_final"] += sum(1 for l in latest.values() if l.get("error"))
            for l in latest.values():
                if not l.get("error"):
                    var = rows_by_id[l["id"]].get("variant", "direct")
                    totals[prov]["rows"][var] += 1
                    totals[prov]["cost"][var] += l.get("cost_usd") or 0
                    if l.get("latency_ms") is not None:
                        totals[prov]["lat"][var].append(l["latency_ms"])
            results[prov] = latest
        gold = None
        has = collections.Counter(g for r in rows for g in gold_labels(point, r))
        if has.get("adjudicated"):
            gold = "adjudicated"
        elif has.get("outcome"):
            gold = "outcome"
        example_gold = "gold" if has.get("gold") else gold
        rep_all = {}
        for prov in PROVIDERS:
            rep = {"point": point, "provider": prov, "rows_in_scope": len(rows), "gold_for_decisive": gold,
                   "scoring": "summarize.py (see its docstring)"}
            for split in ("test", "dev"):
                rep[split] = {}
                for var in VARIANTS:
                    sl = [r for r in rows if r.get("split") == split and r.get("variant", "direct") == var]
                    rep[split][var] = section(point, sl, results[prov])
            rep["incumbent"] = {split: incumbent(point, [r for r in rows if r.get("split") == split and r.get("variant") == "direct"])
                                for split in ("test", "dev")}
            rep_all[prov] = rep
            write_private(os.path.join(OUT, point, f"report-{prov}.json"), json.dumps(rep, indent=1, ensure_ascii=False))
        # ---------------- scoreboards (test split)
        src_counts = collections.Counter(r["labels"]["system"].get("source", "?").split(":")[0] for r in rows if r.get("variant") == "direct")
        inc_kind = "/".join(sorted(src_counts))
        inc_test = rep_all["openai"]["incumbent"]["test"].get("system", {})
        cells = [rep_all[p]["test"][v] for p in PROVIDERS for v in VARIANTS]
        if has.get("gold"):
            board.append((point, inc_kind, inc_test.get("vs_gold"), [c.get("vs_gold") for c in cells]))
        else:
            ref = "outcome" if has.get("outcome") else "system"
            board_nogold.append((point, inc_kind, ref, inc_test.get(f"vs_{ref}") if ref != "system" else None,
                                 [c.get(f"vs_{ref}") for c in cells]))
        # ---------------- per-point markdown
        for split, sink in (("test", md_points), ("dev", dev_md)):
            n_cases = sum(1 for r in rows if r.get("split") == split and r.get("variant") == "direct")
            n_gold_split = sum(1 for r in rows if r.get("split") == split and r.get("variant") == "direct" and "gold" in gold_labels(point, r))
            lines = [f"### {point} ({split}: {n_cases} cases, {n_gold_split} with gold; incumbent = {inc_kind}; decisive gold = {gold or 'none'})", "",
                     "| provider | variant | acc / κ (n) vs system | vs outcome | vs adjudicated | vs gold (C∩N) | decisive A: cov → acc sys, gold | decisive B | p50 / p95 ms |",
                     "|---|---|---|---|---|---|---|---|---|"]
            for prov in PROVIDERS:
                for var in VARIANTS:
                    s = rep_all[prov][split][var]
                    err = f" ⚠{s['errors']} err" if s["errors"] else ""
                    nr = f" ⚠{s['not_run']} not run" if s["not_run"] else ""
                    lat = s["latency_ms"]
                    lines.append(f"| {prov} | {var}{err}{nr} | {fmt_ak(s.get('vs_system'))} | {fmt_ak(s.get('vs_outcome'))} | "
                                 f"{fmt_ak(s.get('vs_adjudicated'))} | {fmt_ak(s.get('vs_gold'))} | {fmt_dec(s['decA'], gold)} | "
                                 f"{fmt_dec(s['decB'], gold)} | {lat['p50']} / {lat['p95']} |")
            inc = rep_all["openai"]["incumbent"][split]
            for name, m in inc.items():
                lines.append(f"| incumbent | {name} | (itself) | {fmt_ak(m.get('vs_outcome'))} | {fmt_ak(m.get('vs_adjudicated'))} | "
                             f"{fmt_ak(m.get('vs_gold'))} | | | |")
            extra = []
            if point == "patrol_fix_semantic_admission":
                extra.append("Coarse route (same_root / distinct / insufficient_evidence) vs system: " + "; ".join(
                    f"{p} {v} {fmt_ak(rep_all[p][split][v].get('vs_system_coarse_route'))}" for p in PROVIDERS for v in VARIANTS))
            if point == "provider_failure_class":
                hc = rep_all["openai"][split]["direct"]["healthy_run_check"]
                extra.append(f"Outcome here is retry fate, not a class, so it is not scored as accuracy. Healthy-run check "
                             f"(outcome = run completed normally, so other_or_healthy is right; n={hc['n']}): system "
                             f"{hc['system_other_or_healthy']}; " + "; ".join(
                                 f"{p} {v} {rep_all[p][split][v]['healthy_run_check']['pred_other_or_healthy']}" for p in PROVIDERS for v in VARIANTS))
            if point == "ci_failure_triage":
                extra.append("Outcome exists only as defect_from_diff (a fix landed), so vs-outcome accuracy is recall of that class.")
            if point == "visual_capture_need":
                extra.append("Decomposed `unsettled` is mapped fail-closed to needs_capture for accuracy and counted as not decisive.")
            if extra:
                lines += [""] + [f"- {e}" for e in extra]
            lines.append("")
            if split == "test":
                ex = pick_examples(point, rows_by_id, results, example_gold)
                if ex:
                    lines.append("Illustrative disagreements (test):")
                    lines.append("")
                    for kind, base, sysv, g, preds, state in ex:
                        ps = ", ".join(f"{p[0]}/{p[1][:3]}={v}" for p, v in sorted(preds.items()))
                        gtxt = f"; {example_gold}={g}" if g is not None else ""
                        lines.append(f"- **{kind}** `{base[-60:]}`: system={sysv}{gtxt}; {ps}")
                        lines.append(f"  > {short_state(state)}")
                    lines.append("")
            sink.append("\n".join(lines))
    # ---------------- top sections
    findings = ""
    if args.findings and os.path.exists(args.findings):
        findings = open(args.findings, encoding="utf-8").read().strip() + "\n"
    head = ["# Decision-model comparison: OpenAI Decisions (gpt-6-luna) vs TypeSafe Jev (jev-1.14.0)", "",
            "Generated by `summarize.py` from the runner caches. Scored rows: the sanitized datasets with out-of-scope "
            "projects removed. Metrics are on the **test** split unless a table says otherwise; dev is in its own "
            "section at the end.", ""]
    if findings:
        head += [findings]
    cols = " | ".join(f"{p} {v}" for p in PROVIDERS for v in VARIANTS)
    head += ["## Gold scoreboard (test split, accuracy vs gold = Claude∩Neon)", "",
             "Gold is the subset of hand-adjudicated cases where a second, blind annotator (Gemini 4 Neon) gave the "
             "same label. The incumbent is Hive's own decision (`labels.system`). Rule abstentions count as wrong.", "",
             f"| point | incumbent | n | incumbent acc | {cols} |", "|---|---|---|---|" + "---|" * 4]
    keys = ["incumbent"] + [f"{p} {v}" for p in PROVIDERS for v in VARIANTS]
    macro = collections.defaultdict(list)
    pooled = collections.defaultdict(lambda: [0, 0])
    for point, kind, inc_m, ms in board:
        n = inc_m["n"] if inc_m else (ms[0] or {}).get("n", 0)
        head.append(f"| {point} | {kind} | {n} | {fmt_acc(inc_m)} | " + " | ".join(fmt_acc(m) for m in ms) + " |")
        for key, m in zip(keys, [inc_m] + ms):
            if m and m.get("n"):
                macro[key].append(m["accuracy"])
                pooled[key][0] += round(m["accuracy"] * m["n"])
                pooled[key][1] += m["n"]
    head.append("| **mean of points** | | | " + " | ".join(
        f"{sum(macro[k]) / len(macro[k]):.3f}" if macro[k] else "-" for k in keys) + " |")
    head.append(f"| **pooled rows** | | {pooled['incumbent'][1]} | " + " | ".join(
        f"{pooled[k][0] / pooled[k][1]:.3f}" if pooled[k][1] else "-" for k in keys) + " |")
    head += ["", "Points without a gold set (test split; reference = outcome where it exists, else Hive's LLM decision):", "",
             f"| point | incumbent | reference | n | incumbent acc | {cols} |", "|---|---|---|---|---|" + "---|" * 4]
    for point, kind, ref, inc_m, ms in board_nogold:
        n = (ms[0] or {}).get("n", 0)
        head.append(f"| {point} | {kind} | {ref} | {n} | {fmt_acc(inc_m) if ref != 'system' else '(itself)'} | "
                    + " | ".join(fmt_acc(m) for m in ms) + " |")
    apath = os.path.join(args.annotations, "agreement.json")
    if os.path.exists(apath):
        agreement = json.load(open(apath, encoding="utf-8"))
        head += ["", "## Annotator agreement (Claude vs Neon, all splits)", "",
                 "Claude's first-pass adjudication (`labels.adjudicated`) against Gemini 4 Neon labelling the same "
                 "rows blind (state and direct question only). Gold = the rows where they agree.", "",
                 "| point | question | n | agree | agreement | κ |", "|---|---|---|---|---|---|"]
        for point, a in sorted(agreement["points"].items()):
            head.append(f"| {point} | `{a['question']}` | {a['n']} | {a['agree']} | {a['raw_agreement']:.3f} | {a['cohens_kappa']:.2f} |")
        o = agreement.get("overall") or {}
        if o:
            head.append(f"| **all** | | {o['n']} | {o['agree']} | {o['raw_agreement']:.3f} | {o['mean_kappa_across_points']:.2f} (mean of points) |")
    head += ["", "## Cost and latency", "",
             "| provider | billed (all calls) | in-scope rows | calls kept | rows with final error |", "|---|---|---|---|---|"]
    for p in PROVIDERS:
        t = totals[p]
        billed = f"${billing[p]['billed']:.4f}" if billing else "-"
        head.append(f"| {p} | {billed} | ${t['in_scope']:.4f} | {t['calls']} | {t['errors_final']} |")
    if billing and any(billing[p]["excluded_rows"] for p in PROVIDERS):
        head += ["", "Billed includes " + "; ".join(
            f"{billing[p]['excluded_rows']} {p} rows (${billing[p]['excluded_billed']:.4f})" for p in PROVIDERS)
            + " sent before an owner exclusion; they are not scored or published."]
    head += ["", "Per answered row, all splits and points (latency is wall-clock at the client with 8 concurrent "
             "requests; cost uses each provider's list price per token, see run_decisions.py):", "",
             "| provider | variant | rows | p50 ms | p95 ms | USD per 1,000 rows |", "|---|---|---|---|---|---|"]
    for p in PROVIDERS:
        for v in VARIANTS:
            t = totals[p]
            lat = t["lat"][v]
            per_k = 1000 * t["cost"][v] / t["rows"][v] if t["rows"][v] else 0
            head.append(f"| {p} | {v} | {t['rows'][v]} | {pct(lat, 0.5)} | {pct(lat, 0.95)} | {per_k:.3f} |")
    head += ["", "## How to read the per-point tables", "",
             "`acc / κ (n)` is accuracy, Cohen's kappa and row count. *Decisive A/B*: coverage (share of answered rows "
             "that are decisive), then accuracy vs system and vs the point's decisive gold (`g`: adjudicated if the point "
             "has it, else outcome). Direct: A = confidence ≥ 0.8 (choice) or noul ≤ 0.3/≥ 0.7; B = confidence ≥ 0.9 or "
             "noul ≤ 0.1/≥ 0.9. Decomposed: A = rule settled (no abstention); B = settled and every component answer "
             "decisive. Rule abstentions count as wrong in all-rows accuracy. Incumbent rows score Hive's own decision "
             "(labels.system, and the artifacts LLM where present) against the same labels. `vs gold (C∩N)` is the "
             "Claude∩Neon gold subset.", ""]
    doc = "\n".join(head) + "\n## Per point (test split)\n\n" + "\n".join(md_points) + \
        "\n## Dev split (20%, used for wording iterations upstream)\n\n" + "\n".join(dev_md)
    write_private(os.path.join(OUT, "SUMMARY.md"), doc)
    print(json.dumps({p: {k: (round(v, 4) if isinstance(v, float) else v) for k, v in totals[p].items()
                          if k in ("in_scope", "calls", "errors_final")} for p in PROVIDERS}, indent=1))


if __name__ == "__main__":
    main()
