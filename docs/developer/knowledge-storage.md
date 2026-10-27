# Publish retained sources through bounded transactions

Choose the owner before changing retained storage. The host-private schema-3
components prepare an authenticated Collection path; the committed SDK consumer
still selects schema 2. The existing Corpus/Graph/Research
source stores below use explicit State or remote CAS contracts. Neither path
treats a successfully written orphan page as published content. Start with
[retrieval training](knowledge-extensions.md) and the
[operator source workflow](../operator/corpus.md).

For source stores, read `extensions/knowledge/src/store.ex`, its `store/state.ex` and `store/mcp_cas.ex`
adapters, then entrypoint source/projection continuations. The adapters propose
approved host calls rather than opening storage or network connections themselves.
Generic State knows opaque values/revisions, without enforcing domain root counts
or inspecting note/source fields. The operator's
[explicit Memory workflow](../operator/memory.md) retains that State contract;
[native knowledge permission](../operator/knowledge-permissions.md) does not
implicitly migrate its records or enable schema-3 recall.

## Publish one fresh record with authenticated metadata

Start with `Collection.NormalizerV3`, `Collection.ManagedPages` and its local
`Planner`. NormalizerV3 prepares an unchanged public insert plus authenticated
sidecars; `Collection.execute_managed_v3/6` performs the atomic storage commit.
These are internal host components. The current managed SDK still selects
`Collection.execute_managed/6` and its version-2 Normalizer. Selecting a version
in worker JSON cannot switch the SDK path or supply a domain capability.

The owning adapter must authenticate original sources and current protected
permission before entering Identity → Consent → Collection. Pass the actual
Identity callback's scoped `domain_cap` and `catalog`, and the actual held
Collection `witness`/`read` closure. A matching shaped map proves none of that
provenance. NormalizerV3's exact options are `request`, `recipe`, `constraints`,
`verified_sources`, `policy_sha256`, `now_ms`, `domain_cap` and `catalog`.
It verifies the recipe/constraint/request bindings and authenticated evidence
members, then checks format and selected page MACs before interpreting old rows.

Only one fresh revision-zero public record is supported: a literal at
`note.<lineage>` or a proposal at `pending.<proposalidentity>`. The original
commit must explicitly advance the destructive import floor. Literal categories
are ordinary, preference or current; a proposal remains `never_current` even
when its text quotes a native source. Existing public values or retained live
identities refuse. No replacement, typed correction, pin, forget, retention
change or stored choice/retirement is admitted by this automatic interpreter.

First use needs native-confirmed absence and the matching prepared Identity
catalog. The caller checks actual absence in one ReadView and closes it before
Identity prepares the domain. Inside the publication, Collection checks absence
again under its actual native owner. Initialization emits format plus the anchor
and live zero-fence pages. An active catalog requires the exact authenticated
format already present. An existing root with missing format, unsigned V2 pages
or a disappeared active store refuses. No implicit adoption, reseal, reset or
import path exists.

Keep final Identity activation separate from a successful inner Collection call.
Before returning a first-publication witness, the host opens one new actual
ReadView, checks current root and receipt generation/operation/revisions/value
hashes, verifies the format MAC, and closes it successfully. Changed page values
are bound by their hashes to the normalizer's captured, host-sealed output; this
post-publication read does not separately reopen their MACs. The witness binds
that actual root hash and the catalog fence. Native-owner loss
after Collection committed can leave durable data with Identity still prepared
and an unknown outer outcome. Inspect it; never replay or infer activation from
the inner success alone.

### Preserve clocks and bound each local repair

The anchor retains separate literal and proposal first-admission/baseline clocks.
Later policy can shorten a deadline; recapture, reading or a persistent category
cannot renew it. Admission at or after the retained deadline refuses. Null
deadline is supported only where the reviewed recipe permits persistence.
Worker clock fields do not establish host time or authority.

Live rows preserve all four exact hashes: lineage, current value, historical
recipe and historical publication policy. They also retain first/deadline and
category/eligibility. Historical policy need not equal today's checked policy.
Pages authenticate their actual Collection key, operation ID, revision and raw
body through the private Identity domain key. A new page binds old **global
generation + 1**, even when the inherited page has an older revision. Every
selected nonsingle leaf is checked for its immutable minimum occupancy and range
before a local repair. Parsing a management capsule mints no review authority.

Every lookup uses the actual shared closure. A neighbor request costs four units
including nil positions; a selected value costs another. NormalizerV3 needs at
most 24 of the closure's 32 units without a cache bypass. The combined anchor and
live plans permit at most five metadata changes: four nonnull values and one
deletion with its exact positive old revision. Format is never rewritten or
deleted. Every complete wrapped value remains at most 6144 bytes; the closed
normalization receipt is at most 2048 bytes and lists the exact extra changes in
publication order, including canonical value hashes and null only for deletion.
The current SDK's two-sidecar reserve does not admit an arbitrary v3 plan.

### Exercise actual Collection and domain authentication

After building the bundled helper and matching Mix graph on a supported native
allocation profile, run the complete author integration controls:

```sh
mix test test/ipse/extension/collection_normalizer_v3_integration_test.exs --max-cases 1
```

This file loads nine earlier trusted-Collection fixture controls and runs six
additional actual Collection/Identity/DomainAuth controls. Sources and recipes
are explicit trusted synthetic fixtures, not SessionSource or human-origin
attestations. The actual path calls the same internal seam an adapter uses:

```elixir
Collection.execute_managed_v3(root, namespace, options.request, operation_id,
  Ipse.JSON.digest([options.recipe]), fn witness, read ->
    Ipse.Extension.Collection.NormalizerV3.normalize(witness, read,
      Map.merge(options, %{domain_cap: cap, catalog: catalog}))
  end)
```

Here `cap` and `catalog` come only from the current
`ProjectIdentity.with_domain_publication/6` callback; the runnable test supplies
the complete admission and post-publication verification around this excerpt.
Follow its `publish/4` and `verify_publication/5` helpers when implementing an
adapter. Check that initialization has three extras, follow-on publication
preserves the original format revision, new page revisions use actual global
generation, and live hashes/clocks invert exactly. The 27-publication series
crosses a live split using actual writes, without seeded metadata. CAS conflict
and duplicate IDs cannot enter the callback. Owner-loss tests preserve prepared
Identity and durable Collection state without automatic retry.

The separate `collection_normalizer_v3_test.exs` reproduces the maximum
shrink/redistribution plus live split with 24 reads and five changes, using actual
Identity tags but trusted Collection observations. The actual small series uses
19/23 units and does not exercise that merge. These controls establish neither
current-note recall nor sustainable 2,000-note/annual capacity. Source expiry,
withdrawal, lifecycle management, SDK reservation/dispatch and migration retain
their own integration and qualification requirements.

## Claim a draft before writing immutable pages

A put/open reads a bounded snapshot and validates its partition. New-root admission
uses the actual missing target at revision zero plus captured namespace generation.
Revision and optional generation are checked atomically under the State lock.
Distinct creators that observed the last free root slot cannot both claim it.
Existing-root/page writes omit that generation fence so their own earlier writes
do not invalidate publication. Root CAS still binds exact revision/source generation/
content hash/draft. A positive-revision generic tombstone at a root key is corrupt,
not an available source slot.

Each partition permits 32 roots. Capacity checks cover all root creation, including
suppression import, using actual added record/root counts. A suppression export has
no plaintext source ID; use its destination key rather than reconstructing the ID.
Local checks alone cannot protect concurrent publication without the atomic fence.
Unrelated namespace writes can conservatively conflict; no retry is implicit.

Draft claim precedes content/chunk pages, which precede final root selection.
Unselected pages remain inert. Large text uses explicit open/contiguous append/
publish, binding draft, expected revision, and byte offset. Final publication
checks whole-body length/hash. Resume never completes a partial draft. Every root
mutation advances storage revision; source generation identifies complete text,
not arbitrary storage mutations.

Stored root/page values independently fit 6000 encoded bytes and SDK validation.
Packing/effect planning uses actual envelopes, including escaping. Generic State
supports 256 retained records/1 MiB per namespace, including other partitions,
orphans, old generations, and tombstones. Local plans conservatively account for
record wrappers; qualified MCP has the stricter 88-key ceiling below. Collection
replaces unreachable pages with tombstones, so it reclaims content bytes, not slots.

## Plan projection capacity before model egress

Source-bound fact/vector drafts return selected chunks, opaque token, and a capacity
plan. Check read/effect allowance before inference. Explicit facts pack actual
encoded pages before claim; model extraction receives an affordable allowance.
Count ceilings do not reserve worst-case records. Returned data must fit the plan,
current source/chunks, and live draft before final CAS. An oversized result leaves
inspectable/abortable work, without partial successful projection.

Eight heads per source bind kind/profile consistently at admission/publication.
Updating an existing head remains possible at the ceiling; a ninth identity refuses
before inference. New vector drafts/plans/tokens bind version two and authenticated
selection. Old drafts remain inspectable/exactly abortable but cannot be promoted
or continued with a fresh token. Compatible chains append; explicit replacement
selection starts with `previous: null`, leaving old pages detached until collection.
See [embedding identity](knowledge-extensions.md#authenticate-embeddings-and-their-complete-vectors).

Two 4096-coordinate vectors need twelve coordinate pages, manifest, final CAS,
draft claim, and embedding call, totaling sixteen effects. State indexing admits
one/two selected chunks. MCP admits one and still may refuse capacity. Every MCP
call is an effect, including reads; result windows have their own read allowance.
Preflight cannot promise capacity after competing writers, so exact abort remains
necessary after later refusal.

## Make suppression survive delayed publication

Follow this intervention through the real continuation:

```text
claim generation 4 → dispatch extraction
forget generation 4 → commit permanent suppression
release old extraction → refuse stale or suppressed publication
```

Suppression roots keep hash/generation/partition without text/title/URI. Imports
and delayed drafts cannot restore them. Forget increments generation until its safe
integer ceiling; at that ceiling it keeps generation and advances CAS revision.
Terminal suppression still blocks resurrection. Queries revalidate all supporting
sources rather than rebuilding missing heads.

Older partitions above 32 roots refuse whole snapshots with root-capacity error.
Addressed inspection/export/existing-root maintenance remain available within byte/
record/effect limits and remote snapshot constraints. Another root refuses;
suppression preserves a root and cannot repair excess count. Keep data for deliberate
migration, without truncating tokens or widening query bounds.

Before sharing a binding with new artifacts, drain old Sessions/admitted effects
and retire their writer configuration. Optional State conditions cannot constrain
a trusted writer that omits them. Valid format-one stores within bounds require
no automatic data rewrite.

## Export complete bytes and migrate explicitly

Export captures one generation and returns contiguous UTF-8 prefixes, bounded by
limit×4096, 8192, and remaining bytes; limit is 1..4. It shrinks a prefix until the
whole envelope fits 12000 encoded bytes and SDK bounds. Quotes/control characters/
newlines can require smaller parts. Complete single-part form repeats source.text
only when the whole envelope fits; otherwise metadata and top-level text stay
separate. Never infer raw capacity from unescaped text size alone.

Import reconstructs bytes/hash and accepts only cursor-zero, no continuation,
complete source up to 8192 raw bytes. A complete final fragment at another cursor
is not a full import. Larger migration uses reviewed open/append/publish while
preserving historical import provenance. Head metadata is disclosed; projection
contents are omitted and require explicit rebuilding.

Foreign copies remain historical assertions. Indexing/extraction preserves that
flag, so they remain ineligible as current evidence. Promotion needs explicit
fresh replacement with greater source generation, inspected root revision, no
historical-import marker, and new projections. Reindex alone cannot do it.
Suppression erases no other store, backup, journal, or earlier transfer.

## Abort the exact draft instead of replaying work

Abort requires inspected root revision and exact draft ID for source/fact/vector
work. A source-only predicate additionally protects append/publish; clearing a fact
draft does not convert it into source content. Wrong IDs/revisions, stale completions,
newer drafts, and suppression refuse. Corpus index-abort checks both committed
root generation and next revision before success, not merely cleared draft state.

```sh
mix test test/extensions/knowledge/store_test.exs test/ipse/extension/state_test.exs
mix test test/extensions/knowledge/index_abort_test.exs
elixir dev/verify.exs source knowledge-recovery \
  --sdk _build/dev/lib/ipse/ebin --input /path/to/graph-state-model
```

Use an independently built Graph state-model artifact. The eight-check recovery
proof denies model egress, inspects the draft, and approves its exact abort without
Corpus or a model service. Installed mode uses the same artifact and a matching
archive. These establish lifecycle behavior, not semantic extraction quality.

## Implement a compatible remote CAS owner

Read `store/mcp_cas.ex` with the independent atomic fixture in
[`dev/fixtures/knowledge.exs`](../../dev/fixtures/knowledge.exs). The service must enforce
partition access and transaction conditions internally. Receipts prove service
assertions, not its implementation or authorization policy.
New record-adding work requires explicit `ipse-cas-v3`. Inner envelope is version
three; outer MCP call/text-window transport remains one. Never infer contract
upgrades from replies. This is a complete empty-store request/reply pair:

```json
{"version":3,"contract":"ipse-cas-v3","partition":"manual","request_id":"11111111111111111111111111111111","action":"snapshot","args":{}}
```

```json
{"version":3,"contract":"ipse-cas-v3","partition":"manual","request_id":"11111111111111111111111111111111","action":"snapshot","status":"ok","generation":0,"value":{"records":[],"count":0,"bytes":2,"complete":true}}
```

Echo version/contract/partition/action/fresh lowercase 32-hex request ID. Status is
ok/conflict/refused, generation a nonnegative safe integer, and value an object.
Unknown fields or mismatches refuse as store-response. Failed actions must not
mutate the partition. Action argument/success-value shapes are closed:

| Action | Exact args | Exact success value |
| --- | --- | --- |
| snapshot | Empty object | records/count/bytes/complete:true |
| get_many | keys, 1..8 hashes | records in requested order/complete:true |
| put_immutable_many | pages, 1..2 key/value/expected_revision:0 objects | records in page order |
| cas_root | key/expected_revision/expected_generation/expected_source_generation/expected_content_sha256/draft_id/next_root | record |
| collect | 1..12 distinct keys/snapshot_generation | records in requested order |

Records contain exactly key/revision/deleted/value. Keys are lowercase 64-hex.
Missing is revision-zero/deleted/null; live is positive revision/object; tombstones
keep positive revision/null. Directory rows instead contain key/revision/deleted/
kind, with positive revisions and root/page/tombstone kinds. Keys are unique,
count equals rows and is at most 256, and declared storage bytes at most 1048576.
These wire bounds do not override atomic 88-record admission.

Directory/groups must agree on revision/deletion and generation. Get-many includes
missing records explicitly. Immutable writes need unused keys and exact revision-one
values. Collection checks snapshot generation and all live/draft reachability under
one atomic owner, tombstoning only unprotected pages and advancing revisions/store
generation once. CAS JSON result permits 60000 bytes, read in 4096-byte exact-bound
MCP text windows. Requests fit SDK, 15000 encoded bytes, and 32768-byte approval bounds.
Write batches test the real selected envelope before choosing one/two pages.

### Enforce root conditions and capacity atomically

New roots require revision zero plus captured store generation. Existing roots
use null store-generation condition, keeping exact revision/source generation/
hash/draft. Check every condition atomically before replacement; suppression refuses.
Success returns exact next-root and target revision+1, with captured generation+1
for conditioned creation. V2/v3 records/conflict revisions cannot exceed store generation.

Root conflicts return exactly value.record summary containing key/revision/deleted/
source_generation/content_sha256/draft_id. Missing/deleted use null source fields;
suppression retains generation with null hash/draft; live roots report hash and
nullable draft. At least one requested condition differs. A fully matching summary
cannot claim conflict, and no source body is disclosed.

Qualified v3 owners atomically enforce at most 88 retained keys in the partition,
including pages/orphans/tombstones/roots, across every accepted writer/version route.
Per-client counting is insufficient. Store also checks 88 records/32 roots/encoded bytes/
remaining effects locally. Draft claims reserve no future slots; competition can
still refuse final publication and leave an exactly abortable draft.
A full snapshot needs one directory plus ceil(records/8) effects, twelve at 88.
Further writes/rechecks/model work must fit the sixteen-effect lane. Result-window
reads do not make underlying MCP calls free.

Inherited partitions above 88 fail full snapshots before addressed inspection/export/
abort. Use the service's reviewed administrative export/migration; ordinary commands
cannot bypass that bound. Selected-only query has separate coverage semantics below.
The qualified ceiling prevents Ipse's own writers from creating unreadable snapshots.

### Cut over without rewriting stored bodies

V1/v2 keep original read envelopes and zero-record maintenance. Existing-root open,
exact abort, forget, and collection can work within snapshot/byte/effect bounds.
Put replacement still adds immutable pages and needs v3; append/publish/projection
work adding records refuses atomic-capacity-unavailable on legacy profiles. V1
missing-root CAS also lacks atomic root admission and refuses separately.

Drain older Sessions/effects, qualify the partition-wide rule for every writer,
then select v3 in fresh reviewed config/Session. Retire bypassing routes. The
contract changes neither local State data nor persisted root/page formats and
falls back to no older contract/service.

## Implement selected remote retrieval

Corpus `mcp_query` uses query-v1 on an MCP store, with separately bound storage/query
aliases and equal partitions. Research remains captured-source BM25. Follow
[operator remote selection](../operator/corpus.md#retrieve-server-selected-passages)
for complete options/bindings with mcp-lexical. The closed request/reply shape is:

```json
{"version":1,"contract":"query-v1","partition":"manual","request_id":"22222222222222222222222222222222","query":"release quiescence","top_k":5,"as_of_ms":1700000020000}
```

```json
{"version":1,"contract":"query-v1","partition":"manual","request_id":"22222222222222222222222222222222","status":"ok","generation":0,"algorithm":"fixture_terms","algorithm_version":1,"scanned_sources":0,"scanned_chunks":0,"complete":true,"refs":[]}
```

Only ok/complete is accepted. Echo identity and captured generation. Algorithm
names use 1..64 ASCII letters/digits/underscore/dot/hyphen, version positive safe
integer, scanned sources 0..32/chunks 0..1024. Query permits 1..1024 UTF-8 bytes,
top-k 1..10, as-of nonnegative safe integer. Each real call gets a fresh ID.
Nonempty refs contain exactly source_id/source_key/generation/content_sha256/
chunk_id/score. IDs permit 1..256 UTF-8 bytes without controls; keys equal raw source-ID
hash, generation positive, hashes lowercase 64-hex, score finite. Unique source-key/
chunk pairs cannot exceed top-k. Text result is at most 65536 bytes.

Store reads only selected roots/pages at reported generation, checks bytes/source/
chunk/time eligibility, and revalidates roots. Stale/suppressed/historical/forged/
wrong-partition refs refuse the whole result. Empty refs abstain without Store reads.
No full-directory root-count validation occurs. Scores remain server-asserted,
not local BM25 or proof of the server's index/access policy. The
[public MCP proof](../../dev/verification/knowledge_mcp.exs) tests selected-only reads,
denial, wrong partitions, incomplete/forged/stale replies, exactly one empty-query
call, and inert interrupted recovery. It establishes protocol, not ranking quality.

## Implement the Research search/fetch gateway

An arbitrary search tool is not a compatible gateway. Bind exact reviewed tools
through MCP; no worker networking or automatic provider installation occurs.
These complete synthetic JSON objects show search-v1 request and reply:

```json
{"version":1,"contract":"search-v1","query":"release quiescence","limit":2}
```

```json
{"version":1,"contract":"search-v1","status":"ok","hits":[{"source_id":"manual:release","uri":"local:release-policy","title":"Release policy","snippet":"Release requires quiescence."}],"coverage":{"complete":true},"next":null}
```

Hit fields are exact, bounded to 256/512/128/1024 bytes respectively, and count cannot
exceed requested limit. Incomplete/paginated results do not become complete coverage.
Fetch uses the selected hit URI exactly:

```json
{"version":1,"contract":"fetch-v1","uri":"local:release-policy"}
```

```json
{"version":1,"contract":"fetch-v1","status":"ok","requested_uri":"local:release-policy","observed_uri":"local:release-policy","media_type":"text/plain","observed_at_ms":1700000000000,"text":"Release requires quiescence.","body_sha256":"abbba53d88fbef3ff61fa825de40691302cb2837fefec6b4701c41ec69ff5010","complete":true,"start_byte":0,"end_byte":28}
```

The example hash/span actually match. Real gateways report actual requested/observed
URI, media type, capture time/text/hash, complete body and byte span. Coordinates
address captured UTF-8, not original HTML. Requested URI must equal selection;
changed observed URI is explicit provenance, not independently approved egress.
Results permit 65536 bytes through same-invocation windows; investigation body/output
limits still apply. Bad fields/JSON/hash/span/completeness/receipts refuse.
The host proves recorded calls, not source truth or gateway internals.

## Exercise delayed publication and interrupted inference

Build the actual independently selected artifacts, then run public Session controls:

```sh
IPSE_LIFECYCLE_ARTIFACTS=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LIFECYCLE_ARTIFACTS/graph" --package graph --preset state-model
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LIFECYCLE_ARTIFACTS/corpus" --package corpus --preset state-dense
elixir dev/verify.exs source knowledge-graph-lifecycle --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LIFECYCLE_ARTIFACTS/graph"
elixir dev/verify.exs source knowledge-corpus-lifecycle --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LIFECYCLE_ARTIFACTS/corpus"
```

Each has seven synthetic provider requests/checks and no model weights. Follow
[`knowledge_lifecycle.exs`](../../dev/verification/knowledge_lifecycle.exs): claim,
approve/dispatch, hold response, forget through another Session sharing the binding,
then release. Delayed publication must refuse and inspection/query retain suppression.
Other controls cover cancellation, owner death, profile timeout, exhausted one-request
budget, malformed output, and provider unavailable. Assert socket/lock closure,
uncertainty/reservations, no selected projection, and inert resume separately.
Malformed/unavailable Corpus also explicitly aborts and verifies committed generation/
revision without another provider request.

Graph selects native structured facts and validates actual wire schema/max-items;
Corpus uses typed embeddings. Unknown embedding work retains input but no text-output
liability; unknown extraction retains both. Read canonical records and budget
settlement, not only attempts. The selection scenario additionally uses two equal-
name/width services with different vectors and reported-model/timeout changes.

```sh
mix test test/extensions/knowledge/lifecycle_proof_test.exs test/extensions/knowledge/index_abort_test.exs
elixir dev/verify.exs source knowledge-selection --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LIFECYCLE_ARTIFACTS/corpus"
```

Repeat source scenarios in installed mode with matching archive and the same artifacts.
An older expected revision in the forget control must fail its expected-success
assertion; restore it to prove the actual competing mutation occurred.
[Testing](testing.md) owns inventories/cleanup and complete gates. These fixtures
establish transaction/identity/recovery behavior, not held-out semantic quality.
