# Add decision-bench: decision models on Hive's own decisions

Added `decision-bench/`, a self-contained benchmark that replays 4,644 past Hive
decisions (11 points, direct and decomposed variants) against OpenAI Decisions
`gpt-6-luna` and TypeSafe Jev `jev-1.14.0`. It ships the sanitized datasets
(`xz`), per-point rules, the runner and probe, every call's result record (minus
the request payload), `SUMMARY.md` with its scorer, and the Claude∩Neon gold
annotations. On 382 gold test cases both models beat the regex/heuristic
incumbents (0.654 → 0.924 / 0.940 direct); direct beats decomposed; OpenAI and Jev
tie on accuracy. Rows describing security findings in the owner's private products
are withheld (324 rows). See [[decision-bench]].
