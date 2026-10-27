# Managed-reference pure contract checkpoint

Dated **2026-10-26**. Internal component checkpoint
`db0db6df258aef3469884ca583e795c8b113d9b4` on `codex/p30-p31`.
This is engineering provenance, not an operator procedure or a P31E acceptance
claim. The [frozen contract](contracts.md), [baseline](baseline.md) and
[current plan](../../plan.md) own scope. Current context behavior remains in
[the developer manual](../../developer/workspace-context.md); source admission
is explained in [Session sources](../../developer/session-sources.md).

## Authorized boundary

The developer authorized implementation subagents and this generic core API gap.
The parent approved a pure two-file checkpoint before protected validity recipes,
Collection read views and every-dispatch integration. The checkpoint adds
[`ManagedReference`](../../../lib/ipse/session/managed_reference.ex) and
[its synthetic tests](../../../test/ipse/session/managed_reference_test.exs).
It changes no Session, Turn, SDK, provider, storage or native dispatch path.

Session must validate committed producer/result pairs before admitting lineage.
The pure functions validate consistency, bounds and exact projection; they do not
authenticate a caller, interpret arbitrary stored JSON, or grant freshness,
permission or source truth. Coherent rewriting of an entire valid journal by
trusted same-user code is outside this cooperative integrity boundary.

No new dependency was introduced. Canonical hashes reuse `Ipse.JSON.digest/1`;
encoded bounds use the existing maintained Jason encoder. There are no scripts,
callbacks, domain names, ranking rules or IO inside the component.

## Closed normalized receipts

A dependency contains exactly `version`, `project_id`, `namespace`, `pin_sha256`,
`policy_generation`, `collection`, `record` and `validity`. Version is 1.
ProjectIdentity's project SHA is distinct from the Collection namespace SHA.

| Nested record | Exact fields and meaning |
| --- | --- |
| `collection` | `project`, `generation`, `floor`, `floor_anchor`, `manifest_sha256`; exact host-observed immutable root anchor |
| `record` | `key`, `revision`, `value_sha256`; alternatively null for an absence/empty/status/root dependency |
| `validity` | `recipe_sha256`, `lineage`, `source_versions`, `valid_until_ms`, `status`, `dependencies`; normalized only by a reviewed host recipe |
| Source version | `id`, `version`; bounded 32-hex source IDs or 64-hex content identities |
| Direct key dependency | `key`, `revision`, `value_sha256`; no recursive arbitrary JSON |

Hashes, IDs, key characters, safe JSON integers, nullable expiry and closed enums
are checked explicitly. Source versions/direct dependencies allow 32 entries
each, sorted by canonical digest without duplicate rows. Floor zero requires a
null anchor; a positive floor requires its actual operation ID. Imported floors
may exceed local generation. Null `record` keeps absence observations tainted;
it is not an eligibility escape hatch.

The reviewed validity recipe and actual current protected read are **not yet
implemented** by this checkpoint. A worker field alone cannot manufacture any
of these facts. The future host must derive suppression, expiry, overrides,
lineage and source versions from the pinned recipe and protected current values.

## Admission, inheritance and limits

`new/1` creates a Session-bound state. `union/1` canonicalizes host dependency
groups. `admit/5` proposes `managed_reference_admitted` v1 plus the next state,
binding Session, producer kind/ID/parent ID, effective-message position/hash,
dependency union/hash and deterministic occurrence ID. The caller installs the
next state only after its owning journal append succeeds.

`inherit/3` joins every selected parent's dependencies with additional host reads.
Missing or already withdrawn parents refuse. An invocation's final text/context
must inherit **all** admitted reads, not a worker-selected source subset.
Main assistant answers also need the entire dispatched input union. This includes
paraphrases that contain none of the original quote bytes.

| Resource | Refusal boundary |
| --- | --- |
| One normalized dependency | 8192 encoded JSON bytes |
| Direct publication/read occurrence | 128 dependencies and 128 KiB encoded union |
| Host-derived assistant/checkpoint | Up to the active dictionary's 2048 dependencies/4 MiB |
| Referenced dependency dictionary | 2048 distinct dependencies and 4 MiB actual encoded values |
| Occurrence index | 1024 occurrences and 4 MiB |
| Projection receipt | 12 MiB, independently below the ordinary 16-MiB maximum Journal record ceiling |

Only host-validated producer kinds distinguish direct and derived occurrences.
The message role is bound to that producer kind. Workers cannot label a direct
publication as an assistant answer to evade its limit. Dictionary entries are
retained exactly while an active occurrence references them. Capacity refuses
explicitly; there is no eviction or silent lineage truncation. Smaller configured
journal limits still apply and may refuse the proposed append.

## Plan and apply exact verdicts

`plan/2` binds current message hashes/positions, native pairing, the Session
occurrence index and canonical dependency union into a plan digest. It covers
historical occurrences as well as the newest selection.

`project/3` accepts exactly one host verdict per dependency digest, with fields
`dependency_sha256`, `status`, `current`. Status is one of `eligible`, `expired`,
`suppressed`, `root_changed`, `policy_changed`, `source_changed`, `unavailable`.
An eligible verdict requires a normalized current receipt; other verdicts require
null current data. Eligibility is exclusive at expiry: `valid_until_ms` must be
greater than the actual checked time.

A protected host may supply a fresh receipt proving an unchanged record at a new
root. The pure check preserves project, namespace, pin, policy generation, record
identity, recipe, lineage and source versions; it refuses generation/floor
regression and a different root at the same generation. This allows unchanged
content to remain byte-identical after unrelated publication. It does **not**
perform the required protected reread itself.

The closed binding records Session/turn/request IDs, phase, actual route and
ordered-tools hashes, source/policy generations, checked time and finite deadline.
The live owner must additionally retain its actual job/task lease and check time
again at dispatch; serialized bindings are not transferable capabilities.

Ineligible safe occurrences get a deterministic labelled placeholder. The
`managed_reference_projected` v1 record binds before/after message hashes, plan,
verdicts, request binding and each withdrawn occurrence's position/original/current
hashes. Native call/result IDs, order, count and untouched messages remain exact.
The original transcript bytes remain in the journal.

With no managed dependencies the original message list is returned without an
event. Eligible unchanged messages also remain byte-identical; their historical
projection receipt records the check without claiming perpetual freshness.

## Refuse unsafe projections and stale checkpoints

The generic projector refuses withdrawal of an assistant tool-call message,
opaque `provider_data`, unknown message fields, a derived checkpoint, or an
`ipse_result_excerpt` metadata copy. Real adapters duplicate text in native
continuations; changing only visible `content` would leave stale bytes. Existing
result excerpts also carry original prose in their metadata. A future proven
adapter/host projection may support these shapes. Until then, failure is explicit;
the component never strips a signed or opaque continuation and calls that safe.

`checkpoint/2` exports version-2 taint metadata over a bound complete prefix,
including its full union, occurrence IDs and prefix digest. It does not upgrade
the current Context checkpoint writer. On invalidation the eventual runtime must
reconstruct safely from retained original projections or refuse; a stale summary
must never become a new untainted assertion. The current checkpoint only supplies
the refusal path, not automatic safe-original reconstruction.

`replay_admission/3` recomputes admission after the caller verifies the committed
producer. `replay/4` requires the independently admitted dispatch binding and
recomputes the exact historical projection without IO. Its result explicitly sets
`live_pending: true`. Historical eligibility never authorizes another dispatch or
restarts an interrupted subscriber.

## Actual checks and first outcomes

All fixtures are newly authored synthetic JSON/messages. No qualification input,
private corpus, gold label, live account, model call, terminal or native helper
was used. No full suite or platform/native acceptance ran for this checkpoint.

Verification directory: `/tmp/ipse-managed-reference-20261026-01`.
The focused harness loads existing complete dependency/application BEAMs read-only
from `/tmp/ipse-collection-call-build-20261026-07`, then compiles only the new module
with `Code.with_diagnostics/1`. It rejects warning/error diagnostics and loads the
new test file. It does not mutate that prior build or other agents' artifacts.

| Receipt | Actual outcome |
| --- | --- |
| `tests-first.log` | Test compilation refused a fixture helper named `binding`, conflicting with Kernel; renamed import boundary before tests |
| `tests-second.log` | 16/17; encoded-size fixture could not reach its requested size, plus an unused fixture default; both repaired |
| `tests-third.log` | 17/17 |
| `tests-fourth.log` | 18/19; 128 normal-sized dependencies exceeded the independent 128-KiB limit; count-bound fixture made smaller rather than widening policy |
| `tests-fifth.log` | 19/19 |
| `tests-final.log` | 20/20; seed 267009; 12.2 seconds |
| `tests-verified.log` | Final 20/20; seed 558622; 12.5 seconds |
| `compile118-final.log` | Elixir 1.18.5 focused compile, diagnostics empty; host OTP 29 |
| `format118-final.log` | Both files match Elixir 1.18.5 formatting |

Current Elixir 1.20.4 formatting and focused compilation also pass. This is **not**
an OTP-27 run. The initial 1.18 formatter found one `with` layout difference;
an explicit range helper made both formatters agree. Initial harness compiler
option deprecation warnings were removed by using diagnostic capture. First
failure logs remain intact.

Tests cover zero-domain byte identity, closed/missing fields, absence taint,
imported floors, exact expiry, canonical unions and parent inheritance, normal
assistant paraphrases, unchanged-record root clearance and substitution refusal,
exact native pairing, opaque duplicate-prose refusal, coherent request/session
crossbinding, replay tampering, reference-counted release, forty turns of four
distinct notes, 2048 dictionary entries, 1024 occurrences, exact 8192-byte
dependency admission, 8193-byte refusal and actual aggregate dictionary bytes.

## Remaining integration gates

The host still needs a reviewed generic validity recipe, owner-bound protected
Collection read witnesses/views, invocation read accumulation and exact successful
publication pairing. Every main/continuation/compaction/extension inference needs
the live barrier after service-slot waiting and before durable dispatch admission.
Assistant SourceIndex eligibility must inherit dispatch taint. Checkpoint rebase,
safe excerpt/adapter projections, bounded original reconstruction, saved validators
and same-job cancellation/revocation races remain integration work.

Current manuals were reviewed as whole chapters for this checkpoint. Their public
runtime behavior remains unchanged because no production path invokes this module.
The eventual integration must reconcile the complete affected operator/developer
chapters before any sub-goal or milestone completion claim.
