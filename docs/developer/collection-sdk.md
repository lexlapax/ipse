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
validates its closed storage request. Session records the exact inner intent
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
work. `Consent.publish` rechecks the pinned policy under the control lock; its
callback rederives the current source proofs and applies constraints again before
the short Collection transaction. Lock order is ProjectIdentity, Consent, then
Collection. Slow IO runs in owned effect workers, never inside Session.

## Declare the narrow operations

Declare and explicitly trust `host.actions` plus `host.collection.read` and/or
`host.collection.write`. Source evidence additionally needs `host.sources`.
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
a conflict requires deliberate fresh inspection, not an automatic retry.

The complete `status` projection must fit too; oversized metadata returns the
fixed `collection_result_limit` failure rather than truncated migration facts.
Read actions use the explicit 512-read/two-minute bounds and consume no Consent
period IDs. `host.actions.mixed` separates 512 reads from sixteen other actions;
without it, the existing cumulative action-family limits still apply.

A publication request has exactly these outer fields:

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
| Inner collection action | Version 2, exact `effect_binding` |

The outer binding contains `kind: "semantic.outer"`, `version: 1`, host-derived
`class`, namespace, pin, artifact SHA256 and descriptor SHA256. Replay derives that
same class from the hash-matched original policy, so changing all class fields
together cannot downgrade an honestly mutating export. A read outer categorically
denies every mutating inner action even under broad `--yes`. The inner binding contains
`kind: "collection"`, `version: 1`, namespace, pin, inner operation and exact inner
request digest. Saved validation matches the Session header pin, artifact,
descriptor, parent source and chronological results. Old versions do not acquire
the new approval tag. SDK-2 output retains its paged binding without downgrading
to a legacy inline or saved result.

The publication reserves one operation, encoded worker-request input bytes and
16384 output bytes; model, download and money resources are zero. Known successful,
conflicting or failed-no-effect callbacks settle conservatively inside
`Consent.publish`, once. Unknown outcomes retain liability. Duplicate operation
IDs are inspection facts and never new permission to execute. Cancellation or
owner loss stops the current owned lane; a saved prefix never replays it.

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
```

The Session fixture compiles an independent SDK-2 artifact and uses a synthetic
provider, temporary operator state and the actual bundled protected helper. Check
headless capture, revoked preflight, ordinary-write denial, exact paged output,
tampered replay, source revalidation, ambiguity and conservative conflict receipts.
Inspect an owner-loss case paused at its actual in-publication Session proof
query; no late write or successful settlement may appear. The test uses OTP's
system debug callback to pause that exact second commit-proof request after the
durable publishing receipt, rather than relying on a fleeting lock-busy interval.

Then run the existing invocation, source and lifecycle regressions. These tests
prove protocol and ownership behavior on the tested filesystem/platform, not
human identity, model quality, domain eligibility or installed-user acceptance.
