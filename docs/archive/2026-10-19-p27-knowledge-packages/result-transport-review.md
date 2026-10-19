# Complete-result implementation review, 2026-10-19

Historical implementation and verification record after `f342528`, not a P27
completion verdict. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
owns acceptance. Use the [invocation training manual](../../developer/extension-invocations.md)
and [extension user manual](../../operator/extensions.md) for current procedures.
The [design record](result-transport-design.md) explains the selected architecture.

## Review the whole contract

Two fresh reviewers independently traced the complete SDK-2 transport, rather
than reviewing only its latest edits. Their common brief included negotiation,
original-invocation eligibility, terminal Bootstrap and Worker behavior, Host
assembly and cleanup, Session authority, Writer reservations, source closure and
recovery, model and human reads, CLI and conformance, metadata and private-view
consumers, resource bounds, and structural ownership. Reviews were read-only.
There was no configured model panel; these are independent review contexts,
not a claim of different serving models.

Both initial reviews found an issue. The lead accepted both, repaired the source,
and added permanent regressions. Each original reviewer independently checked
its repair. A third fresh reviewer then traced the whole implementation and
reported no findings. It also reviewed the complete operator extension chapter
and developer artifact, invocation, persistence, and extension chapters.

## Reject an approval after the original deadline

The first reviewer reproduced a state write after the aggregate clock expired.
Session's extension-action approval checked the activation lease, but did not
check the original 120,000-ms clock. Host executed immediately after receiving
that approval. Its later publication refusal did not undo the write.

The synthetic reproduction requested a real `state.put`, waited for its approval,
aged the Session clock past its existing deadline, and approved. The old candidate
recorded a successful mutation. This used isolated state and the same clock-aging
method as the aggregate-timer test, with no production timeout change.

The repair checks time before action admission and after relevant journal writes
before returning executable context. Approval checks both sides of its durable
records. Inference admission and question acceptance retain the same original
clock. Host checks a deadline carried in trusted execution context immediately
before dispatching an admitted effect. Observation and completion receipts remain
recordable after expiry, so already-dispatched work does not lose its evidence.

The permanent regression verifies no state write, action intent, action result,
source begin, or final result after expired approval. An approved-action control
also verifies that a timely write continues into one saved result with the exact
ordered action commitment. The original reviewer independently reran the expired
approval regression and found no remaining defect in the repair.

## Retain completion metadata without exposing the body

The second reviewer found that `Lifecycle.Metadata.describe/1` accepted version 2
only for action intents and results. Every new version-2 invocation final therefore
became an unsupported record. Metadata feeds and observations missed completion,
and history reported a gap.

The closed vocabulary now admits version-2 `extension_invocation_result`. Its
projection contains only the valid invocation ID and numeric action count.
Saved descriptors, input arguments, text, and source bodies are excluded. Begin,
fragment, and seal records remain unsupported, as does an invented version 3.

A permanent test covers shared projection and diagnostic wrapping with private
sentinels. The original reviewer independently verified compiled projection,
actual in-memory feed admission and delivery, and journal-backed `History.execute`.
Those probes establish metadata integration, not a new private result-read grant
or native feed-worker cleanup claim.

## Checks and remaining gates

| Check | Observed result |
| --- | --- |
| SDK negotiation, Source, View and Writer reservation group | 47 passed in 8.4 seconds |
| Existing invocation, Worker, Registry, catalog, manifest and CLI group | 102 passed in 46.6 seconds |
| Review repairs with Session, metadata and legacy invocation tests | 70 passed in 34.3 seconds |
| Final real Session suite | 12 passed in 9.6 seconds |
| Contributor aggregate and preparation examples | Executed successfully against the built runtime |
| Documentation and audience rules | 248 files, 2,683 local links, zero errors |
| Full source baseline | 1,241 passed, 32 platform-tagged exclusions, 727.2 seconds; strict stdio probe and 60,000-ms timeout |
| Build, both formatters, strict compile, CI policy and demo | Passed on the repaired candidate |
| macOS native checks | Four Rust policy tests and 30 integration tests passed, six exclusions |
| Fresh bundled runtime and base extracted-package verifier | Passed with a utility-only runtime PATH |
| Generic SDK-2 source and installed-runtime proofs | Passed independently by the lead; exact 4 MiB, 1,024 fragments, one load and callback, zero model requests, confirmed cleanup and inert recovery |
| Exact-source Serenity Linux at `11d067f` | 1,258 passed, 15 excluded with native sandbox enabled; demo, package, installed verifier and exact 4-MiB source/installed proofs pass |
| Hosted `11d067f` run 39328913714 | Red on both platforms from twelve invalid tests in compiler-marker fixture setup under Elixir 1.18; corrected fixture and next-source gates recorded separately |

Session tests use separately compiled, inertly imported SDK-2 artifacts. They
cover command and model-tool publication, whole historical materialization,
bounded views, command/model and foreign-Session isolation, denial before load,
invalid-schema diagnostic prefixes, cancellation and aggregate expiry, capacity
refusal before source begin, invalid sealed source before tail repair, CLI
Unicode-value preservation, and conformance against the latest saved value.
The exact 4-MiB case transfers 1,024 fragments, closes its worker, reopens the
Session, materializes the same bytes, and verifies unchanged journal and callback
markers. This is actual native worker transport, not OS sandbox enforcement.

The first full-suite attempt was deliberately terminated when the deadline defect
was confirmed. Its log ends in SIGTERM without a completed result. The shell
returned zero and ran the demo anyway, so shell status alone was rejected as a
passing gate. The replacement requires a completed passing suite summary and
rejects a SIGTERM log before accepting subsequent checks. That replacement
completed successfully with the results above. All 22 runtime file hashes still
match the fresh whole-implementation review.

The [saved-result example](../../../examples/saved-results/README.md) supplies
the reproducible source and installed checks. The installed runtime uses a
precompiled harness and artifact with a utility-only PATH plus bundled `erl`.
Archive, artifact, extracted host, harness and utility inventories remain unchanged.
The lead independently reran both verifiers after reviewing their source.
The archive SHA-256 is
`d30dcec6769006d37ebd733eec5b2dc61cada8a9cd98aa166c2bf49362c1c062`, the
artifact SHA-256 is
`25880c528b2533847d98ecb5b34f6d988c80ecda85f4c286258d8cb95ee4c07b`, and the
complete output SHA-256 is
`e95a2985de63f8f10a659b57bb169afc34d4a04067c397d6907d956e55b2b89b`.
These example scripts and documentation were added after the completed full source
baseline; their actual source and installed executions supply their separate checks.

The Linux archive SHA-256 is
`2d10587d9dbb07dbfc908cb0266e9cf2c8a87f4ca08583d4aa4d130f9748cf08`.
Its independent saved-result artifact SHA-256 is
`cd83fdc2ae705bdd7865137dc170a98369f7c61c2ca83b559e06c601b0f6026d`;
the complete output digest matches the macOS proof above. Linux used an isolated
detached worktree on Serenity and left its main checkout unchanged. Its native
checks do not replace the red hosted floor-version gate. The
[domain-result record](complete-domain-results.md#platform-and-resource-boundaries)
explains the compiler-marker setup repair and its separate Elixir 1.18.5 check.

At this generic snapshot, knowledge packages retained their inline finish paths.
Their later [migration and complete-result verification](complete-domain-results.md)
are recorded separately. Lifecycle audit, independent semantic review and the
exposed quality/resource comparison remain open.
No original paused prediction or budget was replayed or renewed.
