# Decision-eval dataset format (shared by every decision point)

> This is the spec the dataset builders worked from, published as written apart from
> path and layout notes. In this repository each point lives in `decision-bench/<point>/`,
> the dataset is compressed as `dataset.jsonl.xz`, and `decision-bench/README.md` replaces
> the per-point READMEs and `stats.json` the spec asks for. Published rows also carry
> `variant` and `split` (Revision 2), and some points add `rule` (a pointer to the rule
> function, decomposed rows only), `rule_facts` (code facts the rule reads) and
> `labels.llm_inference` (a second LLM label, visual_capture_need only).

Goal: replay past Hive decisions against two decision-model APIs (OpenAI Decisions
`gpt-6-luna` and TypeSafe Jev) and compare them with what Hive actually decided and,
where derivable, with what turned out to be right. One shared runner will call both
APIs, so every dataset must use exactly this format.

Directory: `<point>/` where `<point>` is a short snake_case name.

## `<point>/dataset.jsonl` — one JSON object per line

```json
{
  "id": "<point>:<stable id, e.g. project:slug:file:index>",
  "point": "<point>",
  "state": "<plain text the model sees; <= 120000 chars (~30k tokens)>",
  "questions": [
    {
      "name": "verdict",
      "type": "choice",              // "predicate" | "choice" | "score"
      "instructions": "<what to decide, paraphrasing Hive's own prompt/rule>",
      "choices": [ {"value": "keep_gate", "description": "..."},
                   {"value": "auto_apply", "description": "..."} ]
      // predicate: no choices/levels; answer is P(yes)
      // score: "levels": [ {"label": "low", "description": "..."}, ... ] (2-10, ordered)
    }
  ],
  "labels": {
    "system":  {"verdict": "<what Hive decided>", "source": "llm:<model>|regex|heuristic"},
    "outcome": {"verdict": "<what later evidence says was right>", "source": "<how derived>"},   // optional
    "adjudicated": {"verdict": "...", "source": "claude-adjudicated", "note": "<one line>"}       // optional
  },
  "meta": { "project": "...", "task": "...", "recorded_at": "...", "source_path": "..." }
}
```

Rules
- `state` is self-contained: everything the decision needs, nothing it does not. Wrap
  untrusted text (PR bodies, agent output, reviewer text) in clear delimiters.
- Redact secrets before writing `state`: tokens/keys (OpenAI, GitHub, Slack and AWS key formats;
  secret-manager references that carry no value may stay), bearer headers, URL userinfo (`https://user:pass@`), private
  keys, `.env` values. Drop the row if unsure.
- One `questions` list per point, identical across rows (same instructions/options), so
  results are comparable. Keep `instructions` faithful to Hive's current prompt or rule.
- Cap each dataset at 1500 rows; if more exist, stratified-sample by label and project and
  say so in the README.
- `labels.system` is required. Add `outcome` wherever later evidence exists (e.g. retry
  succeeded after cooldown, operator overrode, finding later fixed/ignored, PR later
  reverted). Where `system` comes from regex/heuristics (known to misfire), add an
  `adjudicated` gold subset of 50–100 rows that you label yourself after reading the full
  context, stratified to include suspected misfires.

## Revision 2 — TypeSafe skill guidance (supersedes the single-question form above)

The builders followed TypeSafe's agent skill (`typesafe-ai`, plugin 0.6.2) when writing
states and questions. Its key rules:

### Answers are judgments; code makes the decision
Do not only ask "should Hive do X?". Break the decision into the atomic, observable
judgments it depends on, and map them to the verdict with a truth table in code.

- Each `<point>/` therefore carries two variants:
  - `"variant": "direct"`: the one-question form above, kept as a baseline.
  - `"variant": "decomposed"`: 2–8 atomic questions plus `<point>/rule.py` with
    `decide(answers: dict) -> verdict`. Every combination of answers must have an outcome,
    including a Noul in the unsettled band (0.3–0.7) and the "nothing fits" case.
- Write both variants as rows in the same `dataset.jsonl`. Ids are suffixed `#direct` and
  `#decomposed`.

### State is a JSON object with named fields, not a serialized string
- `state` may be (and preferably is) a JSON object with descriptive keys, for example
  `{"finding": {...}, "plan_excerpt": "...", "diff_hunk": "..."}`. Questions refer to
  fields by path in backticks.
- Use names, not raw ids. Include only relevant fields; an irrelevant or empty field can
  sway answers.
- State facts code already knows rather than leaving the model to infer them.
- Apply the human test: a smart person shown only this state and this question could
  answer quickly. If not, fix the state.

### Question writing
- One judgment per question; split "or"/"and".
- Ask the concrete, observable thing. Phrase it so that true = yes.
- Option and level descriptions go in the criteria, not in the question text.
- Option names are descriptive (`quota_wall`, not `A`).
- Pair a Choice with a companion Noul "does any option fit?" instead of a
  none-of-the-above option.
- Describe a Noul's false case as a concrete situation.

### Types
- Use TypeSafe names: `noul` (yes/no probability), `choice`, `score`. The runner maps
  `noul` to OpenAI `predicate`.
- Each question object:
  ```
  {"name", "type", "instructions", "criteria": {"true": "...", "false": "..."}}   # noul
  {"name", "type", "instructions", "choices": [{"value", "description"}]}        # choice
  {"name", "type", "instructions", "levels": [{"label", "description"}]}         # score
  ```

### Fairness and labels
- Never tune wording on the rows you evaluate. Mark 20% of rows `"split": "dev"` for wording
  iterations and the rest `"split": "test"`.
- No criteria that name specific test items.

## `<point>/README.md` (not published)
Data sources, how each label was derived, counts and label balance, known gaps and
biases, and 2 example rows. The published package summarises these in its top-level
README.md instead.

## `<point>/stats.json` (not published)
`{"rows": N, "label_balance": {...}, "with_outcome": N, "with_adjudicated": N,
"state_chars": {"mean": x, "p95": y, "max": z}}`
