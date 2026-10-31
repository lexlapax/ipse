# New literal publication at the final locked admission

Scoped implementation, 2026-10-29, following the
[independent contract review](notes-publication-restoration-independent-review.md).
The [plan](../../plan.md) owns acceptance. This restores a single new v3 capture;
it does not qualify retained-note output, correction, supersession or every capture
source. Ordinary admission is the final locked decision, not a promise that the
physical rename finishes before the clock advances.

`Collection.with_notes_publication_deadline/2` creates a trusted process-local
scope in the actual `Resources.file_effect` owner. Its positive safe-integer
policy deadline is narrowed by any inherited deadline. The v3 normalizer's
original nullable `valid_until_ms` narrows that bound again before the existing
atomic mutation. Entry after expiry refuses; nested scope and exception exits
restore the original owner state. Only this named scope uses the existing native
`Transaction.switch_before` admission for notes. Generic strict legacy notes
APIs remain refused. A confirmed ordinary mutation is not downgraded merely
because the clock advanced after admission; native Review has its separate
live-success rule.

`ManagedCollectionCall.new_capture?/1` requires a fully valid v3 request with
exactly one new nonnil map at revision zero. Invocation permits that shape after
the existing publication prerequisites; legacy, replacement, deletion, retention
and supersession shapes keep their fences. Source/recipe/Consent checks,
reservation, original native writer ownership, accounting and deferred settlement
remain in the existing production path. A fresh notes scope is not permission
to renew a source clock or replay an unknown operation.

The [manifest](notes-publication-admission/manifest.json), SHA-256
`af4274dbf884df9c4912d564ad0307559f526e58fa3dcc3b78f9844546b7ed59`,
retains twelve source/test/helper snapshots and twelve launcher/log/freezer files,
plus complete runtime/private-asset inventories of the actual intake parent and
notes-admission graphs. The helper is
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
DocumentStage is a separately reviewed complete-value-reader overlay, not a
notes deadline change. Inherited source manifests describe their checkpoints;
the explicit overlays and graph inventories describe this candidate. The first
freezer attempt used the wrong parent manifest filename and failed after copying
files; correcting that filename produced this manifest without rerunning effects.

`47167` strictly compiled the four production overlay modules with no diagnostics.
`47168` passed six selected tests (43 excluded): a real signed v3 native mutation,
actual synced-staging expiry for each shorter policy/normalization deadline,
invalid/elapsed entry without callback, same-owner nesting/exception restoration,
and new-capture shape checks. Each native expiry observed the actual owner deadline,
left no published root and preserved the prepared-domain unknown outcome. Test-only
constant-comparison and unused-alias warnings are retained with the exact initially
executed fixture sources. No product clock was substituted.

The fixture then replaced constant comparisons with a helper and strengthened the
multiple-change countercase to two distinct keys. `47169` stopped on the unused
test alias before running tests; its exact intermediate source remains. `47170`
strictly compiled the final tests without diagnostics and ran only the strengthened
pure shape case (one pass, 48 excluded). The native positives were not rerun against
that final fixture text. No model call, aggregate suite, package or platform
qualification ran. The separate [own-read prerequisite repair](notes-publication-prerequisites.md)
and [genuine Session capture](remember-publication-absence-integration.md) build on
this candidate; independent implementation review is pending.
