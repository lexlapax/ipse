# Producer embedding selection adoption — 2026-10-29

This bounded domain increment adopts the independently accepted
[Host selection API](embedding-selection-bootstrap.md) and
[implementation review](embedding-selection-bootstrap-implementation-independent-review.md).
The [public page gate](shared-producer-public-gate.md) remains in place.
Selection discovery/pinning supplies no source eligibility or dispatch fence;
the [source-policy HOLD](shared-producer-first-page-independent-review.md) and
[plan](../../plan.md) remain authoritative.

The [manifest](shared-producer-selection-adoption/manifest.json) pins exact
domain/build/test snapshots, chronology and failed attempts, retained synthetic
journal, candidate/final artifacts and the coherent Host runtime. Compiled
binaries remain under `_build`, not in the archive. Final verification uses
`_build/document-held-read-sol-20261029`, the
[fresh current-source reader cohort](document-held-reader.md), with matching
helper SHA-256
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
No Core, native, Host inference, Actions, Invocation or DocumentStage source was
edited for adoption. There was no capacity/model-service run or quota change.

Manifest SHA-256 is
`df7c466ab04b233f7939a112487a9e46c8645c93955bb038502c97760803030f`.
The additive [read-only verifier](shared-producer-selection-adoption/verify.exs)
and [47173 result](shared-producer-selection-adoption/verification-47173.log)
verify all 785 recorded rows: 12 sources, 15 logs, 6 reports, 78 artifact files,
668 regular runtime files, 2 symlinks, the separately authenticated helper and
3 ancestor manifests. Symlinks are checked without traversing them; helper bytes
are checked separately. The seven changed domain/build/test files also pass
`mix format --check-formatted`. All fixture handles are terminal.

## Current domain behavior

`Adapters.start(..., :embedding_profile, ...)` emits exactly the existing
read-only `embedding.profile` v1 request for an explicitly configured embedding
alias. It validates returned alias/version/hash and preserves the Host's public
configured profile. The Host remains responsible for the admitted profile/hash
binding; the extension does not duplicate its selection-hash algorithm.

`generation_produce` now supports the minimal setup request:

```json
{"store":"local","version":1,"action":"selection","embedding":"learned"}
```

The setup needs no Job or source body. It returns configured profile metadata,
the existing selection digest and explicitly `reported_model: null`. Configured
model identity is not represented as an observed provider model or model-weight
proof. It does not fabricate a complete vector selection or begin a producer
Job. Its coverage records one read and zero effects.

The adapter's existing embed arguments retain their exact old unpinned request
shape. An optional exact `expected_selection_sha256` adds only that field to
the v2 create request; nil/malformed pins refuse before a request. The private
producer supplies its stored `vector_selection.selection_sha256` on **every**
batch. Result selection, reported model, dimensions, raw/canonical input hashes
and full vectors retain their existing validation. A pin mismatch is rejected
by the reviewed Host binding before inference; unpinned legacy callers remain
supported. The public page action still returns
`shared_producer_source_dispatch_unavailable` before claim or inference.

The bounded export schema uses common required fields and optional progress
fields; exact per-action keys are checked in Corpus. This reuses supported tool
schema features rather than widening Core schema support. The package builder
now validates the compiled catalog/schema before emitting an artifact, so
unsupported declarations fail during build. Lifecycle separately built the
current native Knowledge artifact with this check; no SDK dependency change
was necessary.

## Focused verification and chronology

| Check | Outcome |
| --- | --- |
| `47162`, coherent Host base | Nine existing producer controls passed, including all private batch pins; four new fixtures failed because their profile snapshot omitted the explicit embedding capability |
| `47168`, new cases only | Four new selection/bootstrap/pin controls passed, nine excluded; exact old/new wire shapes, configured-only setup, malformed/foreign responses and mismatched binding reaching zero inference continuation |
| `47169` | Final package strict compile and catalog validation passed |
| `47170` | One actual public Session passed in 7.5 s: read-only setup, normal source/Job setup, page gate and read-only inspect |
| `47171` | Retained journal readback: exact metadata-bound profile/hash, reported model nil, one read/zero effects, no inference admission, zero page Host actions/claims and unchanged native boundary |

The nine and four focused results are separate executions; they are not
relabeled as one thirteen-case pass. Passing existing cases were not repeated
solely to repair new fixture assertions. The final package and actual Session
use the complete current Host source base, with no accumulated Core overlays.
The actual captured source/setup/gate journal is **509,717 bytes / 173 events**.
Its read-only setup has `approval: not_required`; no inference, Usage admission,
embedding result or provider request occurs. The saved public selection object,
journal and native before/after boundary remain available for review.

Earlier failures are retained. `47157` had a test-only assert/case syntax error.
`47158` used the accepted selection overlay whose older document adapter
rejected the established closed-model snapshot marker 2 before producer logic.
Read-only `47160` proves that graph accepts no marker/marker 1 and rejects
marker 2; `47161` proves the coherent current graph accepts all three. The
developer model matches current source and was not changed or silently overlaid.
`47165` passed two new cases before two test assertions expected an obsolete
two-element error tuple. Those assertions were corrected without production
behavior changes.

`47166` refused artifact import before Session/native work: the first declared
`oneOf` export schema was unsupported. `47167` records that exact diagnosis.
The flat supported schema and builder catalog check replace it; Core schemas
and authority were not widened. The initial artifact files and failed source
snapshots remain pinned. Earlier successful compile-only artifacts are not
called admitted or usable packages.

## Remaining source guard and producer work

Host source admission still must occur after human approval at the short final
locked one-use EgressGate boundary. The admitted remainder is in-flight
liability; this increment does not propose a socket-lifetime lease subsystem.
Operator/artifact-bound admission requirements must prevent omitted guards from
bypassing source policy while preserving unrelated embeddings/old bindings.

The next reviewed claim schema needs authenticated selected source byte ranges,
claim native revision/logical hash/committing operation ID and per-input ordinal,
raw/canonical hashes. Host can authenticate the current source bundle and compare
exact `Source.text` slices to actual embedding inputs without reproducing domain
chunk/citation algorithms. Same-live-invocation provenance, poisoned unknown/
failed batches, policy times and progress must remain explicit. No range claim
schema or source guard field was invented here; that design remains pending.

Later pages, facts, group completion, observed-model bootstrap where needed,
recovery, exact operation/journal/physical capacity and representative Word
qualification remain open. The page gate is temporary containment, not a goal
redefinition or permanent exclusion of finite-TTL sources.
