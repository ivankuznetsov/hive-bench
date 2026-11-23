# Claude vs Neon: disagreements for tie-break

Second annotator: Gemini 4 Neon (`opencode/gemini-4-neon#medium`, OpenCode 2.3.2), blind: it saw only each row's `state` and the point's direct question, never `labels`, `meta` or Claude's verdict. Rows: every adjudicated `#direct` row in the sanitized datasets, minus `[PRODUCT]*` projects. 563 rows scored, 499 agree (88.6%), 64 disagree; gold (both agree) = 499 rows in `gold.jsonl`.

Label mappings (adjudicated vocabulary → direct question):

- `patrol_finding_dedup`: direct question is the noul `same_issue`; adjudicated `same` -> true, `different` -> false
- `visual_capture_need`: direct question is the noul `needs_visual_capture`; adjudicated `needs_capture` -> true, `no_capture` -> false
- `recovery_same_root`: noul `same_root`; adjudicated true/false used as is
- `plan_review_level`: direct rows carry `review_level` plus 5 category nouls; only `review_level` (skip/standard/mandatory) was asked. Claude's level was derived by rule.decide from Claude's per-category labels plus code facts, never `skip`
- `ci_failure_triage`: choice `ci_cause`; same vocabulary
- `provider_failure_class`: choice `failure_class`; same vocabulary
- `refactor_merge_classifier`: choice `verdict` (feature/skip); same vocabulary
- `task_workflow_routing`: choice `workflow_profile` (express/standard/full); same vocabulary

| point | n | agree | kappa | disagreements | pending |
|---|---|---|---|---|---|
| ci_failure_triage | 78 | 75.6% | 0.66 | 19 | 0 |
| patrol_finding_dedup | 85 | 97.7% | 0.93 | 2 | 0 |
| plan_review_level | 45 | 86.7% | 0.73 | 6 | 0 |
| provider_failure_class | 82 | 97.6% | 0.97 | 2 | 0 |
| recovery_same_root | 64 | 100.0% | 1.00 | 0 | 0 |
| refactor_merge_classifier | 73 | 87.7% | 0.73 | 9 | 0 |
| task_workflow_routing | 58 | 60.3% | 0.39 | 23 | 0 |
| visual_capture_need | 78 | 96.2% | 0.90 | 3 | 0 |

## ci_failure_triage

19 of 78 disagree; kappa 0.6639. Question `ci_cause`.

### `ci_failure_triage:hive:add-a-daemon-quiescence-command-260923-b4d3:b5b5775b8a92#direct`

- State: PR hive#1483 (fix attempt 1); diff 98 files +7841/-126
  Failed jobs: CI / coverage shard 2/6; CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: ##[error]Process completed with exit code 1.
- Claude: **unknown**: coverage shard failed with no detail
- Neon: **defect_from_diff**: UsageDbTest#test_record_with_broken_path_raises_typed_authoritative_failure failed with Hive::RuntimeControlPlane::Unavailable ('runtime fence directory is unsafe') instead of IntegrityError, directly matching this PR's changes to runtime_control_plane and file_fence.rb.
- Tie-break: 

### `ci_failure_triage:hive:add-repository-aware-answer-suggestions-260826-528d:3af1bcbcbe11#direct`

- State: PR hive#1352 (fix attempt 2); diff 96 files +8091/-49
  Failed jobs: Install smoke / Shell checks; CI / coverage shard 1/6; CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: ##[error]Process completed with exit code 1.
- Claude: **unknown**: shellcheck flags a file outside the diff plus a coverage shard failure without detail
- Neon: **defect_from_diff**: Shellcheck failed with SC2016 on web/test/e2e/support/claude and a unit test failed in test/unit/commands/brainstorm_suggestion_test.rb, both of which are modified or added in the PR diff.
- Tie-break: 

### `ci_failure_triage:hive:add-repository-aware-answer-suggestions-260826-528d:8ee219c16410#direct`

- State: PR hive#1352 (fix attempt 1); diff 95 files +8089/-47
  Failed jobs: Install smoke / Shell checks; CI / coverage shard 1/6; CI / coverage shard 2/6; CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: hive: review GitHub publish skipped; pull-request identity could not be proven (Hive::GhError: identity offline)
- Claude: **unknown**: shellcheck flags a file outside the diff plus shard failures without detail
- Neon: **defect_from_diff**: ShellCheck fails with SC2016 on web/test/e2e/support/claude and coverage shard 1/6 fails HiveCommandsBrainstormSuggestionTest, both directly added or modified in the diff.
- Tie-break: 

### `ci_failure_triage:hive:edit-resume-wedge-a-needs-261029-7b52:ci-blocked.md#direct`

- State: PR hive#None (fix attempt None); diff 80 files +3866/-178
  Failed jobs: CI command output
  First error: rake test (Ruby 3.4) Require coverage, functional e2e, systemd user, and expensive proof gates 2026-11-03T10:44:34.2000044Z ##[error]Process completed with exit code 1.
- Claude: **unknown**: only aggregate gate output captured
- Neon: **environment_or_billing**: The only concrete failure shown in the log is bundler-audit reporting security advisory GHSA-h7wh-q2qr-458c on rails-html-sanitizer in web/Gemfile.lock, which is unchanged by the diff.
- Tie-break: 

### `ci_failure_triage:hive:every-generator-receives-every-ambient-pro-coding-dabd811e:59e27a4d716b#direct`

- State: PR hive#1585 (fix attempt 1); diff 29 files +1645/-67
  Failed jobs: CI / coverage shard 1/6; CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: ##[error]Process completed with exit code 1.
- Claude: **defect_from_diff**: coverage shard failed (detail not in tail); fixer commit turned CI green
- Neon: **flaky_or_infra**: DaemonQuiescenceCoordinatorIntegrationTest failed with reason 'deadline_exhausted', a timing-dependent timeout unrelated to the PR's bench credential isolation diff.
- Tie-break: 

### `ci_failure_triage:hive:extend-idempotency-keys-and-durable-260923-ccce:ci-blocked.md#direct`

- State: PR hive#None (fix attempt None); diff 132 files +19101/-505
  Failed jobs: CI command output
  First error: rake test (Ruby 3.4) Require coverage, functional e2e, systemd user, and expensive proof gates 2026-09-27T17:23:18.2686074Z ##[error]Process completed with exit code 1.
- Claude: **unknown**: only aggregate gate output captured
- Neon: **defect_from_diff**: The required rake test gate failed because coverage (Ruby 3.4) exited 1 during 'Merge shards and enforce exact coverage' after verifying all 6 shards on a PR adding 19,101 lines.
- Tie-break: 

### `ci_failure_triage:hive:let-the-native-hive-cli-260923-01dd:ci-blocked.md#direct`

- State: PR hive#None (fix attempt None); diff None files +None/-None
  Failed jobs: CI command output
  First error: coverage shard 3/6 UNKNOWN STEP 2026-11-07T21:51:12.6730767Z 2) Error:
- Claude: **defect_from_diff**: diff's remote fixtures fail with Bundler::GemNotFound under CI's bundler environment
- Neon: **environment_or_billing**: The coverage shard failed with Bundler::GemNotFound because rails-8.1.4.1 and related gems were missing from the CI runner's locally installed gems.
- Tie-break: 

### `ci_failure_triage:hive:make-hive-act-workflow-retry-260925-8c91:0d96684a6dc2#direct`

- State: PR hive#1625 (fix attempt 1); diff 36 files +1669/-81
  Failed jobs: CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: [Merge shards and enforce exact coverage] ##[error]Process completed with exit code 1.
- Claude: **unknown**: only aggregate gate jobs are red; no child log available
- Neon: **defect_from_diff**: The coverage gate failed at 99.99% due to uncovered lines in four files modified or added by this PR (manual_retry.rb, recovery_coordinator.rb, operational_status.rb, and dispatcher.rb).
- Tie-break: 

### `ci_failure_triage:hive:make-wiki-commands-md-authoritative-for-co-coding-5d38a704:029b7cea418c#direct`

- State: PR hive#1391 (fix attempt 2); diff 51 files +1951/-267
  Failed jobs: CI / coverage shard 3/6; CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: ##[error]Process completed with exit code 1.
- Claude: **defect_from_diff**: coverage shard failed (detail not in tail); same task fixed by code
- Neon: **flaky_or_infra**: The single failure is in OpenCodeAgentLifecycleTest#test_long_session_export_larger_than_the_old_four_megabyte_cap_completes, which is completely unrelated to the PR diff that only modifies wiki/docs files and wiki/command index tests.
- Tie-break: 

### `ci_failure_triage:hive:patrol-hive-e2e-run-scenarios-swallows-une-coding-6ea02fac:01298094c6d1#direct`

- State: PR hive#1589 (fix attempt 2); diff 12 files +622/-111
  Failed jobs: CI / Hive web integration tests; CI / Hive web (Rails tests + system)
  First error: [Rails integration tests] hive: pairing store at /tmp/hive-web-test20261103-2412-jzdy9b/hive-home/.bot.pairings.json is unreadable (JSON::ParserError: expected object key, got 'not' at line 1 column …
- Claude: **flaky_or_infra**: single web integration 404 failure matches the known tasks_test 404 flake; diff is unrelated e2e/docs
- Neon: **unknown**: Hive web integration tests failed with a 404 Not Found where 2XX was expected, but the log omits the failing test name, route, and stack trace, leaving too little detail to tell whether the web/Gemfile.lock change or flakiness caused it.
- Tie-break: 

### `ci_failure_triage:hive:patrol-idea-preview-drops-wide-character-b-coding-e7f00c36:f12afc9dae96#direct`

- State: PR hive#1593 (fix attempt 1); diff 5 files +270/-12
  Failed jobs: CI / bundler-audit; CI / coverage shard 6/6; CI / coverage shard 2/6; CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: No vulnerabilities found
- Claude: **unknown**: bundler-audit advisory (environment) plus unexplained coverage shard failures
- Neon: **defect_from_diff**: Coverage shards 2/6 and 6/6 fail deterministic assertions in test/unit/tui/views/idea_preview_test.rb and test/unit/tui/bubble_model_test.rb, both directly modified by this PR.
- Tie-break: 

### `ci_failure_triage:hive:patrol-terminate-process-escalates-to-sigk-coding-c041e9bd:d3b0af730c41#direct`

- State: PR hive#1390 (fix attempt 1); diff 10 files +871/-64
  Failed jobs: CI / coverage shard 1/6; CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: Finished in 19.231567s, 6.7597 runs/s, 65.6213 assertions/s.
- Claude: **defect_from_diff**: coverage shard failed (detail not in tail); fixer commit turned CI green
- Neon: **flaky_or_infra**: A single unrelated test (AttemptsSupervisorTest#test_patrol_diagnostic_pipe_binds_one_artifact_and_exact_log_to_terminal_receipt) failed with Expected 7 vs Actual 70 while the diff only changes process_kill and commands/drop.
- Tie-break: 

### `ci_failure_triage:hive:support-multiple-dependencies-per-task-260928-b4f8:4be60447be73#direct`

- State: PR hive#1509 (fix attempt 1); diff 86 files +3534/-432
  Failed jobs: CI / coverage shard 2/6; CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: ##[error]Process completed with exit code 1.
- Claude: **unknown**: coverage shard failed with no detail in the log
- Neon: **flaky_or_infra**: ChangedTestRunnerTest failed with Errno::ENOENT on .git/objects/maintenance.lock during Dir.mktmpdir cleanup, a transient git maintenance race unrelated to the PR's task-dependency changes.
- Tie-break: 

### `ci_failure_triage:hive:track-skill-and-workflow-proposal-260829-f948:bcdcee9ccb42#direct`

- State: PR hive#1419 (fix attempt 1); diff 2107 files +206629/-41119
  Failed jobs: CI / coverage (Ruby 3.4); CI / rake test (Ruby 3.4)
  First error: [Merge shards and enforce exact coverage] ##[error]Process completed with exit code 1.
- Claude: **unknown**: only aggregate gate jobs are red
- Neon: **defect_from_diff**: The exact coverage gate failed at 117627/117631 lines because of uncovered lines in lib/hive/commands/proposal.rb (added in the diff) and lib/hive/attempts/command_progress.rb.
- Tie-break: 

### `ci_failure_triage:hivedev:c6-implement-cached-observations-that-260923-0061:ci-error-01.md#direct`

- State: PR hivedev#None (fix attempt None); diff 130 files +9219/-109
  Failed jobs: CI command output
  First error: (See full trace by running task with --trace)
- Claude: **unknown**: compat task failed; the error itself is not in the captured output
- Neon: **flaky_or_infra**: The local CI compatibility test run was aborted mid-execution by an external SignalException: SIGTERM rather than completing with a reported test failure.
- Tie-break: 

### `ci_failure_triage:hivedev:f2-build-the-pinned-workspace-260923-d691:ci-blocked.md#direct`

- State: PR hivedev#None (fix attempt None); diff 133 files +12473/-83
  Failed jobs: CI command output
  First error: Finished in 60.068836s, 5.4438 runs/s, 37.5569 assertions/s.
- Claude: **unknown**: workspace smoke hits a read-only Hive state mount; the cause is outside this diff but not clearly environment
- Neon: **defect_from_diff**: Two workspace smoke checks in test/smoke/workspace_smoke.rb failed, including read-only inventory exiting 69 on a read-only Hive state mount, in workspace boot and inventory code added by this diff.
- Tie-break: 

### `ci_failure_triage:hivedev:f3-write-the-persistent-root-260923-2b70:ci-blocked.md#direct`

- State: PR hivedev#None (fix attempt None); diff 80 files +10458/-212
  Failed jobs: CI command output
  First error: 289 runs, 2719 assertions, 1 failures, 0 errors, 0 skips
- Claude: **unknown**: workspace test and smoke failed; the real error is masked by an error_highlight crash
- Neon: **defect_from_diff**: Both bundle exec rake workspace:test (1 test failure) and workspace_smoke failed in workspace test suites and code heavily modified by the PR diff.
- Tie-break: 

### `ci_failure_triage:topgreendeals.co.uk:fix-and-comprehensively-verify-the-260814-91b0:1b5f0934640d#direct`

- State: PR topgreendeals.co.uk#402 (fix attempt 1); diff 193 files +3596/-276
  Failed jobs: CI / test_rails
  First error: Failure:
- Claude: **unknown**: 37 browser/visual test failures with no detail in the tail
- Neon: **defect_from_diff**: The test_rails job failed with 37 deterministic test assertion failures in a PR that modifies 193 files across views, controllers, and test suites.
- Tie-break: 

### `ci_failure_triage:topgreendeals.co.uk:fix-and-comprehensively-verify-the-260814-91b0:98e3c641d9d7#direct`

- State: PR topgreendeals.co.uk#402 (fix attempt 2); diff 196 files +3651/-279
  Failed jobs: CI / test_rails
  First error: unknown OID 2278: failed to recognize type of 'pg_advisory_xact_lock'. It will be treated as String.
- Claude: **defect_from_diff**: one deterministic accessibility test failure; fixer commit turned CI green
- Neon: **unknown**: The test_rails log shows 1 failure and a bare 'Failure:' line without the failing test name, assertion, or traceback, so there is not enough evidence to determine the cause.
- Tie-break: 


## patrol_finding_dedup

2 of 85 disagree; kappa 0.9296. Question `same_issue`.

### `patrol_finding_dedup:topgreendeals.co.uk:ordinary:command-bin-brakeman-10~command-bin-kamal-7#direct`

- State: New: [documentation] Hardcoded values drift from actual config: dev port 3003 vs documented 3000, and a hardcoded production IP (bin/dev, bin/migrate-database)
  Known: [maintainability] Hardcoded production IP and DB credentials duplicated from deploy config (bin/migrate-database, config/deploy.yml)
- Claude: **false** (`different`): Only the hardcoded IP overlaps; new adds port-doc drift, known adds duplicated DB names.
- Neon: **true**: Both report the same hardcoded production IP drift at `bin/migrate-database:54` (`topgreendeals_production@[PUBLIC_IP_1]`) diverging from `config/deploy.yml`, even though each bundles an additional nearby hardcoded-value issue.
- Tie-break: 

### `patrol_finding_dedup:topgreendeals.co.uk:ordinary:command-bin-thrust-6~command-bin-rails-7#direct`

- State: New: [bug] Production backup and verification counts capture Kamal wrapper output (bin/migrate-database)
  Known: [bug] Verification counts are polluted by kamal output and unstripped newlines (bin/migrate-database)
- Claude: **false** (`different`): Partial overlap: new adds a polluted production backup file that the known count fix would not resolve.
- Neon: **true**: Both findings report the same defect in bin/migrate-database where `kamal accessory exec` stdout interleaves Kamal/SSHKit log lines into COMPANY_COUNT/REVIEW_COUNT at lines 130-131 (with new_finding also citing the same stdout pollution at line 95).
- Tie-break: 


## plan_review_level

6 of 45 disagree; kappa 0.7343. Question `review_level`.

### `plan_review_level:hive:add-a-digest-cli-mode-260702-2eed:fa4f79d516b33b88#direct`

- State: Plan: Plan — add-a-digest-cli-mode (merged-PR digest source)
  21 declared files in 11 production areas; protected paths touched: none
- Claude: **standard**: additive digest source; 'drop' means skip a repo (Claude's categories true: none)
- Neon: **mandatory**: The plan genuinely changes an existing public interface (adding --source and --repo modes to hive digest in lib/hive/cli.rb) and adds a new versioned JSON schema (schemas/hive-merged-pr-digest.v1.json registered in SCHEMA_VERSIONS).
- Tie-break: 

### `plan_review_level:hive:add-a-refactor-patrol-architecture-260702-9048:456422760022017c#direct`

- State: Plan: Plan: `hive refactor-patrol` (v1 — discovery/reporting)
  27 declared files in 9 production areas; protected paths touched: none
- Claude: **standard**: reporting-only command; secret-scanning named as existing machinery (Claude's categories true: none)
- Neon: **mandatory**: The plan defines two new versioned JSON schemas (`schemas/hive-refactor-patrol-thesis.v1.json` and `schemas/hive-refactor-patrol.v1.json`) and introduces a new durable `.hive-state/refactor_patrol/` JSON state store in `state_store.rb`.
- Tie-break: 

### `plan_review_level:hive:detect-the-runtime-sqlite-database-261029-6b16:7adf022bad56907a#direct`

- State: Plan: Runtime SQLite NOCOW prevention and diagnosis
  23 declared files in 2 production areas; protected paths touched: none
- Claude: **standard**: read-only storage diagnostics and directory preparation (Claude's categories true: none)
- Neon: **mandatory**: The plan modifies runtime SQLite storage initialization in `Database#migrate!` and `Installation.setup` to apply `chattr +C` attributes and inserts pre-`ActivationLock` hooks in `Installation.setup` and `Daemon#start_daemon` with concurrent first-start handling, directly affecting stored data initialization and locking/concurrency.
- Tie-break: 

### `plan_review_level:hive:implement-post-merge-architecture-patrol-260706-2c14:bd93a3ea02e39e52#direct`

- State: Plan: "feat: Add scheduled post-merge architecture patrol"
  33 declared files in 3 production areas; protected paths touched: none
- Claude: **standard**: scheduled reporting patrol; 'ownership' is tail ownership (Claude's categories true: none)
- Neon: **mandatory**: The plan introduces new durable filesystem state and a JSON report schema (schemas/hive-refactor-patrol-post-merge.v1.json), adds nonblocking locking, crash recovery, and daemon work-ownership transitions, and changes the public --path CLI option.
- Tie-break: 

### `plan_review_level:hive:make-default-hive-digest-and-260715-de18:5395e061e237c0b7#direct`

- State: Plan: Default Merged-PR Digest and Line Stats - Plan
  42 declared files in 7 production areas; protected paths touched: none
- Claude: **standard**: default digest source changes but no contract or schema change (Claude's categories true: none)
- Neon: **mandatory**: The plan genuinely changes an existing public interface by switching the default hive digest source and JSON envelope from shipped to merged-prs, adding the digest.source config key, changing merged-PR footer output, and failing closed on zero auto-discovered repositories.
- Tie-break: 

### `plan_review_level:honeycomb:seed-the-catalog-package-hive-260709-f23c:0689319247fce4ec#direct`

- State: Plan: Seed the Catalog with Bench and Docs Sync - Plan
  20 declared files in 7 production areas; protected paths touched: none
- Claude: **mandatory**: package permissions; signed immutable package publication (Claude's categories true: auth_secrets_permissions, deployment_release_supply_chain)
- Neon: **standard**: The plan only adds seed honeycomb content, generated manifests/catalog outputs, README entries, and tests without changing schemas, security tooling, or other sensitive areas, but it declares 20 files across multiple production areas and omits a rollback step.
- Tie-break: 


## provider_failure_class

2 of 82 disagree; kappa 0.9663. Question `failure_class`.

### `provider_failure_class:hive:patrol-streamlog-append-after-a-torn-tail-cae9b7acb4:patrol-fix-fix:2026-08-26T05:43:51Z#direct`

- State: pi patrol-fix-fix: exit None, timed_out False, 1800s
  Tail: {"type":"message_update","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"assistantMessageEvent":{"typ…
  Tail: {"type":"message_update","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"assistantMessageEvent":{"typ…
- Claude: **network_transient**: provider stream ended without finish_reason; output stalled at zero tokens
- Neon: **other_or_healthy**: The log cuts off mid-stream at 1800s with no CLI crash or provider error, and Hive's wrapper raised before capturing an exit code.
- Tie-break: 

### `provider_failure_class:hive:patrol-terminate-process-escalates-to-sigkill-witho-7ffd11994c:patrol-fix-fix:2026-08-27T22:41:45Z#direct`

- State: pi patrol-fix-fix: exit 0, timed_out False, 1050s
  Tail: [structured message omitted type=agent_end]
  Tail: {"type":"agent_settled"}
- Claude: **other_or_healthy**: mid-run 'finish_reason: error' recovered; run finished normally
- Neon: **network_transient**: The assistant stream aborted mid-thought with stopReason 'error' and errorMessage 'Provider finish_reason: error', indicating an upstream provider failure.
- Tie-break: 


## recovery_same_root

0 of 64 disagree; kappa 1.0. Question `same_root`.

No disagreements.

## refactor_merge_classifier

9 of 73 disagree; kappa 0.7264. Question `verdict`.

### `refactor_merge_classifier:hive:pr-1167:f502d747bffc#direct`

- State: PR hive: fix(ci): make CI faster to diagnose without weaker gates (33 files, human contributor)
  Body: ## Summary - Makes CI faster to diagnose without skipping or weakening any required proof. The six-way coverage lane still enforces exact 100% line coverage, and every existing functional gate still …
- Claude: **skip**: CI diagnostics tooling (maintenance).
- Neon: **feature**: This PR introduces significant new CI and testing engineering capabilities across 33 files, including bin/test, failure-evidence and coverage artifacts, and a new nightly flake-sweep workflow and reporting scripts.
- Tie-break: 

### `refactor_merge_classifier:hive:pr-1170:0465980a69b7#direct`

- State: PR hive: fix(opencode): make prepared startup reliable (61 files, human contributor)
  Body: ## What changed - accept OpenCode exact configured prepared-plugin identity when it byte-matches Hive pinned Compound Engineering package - keep arbitrary configured identities and filesystem shadows…
- Claude: **skip**: Bundle of OpenCode startup reliability fixes; new tolerances serve existing flows (borderline).
- Neon: **feature**: Despite its `fix(opencode)` title, this 61-file PR meaningfully extends OpenCode runtime, plan-review, and recovery capabilities across `agent-cli-runtime`, `plan_review`, `stages`, and `daemon` with custom model routing, upstream 504 timeout classification, completion attestation, and plan-review support.
- Tie-break: 

### `refactor_merge_classifier:hive:pr-1172:0f51623f1920#direct`

- State: PR hive: fix(opencode): reap escaped processes and finish authoring safely (32 files, human contributor)
  Body: OpenCode can launch a server through `setsid`, then exit while the reparented server keeps running. This gives each invocation a random inherited custody token and reaps matching PID/start-time ident…
- Claude: **skip**: Process-reaping and authoring reliability fix; adds custody token mechanism but primarily a fix (borderline).
- Neon: **feature**: The PR introduces substantial new engineering capabilities including inherited-token process custody reaping, sibling user-systemd scope isolation for detached attempts, and safe PR-authoring handoff.
- Tie-break: 

### `refactor_merge_classifier:hive:pr-1174:b7a99fe83ba6#direct`

- State: PR hive: fix(status): bound attempt store work per scan (27 files, human contributor)
  Body: ## Summary Full and bounded daemon status scans now open one Attempts store and one immutable binding reader per snapshot, then share them through task projection and closure validation. Repeated bin…
- Claude: **skip**: Performance refactor of status scans.
- Neon: **feature**: This PR introduces a substantial engineering change across 27 files, adding snapshot-scoped Attempts store and immutable binding reader sharing, removing runtime migration hooks, and updating config/component-boundaries.yml.
- Tie-break: 

### `refactor_merge_classifier:hive:pr-1273:41e87a413d74#direct`

- State: PR hive: fix(patrol): isolate controller checkout validation (27 files, human contributor)
  Body: ## Summary - Patrol Fix validation now runs in a pristine detached checkout of the receipt-bound commit, so formatter and test writes cannot change the authoritative patch checkout. - Controller work…
- Claude: **skip**: Validation isolation hardening in a containment program; no new user capability (borderline).
- Neon: **feature**: It delivers U4 of the Patrol failure-containment program across 27 files, introducing pristine detached-checkout validation, consistent controller-workflow rebase skipping, and `schemas/hive-run.v2.json` updates.
- Tie-break: 

### `refactor_merge_classifier:hive:pr-1442:5f70fd6e8542#direct`

- State: PR hive: fix(web): group workflows and modules under Honeycombs (14 files, human contributor)
  Body: ## Summary Hive web now groups Workflows and Modules under one Honeycombs section, with a short introduction explaining that both can be installed. Switching between them preserves the selected proje…
- Claude: **skip**: Regroups existing Web pages under one section; navigation reorganization, not new capability (borderline).
- Neon: **feature**: This PR extends the Hive web product UI by introducing a new Honeycombs section grouping Workflows and Modules across routes, views, helpers, stylesheets, and wiki/architecture.md.
- Tie-break: 

### `refactor_merge_classifier:hive:pr-1546:e85ba37a50d3#direct`

- State: PR hive: fix(agent): stop tasks on a provider-refused model instead of retrying it as a limit (37 files, human contributor)
  Body: ## Summary #1473 classified Codex's "The '<model>' model is not supported when using Codex with a ChatGPT account" as a plan limit. That's a configuration problem, but it rode the hourly limit cooldo…
- Claude: **skip**: Error classification fix moving a model refusal from limits to operator stop.
- Neon: **feature**: Despite its fix prefix, this PR introduces ADR-057, a new Hive::ModelUnsupported subsystem, and a cross-cutting operator-owned stop outcome wired across 14 lib/ files spanning agent, stages, daemon, babysitter, and status reporting.
- Tie-break: 

### `refactor_merge_classifier:hive:pr-1567:b8b2918db0de#direct`

- State: PR hive: fix(plan-review): let operators answer gated findings with a chosen alternative (8 files, human contributor)
  Body: ## Problem Decision triage requires every `gated_auto` finding to list at least two operator alternatives. But `approve-finding`, which applies the reviewer's recommendation, was the only action that…
- Claude: **feature**: Lets operators answer gated findings with a chosen alternative: small capability extension (borderline).
- Neon: **skip**: The PR fixes a workflow bug so operators can use answer-finding to select an alternative on open gated_auto plan-review findings.
- Tie-break: 

### `refactor_merge_classifier:writero:pr-108:191ab36772ac#direct`

- State: PR writero: fix(export): Unicode PDFs, working image links in Markdown, clean standalone HTML (17 files, human contributor)
  Body: ## Summary Three export bugs: 1. **PDF dropped Unicode.** Prawn used DM Sans, which has no Cyrillic or arrows, and a hardcoded filter stripped some symbols on purpose. PDFs now embed Noto Sans (regul…
- Claude: **skip**: Export bug fixes; font embedding serves the fix (borderline).
- Neon: **feature**: Despite the fix prefix, the PR meaningfully extends the export feature by vendoring Noto fonts for Unicode and rich PDF rendering, adding HTML video export and responsive standalone styling, and switching Markdown/HTML media to external signed blob URLs across export, API, MCP, and ArticleDiffService.
- Tie-break: 


## task_workflow_routing

23 of 58 disagree; kappa 0.3855. Question `workflow_profile`.

### `task_workflow_routing:agent-plugins:migrate-every-agent-plugin-to-260709-3082#direct`

- State: Project agent-plugins; idea: Migrate every agent plugin to portable skills across Claude Code, Codex, Pi, and OpenClaw. First, update the Screenote plugin's screenote, snapshot, and feedback skills to stop using the Screenote MCP server and instead invoke the merged OAuth-first Screenote CLI from screenote PR #37. Use the machine-readable JSON command cont…
- Claude: **standard**: Well-specified 13k-line multi-host packaging; shipped with no reviewers and no follow-ups; brainstorm choices were defaultable, size rules out express.
- Neon: **full**: It is a large, repo-wide migration of every marketplace plugin across four agent platforms that removes MCP wiring, handles OAuth token security, and introduces canonical multi-agent packaging and CI validation.
- Tie-break: 

### `task_workflow_routing:hive-site:build-hive-sh-honeycombs-in-260717-025e#direct`

- State: Project hive-site; idea: Build hive.sh/honeycombs in this hive-site repository as a fully static Jekyll catalog page. Consume a checked-in _data/honeycombs.json copy of the canonical honeycomb catalog v2 through a documented, validated, atomic maintainer sync command; never fetch at build time or runtime. Follow the existing /bench page pattern. Render…
- Claude: **express**: Static Jekyll page plus sync script; brainstorm questions went unanswered; one pass caught all Highs.
- Neon: **standard**: It builds a static Jekyll catalog page and maintainer sync command following the existing /bench pattern with fully specified fields and constraints, larger than an express edit but straightforward enough for standard review.
- Tie-break: 

### `task_workflow_routing:hive:add-fail-closed-dependency-and-260716-ee95#direct`

- State: Project hive; idea: Add fail-closed dependency and repository admission validation. Context: Honeycomb dependencies existed only in plan prose, so tasks launched concurrently. Task 1854 was created under Honeycomb although its implementation belonged in hive-site. Hive currently stores one scalar depends_on and some malformed or unresolved depende…
- Claude: **full**: Two brainstorm rounds of owner scope decisions on fail-closed scheduler gating; no plan or code review ran.
- Neon: **standard**: Adding fail-closed dependency and repository admission checks before daemon dispatch while explicitly keeping the existing depends_on model is a focused feature whose decisions follow from the idea and codebase.
- Tie-break: 

### `task_workflow_routing:hive:add-first-class-opencode-support-260812-bc06#direct`

- State: Project hive; idea: Add first-class OpenCode support to components/agent-cli-runtime, Hive's unified Ruby agent CLI library. Implement an OpenCode agent profile with executable discovery, minimum-version and capability probing, authentication/readiness checks, argv and stdin compilation, headless invocation, backend/model routing using OpenCode's …
- Claude: **standard**: Well-specified; one pass with two reviewers caught 12 security Highs (permissions, env leakage); nothing needed the owner.
- Neon: **full**: Adding first-class OpenCode support to agent-cli-runtime is a major new provider subsystem involving auth, permissions, isolated config, provider-neutral contracts, and release packaging.
- Tie-break: 

### `task_workflow_routing:hive:bundle-provision-agent-skills-at-260709-79d9#direct`

- State: Project hive; idea: Bundle/provision agent skills at install so default settings work out of the box (claude/codex/pi). Today hive installs the pipeline but NOT the skills its default config references (ce-brainstorm, /plan, ce-code-review, pr-review-toolkit) — a fresh install fails doctor and silently improvises reviews. Evidence 2026-07-09: even…
- Claude: **standard**: Detailed spec; 6k lines that rewrite user agent configs; shipped without reviewers and no follow-ups, but too risky for express.
- Neon: **full**: Provisioning third-party agent plugins across Claude, Codex, and Pi touches `install.sh`, `hive init`, `hive doctor`, and external user config files like `~/.codex/config.toml` while managing an explicit code-execution consent boundary.
- Tie-break: 

### `task_workflow_routing:hive:create-and-ship-a-first-260719-7fa2#direct`

- State: Project hive; idea: Create and ship a first-class natural-language Hive workflow creator AgentSkill, integrated with the repository's existing OpenClaw skill packaging and custom-workflow CLI. A user must be able to tell an agent in ordinary language, for example “Create a three-stage editorial workflow that researches, drafts, and requires approv…
- Claude: **full**: The owner overrode the literal idea (approval as its own stage); pass 2 still raised 11 security Highs (symlinks, read-only routes that mutate).
- Neon: **standard**: It is a thoroughly specified AgentSkill, packaging, documentation, and test-fixture addition built on existing hive workflow CLI commands whose remaining choices follow from the repository.
- Tie-break: 

### `task_workflow_routing:hive:fix-claude-tmux-ready-detector-260629-50cc#direct`

- State: Project hive; idea: Fix Claude tmux ready detector and package wrapper
- Claude: **express**: 226-line incident fix; brainstorm answers were the obvious defaults (version-tolerant detector, exclude daemon drift); reviews found no Highs.
- Neon: **standard**: This brief, underspecified bug fix for the Claude tmux ready detector and package wrapper requires codebase-grounded decisions and standard review rather than skipping brainstorm with cheaper models.
- Tie-break: 

### `task_workflow_routing:hive:improve-the-canonical-hive-openclaw-260725-7ad6#direct`

- State: Project hive; idea: Improve the canonical Hive OpenClaw skill so answering brainstorm questions is always an interactive one-question-at-a-time workflow. Trigger this behavior whenever the user asks for Hive questions, asks what is waiting for brainstorm input, asks to answer questions, or wants help completing a Hive brainstorm. Do not dump every…
- Claude: **full**: The owner's brainstorm answer replaced the requested contract with two modes (Guided/YOLO); answer-binding security Highs persisted into pass 2.
- Neon: **standard**: Although it is a skill update with projection sync and tests, its detailed persistence, idempotency, and fail-closed state-handling semantics warrant standard planning and dual code review.
- Tie-break: 

### `task_workflow_routing:hive:make-default-hive-digest-and-260715-de18#direct`

- State: Project hive; idea: Make default `hive digest` and daemon auto-digest use the same source. ## Problem PR #647 added an opt-in CLI source (`hive digest --source merged-prs` / `--repo`), but deliberately left: - CLI default = shipped Hive tasks that hit `9-done` that day - daemon auto-digest = `hive digest --date <day> --json` with no `--source` So …
- Claude: **full**: The owner made product choices (config key, stats footer); PR #752 was closed as stale with swallowed errors and redone twice.
- Neon: **standard**: It unifies the default source across the CLI digest command and daemon DigestScheduler with clear preferred behavior and acceptance criteria that follow from the existing digest implementation.
- Tie-break: 

### `task_workflow_routing:hive:make-pr-opening-and-review-260716-6636#direct`

- State: Project hive; idea: Make implementation ownership automatic across execution, PR opening, and review fixes. By default, open_pr and review.fix use the resolved execution agent/provider in fresh sessions; users should not need an inherit_execute setting or duplicate stage configuration. Review fixes use the execution model because they modify code.…
- Claude: **standard**: Detailed idea; second-round answers clarified persistence; shipped without reviewers, and the later task only built on it.
- Neon: **full**: It changes core stage routing and persists task-generation execution identity in stored state while requiring safe compatibility for legacy in-flight tasks, warranting adversarial review and full verification.
- Tie-break: 

### `task_workflow_routing:hive:patrol-streamlog-append-after-a-torn-tail-coding-3fc93742#direct`

- State: Project hive; idea: # Patrol Fix escalation: patrol-streamlog-append-after-a-torn-tail-cae9b7acb4 This standard coding task is the controller-linked successor of Patrol Fix task `hive:patrol-streamlog-append-after-a-torn-tail-cae9b7acb4`. Investigate the broader product or repository decision before implementation. The wrapped material is untruste…
- Claude: **full**: Durability fix with boilerplate brainstorm answers; the adversarial plan lens caught real sequence-republish and lock-wedge design flaws.
- Neon: **standard**: It is a contained, already-diagnosed StreamLog fail-closed sealing fix with a transient-error regression test and wiki update that needs stronger review than express after a prior silent-drop defect, but does not require owner brainstorm rounds.
- Tie-break: 

### `task_workflow_routing:hive:per-stage-claude-model-config-260709-35f7#direct`

- State: Project hive; idea: Per-stage claude model config: allow plan/execute/review stages to pin different claude models (e.g. plan on claude-fable-5, execute on claude-opus-4-8). Today claude.model is global (Config.claude_cli_flags reads cfg.dig claude,model only), so mixed-claude-model pipelines need a config flip between hive invocations — hit for r…
- Claude: **full**: Owner answers widened a claude-only knob into an all-provider, all-stage model map; PR #706 was closed and rebuilt.
- Neon: **standard**: It is a contained feature adding stage-level Claude model overrides to Config.claude_cli_flags where the minor config-key choice follows from existing codebase conventions.
- Tie-break: 

### `task_workflow_routing:hivedev:c6-implement-cached-observations-that-260923-0061#direct`

- State: Project hivedev; idea: [C6] Implement cached observations that are browsable without waking compute. The spec is final: docs/architecture/hive-cloud.md (sections: Workspace lifecycle and wake-up (cached observations)) is the source of truth. Write brainstorm.md directly from this task and that document, and ask no questions unless something is genuin…
- Claude: **standard**: A final architecture spec with agent-written brainstorm; the whole-document plan review caught a token-scope issue; one owner approval; one real pass-2 High.
- Neon: **full**: Implementing C6 cached observations, durable operations, allowance checks, compute wake-up, and task-state revalidation is a complex new subsystem with stored-data and correctness invariants.
- Tie-break: 

### `task_workflow_routing:hivedev:f2-follow-up-hardening-deferred-261102-7d36#direct`

- State: Project hivedev; idea: F2 follow-up hardening (deferred from f2-follow-up-fix-the-261030-6527 review pass 6, operator-approved 2026-11-02). Fix these four review findings without widening scope: (1) Restrict the host Git parser to a trusted executable: filesystem-only inventory (lib/hivedev/workspace/inventory.rb:610-639) selects any `git` on inherit…
- Claude: **standard**: Four precisely specified hardening fixes; the owner accepted defaults; later passes chased ever-narrower traversal edge cases.
- Neon: **full**: All four findings are security-critical hardening fixes in multi-tenant hivedev—blocking untrusted PATH git execution, fixing secret redaction bypasses, reporting incomplete traversal, and using effective UID—where adversarial and full review are needed to catch subtle bypasses.
- Tie-break: 

### `task_workflow_routing:honeycomb:registry-layout-package-manifest-schema-260709-1f1a#direct`

- State: Project honeycomb; idea: Registry layout + package manifest schema. Define the honeycomb package format and repo structure: packages/<name>/ containing workflow.yml (hive DescriptorParser-valid), instructions/ (the stage instruction files), README.md, and manifest.yml (name, version semver, author, license, hive min version, permissions summary auto-de…
- Claude: **standard**: New package-format and integrity contract (4.7k lines) that later tasks build on; shipped without reviewers, but too foundational for express.
- Neon: **full**: Defining the honeycomb package layout, `manifest.yml` and `catalog.json` public contract, derived permissions summary, and SHA-256 integrity validator establishes foundational schema and security guarantees for a security-reviewed registry.
- Tie-break: 

### `task_workflow_routing:honeycomb:seed-the-catalog-package-hive-260709-f23c#direct`

- State: Project honeycomb; idea: Seed the catalog: package hive-bench's bench workflow as the first community entry (source: hive-bench PR #1 workflows/bench.yml + workflows/bench/), and a minimal example workflow (docs-sync or similar two-stage demo) as the tutorial entry. Both must pass the package validator and demonstrate the manifest/sha flow end to end. …
- Claude: **express**: Packaging two catalog entries (1.4k lines, mostly vendored files); the owner's only correction was a tier label.
- Neon: **standard**: Packaging an existing workflow plus a minimal demo to pass the existing validator and documenting them in the README is an ordinary feature whose choices follow from the codebase.
- Tie-break: 

### `task_workflow_routing:openclaw-shopping:local-shopping-store-cli-and-261105-856c#direct`

- State: Project openclaw-shopping; idea: Local shopping store, CLI and OpenClaw skill skeleton Product: a local-first shopping companion skill for OpenClaw (see docs/product-brief.md part A). It must work fully without Todero and never depends on Hive. Build the foundation: - An OpenClaw skill (SKILL.md with OpenClaw metadata, references) that drives a small local str…
- Claude: **standard**: The idea delegated the runtime choice; mandatory plan review raised no gates; pass 2 caught a real concurrent-edit data-loss bug.
- Neon: **full**: Creating the foundational local SQLite store, entity schema, CLI contract, and language/runtime choice establishes a new subsystem and stored-data foundation for all subsequent tasks.
- Tie-break: 

### `task_workflow_routing:screenote:replace-screenote-cli-api-key-260708-545b#direct`

- State: Project screenote; idea: Replace Screenote CLI API-key authentication with OAuth-first authentication. The current Go CLI PR was planned around project API keys, but the product decision is that the CLI must use OAuth instead. Remove --api-key, SCREENOTE_API_KEY, and api_key config as the primary CLI auth contract. Add deterministic OAuth credential/to…
- Claude: **express**: The product decision (OAuth) was already in the idea; brainstorm answers were defaults; both review passes found no Highs; no follow-ups.
- Neon: **full**: Replacing CLI API-key auth with OAuth across the Go CLI and Rails backend is a security and public-contract change with interactive-login product decisions.
- Tie-break: 

### `task_workflow_routing:topgreendeals.co.uk:add-a-public-top-green-260724-cdea#direct`

- State: Project topgreendeals.co.uk; idea: Add a public Top Green Energy Digest section to TopGreenDeals and expose an approval-gated publishing flow through the existing OpenClaw admin API. The public experience should include an SEO-friendly digest index and individual article pages with stable slugs, publication dates, concise article content, source attribution, can…
- Claude: **standard**: Approval-gated publishing API; pass 2 caught 4 real Highs (replay authorization, redaction); nothing needed the owner.
- Neon: **full**: Adding a draft-and-publish digest model and a security-sensitive two-step approval-gated admin publishing API involves stored-data, authorization, and public-contract changes.
- Tie-break: 

### `task_workflow_routing:topgreendeals.co.uk:add-the-completed-zero-bills-260801-ec79#direct`

- State: Project topgreendeals.co.uk; idea: Add the completed Zero-Bills & Net-Zero New-Build Homes UK article package to the TopGreenDeals website. Source package from completed Hive task 42405: - Final article: /home/user/Dev/topgreendeals/.hive-state/stages/6-done/continue-nationwide-research-and-source-260730-c0fa/article.md - Research/source ledger: /home/user…
- Claude: **express**: Publishing a finished article package; the three brainstorm rounds only confirmed defaults; the pass-2 High was stale visual baselines.
- Neon: **standard**: Integrating an already completed article package into the existing Rails content model, structured data, internal links, and tests is ordinary work whose details follow from the codebase.
- Tie-break: 

### `task_workflow_routing:topgreendeals.co.uk:fix-and-comprehensively-audit-incorrect-260720-f202#direct`

- State: Project topgreendeals.co.uk; idea: Fix and comprehensively audit incorrect postcode district geography on the public /areas page. User evidence: production displays W1H as Islington, while the authoritative outcode is Westminster; adjacent W1A W1G W1J W1S and W1W also look wrong. Root cause to verify: PostcodeDistrict is created once in lib/tasks/discovery.rake …
- Claude: **standard**: Production data backfill with brainstorm questions left unanswered; one two-reviewer pass raised 16 Highs (authorization, sealing); no owner input.
- Neon: **full**: Implementing an authoritative postcode-district resolver and an idempotent backfill with ambiguity handling, checkpointing, rollback, and a production runbook is high-risk stored-data migration work.
- Tie-break: 

### `task_workflow_routing:topgreendeals.co.uk:improve-seo-and-geographic-coverage-260926-9a64#direct`

- State: Project topgreendeals.co.uk; idea: Improve SEO and geographic coverage for all existing UK solar installer location pages other than Essex and Kent/Medway, which have separate work. Start from current main in an isolated worktree and preserve the dirty primary checkout. Audit every published SolarInstallerLocation and all postcode districts using current read-on…
- Claude: **express**: The owner's two brief brainstorm answers matched obvious defaults; plan review raised no gates; the only pass-2 High was a missing regression test.
- Neon: **full**: Auditing all UK solar installer location pages and implementing a prioritized SEO and district-mapping batch involves large-scale stored-data changes, public canonical/sitemap contracts, and product prioritization decisions.
- Tie-break: 

### `task_workflow_routing:topgreendeals.co.uk:improve-the-kent-solar-installer-260923-1cea#direct`

- State: Project topgreendeals.co.uk; idea: Improve the Kent solar installer page for SEO and qualified enquiries. User request Improve the Essex and Kent installer pages next, via Hive tasks. This task covers Kent and follows the Essex pilot, which in turn follows GA4/internal-analytics task 43323. Project: TopGreenDeals/main workspace. Target and evidence - Existing pa…
- Claude: **express**: Follow-on of the Essex pilot that reuses its components; one owner scope answer (county boundary); delivered elsewhere, little evidence (low confidence).
- Neon: **standard**: Improving the Kent installer page follows the established Essex pilot and existing analytics definitions while requiring careful SEO, content, and idempotent database-backed updates.
- Tie-break: 


## visual_capture_need

3 of 78 disagree; kappa 0.9037. Question `needs_visual_capture`.

### `visual_capture_need:hive:extend-idempotency-keys-and-durable-260923-ccce#direct`

- State: hive: feat: add durable command receipt foundations
  132 files; top dirs: 
- Claude: **false** (`no_capture`): command-receipt backend; web sign-in only records a GitHub id, no rendered change
- Neon: **true**: Alongside backend receipt changes, the PR modifies the browser-side Stimulus controller web/app/javascript/controllers/project_filter_controller.js, web/app/controllers/sessions_controller.rb, and the browser system test web/test/system/pipeline_flow_test.rb.
- Tie-break: 

### `visual_capture_need:hive:make-project-expose-one-authoritative-oper-coding-030cd635#direct`

- State: hive: fix: keep workflow reads bound to their project view
  52 files; top dirs: 
- Claude: **false** (`no_capture`): workflow-binding refactor; view partials touched only for plumbing, no intended visual change; borderline
- Neon: **true**: Modifies Rails dashboard views (web/app/views/tasks/show.html.erb, _primary_actions.html.erb, _state.html.erb) and web models so rendered task and board pages keep workflow presentation bound to their project.
- Tie-break: 

### `visual_capture_need:todero:attachment-preview-turbo-frame-rendered-twice-pe-69936525d35b#direct`

- State: todero: fix(tasks): emit each attachment preview frame only once
  2 files; top dirs: 
- Claude: **true** (`needs_capture`): removes a duplicated turbo-frame from a rendered task partial; browser-verifiable
- Neon: **false**: Although app/views/tasks/_attachments.html.erb is modified, it only removes a duplicate hidden turbo-frame sharing a DOM id so the UI keeps using the exact same surviving frame without any visible or interactive change.
- Tie-break:
