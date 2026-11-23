# Direct v1 credential isolation delivery (U4)

Canonical baseline: 432e730ea7812246496726fcc9153e98be58eb30. Implementation:
dce0f155 (U1), a09fd659 (U2), 7383c88 (U3). Both entire isolation source files
match Hive's packaged snapshot; unrelated baseline divergence remains.

| Acceptance | Evidence |
| --- | --- |
| Entrypoint scope | CREDENTIAL_ISOLATION.md names direct run_all/pipeline_run and unchanged v2 HiveDriver forwarding/auth.json; no v2 source diff |
| Credential policy/refusals | Focused canonical executor/policy/shell run: 43 tests, 682 assertions, all pass; red-before-fix matrix observed ambient forwards/raw diagnostics |
| Actual interpreters | GNU Bash 3.2.57(2) and 5.3.20(1), each 15 policy/shell tests passing; shell syntax checks pass |
| Named gate | test:bench_isolation_proof: 3 tests, 40 assertions, no skips; macos-15 hosted lane configured but unrun locally |
| Real container | Docker 29.9.2; Alpine 3.22.2@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412; six decoy probe variants pass |
| Lint | Owning RuboCop passes changed Ruby/Rakefile; ShellCheck 0.11.0 passes both wrapper copies |
| Canonical broad checkpoint | bundle exec rake test: 266 tests, 1378 assertions, no failures/errors/skips |
| Fresh/install refresh/recovery | Hive bench_workflow_install regression: 4 tests, 59 assertions; old runtime fixture, CLI refresh and isolated state-commit revert preserve unrelated state |
| Slate/preflight | README documents both bare-label refusals, default exit 2, PI_MODELS/README migration and binary/auth/version-only preflight |
| Attachments, separately | Hive test/integration/new_test.rb: 53 tests, 225 assertions, pass; no attachment issue reproduced or repaired |

Runtime SHA256: isolation.sh f4c1f0d9b49ad1baa2cdfe9b921c20f51e3544335ac830138edbdaef7e260587;
isolation_exec.rb 1bbd66693e5ff0f0450807944cbc8ca3dc13a9c8a958d84dfe89734eaa4eede4.
Hive's delivery fragment preserves refresh/revert OIDs and old/new runtime hashes.

Delivery checks also assert literal Docker -e NAME argv (no key values), and
HOME-only environment entries for OAuth/gate runs. Both actual-interpreter
matrices pass with these assertions (15 tests/590 assertions per interpreter).
