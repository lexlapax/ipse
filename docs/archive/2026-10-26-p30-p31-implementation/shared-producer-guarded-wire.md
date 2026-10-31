# Guarded private producer embedding wire — 2026-10-29

This bounded worker increment prepares the
[v3 range claim](shared-producer-range-claim.md) for the separately owned Host
admission integration. It uses the
[stored-byte authenticator](document-source-use-independent-review.md) contract,
but does not wire or qualify dispatch. Public `generation_produce` page production
still refuses before claim or inference; the [plan](../../plan.md) owns acceptance.

## Request and continuation

Adapters accepts exactly the existing unpinned `{profile, inputs}` arguments,
the existing pinned form adding `expected_selection_sha256`, or the guarded form
adding both a valid nonnull selection pin and this closed `source_guard`:

```json
{"version":1,"claim_key":"genproducer.notes","claim_revision":1,"claim_sha256":"COPY_THE_ACTUAL_LOWERCASE_SHA256","batch_index":0}
```

The example is a field illustration, not a usable claim. A guard requires the
actual `genproducer.<partition>` key, positive safe integer revision, lowercase
SHA-256 and integer batch index 0..3. Extra fields, malformed versions, nil guards
and guard-without-pin refuse before emitting a request. The worker supplies no
claim operation ID; the Host must derive and bind the real committing operation.

The outgoing request remains `embedding.create` version 2 with the same profile,
exact texts, timeout and optional pin. Guarded calls add only `source_guard`.
Legacy unpinned/pinned wire shapes and result version 2 are unchanged. Existing
returned profile/model, input-digest, vector-page and full-vector validation stays
in place; a guard is not a successful inference receipt or model provenance.

Every private v3 producer batch includes a guard derived from its confirmed claim
revision, the complete pending claim's ordinary JSON hash and the number of known
matching prior receipts. It retains exact captured ranges and inputs. Unknown
inference stops without a next/adoption token; a new invocation finding pending
work remains inspection-only. No public gate, preset grant, operator binding,
native helper or quota was changed by the worker increment.

## Focused evidence

Manifest [shared-producer-guarded-wire/manifest.json](shared-producer-guarded-wire/manifest.json),
SHA-256 `fc79fe5cef7190e5b2a0f6414b1107e9470f39758e566c6d759a2e0a8a558388`,
pins 27 domain/test/model/freezer sources, three exact SDK source snapshots,
two test logs, four SDK launch/build logs, three ancestor manifests, both 700-entry
runtime/private-asset inventories and the separately authenticated unchanged
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02` helper.
Compiled binaries remain under `_build`. Domain modules strictly compiled in the
fixture VM's memory; no new emitted worker package or installed artifact is claimed.

- `47187` passed two new adapter controls, with twenty other cases excluded,
  on the preceding coherent held-reader SDK. They prove exact worker request
  construction, closed malformed-input refusals, old wire compatibility and
  preserved unknown/result-pin behavior. They do not prove that old SDK accepts
  a guarded operation; it predates that wire shape.
- `47192`, owned by the parent, compiled CollectionStore, Actions and the shared
  inference source into the new guarded SDK graph with empty diagnostics. Its
  prior `47191` formatting syntax error is preserved and occurred before compile.
  This is an SDK surface graph, explicitly not a Session-admission runtime.
- `47193` ran only the new four-batch private model control: one pass, twenty-one
  excluded. All four guarded requests share the same confirmed claim key/revision/
  logical hash and carry indexes `[0, 1, 2, 3]`. Every complete host-call frame
  passes the actual new SDK validator; the largest guarded embedding frame is
  8,609 bytes. The separate unknown-first-batch branch within that control stops
  at one modeled inference, preserves pending status and supplies no replay.

The nine earlier producer controls, original range positive and older selection
cases were not rerun. These are synthetic, private/modeled receipt flows, not
actual provider inference or independently authenticated historical provenance.
The test Host verifies each guard against the actual pending model record and
known batch count; it does not establish a live Session binding or source grant.

The [read-only verifier](shared-producer-guarded-wire/verify.exs) and
[result](shared-producer-guarded-wire/verify.log) check all 1,440 rows and exact
ancestry. The parent inventory equals the accepted DocumentSourceUse graph.
The SDK child changes only five BEAMs: Actions, CollectionStore, EmbeddingCall,
Inference and ModelCall; the shared inference source compiles three modules.
There are no added/removed runtime entries or hidden helper changes. No old
frozen graph was overlaid. All owned handles are terminal.

The forthcoming operator-selected source-use binding and real same-invocation
claim/batch admission remain parent-owned. Approval waiting, current source time,
one-use serialized-wire admission and unknown handling need actual integration
qualification before the public page gate can open. Later pages, facts/group
completion, whole capacity/journal/peak/GC/migration and ordinary Word quality
remain open. No live model, native storage workload, aggregate suite or public
producer acceptance ran for this slice.
