# Evaluation-driver failure paths, 2026-10-19

Historical verification after `94dc78d`. The commit containing this record adds
four public-Session negative cases and their contributor exercise. It changes
no production runtime, domain module or evaluation-helper behavior. Use the
current [evaluation training chapter](../../developer/knowledge-evaluation.md#exercise-failed-paging-and-lost-completion)
for the procedure. Full P27 acceptance remains open in the
[plan](../../plan.md#p27-optional-research-graph-and-rag).

The suite builds an independent synthetic SDK artifact outside the host VM. Its
source command emits valid SDK result envelopes containing deliberately malformed
domain continuations, or holds work behind a filesystem start barrier. Temporary
action logs establish which commands actually ran. The fixture grants only
`invoke.command`; it makes no model, MCP or State request and reads no dataset.
Its private filesystem controls are test instrumentation, not confinement proof.

| Negative case | Direct observed result |
| --- | --- |
| Open returns offset one | `:invalid_draft_continuation`; one durable receipt; no append or publish; explicit later inspection succeeds |
| Append returns the wrong next offset | Same refusal; both completed receipts retained; no publish; explicit later inspection succeeds |
| Held invocation times out | Cancellation completion retained; original invocation ID saved; run remains settled and a later read succeeds; Session cleanup confirmed |
| Session killed after worker starts | Intent retained without result; journal snapshot keeps original Session ID; run marked unsettled; further invocation changes neither journal nor dispatch log; close reports cleanup unconfirmed |

The owner-loss case separately observes the fixture worker's OS-process exit to
prevent a leak. It deliberately does not turn that absence into a Session cleanup
acknowledgment. All four cases show zero canonical model requests. No deadline,
bound, approval, retry or replay policy changed.

The initial run passed three cases and failed the new test's expectation that
`Process.exit/2` returned `:ok`. The actual return was `true`. Correcting that
test-only expectation produced four passes in 14.2 seconds on macOS arm64,
Elixir 1.20.3 and OTP 29. The initial failure remains retained. No production fix
or repeated inference was required.

These cases exercise the Session driver's negative boundary. They do not replace
the still-required domain inference interruption/forget races, memory-selection
independence, capacity audit, maintained frozen comparison runner, held-out
quality/resources or independent semantic review. The earlier
[model workflow record](model-workflows.md) owns its separate 1094-test source
baseline, package and actual tuning receipts.
