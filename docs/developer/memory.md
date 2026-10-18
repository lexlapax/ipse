# Explicit memory extension contract

P26's baseline implements optional working and persistent notes through the same
worker SDK as independent extensions. `Ipse.Extensions.Memory` owns explicit
invocations and domain continuations; `Memory.Records` owns note validation,
source versions, suppression and lexical ranking. `WorkingMemory` restricts
initialization to session scope. Registry supplies inert built-in metadata and
binds each helper BEAM into artifact identity. No Session memory branch, automatic
capture, model call, database or service is added. Full milestone acceptance
remains pending the current verification gates.

Use [operator memory](../operator/memory.md) for selection, commands, sharing,
retention, collection and recovery. This document owns implementation invariants;
[host calls](extension-host-calls.md) owns generic storage/receipt semantics, and
[knowledge research](knowledge-extensions.md) owns deferred P27 comparisons.

## Host contracts and authority

The baseline exposed two generic SDK gaps. Opt-in operator logical bindings
separate storage identity from exact executable/configuration identity, while
`state.scan` and `host.state.scan` permit byte-bounded value pages and up to 512
state-read steps. Legacy namespace derivation remains unchanged. Persistent
memory additionally declares `host.state.bound` and therefore refuses activation
without the operator grant. Bound scopes remain a ceiling; ordinary read/write
grants and full write approval are still required. A long read never grants late
mutation beyond the ordinary step bound.

These mechanisms belong in the host because namespace authority, byte/action
bounds and journal validation are shared guarantees. They neither understand
notes nor grant workers arbitrary paths. Domain code only returns typed host
proposals. Each write is intent-journaled before scoped CAS and its validated
receipt is journaled before continuation. Cancellation can leave an admitted
write unknown; resume restores receipts without replay. Exact execution identity
still refuses changed-code resume even when a logical store is shared.

The existing small protected JSON store was chosen over adding SQLite, DETS or
a remote/vector engine: it already supplies locks, bounded portable values and
cross-VM CAS. It holds at most 256 records/1 MiB, including suppression, rather
than claiming to be an unlimited corpus backend. See the
[dependency decision](dependencies.md#reuse-decisions). Larger storage is a
separately justified extension/backend change, not an implicit P26 dependency.

## Record and source lifecycle

A version-two active note contains an exact logical source ID and its SHA-256,
monotonic source generation, kind (`task_card`/`project_fact`), title/text,
provenance, created/updated/expiry milliseconds and at most eight `derived_from`
source IDs. JSON schemas use the supported bounded subset; domain validation also
checks the complete record shape, byte limits and source/hash/timestamp relations.
Source IDs are literal, not semantic entity resolution or filesystem/URL aliases.

Remember requires the observed storage revision and a strictly greater source
generation for updates. Store revision tracks all CAS writes, independently of
source generation. Conflicts return without automatic retry. An already expired
source cannot be renewed through remember/import; choose a distinct explicit
assertion if that is intended. TTL is based on the system wall clock and is not
proof against clock rollback. Reads do not perform hidden approved writes.
The configured ceiling applies at write/import time; existing expiry fields are
not silently rewritten when options change. Immediate tightening uses explicit
forget and the affected-session policy below.

Forget replaces content with a version-two minimal suppression value retaining
source digest/generation and update time. It uses `state.put`, not deletion:
core tombstones permit a later writer with the current revision to create a new
value. The extension refuses remember/import whenever the existing source is
suppressed, even after rereading it. CAS independently rejects a continuation
prepared before concurrent forget. Suppression consumes quota and is not
silently compacted away. Same-user file edits, deliberate new bindings and omitted
backup rows are outside this policy, not ways to certify safe restoration.

Recall scans all pages at a fixed store generation. Mutation during pagination
causes conflict instead of a mixed snapshot; mutation after the last read cannot
revoke text already observed. The result identifies its generation and as-of
wall clock. Expired, suppressed and transitively blocked/orphan derivatives are excluded
before ranking. Dependencies are explicitly declared; unknown semantic copies
cannot be discovered. Lexical ranking lowercases Unicode letter/digit/underscore tokens and uses word overlap,
deterministic key tie-breaking and at most five results. A score is retrieval
relevance, not truth. Exact byte spans and full-text digests accompany excerpts.
No answer is synthesized and no context publication runs automatically.

## Export, collection and upgrade

Export/inventory scan one generation, then paginate the requested output by key,
record count and bytes. Export converts expired or transitively blocked active
values to portable suppression records; it does not silently mutate the backend.
Inventory retains active source IDs and derivative metadata while omitting text/title/provenance.
Collection removes stored expired content, or a direct derivative after checking
its declared suppressed/expired cause. Apply collection along dependency edges
until the affected derivative content is removed; explicitly forget orphan records
identified by their inventory source IDs. Dependencies are namespace-local, not a
cross-store revocation protocol. Each bounded write is approved;
a generation change or stale target revision refuses without automatic retry.

Import merges one reviewed exported record using target CAS. Existing suppression
wins, unknown versions refuse, stale generations refuse and active expiry cannot
exceed configured retention. To reconstruct a fresh namespace, use a complete
current export and import suppression first. A partial/old backup cannot attest
that a source was never forgotten. Cross-store merges are explicit operator data
transfer, not automatic synchronization or a global deletion-consistency protocol.

Version-one active records have the same bounded fields except `derived_from`.
They require an explicit approved migration to version two before recall/update;
that transformation preserves expiry, provenance and source version. An approved
import upgrades a minimal version-one suppression by digest while retaining its
source generation; it does not need the forgotten plaintext source ID or content. Unknown or
malformed values fail closed. Logical binding allows reviewed code/configuration
versions to address the same records, but does not run migration or approve new
code. Unbound artifact namespaces remain separate and need their matching old
adapter for export before a reviewed import. Raw namespace/lock deletion is not
a migration or collection API.

## Cached context and retained evidence

Memory has no history-read, model or context-publication capability. Explicit
model-tool recall still produces ordinary retained tool messages, and other
extensions can separately publish cached context. Backend suppression does not
invalidate either. This baseline selects an explicit affected-session policy:
close sessions containing prior affected recall, then start fresh with no
forgotten text in any manually reviewed handoff. Idle resume preserves the old
committed projection exactly and never re-reads the backend to rewrite history.

This policy is distinct from live cross-session invalidation, history redaction,
journal/backup retention, secure erasure and prior provider transfers. Those are
not implemented or promised here. A future requirement for automatic revocation
needs a reviewed generic core projection/invalidation contract, not an extension
claim that deletion erased past evidence. The operator guide makes the required
manual boundary explicit.

## Verification and measurements

Focused tests cover stable binding authority and legacy compatibility, byte-limited
scan receipts, isolated session/project/operator scopes, explicit operator sharing,
separate write approval, cancellation/denial, default-off behavior, retained recall,
stale continuations, reread/reingestion/import suppression, derivative closure and
collection, expiration and explicit schema migration. Real Sessions exercise the
owned worker path and restore saved transcripts inertly. Fixture helpers are not
substitutes for live model/algorithm evaluation.

`mix run scripts/measure-memory.exs` uses the frozen
[`examples/memory/corpus.json`](../../examples/memory/corpus.json) across six
real Sessions/two projects: 100 records and 100 queries, including updated,
expired, forgotten and unanswerable cases. Commands use no provider; a provider
callback raises if inference is attempted. Each saved session is validated after
close. The script reports exact source/span checks, recall@5, latency, current-state
bytes and observed VM-memory samples. The corpus is a synthetic exact-token
fixture, not natural-language understanding, semantic citation precision or a
comparison with Zero-Mem. It returns five results, so nDCG@10 is not measured.
Memory samples are not a peak bound; hardware/runtime and costs remain explicit.
Source and installed-package runs must identify their distinct artifacts and
results in [testing](testing.md#current-evidence-and-next-checks).
