# Documentation provenance discovery repair

Historical engineering record, 2026-10-29, based on `7afc3f2` plus the active
P30/P31 worktree. Current procedures remain in the
[testing manual](../../developer/testing.md); the [plan](../../plan.md) owns
milestone acceptance. This repairs a developer check, not runtime behavior or
P30/P31 completion.

The [original check](before.exs) recursively discovered provenance manifests
with `Path.wildcard`. Run47118 followed the preserved navigation symlink
`native-shell-unknown-cleanup/shell-source/docs` back into current documentation
and eventually failed with too many symbolic-link levels. The
[failure log](documentation-checkpoint-47118.log) remains intact; neither the
link nor any archived snapshot was removed or changed.

The [repaired check](after.exs) uses Git's tracked and untracked file list for
the same two provenance path specifications. Unlike Markdown discovery, it
includes ignored provenance files to retain the original wildcard's scope.
It still reads every selected manifest and checks every original snapshot/hash
pair. Independent non-following `rg --files` discovery and Git selected the
same six current real manifests. This avoids treating
navigation aliases as additional archived evidence without weakening hashes.

The [initial nonignored candidate](nonignored-candidate.exs) passed47119,
checking840Markdown files,7,062local links and manual/archive rules with
zero errors; [the log](documentation-checkpoint-47119.log) retains the existing
private-ledger permission warnings. Its exclusion flag was then removed before
commit to preserve checks for ignored provenance files too. Source and logs are
pinned by [the manifest](manifest.sha256).
Final47120passed842Markdown files and7,079local links with zero errors on the
exact committed discovery variant. Its log is retained alongside the earlier
checks. Independent review confirmed the same six manifests using
`rg --files --hidden --no-ignore`, including the unchanged ignored-file scope.
No runtime suite, model/network call, native profile or release was qualified.
