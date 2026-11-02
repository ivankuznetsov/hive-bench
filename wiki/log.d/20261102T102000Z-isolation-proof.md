# Benchmark isolation proof gate (U3)

Added a separate `test:bench_isolation_proof` gate and required CI lanes on
ubuntu-24.04 and macos-15. The proof file is outside defaults/coverage. Local
actual GNU Bash 3.2.57(2) and 5.3.20(1) each passed all 15 policy/wrapper tests.
Six decoy-only probes passed on Docker 29.9.2 with stock Alpine 3.22.2 pinned
to sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412.
The Hive gate passed 3 tests/55 assertions; canonical passed 3/40.
Hosted macos-15 execution remains pending; its lane requires /bin/bash 3.2.
