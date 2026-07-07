# 2026-07-07 — model verification, opus column filling, near-final board

- `harness/verify_models.rb`: every cell's stream-log model ids cross-checked
  against its claim (CLI utility models allowlisted) — 101 substantive stage
  logs, 0 violations. Closes the design review's model-verification question.
- Opus column filling on subscription windows: install fable 6.5 (board's best
  install by far), fix-tmux 8.5, web-install 4.0; 6 cells remain (2 opus,
  4 mixed). Root causes of the two lost days: OAuth refresh-chain races
  (concurrent CLI calls at token expiry -> hard logout) and the OpenRouter KEY
  total-limit cap binding before account balance — both now monitored
  (tmp/claude-monitor.sh pages on LOGGED_OUT; key endpoint checked).
- RESULTS.md updated to near-final (pair exclusions applied, kimi 6/6 complete
  at 3.2, deliberation total: 15 verdicts, gpt revision 0.00);
  `tmp/assemble-final.sh` regenerates the board idempotently as cells land.
