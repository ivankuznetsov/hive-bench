# Direct v1 profile credential policy (U1)

IsolationExec now declares the selected API variable or OAuth path, clears
inherited OAuth controls, and refuses unsupported profiles before spawning.
Policy tests cover every Slate Pi route, missing configuration and parent-env
preservation; old executor expectations now require explicit nil removals.
