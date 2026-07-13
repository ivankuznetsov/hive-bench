# Surface Claude judge authentication failures

`ClaudeJudge` now includes bounded stdout when Claude Code exits nonzero with
an empty stderr stream. Claude Code emits expired-session 401 details in its
JSON stdout, so this turns previously blank Fable judge failures into an
actionable authentication diagnostic.

The dependency guide now requires a real `claude -p` smoke probe rather than
trusting `claude auth status`, which can report logged in for an expired token
that has no refresh token.
