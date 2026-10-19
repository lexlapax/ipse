# Developing the explicit note extensions

The memory extensions are a worked example of domain behavior built through the
public worker SDK. `Ipse.Extensions.Memory` owns explicit invocations and
continuations; `Memory.Records` owns note validation, suppression, and lexical
ranking. `Ipse.Extensions.WorkingMemory` restricts initialization to session scope.
Persistent memory supports project/operator scope and requires an operator logical
storage binding. Neither extension captures prompts or runs inference automatically.

Read `lib/ipse/extensions/memory.ex` with
`lib/ipse/extensions/memory/records.ex`. The host sees ordinary state proposals,
not a special memory operation. Registry supplies inert built-in metadata and
pins helper BEAM identity. Selection and user commands are documented in the
[operator memory manual](../operator/memory.md).

Both memory artifacts declare their selected State scope option in inert built-in
metadata. When an operator binding is present, Registry compares its scope ceiling
with that option at admission and revalidation. A project-only binding cannot
activate operator-scoped persistent memory or session-scoped working memory.
Working memory may remain unbound. Persistent memory's `host.state.bound`
capability independently requires a binding. These checks execute no extension
code and grant no additional scope. State still enforces each operation's ceiling.

## Follow remember through a continuation

An explicit remember request reads existing state, validates the observed storage
revision and logical source generation, then returns an approved `state.put`
proposal. Host intent precedes scoped compare-and-swap; the validated receipt
precedes extension continuation. Store revision counts all CAS writes. Source
generation versions one logical assertion, so updating it requires a strictly
greater generation. A conflict returns without retry.

Memory refreshes its clock after the target read. For remember or active import
replacing an active target, `write/3` copies the target's expiry into the generic
State `write_before_ms` precondition. It never uses the replacement's later expiry
for this condition. Session displays and journals the exact request through its
ordinary approval path. State checks its own clock under the namespace lock and
again before publication. A known `write_deadline_elapsed` failure becomes
`source_expired` without another write. Follow the real Session delayed-approval
tests for both operations, their live-renewal controls, and idle resume after the
failed receipt. The [host-call chapter](extension-host-calls.md#bound-a-prepared-write-by-time)
owns the generic request and receipt contract.

Version-2 active notes have this bounded domain shape:

| Field | Meaning and limit |
| --- | --- |
| `source`, `source_sha256` | Literal logical ID, at most 512 bytes, and its exact SHA-256/key |
| `source_generation` | Positive monotonic source version |
| `kind` | `task_card` or `project_fact` |
| `title`, `text`, `provenance` | At most 128, 2,048, and 512 bytes |
| `created_at_ms`, `updated_at_ms`, `expires_at_ms` | Creation ≤ update < expiry |
| `derived_from` | At most 8 literal source IDs, each at most 512 bytes |
| `version`, `state` | 2 and `active` |

Encoded notes fit 8 KiB. Closed schemas and domain validation both run. IDs are
literal strings, not entity resolution or filesystem aliases. TTL uses wall clock
and cannot defend against clock rollback. Retention ceilings apply at write/import;
changing configuration does not silently rewrite old expiry. Expired assertions
cannot be renewed through remember/import under the same source.

For a reading exercise, follow "explicit notes rank with exact provenance" in
`test/extensions_memory_test.exs` from arguments through `Records.build/4` and the
host receipt. Find which revision belongs to the store and which to the source.
Then inspect the stale-update refusal; neither version may be guessed after a
conflict.

## Make forgetting survive delayed work

Forget writes a minimal version-2 `suppressed` value with only source digest,
source generation, update time, state, and version. It does not delete the key.
Core tombstones allow later writes with the current revision; domain suppression
must instead reject remember/import even after rereading. CAS independently blocks
a continuation prepared before a concurrent forget.

Suppression consumes quota and is not silently collected. The generic protected
JSON store has at most 256 records/1 MiB, including suppression. `host.state.bound`
separates a reviewed logical store from exact executable/configuration identity;
it does not approve new code or migrate records. Legacy unbound namespace
derivation stays unchanged. Bound scopes remain ceilings, and writes still require
ordinary grants and full approval.

`state.scan` returns byte-bounded value pages at a fixed generation.
`host.state.scan` permits up to 512 read steps; it does not allow writes after the
ordinary 16-step allowance. Recall fails on mutation during pagination instead of
mixing generations. Mutation after the last read cannot revoke text already seen.

Recall seeds dependency exclusion with `Records.visible?/2`, then propagates
exclusion through declared derivatives. Expired, suppressed, unmigrated and
orphan-derived records therefore block transitive dependents before ranking.
Ranking uses lowercase Unicode letter/digit/underscore
word overlap, deterministic key tie-breaking, and at most five results. Excerpts
carry exact byte spans and full-text digests. Scores express lexical relevance,
not truth; the extension synthesizes no answer and publishes no context by itself.

Inspect starts with `state.get` to preserve the actual revision and missing/deleted
record semantics. For an active record it scans dependencies at that exact store
generation and applies the same exclusion closure as recall. It returns the full
record only when its schema version, expiry and dependencies are eligible at the
final scan's time. Otherwise it drops text, title and provenance and reports
`visibility: "metadata_only"`. Suppression is already minimal. No read writes a
replacement record. Follow the changed-generation regression before modifying
this flow; a second unpinned read would reintroduce a race.

## Preserve suppression across export and upgrades

Export/inventory scan one generation and paginate by key/count/bytes. Export
preserves stored values exactly, including expired and transitively blocked active
records. Visibility filtering is not a storage transition: a missing parent may
arrive later, and an approved source update may remove a dependency. Converting
those records into suppression would change restore behavior. Inventory omits
text, title and provenance but retains source and derivative metadata.
Collection replaces expired content, or a direct derivative after checking its
suppressed/expired cause. Walk dependency edges to
remove affected derivative content; explicitly forget orphan IDs from inventory.
These dependencies are namespace-local, not cross-store synchronization.

Collecting a missing source at expected revision zero returns `not_found` after
its read, with no write or new suppression, including when a cause is supplied.
The revision precondition still returns `conflict` for a mismatched expectation.
The missing-target check precedes dependency-cause lookup. Explicit forgetting of
an absent ID creates permanent minimal suppression and consumes a namespace slot.

Import merges one reviewed record through target CAS. Existing suppression wins;
stale generations, unknown versions, and excessive expiry refuse. Restore a fresh
namespace from a complete current export, importing suppression first. A partial
or old backup cannot establish that a source was never forgotten.

An explicit import may restore an already-expired active record with its original
expiry. This preserves the backup without renewing visibility. A previously
expired or suppressed target cannot be renewed by remember or another active
import. A newer-generation expired import may replace a still-live target;
the replacement becomes hidden immediately. The write deadline still comes from
the live target, not the imported expiry. Export is an operator command and may
retain text hidden from model tools;
collection, backup retention and earlier journal disclosure remain distinct.
Trace the complete-export regression through a missing-parent child, a forgotten
ancestor, an expired record and a fresh target. Compare visibility after the
parent arrives and after an approved dependency-removing update in both stores.

Import may restore valid version-one active values unchanged. They and their
declared derivatives remain hidden until explicit approved migration to version 2.
A newer-generation version-one import may also replace a live version-two target,
making it legacy and hidden until migration. Import preserves the approved schema
and expiry rather than silently upgrading either.
Remember also refuses updates to an unmigrated target. Migration preserves expiry,
provenance, and source generation, and cannot make an expired record visible.
Active import cannot replace an unmigrated target either. Incoming suppression
still wins before that migration check.
Minimal legacy suppression can upgrade by digest without forgotten plaintext.
Malformed records fail closed. Raw namespace/lock deletion is not a migration API.

## Keep backend state distinct from retained context

Memory has no history-read, model, or context-publication capability. Explicit
recall still creates normal tool messages, and scanned values remain in private
state-action receipts, including nonselected notes. Forget/TTL/collection do not
redact either. Repeated scans can exhaust finite journal storage.

Close sessions that retain affected recall and start fresh without forgotten text
in any reviewed handoff. Idle resume restores its old projection and never rewrites
history from current memory. Automatic cross-session revocation, secure erasure,
backup deletion, and undoing prior provider transfer are not implemented. A future
automatic policy needs a reviewed generic host invalidation contract.

```sh
mix test test/extensions_memory_test.exs test/extensions_memory_session_test.exs
mix test test/extensions_state_test.exs test/extensions_state_binding_test.exs test/extensions_state_scan_test.exs
```

Domain fixtures teach source versions, expiry, ranking, derivatives, migration, and
stale-import suppression. Real Session fixtures establish separate approval,
cancellation, isolation, and inert recovery. Binding/scan tests establish the
host guarantees the domain relies on. `mix run scripts/measure-memory.exs` is a
credential-free lexical corpus exercise; it measures that workload, not semantic
understanding, peak memory, or secure erasure.
