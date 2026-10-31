# Document deadline inheritance and typed refusal — 2026-10-29

This additive correction follows the [strict deadline interposition/gate](strict-deadline-interposition.md)
and its [independent review](strict-deadline-gate-independent-review.md). Earlier
[fused-write](fused-document-writes.md), [vector](packed-vector-projections.md) and
[fact](packed-fact-projections.md) positive publication cohorts remain historical.
They do not establish a strict completion deadline or a currently supported
large-source publication journey. Current scope belongs to the [plan](../../plan.md)
and [operator Corpus manual](../../operator/corpus.md).

DocumentStage now takes the minimum of an inherited trusted deadline and its
optional requested deadline. A nil or later nested request cannot clear or
extend the inherited scope. Invalid or expired inherited scopes refuse before
mutation; an earlier nested deadline narrows it. The exact prior logical scope
is restored after the call. There is no new worker argument, authority grant,
expiry reinterpretation or fallback to untimed publication.

CollectionStore preserves the Core gate as the closed failed result
`{"code":"document_store_deadline_unavailable"}` for mutations. Historical
`document_store_refused` failures remain valid; invented codes and extra fields
do not. The Collection SDK adapter preserves this cause to its extension caller.
This reports a temporary unsupported fence rather than a successful write,
unknown receipt or permission to retry through another path. The executor and
strict gate remain unchanged.

Focused controls:

- `46887` passed the actual SDK/Session diagnostic: one attempted fused mutation,
  unchanged native status, no fallback, typed refusal visible to the worker and
  user, closed result validation and inert Saved reconstruction. The first
  inherited-scope tracing control missed its event because Collection was not
  loaded before tracing; that harness failure is retained.
- `46888` passed the scoped inherited-deadline control in 0.4 s. An actual exported
  Collection call trace observes the effective native-publication deadline for
  nil, later and earlier child requests. The current gate refuses each protected
  attempt. Expired/invalid inherited scopes never call that publication entry;
  prior scope restoration and a separate ordinary untimed inline call are checked.
- `46889` repeated the diagnostic alongside the strengthened shared-codec
  read-only control: two passed in 12.0 s. The Session diagnostic still attempted
  no fallback and changed no native records. The codec preview used only reads.

The [manifest](document-store-deadline-diagnostic/manifest.json) pins exact source,
logs, host BEAMs and source gate provenance. The tested DocumentStage BEAM is
`5dd124…`; CollectionStore is `3af4d2…`. Both live under
`_build/shared-projection-codec-20261029/lib/ipse/ebin` for the matched overlay.
No native/helper or Runner change is required for this correction. Native fixture
homes are actual `/tmp` tmpfs; generated artifacts remain under `_build`.

Ordinary no-deadline fixture storage is not Consent authority or protected
publication qualification. Stage expiry itself invokes the strict fence even
without managed inputs. Strict deadline-bearing State writes have their separate
gate and are not qualified by these controls. This receipt neither changes the
strict contract nor admits an operation-admission alternative.
