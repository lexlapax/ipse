# Supervised development evidence

Record the stable baseline commit and candidate branch/worktree; keep the runner
unchanged. Preserve unrelated edits and private credentials/transcripts.

Before edits: task, intended behavior, concrete acceptance checks, selected
provider/profile, limits and approval policy. Distinguish instructions, configuration
and permissions. Do not add a dependency without the repository's required approval.

During work: inspect the proposed diff, run focused meaningful tests and record
actual failures. A tool intent is not a successful effect. A timeout, cancellation,
unknown child or missing result requires inspection, not replay or a success claim.

Before completion: review source/tests independently; verify formatting, compilation,
full relevant suite, demo and package where required; review operator/developer
examples and local links/anchors. Separate fixture, live provider, host-native,
hosted CI and released-artifact evidence. Excluded tests were not run. Syntax checks
on Linux do not establish local Mac execution. Keep traces content-free and raw
journals private. Use exact commit/run references in public evidence.

For idle resume, close the session first, then snapshot private journal/workspace
state and compare immediately after resume before prompting. CLI /exit may append
a cancellation event; a pre-exit checksum is not the correct unchanged-resume baseline.
Git diff omits untracked files, so also record status and relevant new-file digests.

Present remaining limitations, exact proposed publication action and the review
result. Follow existing task authority rather than assuming the skill is approval.
