# Completed-backup isolated wrapper repair — 2026-11-06

In the separate run checkout `_build/verification/p31-focused-run-20261106-04/source`,
the combined knowledge-wrapper run exited 2: two of three outer tests passed.
The completed-backup isolated child failed its strict compiler-diagnostics check
because its compile set omitted `IpseKnowledge.Store.State` and
`IpseKnowledge.Store.MCPCAS`; Store references both. The original failure is
retained in `../knowledge-wrappers.log` relative to that checkout's parent,
SHA-256 `a1bddb72dc1693d81be9f0bf543a20a7484676d69d60664b510943c28c6d484c`.
The missing-module warnings were not ignored.

The test-only repair adds `store/state` and `store/mcp_cas` to the wrapper's
source list. It preserves the empty compiler-warning requirement, both pass
markers, and the requirement for exactly 19 inner tests with zero failures,
skips or exclusions. The pre-repair wrapper SHA-256 is
`54498587788144d5539a30eda32ad153a124fad0cd907434eb19dfa188ead659`; the
workspace and repaired checkout wrapper SHA-256 is
`e76f1861e2a6a3e1767c5fbc67c23ecbd59a0fd1ac33d31c3e4601020902593b`.
The repair is a deliberate test-only difference from immutable snapshot
`_build/verification/integration-snapshot-20261106-06/source`, in addition to
the previously reviewed test-helper retention overlay.

The subsequent isolated completed-backup wrapper run exited 0 and reports one
outer test passed. The wrapper itself requires the 19 inner cases to pass;
the outer log does not separately print their individual results. The retained
log is `_build/verification/p31-focused-run-20261106-04/collection-completed-wrapper-repair.log`,
SHA-256 `38849650425f6953b1e025b74b90b4ce124832a63ecf5bcfd5f461f14fd0e3a8`.
Exit codes were observed by the operator; separate exit-code files were not
created. This focused rerun does not retroactively make the combined run pass
or establish native backup/restore qualification.

A later combined knowledge-wrapper rerun with the repaired wrapper reports all
three outer tests passed. Its retained
`_build/verification/p31-focused-run-20261106-04/knowledge-wrappers-repaired.log`
SHA-256 is `b44da0066b8216f4d4e7bc3fbd5512ef6ca3abc87e62ecc5d36765bbb5578728`.
This later result is separate from, and does not erase, the original combined
failure and the focused single-wrapper rerun recorded above.
