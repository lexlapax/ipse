# Declared planning MCP reads: implementation follow-up

2026-10-27. This is a historical implementation and synthetic-test record, not
P31I acceptance. It supersedes the inactive-dispatch status in the earlier
planning MCP records; their individual test results remain historical evidence.
The current changes are uncommitted and must be reviewed against their actual
source bytes.

The Session path now permits a host-discovered MCP tool in planning or a draft
only when the operator declaration binds its server, tool, configured endpoint
and descriptor. It checks the current Session checkpoint, approval ceiling,
arguments and declaration before approval and again before launch. Draft reads
also require a pinned catalog, source and active lifecycle with room to record
the call. The adapter reconnects and rediscovers the descriptor before dispatch.
The Session journals the restricted intent and tool start before the owned task.
This is not a guarantee that a server honestly implements read-only behavior.
Session configuration remains fixed until a new Session is started.

A synthetic approved read exposed an existing source-reference problem: the
MCP manifest used atom keys before JSON serialization, so a lifecycle source
lookup did not match the decoded record. Normalizing the manifest before the
journal append allows the lifecycle to record and retrieve the evidence. The
synthetic tests also exercise user denial, descriptor drift, exhausted evidence
capacity, changed in-memory declaration after approval, read-only and explicit
denial, workspace-write denial, actual operator configuration loading, owner
death during a call and restoration without automatic replay.

An isolated graph rooted at 668e6a3 with the selected implementation and test
files had tree `e553da6e82f88b53347c41cfc9e79633da60d9ec` and passed 111
focused tests with seed 20270614 and one test case at a time. Later test-only
additions include the source-page check, declaration mutation isolation and
operator-configuration integration. The resulting tree
`798d90b5a6183d487e75291b51a06f683b7b781e` passed 34 MCP Session and mode
tests with seed 20270616 and one test case at a time, and forced test-environment
compilation with warnings treated as errors. The production helper used in that graph
had SHA-256 `891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.
These tests use synthetic MCP servers and do not establish native profile or
live-provider acceptance. The journal checks bind records structurally under
the Session-owned journal trust model; they do not authenticate a wholesale
rewrite of the journal and header.

The working-tree synthetic PTY journey now approves a declared read, accepts
the resulting draft, checks the source page and the following inference lineage,
and refuses a restored acceptance with its evidence removed. Its focused test
passed with seed 20270617. A broader fixed-graph run with seed 20270618 passed
43 of 45 tests; its two PTY failures occurred with a stale companion fixture
and terminal implementation. After aligning those files, fixed tree
`4803e749a10606884773cc5d490fb8db50b900d0` passed all 45 draft acceptance,
MCP Session, mode and planning replay tests with seed 20270619 and one case at
a time. The PTY test also checks that the approval display includes the target
and query. This synthetic journey is not a live-provider or
whole-platform acceptance check.

An adversarial synthetic follow-up forced the committed start above the
source-reference size limit by changing the Session's in-memory sandbox value
after approval. With seed 20270620, lifecycle recording stopped for
`source_unavailable`, but the server still received the call. The uncommitted
repair checks that the lifecycle actually bound the start before launching a
draft planning read; the same probe passed with seed 20270622, recorded an
error outcome, and restored. This injected state does not establish that normal
operator configuration can supply the oversized sandbox value. Other causes of
an unavailable source still need their own evidence where applicable.
Fixed tree `bea476ebedcf0384574202ec90f6c0127e50ce55` passed all 46 draft
acceptance, MCP Session, mode and planning replay tests with seed 20270623 and
one case at a time, followed by forced test-environment compilation with warnings
treated as errors.

A controlled synthetic server now pauses after receiving a declared read. A
test changes the in-memory approval value to an atom that encodes as the same
JSON string, forcing the result record to have no source without changing the
stored JSON. With seed 20270624, the result was recorded as successful but the
draft had no evidence, so the actual acceptance rendering refused. Restore and
resume also refused rendering and did not call the server again. This is an
injected source failure, not evidence that the normal adapter emits atom values
or that every result-write failure has this recovery behavior. Fixed tree
`0ef264096e34ef6dadd890da841cab7759b8167b` passed all 47 draft acceptance,
MCP Session, mode and planning replay tests with seed 20270625 and one case at
a time.

The planning replay validator also accepted a duplicated intent/start pair for
one model call in a synthetic history (seed 20270626). This finding concerns
what that validator accepted; it does not establish that an effect was replayed
or that every other restore validator accepted the history. The uncommitted
guard tracks started calls by request, turn and call ID across epochs and
rejects duplicates for both restricted and ordinary MCP starts. It still allows
the same call ID in a distinct request. Focused validator tests passed with seed
20270627, and a synthetic Session journal with a duplicated pair was rejected by
restore with seed 20270628. These checks are not authentication against wholesale
journal rewriting. Fixed tree `34d79a56bc8290f10ef40c198116dd8387cfc5bf`
passed the 47 focused draft, MCP Session, mode and replay tests with seed
20270629. A test-only addition covering a repeated start across a resume epoch
passed the replay suite with seed 20270701 on tree
`e5da32064366c52ee25c19a57c22e0e6d03bd3ec`, followed by forced strict
test-environment compilation. The broader 47-test run predates that last
test-only addition.

Whole-source regression on an admitted host, operational review, and the
requested adversarial audit remain open. See the [continuation handoff](handoff-20261027-terra.md) and the
[working review prompt](review-prompt-working.md).
