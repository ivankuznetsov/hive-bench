# Review patch fallback and local Bundler exclusion

- Made failed review stages restore `candidate-execute.patch` as the scored
  `candidate.patch`, preventing partial review side effects from replacing a
  valid implementation.
- Changed in-container diff capture from `git add -A` plus cached diff to
  intent-to-add plus working-tree diff, so excluded build trees are not staged
  into the branch consumed by review.
- Added `.bundle-local/` to both host and container capture exclusions after a
  live GLM cell swept 4,991 local gem files into a 47 MB patch.
- Added regression coverage for the failed-review fallback and the new
  generated-tree exclusion.
- Follow-up review made capture and fallback-copy failures fail closed, covered
  zero-byte execute patches, consolidated shell exclusions, and replaced the
  source-text assertion with a real temporary-Git capture test.
- The host `GitRestore` now also rejects intent-to-add failures instead of
  returning a tracked-only patch that silently omits new solution files.
- Capture now enumerates non-ignored, non-vendored untracked paths before
  intent-to-add. This avoids false failures when an excluded build tree is also
  ignored (for example `vendor/bundle/`) while preserving index-error detection.
- Intent-to-add consumes the NUL-delimited file list with literal pathspec mode,
  so legal filenames containing Git pathspec magic cannot expand back into an
  excluded generated tree.
