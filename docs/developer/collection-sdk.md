# Publish evidence through a protected collection

Use this contract when a reviewed extension needs a local immutable collection
under saved semantic permission. Start with [extension authoring](extensions.md)
and [Session evidence](session-sources.md). Ordinary extension state remains the
smaller contract for explicitly approved key/value work. This chapter owns the
generic host boundary; domain schemas, note eligibility and operator setup belong
to the feature using it.

An artifact capability, source receipt or policy-shaped JSON grants no semantic
permission. A fresh Session pins a previously reviewed protected policy and actual
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

[`SemanticAdmission`](../../lib/ipse/extension/semantic_admission.ex) admits an
outer tool or command outside the Session GenServer. The check holds the actual
ProjectIdentity and Consent locks, requires the exact active pin and artifact,
honors execution ceilings, and derives the outer class from the exact exported
descriptor's mappings. Any publication mapping keeps that export mutating and
requires a constrained publication mapping. An export with only read mappings can
enter under the read class, including planning mode. It permits entry to the reviewed worker only. The host
repeats that current check before worker startup.

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
Managed settlement waits until the enclosing Identity checks and release succeed.
Lock order is ProjectIdentity, Consent, then Collection. Slow IO runs in owned
effect workers, never inside Session.

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
changes; the current trusted normalizer explicitly supports **one new record**
only. Replacement, deletion, typed acceptance and operator retention journeys
are not implemented by this adapter.

`advance_floor: true` is mandatory even for a first insert. It fences older
backups that lack retained source clocks. The host never rewrites a false value,
its hash, or its approval. Legacy `collection.call` is not promoted into this
protocol.

Inside `Consent.publish_deferred`, current source proofs and reviewed constraints are
checked again. `Collection.execute_managed/6` then checks the original generation,
revision and operation ID under one native collection lock before invoking the
trusted `Collection.Normalizer`. Its read closure is host-only and expires when
the callback returns. The normalizer derives literal identity and exact quote
support, or a proposal identity and finite pending deadline. It ignores worker
clocks, preserves separate first-note and first-proposal anchors, and appends two
bounded reserved sidecar changes atomically with the original unchanged change.
Packed pages and the normalization receipt use version 2; older unreleased page
versions refuse. Capacity refuses rather than evicting an anchor. Legacy raw
override JSON cannot stand in for an unimplemented typed operator choice.

The success value contains `version: 1`, `binding`, `normalization` and `receipt`.
The binding hashes the original request, recipe and normalization receipt. The
durable receipt hashes that binding and the explicitly normalized commit, and
carries generation/floor. Storage wire version 5 preserves the managed binding;
legacy receipts retain their original formats. Worker replies omit sidecar values
and keep the complete action continuation within 16384 bytes.

These are publication and historical-integrity facts. Raw collection reads and
normalization metadata **do not establish current managed eligibility**. Live
read-view validation, every-dispatch withdrawal, inherited assistant/summary taint
and resume revalidation remain separate integration work. Do not expose a stored
`current` label as a freshness guarantee.

The internal `Collection.ObservedRead` foundation can pair a `get`, `snapshot`,
or bounded public `scan` result with the root witness from the same checked view.
It is not connected to Session actions or managed eligibility. A scan checks its
generation under the revalidated root lock before reading selected values and
filters reserved keys before selection. It refuses a stale generation instead of
returning the ordinary scan conflict. Legacy roots and over-capacity view indexes
refuse; snapshot also needs its public probe record to be readable if present.
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

Only original input, atomic verified native operator answers, original visible
assistant answers and typed tool-outcome metadata currently support capture
proofs. Their non-file `path` is nil. Tool stdout, file-read content, external
effect text, decision advice and legacy/unverified text refuse capture proof
resolution. Public readability does not imply capture eligibility. File-derived
capture needs a separately validated original path receipt; printed or truncated
arguments cannot supply one. A native answer such as `2` proves those original
answer bytes, not an assistant premise selected by that answer.

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
| Managed inner action / result | Version 3, distinct managed `effect_binding` version 2 |

The outer binding contains `kind: "semantic.outer"`, `version: 1`, host-derived
`class`, namespace, pin, artifact SHA256 and descriptor SHA256. Replay derives that
same class from the hash-matched original policy, so changing all class fields
together cannot downgrade an honestly mutating export. A read outer categorically
denies every mutating inner action even under broad `--yes`. The inner binding contains
`kind: "collection"`, `version: 1`, namespace, pin, inner operation and exact inner
request digest. A managed binding instead has `kind: "collection.managed"`,
version 2, namespace, pin, exact outer descriptor digest, inner commit digest and
recipe digest. Saved validation matches the Session header pin, artifact,
descriptor, parent source and chronological results. Old versions do not acquire
the new approval tag. SDK-2 output retains its paged binding without downgrading
to a legacy inline or saved result.

Legacy publication reserves one operation, encoded worker-request input bytes and
16384 output bytes. Managed publication additionally reserves two full 6144-byte
sidecar values, their exact worst-case key/revision/change envelopes and comma
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
Identity completion and release permit the host to finalize that exact ticket
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

From a built checkout:

```sh
mix test test/ipse/extension/collection_call_test.exs test/ipse/extension/collection_policy_test.exs
mix test test/ipse/extension/collection_call_session_test.exs test/ipse/extension/source_read_test.exs
mix test test/ipse/session/resources_authority_test.exs test/ipse/extension/result_source_test.exs
mix test test/ipse/extension/managed_collection_call_test.exs test/ipse/extension/managed_collection_call_session_test.exs
mix test test/ipse/extension/managed_collection_accounting_test.exs
mix test test/ipse/extension/managed_recipe_test.exs test/ipse/extension/semantic_consent_v2_test.exs test/ipse/extension/activation_test.exs
```

The Session fixture compiles an independent SDK-2 artifact and uses a synthetic
provider, temporary operator state and the actual bundled protected helper. Check
headless capture, revoked preflight, ordinary-write denial, exact paged output,
tampered replay, source revalidation, ambiguity and conservative conflict receipts.
Two successive protected saves independently reconstruct their normalized commits
and exact input charges under a finite period budget. A native-owner loss after
normalization verifies that measured costs cannot turn uncertainty into a refund.
Source-derived accounting fixtures separately exercise unreachable malformed
measurements, callback repetition and foreign-process capture; they are not native
publication evidence.
Inspect an owner-loss case paused at its actual in-publication Session proof
query; no late write or successful settlement may appear. The test uses OTP's
system debug callback to pause that exact second commit-proof request after the
durable publishing receipt, rather than relying on a fleeting lock-busy interval.

Then run the existing invocation, source and lifecycle regressions. These tests
prove protocol and ownership behavior on the tested filesystem/platform, not
human identity, model quality, domain eligibility or installed-user acceptance.
The pure managed-policy tests use the actual native capture schemas, exact source
identity/proposal hashes, unchanged JSON limits and explicit v2 pin/effect
validation. They also require nil historical activation to stay absent and reject
service-reference substitution, child widening and base-catalog collisions.
