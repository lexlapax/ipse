# Publish evidence through a protected collection

Use Collection when a reviewed extension needs local immutable generations,
bounded staged values and CAS. Start with [extension authoring](extensions.md)
and [Session evidence](session-sources.md), then choose the authority contract:

| Work | Host route and authority |
| --- | --- |
| Small explicit key/value state | Ordinary State approvals; see [State](extension-state.md) |
| Ordinary document storage | Fixed `collection.store` project binding and separate full-argument approval |
| Protected knowledge capture/read | Reviewed semantic mappings, saved policy and current source admission; one new v3 capture has its own admission scope |

This chapter owns the generic host boundary. Domain schemas, note eligibility,
projection algorithms and operator setup belong to the selected feature. The
ordinary document route does not inherit a saved capture grant, and a protected
export cannot lend its permission to ordinary writes.

An artifact capability, source receipt or policy-shaped JSON grants no semantic
permission. For protected knowledge, a fresh Session pins a previously reviewed policy and actual
project/artifact/routes. Active admission version 2 also saves the bounded original
reviewed policy, whose canonical hash must match the pin. It contains public route
disclosures and constraints, never credentials. The enclosing descriptor permits
64 KiB and sixteen lexical levels, including the policy wrapper; policy/settings
keep their existing limits. Ordinary SDK objects remain 16 KiB/depth twelve and
journal/header capacity still applies.
Legacy version-1 admission can resume inertly but cannot authorize a new protected
outer call. Resume preserves the original pin, including absence. Every live
read and publication checks the current protected policy again. Coherent hostile
rewriting by trusted same-user code is outside this cooperative integrity boundary.

## Follow one capture across its owners

Start with one new v3 record under the selected protected policy. The worker
request must pass `ManagedCollectionCall.new_capture?/1`: a completely valid
metadata-version-3 commit, exactly one new nonnil map and revision zero. Session
retains the complete host-owned inherited-plus-own dependency union. Every
root-only prerequisite must either match its own committed
current-parent snapshot/nil-get or have an exact positive host classification
derived from its original authenticated receipt/result pair. Cached classification
permits closed snapshots, explicit nil-gets and an initial empty metadata-only
index, never arbitrary index pages or record contents. All root-only members must bind one
identical complete root, project, pin, policy and expected generation. Scans,
mixed root-only observations, missing/false cache entries and unmatched results
refuse. These observations are
[CAS prerequisites](../archive/2026-10-26-p30-p31-implementation/notes-publication-prerequisites.md),
not current permission; the protected publisher rechecks that later.

An invocation that has read authenticated literal, historical or accepted-note
content takes the separate `Session.ManagedCapture` path for the same one-new-v3
shape. Structural admission preserves every inherited and own dependency; it
does not classify content as payload-free metadata. Before publication locks,
`ManagedUse.with_publication_dependencies/4` authenticates the current records,
recipes, policy and acceptance links, then retains original Session sources and
any original management journals together with the candidate's exact source.
The selected publisher acquires Identity, Consent and Collection in their normal
order. Its actual root witness must equal every provisional current observation;
a newer root requires a new attempt, never an implicit rebase of the candidate.

At the native mutation, the capture-specific Session ticket binds the original
parent, exact action and full dependency digest. `Runner.SessionSource` transfers
the consuming Session, drained Writer and original source owners into that same
transaction; accepted references additionally import their management journals.
The earliest source, policy and normalization deadline limits the native final
decision. All source/control scopes and Identity must close before deferred
settlement can release unused input. Loss keeps the operation uncertain, including
when Session stops before an action result can be appended. Saved retains the
original dependencies without reconstructing a publication permit.

The current native Session controls cover a genuine literal A followed by a new
unattended-input B proposal, source/policy withdrawal after B delivery and loss
of A's native owner after staging. B remains attributed and never-current until
its separate acceptance; the full conversation union still contains A. These
controls do not qualify historical/accepted-note publication combinations,
maximum source counts, all later-use sinks or complete capture quality. See the
[capture integration record](../archive/2026-10-26-p30-p31-implementation/current-source-capture-publication-20261102.md).

`/remember` obtains a fresh native statement/category confirmation before this
path. Its terminal-client positive covers one new literal. A later direct
authorized-client headless control saves a genuine typed host outcome with the
earlier recall-root dependency preserved. The
[causal-root implementation](../archive/2026-10-26-p30-p31-implementation/causal-root-cache.md)
and [reviewed direction](../archive/2026-10-26-p30-p31-implementation/causal-root-and-source-tools-direction-independent-review.md)
explain that bounded historical classification; the
[implementation review](../archive/2026-10-26-p30-p31-implementation/causal-root-cache-independent-review.md)
accepts that scope. Model-selected source tools now preflight all actual selected
provenances before lookup and rederive them at result admission. Even an initially
empty call must classify its complete selected union. Only truly empty or
authentically cached payload-free same-root dependencies continue; missing
producer/cache state and record-bearing data refuse. Starts suppress source
arguments and subscriber results use a fixed status-only preview. The
[source-tool review](../archive/2026-10-26-p30-p31-implementation/managed-source-tool-preflight-independent-review.md)
accepts this bounded source/preview and inherited-root implementation. After a
known new-v3 capture, the host can preserve prior root-only observations as
historical while guarding subsequent use with its exact own adjacent successor.
It checks the original complete write union, fresh snapshot, actual own receipt
and floor anchor, then resolves both active observations and producer/call
obligations through that same successor. Original dependencies and messages stay
unchanged; an independently guarded notice explains their historical meaning.
Record contents, mixed roots, missing cache and unknown or intervening writes
refuse. The [own-write implementation review](../archive/2026-10-26-p30-p31-implementation/own-root-transition-independent-review.md)
includes an actual synthetic-model turn that captures, performs later source
reads and completes successfully. Full notes and provider qualification remain
separate; the earlier settled-but-failed turns retain their original scope.
The [admission review](../archive/2026-10-26-p30-p31-implementation/notes-publication-implementation-independent-review.md)
and [earlier controls](../archive/2026-10-26-p30-p31-implementation/remember-terminal-headless-controls.md)
retain their original scope. Ordinary Collection storage and document grants confer no
saved semantic authority.

[`SemanticAdmission`](../../lib/ipse/extension/semantic_admission.ex) admits an
outer tool or command outside the Session GenServer. The check holds the actual
ProjectIdentity and Consent locks, requires the exact active pin and artifact,
honors execution ceilings, and derives the outer class from the exact exported
descriptor's mappings. Any publication mapping keeps that export mutating and
requires a constrained publication mapping. An export with only read mappings can
enter under the read class, including planning mode. It permits entry to the
reviewed worker only. The host repeats that current check before worker startup.
A supported publication request from that read-class export is still denied,
including under ordinary `--yes`; neither Consent accounting nor the Collection
generation advances. Test that permission boundary with a supported request:
refusal of an unsupported legacy shape before intent does not exercise it.

The worker requests source list/read/quote through its normal action chain and
constructs a candidate value. [`CollectionCall`](../../lib/ipse/extension/collection_call.ex)
validates legacy storage requests;
[`ManagedCollectionCall`](../../lib/ipse/extension/managed_collection_call.ex)
validates explicit managed publications. Session records the exact inner intent
before any reservation or storage effect. A private Session query rederives all
quote proofs from the current writer-owned source window. JSON cannot select the
project, namespace, policy, origin, operation label or constraints.

The host selects exactly one current mapping matching the outer descriptor,
inner operation, actual candidate keys/schema and resolved source origins.
[`CollectionPolicy`](../../lib/ipse/extension/collection_policy.ex) applies its
reviewed prefix, closed value schema, evidence field path, allowed origins and
deletion rule to every change. Missing or ambiguous mappings refuse. One strong
source cannot upgrade other sources in a mixed batch.

ProjectIdentity remains locked while the host reserves and admits protected
work. Legacy `Consent.publish` and managed `Consent.publish_deferred` recheck the
pinned policy under the control lock. Their callbacks rederive current source
proofs and apply constraints again before the short Collection transaction.
Managed settlement waits until the enclosing source scopes, Identity checks and release succeed.
Lock order is ProjectIdentity, Consent, then Collection. Slow IO runs in owned
effect workers, never inside Session.

For metadata version 3, the publication authorizer receives the fresh/active
selection from that same retained Identity transaction. It checks native root
absence only for first use, before prepared state is written. An earlier busy
verifier is no initialization evidence. Active domains still require their
authenticated format; prepared domains refuse without retry. The
[storage walkthrough](knowledge-storage.md#publish-one-fresh-record-with-authenticated-metadata)
connects this selection to the actual Collection witness and final activation.

For the new-v3 shape, `Collection.with_notes_publication_deadline/2` installs a
trusted same-owner [admission scope](../archive/2026-10-26-p30-p31-implementation/notes-publication-admission.md)
around that existing publisher. The authenticated policy
deadline and the v3 normalizer's original nullable lineage deadline narrow the
native owner's final locked root-switch decision after synced staging. An expired
decision refuses; an admitted switch may physically finish later. Nested scopes
preserve the minimum and restore previous state on exit. This scope grants no
source or Consent authority and never renews a source clock.

Generic strict `publication_deadline_admission/1`, `with_publication_deadline/2`
and notes-profile `execute_profile_before/6` remain refused. The legacy
`collection.call` publisher uses the same notes-profile final-decision mechanism
after its own source, exact mapping, mode and Consent checks. Its unmanaged
storage entry refuses a managed namespace; this does not enable managed
replacement or supersession. The action gate retains the one-new-record predicate
for `collection.managed`. Selected native management routes use their own review
and publication checks. A direct Core component positive does not qualify every
public source, later-use sink or full notes readiness.

## Declare the narrow operations

Declare and explicitly trust `host.actions` plus `host.collection.read` and/or
`host.collection.write` for the legacy protocol. Explicit managed publication
requires `host.collection.managed`; read/write grants do not imply that capability.
Source evidence additionally needs `host.sources`.
These declarations do not create a saved policy or activate an old Session.

A read request is:

```json
{"api_version":1,"kind":"host_call","request":{"op":"collection.call","request":{"op":"snapshot"}}}
```

The closed inner read operations are `status`, `snapshot`, `get`, `inspect` and
`scan`, with the argument schemas of
[`Collection.valid_request?/1`](../../lib/ipse/extension/collection.ex).
`scan` narrows the internal limit to 1..4. It keeps complete records and returns
an actual last-key continuation when the complete action reply would exceed
16 KiB. It never slices a value. Follow that returned key with the same generation;
a conflict requires deliberate fresh inspection, not an automatic retry. The host
filters `host.validity.*` keys from validated metadata before selecting any values
under that one native lock. Returned continuation keys name only actual public
records, including an empty public view. Direct gets, scan-after keys and commits
in that reserved namespace refuse at the SDK boundary. Internal operator
`Collection.execute/4` remains a separate raw storage API.

`status` exposes fixed aggregate counts and opaque migration/checkpoint IDs plus
digests of their complete control metadata. Import plans, retained keys and
private continuation keys are not disclosed. The complete projected action reply
must still fit; otherwise it returns the fixed `collection_result_limit` failure.
Read actions use the explicit 512-read/two-minute bounds and consume no Consent
period IDs. `host.actions.mixed` separates 512 reads from sixteen other actions;
without it, the existing cumulative action-family limits still apply.

A **legacy** publication request has exactly these outer fields:

```elixir
%{
  "op" => "collection.call",
  "request" => %{
    "op" => "commit",
    "expected_generation" => generation,
    "advance_floor" => false,
    "changes" => [
      %{"key" => "pending.example", "expected_revision" => 0, "value" => candidate}
    ]
  },
  "proofs" => [%{"handle" => evidence_handle, "quote" => exact_text}]
}
```

This is a callback fragment: use the actual schema/key prefix in the reviewed
policy and actual source handles. Every commit, including deletion, requires
1..8 distinct closed proof requests. A commit permits at most eight changes;
the entire encoded request, including handles, candidate evidence and escaping,
must fit 8192 bytes. The general SDK object remains 16 KiB. No truncation or
request rewriting makes a proposal fit.

Every replacement (`expected_revision > 0`) or deletion requires explicit
`advance_floor: true`, checked both before intent and under publication policy.
Fresh unique revision-zero inserts may use false. A collection's imported lineage
floor can exceed its local generation; these are separate counters. Worker
migration, import/export, rollback and maintenance operations are unavailable.

## Stage ordinary documents under their own grant

Use `collection.store` for the fixed document profile. This is a separate ordinary
approval contract, not a `collection.call` proof batch or saved capture consent.
Declare `host.actions` and `host.collection.store`. Operator trust supplies
`collection_bindings` with the selected instance, ID `documents`, project scope
and profile `document_graph_v1`. The host resolves an already admitted project;
worker arguments cannot choose a namespace, profile, path, quota or project grant.
`extensions/knowledge/config.exs` derives this trust entry for the
`collection-documents` preset from its options. It takes no collection-binding
flag, and a Collection-only preset takes no State binding.

Trace [`CollectionStore`](../../lib/ipse/extension/collection_store.ex),
[`DocumentStage`](../../lib/ipse/extension/collection/document_stage.ex) and the
fixed [`Profile`](../../lib/ipse/extension/collection/profile.ex) together.
CollectionStore binds the actual project/session, artifact identity, invocation
and exact request before Session journals an action. Ordinary mutations show
full approval arguments. For example, the callback's inner request uses observed
generation/revision and a hash of the complete original encoded value:

```elixir
original_sha256 = Base.encode16(:crypto.hash(:sha256, original_bytes), case: :lower)

%{"op" => "collection.store", "scope" => "project",
  "request" => %{"op" => "value.open", "slot" => 0, "epoch" => fresh_epoch,
    "key" => actual_key, "expected_revision" => observed_revision,
    "generation" => observed_generation, "byte_count" => byte_size(original_bytes),
    "sha256" => original_sha256}}
```

Opening is not permission to finish later. Sixteen reusable slots bind a random
epoch, actual project/session/artifact, opening invocation, target/revision,
original byte count/hash and one-hour expiry. A complete body is at most 60 KiB;
each append part is at most 6 KiB and there are at most ten parts. The unchanged
16 KiB SDK envelope and 8 KiB string bounds can require smaller parts after escaping.
Append requires the exact next offset. Seal checks all original bytes, hash,
duplicate-safe JSON and ResultDocument validity before selecting a sealed stage.
Explicit continuation may use a later invocation in the same exact owning
session/identity; it retains the opening invocation as provenance.

`commit` consumes up to eight exact sealed references and publishes their target
values while deleting header/ready records in one generation/revision CAS.
The host's internal plan permits at most 32 changes; the ordinary notes commit
still permits eight. Reads, reclaim, abort and slot reuse do not rebase a staged
target. A stale generation, changed owner/epoch, wrong hash or duplicate consume
refuses. Expired reclaim requires the exact expired epoch, runs under the same
Collection lock and cannot overtake an earlier native mutation.

Small `value.put_inline` and `value.prepare_inline`, and bounded multipart
`value.write_parts`, reuse this fixed grant. Prepared values remain unselected
until their consuming CAS. Fused packet transport does not increase value,
string, request, stage, namespace or approval limits. `document_store` capability
metadata is a negotiation result, never permission to invent a larger packet.

For a metadata inventory, the same document read grant accepts `value.index`.
Start at a checked snapshot generation with a null cursor:

```elixir
%{"op" => "collection.store", "scope" => "project",
  "request" => %{"op" => "value.index", "generation" => observed_generation,
    "after" => nil, "limit" => 16}}
```

Each page returns complete public descriptors containing `key`, `revision`,
`record_sha256` and `record_bytes`, together with the checked generation/floor,
public count, `next` cursor and `coverage: "public_document_records"`. The hash
and size describe the physical packed record; they differ from `value.stat`'s
logical original-body hash and byte count. Inventory opens no value object and
does not establish that its bytes or semantic references remain valid. All
`host.*` keys, including other invocations' stage metadata, are excluded before
selection and counting. A private cursor refuses.

Request at most sixteen descriptors and continue only with the returned cursor
at that exact generation. Pages shrink by whole descriptors to the 4 KiB result
bound, so do not assume every nonfinal page contains sixteen rows. A changed
generation conflicts; begin a fresh scan explicitly rather than joining pages
from different roots. A single page or caller-chosen cursor is not complete
coverage. This read requires no mutation approval and grants no deletion,
maintenance fence, export or migration authority.
As with the existing Collection snapshot path, inspecting an absent store can
create its private directories and persistent lock file; it does not publish a
document value or root. Leave that lock inode in place.

To inspect one selected object's original packing, request `value.layout` at
the same captured generation:

```elixir
%{"op" => "collection.store", "scope" => "project",
  "request" => %{"op" => "value.layout", "key" => actual_key,
    "generation" => observed_generation}}
```

The response returns the checked summary, key and a closed version-1
`document_packed_layout_v1` descriptor. Its `record_sha256`/`record_bytes` identify
the exact encoded immutable object verified by Core. Its `sha256`/`byte_count`
identify the logical concatenation of the stored parts. One through ten ordered
part descriptors retain each original offset, count and hash. Existing
`value.read` slices can cross those boundaries. Two packings of identical
logical bytes can therefore have different physical hashes and layouts.

An absent public record returns `layout: null`; stale generations, private keys,
corrupt objects and invalid packed/logical values refuse. The existing read
grant and budget apply, with no mutation approval. The bounded descriptor
contains no body, path or extra authority. It supports faithful export planning,
but is not a complete export or GC/migration grant: a future writer must still
copy or reproduce the exact physical bytes and check their digest. Whole-store
document migration and its operation/allocation accounting remain separate.

Host code that must keep a document view current can use
`Collection.with_document_read/3`. It retains the actual fixed-profile native
owner through a trusted same-process callback and allows at most 512 key-only
record reads. It exposes no scan, mutation or worker callback; escaped/foreign
readers and nested owners refuse. The notes `with_managed_read/3` path keeps its
separate 32-unit bound. Exhaustion and owner loss prevent known success.

Inside the retained document callback, `DocumentStage.read_value/2` validates the
physical packed wrapper, complete ordered parts, byte count and body hash, then
decodes the complete logical object with existing duplicate-key/structural checks.
It returns logical `sha256`/`byte_count` plus actual native revision and committing
operation ID. Those logical hashes differ from `value.index`/`value.layout`'s
physical record hash. Absence returns nil; corrupt or escaped reads refuse.
These [reader](../archive/2026-10-26-p30-p31-implementation/document-held-reader.md)
and [complete-value](../archive/2026-10-26-p30-p31-implementation/document-held-value.md)
primitives establish owned transport, not source eligibility, inference permission
or whole-workload memory qualification.

### Decide expiry at the actual native owner

For each append/seal/consume/fused mutation, DocumentStage takes the minimum of
the original slot expiry and every trusted inherited deadline. Nested scopes
can narrow but cannot clear or extend that minimum, and restore their exact
previous value on every return. Collection's document-only deadline entry carries
it through complete synced staging to `Transaction.switch_before/4`.

The same native process owns the retained Collection lock, checks staged inode
and target safety, samples the wall clock immediately before the fixed root
replacement, renames and syncs the directory. Equality/expiry refuses that new
decision. An admitted replacement may physically finish after expiry; no
clock-atomic rename or physical completion timestamp is promised. The native
elapsed reply contains an error code, not State's `checked_at_ms` receipt.
Any failure after staging remains conservatively unknown, because immutable
objects or the active root may already have changed. Final native check and
acknowledged release precede every known result; no automatic replay follows loss.

Ordinary State uses its own restored locked-decision contract and richer typed
elapsed result; see [State](extension-state.md#bind-a-prepared-write-to-its-targets-expiry).
Neither contract removes the separate managed-source/output gates. Invocation
refuses a managed `collection.store` mutation before intent or approval. At
execution, CollectionStore also refuses every mutating request whose trusted
`ManagedToolUse.with_effect` callback supplies a non-null deadline. Only an exact
empty dependency union takes the ordinary nil branch; unavailable, corrupt or
missing-dictionary lineage is managed/refused. No worker flag selects the branch.

## Continue a supplied shared generation

The document grant supplies transport; shared projection policy stays in the
knowledge extension. Read [`Collection.Job`](../../extensions/knowledge/src/store/collection/job.ex),
[`Finalization`](../../extensions/knowledge/src/store/collection/finalization.ex),
[`Reduction`](../../extensions/knowledge/src/store/collection/reduction.ex),
[`Paged`](../../extensions/knowledge/src/store/collection/paged.ex) and
[`Selected`](../../extensions/knowledge/src/store/collection/selected.ex) as one
worked continuation. None grants later-use source authority or makes an inference
request. Supplied vector/fact identities must be checked separately from model
receipt provenance.

Corpus exposes two exact command contracts in the `collection-documents` preset:

| Export | Arguments and result boundary |
| --- | --- |
| `projection_selected` | `store`, 1..8 unique `source_ids`, exact `vector_selection`/`fact_selection`, `as_of_ms`, `top_k` 1..8; hydrates complete selected groups and source bundles before returning bounded eligible facts/citations in stored order |
| `generation_job` | `store`, `action` in `begin/inspect/abort/finalize/finalize_paged`, `continuation`, exact `vector_selection`/`fact_selection`, optional `response`; known intermediate progress returns a complete next command |

The vector selector binds `selection_sha256`, `profile`, `model`, `dimensions`
and canonical `float32le` encoding. The fact selector binds the extraction
identity; explicit facts use `{"kind":"explicit","profile":null,"version":1}`.
Selected reads recheck the complete manifest chain, group page hashes, source
heads, catalog generation/floor, selectors and native generation. Every supplied
vector input and fact citation is reconstructed against its exact source chunk.
They report partial-document warnings and fact-window exclusions, not a synthetic
similarity ranking. Read hydration uses at most 512 calls and zero effects; a
wide selection can exhaust the budget and refuse without partial evidence.
Group packing splits pages on both logical JSON size and the native packed-value
limit, including escaping. A single row that cannot fit refuses before publication.

A job begins against one coherent captured catalog and old selected root.
`inspect` returns its retained physical revision and recovery token. Group append
is a private validated adapter operation, not a public Corpus action. It verifies
the exact captured source/head order and model/extraction selectors, then stores
immutable units before advancing job/captured-catalog metadata together. A public
`begin` does not populate those groups or complete a build by itself.
Append returns a known continuation after preparing each metadata stage. Those
stages retain their original Session ownership and expiry; only the final
continuation verifies both stages, the captured selected root and all immutable
prerequisites at one native generation before the atomic switch. A continuation with live stages is not a
fresh-Session handoff or authority to replay an unknown effect.

For repeated public steps, select `response: "compact_v1"` explicitly. The
default `full` response keeps the complete Job in `coverage.job`. Compact output
instead puts a versioned `shared_generation_progress` object in
`coverage.job_progress`, with the complete logical Job digest/byte count,
catalog/root and selection bindings, source/cursor/fact counts and reduction
scalars/reference counts. It preserves outcome, stale state and the exact
continuation. The digest is not the packed physical record hash, a complete Job
or a capability; choose `full` when the complete value is required. The worker
removes this presentation option before calling the same controller, so it
cannot change approval, publication or recovery behavior. Returned commands
retain the response mode.

`finalize` advances version-two jobs through bounded manifest batches, entity-run
merge, source-head digest, entity-row digest and selection. A reducer accepts at
most sixteen captured group summaries per batch and merges at most eight runs;
entity pages contain at most 64 rows. It requests exact missing immutable inputs
instead of hydrating the whole namespace. Finalization preserves version-one job
inspection and existing directory formats.

Choose `finalize_paged` explicitly from a complete captured version-one job in
its `manifests` phase, before starting the older reduction. This creates Job3
and eventually Root2; it does not convert a partially reduced Job2 or silently
switch when a budget runs out. Subsequent continuations must keep that action.
The paged recipe uses 32-row entity/run pages and a named ordered-page commitment
instead of v1's flat entity-row digest. Each durable step validates one complete
entity page and advances a closed cursor/count/last-ID state. Every resumed
metadata position reconstructs its semantic input before staging. Root2 readers
validate global page order, canonical IDs and memberships; older readers refuse
the new root version. Both paths retain the existing source-head digest and
manifest/group/source formats.

Continuation tokens bind job ID, physical job/root revisions, captured catalog,
complete plan digest, unit position and exact stage progress. They are inspected
data, not capabilities. Resuming at a later position still verifies every required
immutable predecessor. Each invocation retains 512 reads and sixteen effects;
known partial progress yields an explicit next command, and unknown stops without
one. Do not edit a token to skip work or automatically replay a failed phase.

Before final selection, the controller checks complete manifest/entity-page hashes
and sizes, prepares exactly job/catalog/selected-root stages, rechecks prerequisites
at their sealed generation, then sends `value_commit_at` with that **same** native
generation. Refreshing the epoch after proof would defeat CAS. Only that final
three-stage commit changes selection; earlier phases retain the old root.

Small actual Session controls cover both root versions, stale final approval
and interrupted publication without replay. The maximum-width paged final-call
protocol model includes all nested calls, but neither it nor that small native
journey qualifies the complete shared build. Full 1,000-source/20 MiB evidence/
10,000-chunk/5,000-entity/20,000-assertion geometry, rebuild overlap, total native/
journal peaks, GC/job reclamation, migration/floors and installed Word fidelity
remain unqualified. The fixed 8,192-key/32,768-operation/192 MiB document limits and
256 MiB combined target are not raised by staging or continuation. Keep synthetic
initial data, actual reads, proposed writes and successful native effects distinct.
In particular, the public command does not yet provide the bounded producer
that feeds supplied groups into private append. That integration must fit both
storage operations and the Session journal; a successful finalizer alone does
not supply it.

The separate opt-in `collection-dense` artifact offers `generation_produce`
action `selection` with exactly `store`, `version: 1`, `action: "selection"` and
the configured embedding alias. This read returns `configured_profile`, its
selection digest and `reported_model: nil` without inference or a Usage charge.
Producer calls propagate that digest as `expected_selection_sha256`;
legacy unpinned adapter requests retain their exact shape. A pin prevents a
changed configured route from reaching inference but supplies no source authority.
Version-1 public `page` uses the same bounded v3 first-page producer qualified through the
private fixture artifact. It durably commits a claim before inference, then sends
`source_guard` with version 1, exact `claim_key`, `claim_revision`, `claim_sha256`
and zero-based `batch_index`. It supplies no committing operation ID: Host reads
that from the actual retained record and requires the matching confirmed action
in this live invocation. Each batch reauthenticates source slices, source times
and job/catalog/root before final egress admission after approval. A confirmed
claim alone cannot authorize another Session or repeat an uncertain batch.
Version 2 instead uses v4 reusable slots and guard version 2. The Host observes
actual absence or an exact closed prior ready row before the inline claim CAS,
then binds its known committed result to the live invocation. A returned public
continuation supplies the next cursor and prior ready descriptor; it grants no
authority without that new claim and source admission.

The same v2 binding also fences the private explicit fact-projection commit.
Its `collection.store` request carries `source_guard: "explicit_fact_projection_v1"`
and a two-stage `commit` at the inspected generation. After approval, Host
authenticates the sealed stages, source and catalog under the retained document
reader, rechecks the live Session, and uses the earliest source or stage expiry
for the native commit. Multipart input uses `explicit_fact_input_v1` on a
generation-bound inline write to one of eight `factdraft.` slots; Host checks
the page, manifest and current source before deriving its deadline. The
selected identity cannot publish `facts.` or `factdraft.` records by omitting
their guards. The dense Corpus
`generation_produce` action `facts` accepts explicit fact fields and compact
`[chunk ordinal, start byte, end byte]` spans, reconstructs canonical citations
from the selected source, and returns staging continuations. The guard does not
certify fact truth or model provenance. This action does not complete group
append, model extraction or full-capacity qualification. Admission limits the
encoded arguments with a null continuation to 12,000 bytes, reserving room in
the 16 KiB Session envelope for the staged-write checkpoint. Wider explicit
input uses `facts_page` and `facts_commit`: the latter rereads fixed slots at
one generation and validates the full ordered manifest on each continuation.
`facts_slots` reads revision descriptors without loading draft contents. The
local planner at [plan_fact_input.exs](../../dev/knowledge/plan_fact_input.exs)
prepares pages from an exact source record and fact rows; it grants no authority.
Individual synthetic Session controls cover a full-width 32-fact projection,
but do not qualify the populated multi-source resource peak or cleanup.

This requires an explicit operator binding v2 with
`source_use: shared_producer_v1` and a registered inference route. All embeddings
from that identity require guards, so unguarded query embeddings belong to a
separate v1 instance. The fixed-choice generator flag selects v2 only on
`corpus/collection-dense`; its absence preserves old bindings. An unsupported v1
producer can leave a pending claim then refuse inference without egress. `inspect`
is read-only; pending/unknown and legacy claims provide no replay/adoption token.
The [public adoption review](../archive/2026-10-26-p30-p31-implementation/shared-producer-public-adoption-independent-review.md)
accepts the canonical route by exact source/descriptor comparison and build/protocol
controls, separately from the native-tested private artifact.
The [actual Session cases](../archive/2026-10-26-p30-p31-implementation/shared-producer-guard-session.md)
and [finite-TTL positive](../archive/2026-10-26-p30-p31-implementation/shared-producer-finite-guard-session.md)
prove the stated synthetic first-page flow. A separate [v4 two-page Session](../archive/2026-10-26-p30-p31-implementation/shared-producer-v4-public-session.md)
uses an initially empty root. Neither proves facts, group completion, historical
model provenance or full capacity. Short locked admission permits
already-admitted bytes to remain in flight after a later source change.

## Publish with host-computed validity metadata

Use `collection.managed` only with an explicit settings-v2 policy and the
`host.collection.managed` capability. A callback submits:

```elixir
%{
  "op" => "collection.managed",
  "recipe_sha256" => reviewed_recipe_sha256,
  "request" => %{
    "op" => "commit",
    "expected_generation" => generation,
    "advance_floor" => true,
    "changes" => [
      %{"key" => actual_key, "expected_revision" => 0, "value" => candidate}
    ]
  },
  "proofs" => [%{"handle" => evidence_handle, "quote" => exact_text}]
}
```

The worker's recipe hash is a selection hint. The host resolves the current
protected registry, authenticates every source, and requires exactly one matching
mapping/recipe for the actual key, schema and origins. Missing or ambiguous
matches refuse, including an apparently stronger recipe selected by the worker.
The original request is hashed and journaled unchanged. The complete request still
fits 8192 bytes and carries 1..8 proofs. Structural validation permits eight
changes; this worker publication path supports **one new record** only. It cannot
replace/delete records or accept existing proposals. Typed standalone host
management uses the separate normalizer entry points described below; a worker
cannot select them by changing its publication request.

`advance_floor: true` is mandatory even for a first insert. It fences older
backups that lack retained source clocks. The host never rewrites a false value,
its hash, or its approval. Legacy `collection.call` is not promoted into this
protocol.

Inside `Consent.publish_deferred`, current source proofs and reviewed constraints are
checked again. `Collection.execute_managed/6` then checks the original generation,
revision and operation ID under one native collection lock before invoking the
trusted `Collection.Normalizer` for the version-2 request shown above. A request
with `metadata_version: 3`, used by the native Knowledge artifact, instead uses
`execute_managed_v3/6` and `NormalizerV3`; source-dependent capture uses the
host-only `execute_managed_capture/7` variant with the retained owner handoff above.
Its authenticated pages and receipt
have version 3 and can require up to five sidecar changes. In both paths the read
closure is host-only and expires when the callback returns. The normalizer
derives literal identity and exact quote support, or a proposal identity and
finite pending deadline. It ignores worker clocks and preserves separate
first-note and first-proposal anchors. Capacity refuses rather than evicting an
anchor. Legacy raw override JSON cannot stand in for an unimplemented typed
operator choice.

For version-2 and version-3 proposals under `pending.`, the host also checks the
retained count and encoded bytes under that same Collection lock. Its fixed-prefix metadata summary
walks at most 64 already-loaded references without reading values, charges eight
of the callback's 32 read units, and refuses a new proposal at 64 records or above
256 KiB including the candidate. The summary does not grant source authority or
purge expired proposals. Version-2 recipes with other prefixes and other
publication routes need their own admission and capacity rules. A legacy
pending publication can now refuse when the retained queue is already full;
existing journal outcomes are not replayed or retroactively changed.

The success value contains `version: 1`, `binding`, `normalization` and `receipt`.
The binding hashes the original request, recipe and normalization receipt. The
durable receipt hashes that binding and the explicitly normalized commit, and
carries generation/floor. Storage wire version 5 preserves the managed binding;
legacy receipts retain their original formats. Worker replies omit sidecar values
and keep the complete action continuation within 16384 bytes.

These are publication and historical-integrity facts. Raw collection reads and
normalization metadata **do not establish current managed eligibility**. Managed
reads, host-derived producer lineage and owned inference use have separate checks
below. Do not expose a stored `current` label as a freshness guarantee.

## Manage a retained note through native review

Standalone `CLI.Knowledge.Management` derives its project, namespace and management
epoch from actual protected state, selects the installed literal recipe, and
authenticates the selected record. For faithful local preparation, the host can
retain the exact management snapshot with
`Consent.with_existing_management_snapshot/5`, then authenticate the target
inside `ObservedRead.with_managed_record/7` while retaining its Collection owner.
Both belong inside the actual Identity/domain-auth callback. The result is a
stored historical snapshot: it does not renew source eligibility or endorse its
contents. Native journal/tty ownership, complete lease closure and the actual
Review input remain separate and are not enabled by those read APIs.
For note management, `ObservedRead.with_managed_note_record/7` also admits a distinct
accepted-decision target. It authenticates the type-3 signed live row, matching
anchor and same-root immutable acceptance link. The note's sealed value hash
binds that link's exact bytes. `PendingAcceptance.retained_decision_metadata/5`
checks their closed identities and original proof consistency without loading
the original review journal or claiming current source eligibility. This is
historical target inspection, not the version-6 current-use reader.
It cannot relabel an accepted decision as a literal or authorize later delivery.
Public acceptance results and acceptance-journal inspection expose
`accepted_note_key`, derived from the validated native event through
`PendingAcceptance.accepted_note_key/1`. This lets an operator address the target
without a raw Collection lookup. It is an intended identity, not a publication
receipt or current-use proof; inspection retains separate status fields.
`ManagedLifecycle.prepare_retention/4` constructs exact review facts and selects
the literal or accepted representation from authenticated metadata. Its
session-only branch uses `prepare/3` for literal forgetting or
`prepare_accepted_forget/3` for an accepted decision. The latter binds the complete
accepted target and distinct fact kind to one deletion. Literal-only preparation,
correction and supersession still refuse that representation. None of these preparations grants
authority. Native `Runner.Review` binds a volatile
same-owner permit to the complete display and fresh confirmation. Original source
availability and capture TTL are not preconditions for reducing stored authority.
Normal execution ceilings and explicit denial remain enforced.

The public `knowledge forget NOTE_KEY` path uses an owned Resources scope and
private management journal. It prints that journal ID before the complete native
review, so an interrupted caller can inspect the operation. The writer reserves
terminal-record capacity before review
and syncs intent before storage admission. `Consent.forget_deferred/8` uses the
exact existing management epoch/fingerprint and actual live review. This separate
host-only path permits a bounded one-record forget after capture expiry/revocation;
it does not mutate through `with_policy`'s read callback or grant other effects.
It marks its finite operation publishing before entering Core.

`NormalizerV3.forget/3` and `forget_accepted/3` recheck their distinct signed
record/root representations and consume the permit inside the native transaction
before deleting the selected public/live rows and retaining signed lineage
suppression. The accepted branch rechecks the same-root link, then uses the
existing exact-target retirement encoding to bind the removed key and value hash;
the immutable link remains. It does not change the storage format or native ABI.
The caller captures actual normalization
sizing in that same process and checks the returned Core binding. Settlement
waits for Identity finalization and release; success also requires journal close,
retained-lock release and owned-resource cleanup. Uncertain effects never replay.
The original Session, original acceptance journal, shared evidence and new
management review journal remain. An unavailable original source does not block
this reducing operation. It supplies no current-use permission, and an uncertain
forget is never automatically replayed.

For retention, the CLI translates `automatic` to the exact
ordinary 90-day policy, or validates an explicit positive duration, pin or
session-only choice. `Consent.retain_deferred/8` shares the management state
machine but binds `collection.retention`, the retention fact kind and actual
policy-specific native command; it cannot reuse a forget permit. Session-only
uses the matching forget path, including accepted decisions.
`NormalizerV3.retain/3` performs a same-value CAS with a new
record revision and signed choice capsule, retaining original source/admission
clocks and publication policy. Ordinary/duration deadlines use actual native
confirmation time, as the displayed relative rule promises. Expired targets
refuse non-session changes both before review and under the final native lock.
The normalization receipt retains the earlier old/new finite deadline.

Accepted retention uses the distinct `managed_accepted_decision_retention` facts
and `NormalizerV3.retain_accepted/3`. Its original same-value request checks the
exact immutable target under the Collection lock. The normalized mutation contains
only bounded signed anchor/live changes: the public note, revision, operation ID
and immutable acceptance link stay unchanged. The specialized retention validator
checks the target value hash and reuses the V3 metadata bounds. Generic managed
execution refuses this receipt kind; the owned native retention entry must bind
the actual Review, synced intent, live Writer and final publication deadline.
Accounting conservatively includes the original target assertion and actual
metadata/receipt bytes without changing generic SDK accounting admission.

The retained reader validates the native choice against the exact accepted value
hash and unchanged first-admission clocks. Current reads retain original event,
link, source and policy verification, while their version-6 acceptance reference
adds a closed `retention` witness with the choice hash, policy and confirmation
time. Later use recomputes that witness from authenticated current pages. A
reference without it still matches the recorded accepted deadline; the new
witness binds its effective deadline without rewriting the accepted value.
The original record/link revision equality and source-version checks remain.
The existing IMB2 bytes now admit the pin category for note-only accepted rows;
history and pending combinations remain refused. Earlier source decoders with
the 0..2 accepted-category restriction refuse accepted pins, and earlier reference
readers refuse the new witness. Installed upgrade/downgrade qualification remains
separate.
Generic managed mutation still refuses retention and supersession. The public
pin, ordinary and duration choices instead claim the exact review and bind the
synced management intent and its live journal owner through the timed native root
decision. Session-only uses the same reducing path as forget. Public forget uses its distinct
full-facts reducing path and has a
[current-source integration review](../archive/2026-10-26-p30-p31-implementation/management-forget-current-source-independent-review.md).
Its availability does not enable generic retention APIs. Review consumes a live
permit once and withholds success after expiry/loss; it does not promise rollback
of an already admitted effect. Complete managed-fact display additionally needs actual
source/policy lease ownership through the native output sink and acknowledged
closure. The distinct faithful local management purpose permits review of the
explicitly selected retained target, including expired/revoked capture, under
current project/management-epoch/Collection ownership. It must label historical
source/expiry limits and cannot lend that authority to recall, model/MCP egress
or worker delivery. Public forget retains that native display chain; an ordinary
capture admission does not substitute for its fresh Review.
Elapsed-policy reclamation has a separate path. Preserve
earlier stages and unknown operations for inspection without automatic retry.

Authenticated reads interpret that capsule through the pure `ManagedRetention`
module. The effective category/deadline may differ from the unchanged public
capture fields. Existing dependencies retain their old revision and deadline;
only a fresh authenticated read can establish the new choice. Pinning does not
change a worker's origin category or authorize a stronger automatic recipe.

For `knowledge expire NOTE_KEY`, the same management owner authenticates one
already expired effective literal/history policy or accepted-decision deadline.
`prepare_expiry/3`, `prepare_history_expiry/3` and `prepare_accepted_expiry/3`
derive exact target/root/metadata and deadline facts;
`Consent.expire_deferred/7` admits one
zero-service operation under the existing positive management epoch, even with
capture disabled. Its shape/clock checks do not authenticate stored metadata.
The matching `NormalizerV3.expire/3`, `expire_history/3` or `expire_accepted/3` must open the actual
signed anchor/live pages with the real DomainAuth capability, check the exact
preview and fresh host time, and delete the public/live derivative while
retaining the original clocks. For elapsed finite history, the prepared intent
includes the exact authenticated native-choice capsule. If the signed-page repair
fits the existing Core limits, expiry can replace that capsule in the anchor with
a versioned, domain-authenticated digest of the complete capsule; the signed
successor edge and admission clocks remain. Older decoders refuse the new choice
tag rather than interpreting it as an existing choice. The receipt reports whether
it was compacted. A bounded repair that cannot fit keeps
the capsule; this is not general compaction of forgotten-lineage suppression. The
destructive floor advances. Persistent or unexpired targets refuse, and unrelated
notes and shared evidence remain.

The compact digest permits a trusted examiner to compare the retained capsule
against an authenticated current anchor using `ManagedPages.compact_choice?/3`.
`knowledge operation` does not yet perform that comparison; its journal/control
status does not independently authenticate the capsule. A caller must obtain the
current page through DomainAuth before treating the comparison as authenticated.

Accepted expiry uses `ManagedLifecycle.prepare_accepted_expiry/3` and the distinct
`managed_accepted_decision_expiry` fact/receipt kind. Its pure deadline predicate
accepts only the closed retained accepted metadata; it grants no authority.
Inside the actual publication, the normalizer reauthenticates the type-3 live
row, original anchor, exact stored note and same-root immutable acceptance link,
then rederives those facts and checks fresh host time. It removes the public
note/live row and advances the destructive floor, preserving the anchor clocks
and acceptance link. Any signed finite accepted deadline may qualify, including
a preference/current decision bounded by an earlier saved-policy expiry. Null
deadlines and unexpired targets refuse. This is a reducing management operation
after disabled capture or unavailable original sources; it grants no retention
extension, replacement, current use, headless access or model/service effect.

This branch follows the previously saved signed expiry policy rather than
spending a new native Review permit. It exposes no worker operation and cannot
force an earlier deadline. The explicit standalone caller still enforces normal
interactive/native-channel and effect ceilings. Intent, bounded measured
reservation, final Identity release, deferred settlement and checked cleanup
remain mandatory. A settlement failure after publication is unknown; it cannot
be classified as a definite refusal merely because this branch has no consumed
Review wrapper. Original and management journals remain; no idle task or automatic
replay is introduced.

Use `knowledge operation JOURNAL_ID` for bounded original-journal/control inspection.
It neither reconciles nor establishes current eligibility. Legacy/unrecognized
recipes require separately reviewed treatment. Proposal acceptance follows its
[signed event/link workflow](knowledge-extensions.md#confirm-a-pending-decision).
Session-owned literal correction and supersession use a separate typed path.
After new statement endorsement, `ManagedSupersession` performs a Session-chosen
relation review with actual source/policy ownership through native display.
Its trusted normalizer consumes that permit under fresh locks;
`Collection.execute_reviewed_supersession/7` claims the exact normalized effect
and `Runner.SessionSource` attaches Session, Writer and all original sources to
the existing native root decision. The generic API remains closed. Standalone
expiry supplies none of this relation authority. Follow the complete
[source-owner flow](session-sources.md#reconstruct-without-giving-old-tokens-authority)
and its genuine Session tests before changing that boundary. The final
verification section groups the distinct current behaviors.

## Revalidate reads and downstream use

The internal `Collection.ObservedRead` foundation can pair a `get`, `snapshot`,
or bounded public `scan` result with the root witness from the same checked view.
Protected `get` and `scan` actions with reviewed `managed_read` recipes now use
this view through `ManagedRead`. A scan checks its
generation under the revalidated root lock before reading selected values and
filters reserved keys before selection. It refuses a stale generation instead of
returning the ordinary scan conflict. Snapshot rechecks the root without reading
any record values. Legacy roots and over-capacity view indexes refuse.
The first observation discovers managed records without returning their values
to the worker. `StoredSources` obtains original-journal ownership outside
Identity/Consent; the final protected read must reproduce the exact result and
root, authenticate each literal's signed metadata, re-extract it under the
current recipe, check host deadlines and current source selection, and resolve
its stored proofs against their actual committed sources. The consuming Session
supplies its state directory, never a worker path. A source in that same Session
uses its owner-only Writer cache and active action lease. An inactive source in
another Session requires its existing retained lock and fully validated original
journal. Busy sources refuse promptly; copies, missing locks, legacy origins,
different project/namespace scope, incomplete tails and changed versions refuse.
No reader repairs a tail or renews an admission clock. Source ownership remains
held through the final read callback and is checked before its result escapes.
Loss of the native lock owner refuses the result even when the pathname and
journal bytes still match. Cached Writer reads also recheck the canonical
directory and private parent, so moving the directory behind a symlink or
making it public cannot retain source authority.

Accepted decisions use a distinct version-6 observation. The host discovers the
immutable link, retains the original committed management journal outside
Identity/Consent and obtains the original Session source. The final protected
read verifies the actual native event, note/link identities and signed anchor/live
rows. Missing recipes or direct link delivery refuse. Receipt consistency binds
the exact returned value and original source versions; it supplies no current
authority by itself. `ManagedUse` reacquires these owners and current policy for
each later use. The original weak source remains attributed; acceptance does not
convert it into a literal operator statement or independent truth.

Committing that version-6 read is separate from delivering its continuation.
The current [managed export-input adapter](session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
supports versions 3–6. Accepted-decision input requires every original
management-journal owner alongside original Session sources, consuming Session
ownership and current policy at that same native stdin sink. Their complete
settlement precedes callback release. The historical read receipt cannot stand
in for any of those owners.

The adapter retains the admitted dependencies through Session's actual action
commit. `ManagedReads` binds the exact bounded result, request, operation, Session,
pin/epoch and root; every returned literal additionally needs its selected recipe
and exact source versions. Scan receipts retain their root selection as well as
each literal dependency. The owner prepares this privately under its current
worker/action lease. On success it writes `managed_read_observed` before the
action result and admits the continuation only after both durable appends and
the applicable current-input owner fence.
An interrupted receipt without its result supplies no consumed read.

Fresh headers pin `managed_reads_v1`; absent markers preserve older historical
behavior, while explicit null or unknown markers refuse. Existing `Actions`
reconstruction validates chronological bindings, missing/duplicate receipts and
complete dependency coverage. It derives the union of all committed reads for
each completed extension output; workers cannot choose that union. Session
retains the same unions, including an extension question's earlier reads on
resume. Reconstruction performs no storage/source IO and grants no freshness.
`ManagedLineage` derives producer inheritance from actual committed outputs,
selected references, context publishers and saved transformations. Equal text
alone cannot substitute for that provenance. Existing journal reconstruction
replays these host transitions without IO; old successful managed reads lacking
genuine observations remain inspectable but cannot supply current authority.
Dictionary/occurrence overflow refuses instead of silently evicting dependencies.

For root-only publication prerequisites, the same owner keeps a bounded
dependency-digest classification cache. It adds an exact `true` entry only after
the original managed observation matches its active successful action/result;
an orphan receipt or worker JSON cannot populate it. Pending classification is
cleared on lifecycle boundaries, and cache/pending state count toward the existing
2,048-entry/four-MiB lineage limits. Saved rebuilds it chronologically from the
original receipt/result pair rather than trusting a serialized cache. This can
qualify an earlier empty metadata-only index as historical CAS information while
preserving the whole union. Actual source/recipe/policy expiry, native ownership
and the final Collection root still require fresh validation; the cache supplies
neither current-use permission nor full capture readiness.

Before a registered main/helper inference, the owned task obtains historical
preflight verdicts and Session checks/journals the exact input projection and
causal binding. `ManagedUse.verdicts` batches source proofs by original Session
under one aggregate scan budget. Those results are historical. Actual use
reacquires original-source leases and current Identity/Consent, reproduces the
selected root/literal observations and checks policy/literal deadlines after the
last observation. Unchanged signed literals can refresh at newer unrelated roots
without renewing their lifetimes; an exact-root selection cannot.

The native registered transport applies that current authority to Mint's one-use
exact request-body continuation. No authority lock is held while awaiting model
generation. The host buffers managed text, confirms native parsing/socket and
controlled-child cleanup, then revalidates dependencies for final inference-result
release. A changed source or permission can therefore withhold generated text
after the provider received the original request. A volatile owner seal binds the
exact result and buffered text and is consumed once; it grants no reusable
permission. TLS cleanup uses public Mint/OTP interfaces.

Direct managed extension output uses `Session.ManagedOutput` to bind the exact
parent, action/result digests and complete inherited/read union. Fresh journals
declare its causal layout. Intent precedes privately staged raw output; current
source/Identity/Consent checks surround actual release, and strict time checks
follow blocking tool-message journal IO before notification. A cleanup record
closes publication before a paged source becomes publicly readable. Interrupted
prefixes remain historical staged bytes rather than reusable delivery authority.
Self-write confirmation can instead use closed host publication facts without
claiming current eligibility for the worker's raw text.

This path remains under integration review, including live/replay consistency
after uncertain cleanup. Ordinary tool arguments held for approval still need
their separate actual-effect admission and final-output boundaries; an inference
or extension-result release check does not cover those later effects. Unsupported
opaque projections refuse. Read receipts and replay alone never make later uses
current. Automatic recall publishes the same bounded turn-local Reference and
retains its full host dependency union rather than minting new evidence.
Within an active domain-auth callback, `managed_record` checks the selected
recipe against a signed literal's stored value as well as the signed pages. This
refuses historical literals that the current recipe no longer accepts. Evidence,
lineage, text and category come from the selected recipe's paths; the stored proof
is only a structural input until `StoredSources` independently resolves it.
The internal `managed_proposal` operation
also checks a pending Knowledge record, signed format/live/anchor pages and
absence of the selected override at that same root. It uses the selected recipe
paths for evidence and lineage while requiring the Knowledge proposal's ID and
pending state. It checks stored proof-shaped
data for consistency but does not authenticate its source anew or establish
current consent, expiry, display or acceptance. The selected management adapter
uses the retained proposal planning view for its separate native review;
[the feature guide](knowledge-extensions.md#confirm-a-pending-decision) traces its
fresh publication checks. The public value's worker-supplied timestamps are not host clock
evidence; use the separately returned historical metadata when checking the
admission deadline, and still revalidate current time and authority.
Once the view closes, the witness is historical. A future use must establish
current identity, consent, source eligibility, lineage and root at its own
effect or send boundary; the witness grants no authority.

## Build evidence with the public SDK

After a successful source read and exact quote, use:

```elixir
{:ok, proof} = Ipse.Extension.source_proof(evidence_page, quote_result, exact_text)
```

The public helper uses only the shipped SDK dependencies, so independently built
workers need no host `SourceIndex` or `SourceRead` module. It checks matching
page/quote identities, exact bytes, offsets and hashes. The returned JSON remains
untrusted until the host independently resolves the submitted handle and quote.

The stable proof has fourteen fields: `version`, `session_id`, `occurrence_id`,
`version_id`, `kind`, `origin`, `coverage`, `path`, `start_byte`, `end_byte`, `quote`,
`quote_sha256`, `content_sha256` and `receipt_sha256`. Version is 1. Volatile window
IDs, generations, HMAC handles and chunk IDs are absent. The host separately binds
the current window and generations to its publication callback. A resumed Session
requires fresh handles even when its original occurrence/version IDs stay stable.

Only original input, atomic verified native operator answers, explicitly reviewed
operator statements, original visible assistant answers and typed tool-outcome metadata support capture
proofs. Their non-file `path` is nil. Tool stdout, file-read content, external
effect text, decision advice and legacy/unverified text refuse capture proof
resolution. Public readability does not imply capture eligibility. File-derived
capture needs a separately validated original path receipt; printed or truncated
arguments cannot supply one. A native answer such as `2` proves those original
answer bytes, not an assistant premise selected by that answer. The shared
literal-source recipe therefore refuses plain-input and native-answer proofs,
including for other extensions; a proposal recipe can retain them as
never-current evidence when the corresponding effect is permitted.
`native_operator_assertion` requires an actual native statement/category review.
Its `input.assertion.ordinary`, `input.assertion.preference` or
`input.assertion.current` kind binds the reviewed category, and the literal
recipe requires that exact category. Source-page provenance carries its
`assertion_id` and `category`; those public fields do not mint authority. The
source owner resolves the actual occurrence again before publication. Literal
typed tool outcomes support only the ordinary category.

## Review policy registries and activation data

[`SemanticConsent`](../../lib/ipse/extension/semantic_consent.ex) keeps policy
settings version 1 unchanged. Its version-2 data contract separates reusable
constraints and validity recipes from exact effect mappings. This pure contract
does not activate an artifact or make an existing `collection.call` a managed
publication. The managed adapter uses its distinct operation and versioned
binding; unsupported versions fail closed.

Version 2 adds three required fields: `constraints`, `recipes` and `activation`.
The first two are registries keyed by each value's canonical
`Ipse.JSON.digest([value])`. Each permits at most eight entries. Publication
mappings refer to `constraints_sha256` and `recipe_sha256` and declare the distinct
`collection.managed` inner operation. Read mappings keep `collection.call` and
provide a sorted unique `managed_read` list of one to eight recipe hashes.
Each returned record needs exactly one matching reviewed recipe. Helpers
`constraints/2`, `recipe/2` and `managed_recipes/2` resolve these data references;
they grant no permission. Missing, aliased, unused, conflicting or mixed-version
references refuse. The original four mapping identity fields still determine the
exact effect; a worker cannot add its own constraint or recipe fields.

All settings, including registries and activation, still fit **16 KiB/depth
twelve**. The whole policy remains independently bounded at 32 KiB and its saved
admission descriptor at 64 KiB. Registry deduplication shares identical reviewed
constraints instead of widening ordinary SDK objects. A setup adapter must report
capacity refusal rather than remove fields to make a policy fit.

[`ManagedRecipe`](../../lib/ipse/extension/managed_recipe.ex) validates finite
JSON-field selectors and reviewed class/age/origin rules. Its `extract/4` accepts
only exact members of the host-authenticated source set; proof-shaped JSON alone
does not meet this prerequisite. `source_identity/1` hashes the original source
identity fields using the fixed `source.identity.v1` projection. A literal record
uses that lineage in its key and must reproduce the authenticated quote exactly.
Typed tool outcomes support only the ordinary class. A proposal's identity also
hashes its exact text, stays ineligible for current context, and permits at most
seven days. Neither extraction path trusts worker creation/expiry clocks.
Operator retention extraction requires a separate typed host choice tied to its
actual target and original observation; a numeric native answer supplies no
implicit choice or acceptance.

Keep the resulting candidate separate from host truth. Publication's protected
normalizer computes first-admission deadlines and retains anchors after pruning.
Extraction, a structural schema, or a stored eligibility label cannot replace
current source/lineage/expiry checks or the every-dispatch barrier.

`activation` is explicitly null when absent. Otherwise
[`Activation`](../../lib/ipse/extension/activation.ex) validates an exact reviewed
bundle/artifact/sidecar selection, bounded options/capabilities and disclosed
service references. `draft/3` takes the verified project digest, proposed activation
and base catalog before a grant exists. It returns only review data: an overlay
catalog, stable virtual source and activation digest. Setup can prepare the actual
Registry identity, then build the exact protected policy; no provisional grant or
identity is needed. `derive/2` wraps that same data algorithm with strict saved
policy/artifact/route matching. It preserves the supplied base catalog and refuses
collisions. Registry still verifies the actual bundle, manifest, options,
capability ceiling, host/runtime and generation before preparing an identity.
An optional `main_timeout_ms` is an exact reviewed 1000..100000-ms override in
the derived data and activation digest. Absence leaves the ordinary runtime
unchanged; there is no clamp or default. A host applying it must retain the base
configuration fingerprint and save the exact overlay for resume. No service/profile
definitions or child grant can come from activation data.
[`Config.Activation`](../../lib/ipse/config/activation.ex) supplies the Session
selection step: current protected data for a fresh Session, exact saved policy
data on resume, unchanged ordinary fingerprint and current revocation gates.
It verifies installed bytes/sidecar and current bundle membership for fresh
selection, and derives service registrations only from actual base routes.
Timeout overrides must narrow the base; children restore the base catalog,
timeout and registry before their own admission. Follow the
[configuration walkthrough](configuration.md#apply-a-protected-selection-without-changing-base-configuration)
for noncreating status inspection, reciprocal worktree admission and failure
fixtures. `current/2` reads only existing retained state; `readiness/2` additionally
checks the actual overlay under the exact current policy without joining,
reclaiming pending files or returning a prepared runtime. They require safe
existing retained and ancillary writer locks; missing `.lock` or `.writer.lock`
refuses before quota work instead of creating it. Exact
writer identity is checked through the callback within the cooperative host
boundary. The advisory result is not an effect ticket or Collection absence
witness. Ordinary intentional mutation
recovery remains separate. The pure `draft/3` and `derive/2` functions alone grant
no authority.

Keep saved-selection matching distinct from runtime write capability in the CLI.
`Collection.publication_support/0` still reports strict publication support as
false. It does not describe the narrower named new-v3 final-admission scope or
prepare authority. Knowledge status preserves
`activation_ready_now` from the overlay check, reports publication support
separately and requires both for `capture_ready_now`. Permissions inspection
keeps its null activation check and exact raw policy. Thus full notes readiness
remains false despite the narrow capture and public-forget positives. The native
enable review retains its full policy arguments and original compare-and-swap
path; setup alone qualifies neither automatic headless capture nor later use.

## Keep approval and replay facts distinct

Saved semantic permission uses the explicit `saved_consent` tag. Ordinary
`--yes`, per-call approval and session permissions keep their existing tags.
Execution-mode ceilings still deny ordinary writes, shell, MCP, services and
delegation; a protected outer export cannot lend its grant to those operations.

| Receipt | Protected version and binding |
| --- | --- |
| Model-selected `tool_started` and typed tool lifecycle | Version 2, exact `semantic_binding` |
| Outer invocation intent / inline result | Version 3, original closed outer binding |
| Outer paged result | Version 4, retains the original version-3 binding |
| Legacy inner collection action | Version 2, exact `effect_binding` |
| Managed inner action / result | Version 3 action/result; managed `effect_binding` version 3 with `metadata_version: 3` for current V3 capture, version 2 for historical V2 metadata |

The outer binding contains `kind: "semantic.outer"`, `version: 1`, host-derived
`class`, namespace, pin, artifact SHA256 and descriptor SHA256. Replay derives that
same class from the hash-matched original policy, so changing all class fields
together cannot downgrade an honestly mutating export. A read outer categorically
denies every mutating inner action even under broad `--yes`. The inner binding contains
`kind: "collection"`, `version: 1`, namespace, pin, inner operation and exact inner
request digest. A managed binding instead has `kind: "collection.managed"`,
namespace, pin, exact outer descriptor digest, inner commit digest and recipe
digest. A current V3 request requires binding `version: 3` and `metadata_version: 3`.
Historical V2 metadata retains binding version 2; replay does not promote it into
current publication authority. Saved validation matches the Session header pin, artifact,
descriptor, parent source and chronological results. Old versions do not acquire
the new approval tag. SDK-2 output retains its paged binding without downgrading
to a legacy inline or saved result.

Legacy publication reserves one operation, encoded worker-request input bytes and
16384 output bytes. Version-2 managed publication additionally reserves two full
6144-byte sidecar values; version three reserves four full values and one possible
deletion. Both include exact worst-case key/revision/change envelopes and comma
overhead, plus 2048 normalization bytes before effects. Values use the same JSON
escaping as storage; the boundary test exercises control bytes at the full limit.
Model, download and money resources are zero. A successful managed save measures
input once in its actual storage callback:

```text
encoded outer request bytes
+ encoded normalized commit bytes - encoded original commit bytes
+ encoded normalization receipt bytes
```

All lengths use `Jason.encode!/1`, including escaping. The normalizer runs once in
the actual storage callback process with its witness bound to the admitted
operation ID. A private measurement must match that operation and the exact
successful Collection receipt's normalized-request digest, normalization and
binding before it can release unused input. Negative growth, malformed or
over-reservation measurements refuse; SDK fields cannot supply costs. Every
resource dimension must remain within the original reservation. Output stays at
16384 bytes; conflicting and failed-no-effect callbacks retain their conservative
reservation.

The publication remains provisional through the enclosing Identity transaction.
`Consent.publish_deferred` durably records `publishing` with full reserved
liability and null actual/receipt, then checks and releases its nested native lock
before returning a host-private ticket/measurement/receipt packet. Only checked
Identity completion, release and any enclosing original-source scope settlement
permit the host to finalize that exact ticket
with `Consent.settle(..., {:known, actual, receipt})`. Current scope/owner liveness
and every reserved dimension are checked again. The callback-started marker
keeps an enclosing error unknown after an effect may have occurred; it cannot
become a known consent denial. The packet never crosses the SDK boundary.

Storage, Consent or Identity loss before that final step leaves full pending
liability even if normalization measured less or the Collection root was already
published. Final settlement itself can become uncertain after persisting known
actual. Inspect the durable row without replay, rather than assuming every unknown
means it is still pending. A revoked policy stops new effects but does not erase
an already admitted liability or prevent its known accounting completion.
Duplicate operation IDs are inspection facts and never new permission to execute.
Cancellation or owner loss stops the current owned lane; a saved prefix never
replays either publication or deferred settlement.

Session validates the exact current action/job/worker lease before source queries.
`Resources.authorized_effect?/2` is callable only by the actual owning Session and
recognizes its live worker or registered file-effect descendant. A sibling task,
unrelated caller, old job reference or closed scope cannot use the query. Raw
same-VM hostile messages remain outside the trusted-host process boundary.

## Verify the boundary before adding a domain adapter

From a coherent built checkout, start with the boundary your change affects:

```sh
mix test test/ipse/extension/collection_deadline_gate_test.exs
mix test test/ipse/extension/notes_publication_admission_test.exs
mix test test/ipse/session/managed_tool_use_test.exs --only publication_prerequisite
mix test test/ipse/extension/collection_document_stage_test.exs --only document_decision_restoration
mix test test/ipse/extension/collection_document_stage_test.exs --only document_deadline_scope
mix test test/ipse/extension/collection_document_stage_test.exs --only document_decision_expiry
mix test test/ipse/extension/collection_store_session_test.exs --only document_decision_session
mix test test/ipse/extension/managed_collection_call_session_test.exs --only document_decision_gate
mix test test/ipse/session/managed_tool_use_test.exs --only document_decision_lineage
```

Document component controls distinguish live staging from delayed pre-decision
expiry, exact owner/CAS consumption and stale-epoch reuse. The public Session
fixture compiles an independent SDK-2 artifact, requests full ordinary approvals,
transports a value larger than 32 KiB and checks complete reconstruction/replay.
Managed Session cases require refusal before intent/approval/namespace creation;
the pure lineage case also requires missing-dictionary state to fail closed.
Generic strict callback/notes APIs and unsupported management choices remain
negative controls. New-v3 admission and its own-root prerequisites have separate
positive and refusal cases; do not conflate those scopes.

For the extension-owned shared controller, study the selected hydration tests in
`test/extensions/knowledge/collection_adapter_session_test.exs` and the focused
codec/prerequisite/reduction/finalization cases in
`test/extensions/knowledge/collection_directory_test.exs`. A fixture seeded through
trusted Core writes does not prove approved acquisition. Focused public Session
finalization controls separately cover old-root preservation, full approvals,
native three-stage selection, stale-generation refusal and owner loss after
publication without replay; their supplied pending job and reused immutable
values do not qualify a complete build.
The pure finalizer must reach its exact three-stage generation CAS and refuse
missing/reordered prerequisites, changed catalogs and unknown outcomes.
Populated peak/GC/migration and installed document
journeys require their own controls before support claims.

For protected notes, retain exact paged results, tampered replay, source
revalidation, ambiguous mappings, finite accounting and owner-loss fixtures.
Older successful cohorts remain historical unless their source/helper and exact
scope match the current path. Use the new admission/prerequisite and genuine
Session/terminal evidence for the restored slice; headless automatic capture and
complete notes readiness remain open. Measured normalization costs cannot turn native-owner loss
into a refund; malformed-measurement/callback-repetition fixtures prove protocol
checks, not successful native publication.

Then run the relevant invocation/source/lifecycle regressions and required
source/package checks. Record the actual helper, filesystem, source cohort and
executed selections. A protocol pass does not prove human identity, model quality,
current-use authority, complete capacity or installed-user acceptance. The
[testing chapter](testing.md) explains those qualification boundaries.
