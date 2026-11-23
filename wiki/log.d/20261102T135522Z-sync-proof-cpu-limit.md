# Match Hive's hosted-runner credential proof CPU limit

The canonical proof at `f157ef79` inherited the shared fixture's eight-CPU
request. Override `HB_CPUS` to one for real Docker probes, matching Hive's
`715cbeeeb7` correction. Fake-Docker resource assertions and production
defaults stay unchanged. Searching both test trees found no other real-Docker
credential proof missing this override.

A local Docker shim rejected requests above four CPUs and forwarded other
calls to Docker 29.9.2. Before the correction the canonical decoy probe failed
with exit 125. Afterward `test:bench_isolation_proof` passed 3 tests/40
assertions with zero failures/errors/skips; actual Bash 3.2.57 and 5.3.20 each
passed the nested 15-test/590-assertion matrix. All six real credential probes
passed with the pinned Alpine image. The same constrained gate in Hive passed
3 tests/55 assertions and both nested 15-test/602-assertion matrices.

Full-file `cmp` checks still pass for canonical and packaged `isolation.sh`
and `isolation_exec.rb` (R6). This extends U3/U4's recorded local evidence;
hosted Ubuntu and macOS confirmation and upstream publication remain pending.
