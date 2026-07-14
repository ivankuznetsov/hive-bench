# Fix submission runner build

**Action:** Repaired the maintainer-gated corpus validation workflow so it
checks out Hive at immutable commit `5028d7655fb1b0fa0a223e967661c678b09b336f`
and invokes `harness/build_runner.sh`. The previous direct `docker build` call
could never satisfy `Dockerfile.runner`'s required `hive-src.tar`; the canonical
builder creates that archive with `git archive HEAD` and removes it after the
image build. Also made `validator/cli.rb` initialize the harness load path for
its documented standalone invocation; previously it stopped at
`require "lib/git_restore"` before reading an entry. The workflow now executes
validator, harness, and Dockerfile code only from the immutable trusted base SHA
and treats the PR's `corpus/**` as data. A retained approval label cannot launch
a later push: validation requires a fresh `safe-to-validate` label event and does
not rely on GitHub's size-limited path filter. The PR checkout has complete
history for the three-dot merge-base diff, and any changed
path under `corpus/<task>/**` selects that whole entry for validation; a missing
manifest fails closed. Corpus symlinks, manifest spec paths, and gate test-patch
paths that escape their entry are rejected so nested-checkout paths cannot
resolve into trusted files.

**Verification:** The original labeled PR run failed before validation with
`COPY hive-src.tar: not found`. A local canonical image build against the pinned
Hive revision passed, and the exact workflow validation loop accepted all four
changed corpus entries (one judged and three gated). A focused regression proves
the CLI boots without an explicit `-Iharness`; the built-in workflow smoke also
requires quota markers to carry the UTC ISO-8601 `retry_after` timestamp the
daemon needs for automatic resume. The broader checks remain the Ruby suite,
RuboCop, and built-in workflow smoke against the merged Hive revision.
