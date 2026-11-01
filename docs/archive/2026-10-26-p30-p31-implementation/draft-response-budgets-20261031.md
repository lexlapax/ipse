# Separate draft proposal size from provider framing

Dated **2026-10-31**, based on `4e6510e53c2208f3713f315b10aeea5134ab0b6a`
with the source and controls inventoried in the [receipt](draft-response-budgets-20261031.json).
This is historical implementation evidence. Current procedures belong to
[request refinement](../../operator/usage.md#refine-a-request-before-submitting-it)
and the [context training chapter](../../developer/workspace-context.md#withdraw-draft-intent-before-ordinary-work).

The preceding [real native enhancement control](responses-optional-tools-20261031.md)
obtained workspace context and an operator answer, then failed while streaming
its final draft. That failed request and its unknown liability remain unchanged.
It did not establish a completed live draft.

## Problem and resulting behavior

`Draft.draft_config` imposed an extra 65,536-byte response limit. The transport
counts the entire HTTP body, including every SSE event wrapper and provider
continuation. A small proposal fragmented into many events can cross that limit
while remaining well below the separate 32,768-byte proposal bound.

Drafts now retain the selected route's existing transport setting, ordinarily
8,388,608 bytes, including any tighter inherited setting. This reuses the existing
transport and stream parsers; their other bounds remain in force. It changes no
provider, model, billing, reasoning or output-token setting. Drafting still has
its three-request ceiling and restricted tools, and questions grant no effects.

The final proposal independently requires nonempty valid UTF-8 within 32,768
bytes. Previously, a failed final-size check silently left a pending draft while
reporting a successful turn. It now reports an explicit error and records no
`draft_completed`. The original assistant message remains in the journal.
A completed provider response retains known terminal accounting even when the
domain proposal is refused. A partial transport failure retains its ordinary
unknown liability; neither case is replayed automatically.

## Actual verification

Before the source repair, four new synthetic controls produced **one pass and
three failures**: the tighter inherited limit passed; framing, preserved config
and explicit oversized-proposal failure did not. That original log is retained.
After the repair and an exact-size boundary control, all five passed. The final
broader non-terminal cohort passed **76 tests in 6.9 seconds**, including draft
transitions/projection/ceilings and OpenAI, subscription and HTTP transport tests.

The loopback Session controls check an under-2-KiB proposal with over-64-KiB SSE,
an inherited 32-KiB transport refusal, a 32,770-byte UTF-8 proposal refusal, and a
32,768-byte accepted proposal. They verify original history, saved reconstruction,
one request only, absent effect/acceptance records, and the distinction between
completed accounting and partial unknown liability. They use synthetic credentials
and the ordinary provider wrapper, without a native terminal or real service.

Build, formatting, strict compilation, credential-free demonstration, repository
policy and documentation checks are recorded with their actual outcomes in the
receipt. The first sandboxed build failed before compilation because Mix's TCP
filesystem lock was unavailable; the approved loopback-capable retry is distinct.
The whole operator usage and developer context chapters were reviewed; stale
claims that managed read integration was wholly unwired now point to the actual
host path and its remaining gates.

No live request, model download, dependency or native-terminal control was added
for this increment. It does not qualify live draft completion, knowledge-assisted
clarification, acceptance, independent quality or an installed artifact. The
separate e86b1b8 full suite excludes this source and retains its
[native concurrency limitation](full-suite-e86b1b8-concurrency-20261031.md).
P31I and the full goal remain open.
