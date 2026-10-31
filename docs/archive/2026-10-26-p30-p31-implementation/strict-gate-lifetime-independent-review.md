# Independent review of lifetime containment follow-up

2026-10-29. This scoped review covers the frozen
[forgetting, State and document lifetime follow-up](strict-gate-lifetime-followup.md),
not a complete P31 safety review. The reviewer verified all 49 archive file
hashes, 209 runtime BEAM hashes, six archived document source hashes and four
document log hashes. The preserved ptrace diagnostic and helper match their
recorded hashes and rebuild log; the reviewer did not rerun the interposition.

The inspected Collection normalization refuses the reviewed forget, retention
and supersession kinds before mutation. Public reviewed forget and session
retention refuse before review. Valid State writes with `write_before_ms`
refuse before file I/O, with a separate write backstop; ordinary no-deadline
State writes have the recorded compatibility controls. DocumentStage preserves
the earlier inherited deadline, restores its scope, and routes deadline commits
to the refusing profile entry. The closed typed document-store failure and SDK
propagation are present.

The retained controls support the reported late forget and State effects and
the focused interim refusals; they do not establish a strict effect-lifetime
mechanism. The reviewer found older State and DocumentStage tests that still
expect deadline-bearing writes to succeed or use the former elapsed receipt.
Those tests need reconciliation without losing validation of historical
receipts. The P26H3 plan row was corrected during this review to distinguish
its historical completion from the current State gate.

No additional reachable bypass was identified in these scoped paths. The
literal-v4 A/B case, enforceable time and permit lifetime, broader writer paths,
and final integrated adversarial review remain open. No tests were rerun by
this reviewer.
