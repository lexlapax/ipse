# Producer selection adoption — independent review

Read-only review, 2026-10-29. **Accepted for the bounded read-only selection
setup and private batch-pin adoption.** No new blocker was found in this slice.
The [source-policy hold](shared-producer-first-page-independent-review.md),
[public page gate](shared-producer-public-gate.md) and [plan](../../plan.md)
remain in force. This does not accept an inference-capable producer or qualify
source admission.

The reviewed [receipt](shared-producer-selection-adoption.md) is bound by
[manifest](shared-producer-selection-adoption/manifest.json) SHA-256
`df7c466ab04b233f7939a112487a9e46c8645c93955bb038502c97760803030f`.
The independent [read-only verifier](producer-adoption-independent-review/verify.exs)
and [output](producer-adoption-independent-review/verify.log) checked all 785
rows: 12 source snapshots, 15 logs, six reports, 78 files in three exact artifact
file sets, 668 regular runtime files, two symlinks without traversal, the helper
and three ancestor manifests. Helper SHA-256 is
`40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
No runtime tests, effects, model calls or production edits were performed here.

## Source and authority

The frozen Adapters, Corpus, Producer and builder were inspected with the
focused fixtures. `embedding_profile` resolves an explicitly configured
embedding alias and emits the existing read-only Host request. Its closed
response validates version, requested Host profile ID, embedding operation and
digest shape while preserving the complete public profile. The independently
reviewed [Host binding](embedding-selection-bootstrap-implementation-independent-review.md)
authenticates that profile/digest; domain shape validation does not replace it.

Corpus accepts the exact minimal selection arguments, requires the configured
dense collection, and starts no Job/source operation for selection. The result
reports configured identity and `reported_model: null`, one read and zero
effects. It neither fabricates provider-observed identity nor supplies a complete
vector selection. Exact per-action keys remain enforced behind the supported
flat export schema. Builder catalog validation makes unsupported declarations
fail before artifact emission without changing Core schema authority.

The legacy embedding request remains unchanged when the pin is absent. A
present nil/malformed pin refuses; a valid pin is copied into the v2 request and
checked again against the returned selection before vector decoding. Every
private producer batch supplies the stored selection digest. Existing vector,
raw/canonical input and receipt checks remain; unknown responses stop rather
than create a retry continuation. The frozen Producer SHA-256 is
`149e68cb049860252b5800f482ecdbbdaa7fe68f436620bcdc37dd453cfb2f19`.

## Retained observations and limits

The 173-event, 509,717-byte synthetic public Session journal was independently
read without executing it. Its one `embedding.profile` result has
`approval: not_required`; binding/value/setup profile and selection digest agree.
Setup reports no observed model and one read/zero effects. The page invocation
has zero actions and the explicit source-dispatch refusal; the retained native
boundary is identical before/after with no claim. No inference admission event
is present. These observations corroborate containment and setup, not source
freshness or provider egress.

The pinned logs retain nine earlier private controls in 47162, four corrected
new controls in 47168, strict package/catalog validation in 47169 and the actual
public case in 47170. They are separate executions. The initial syntax, missing
fixture capability, obsolete assertion tuple, older marker graph and unsupported
`oneOf` import failures remain visible; earlier compile-only artifacts are not
admitted packages. The 670-node runtime inventory does not itself inventory
every private asset covered by its ancestor reader cohort. No broader current
package, capacity, actual inference or model-weight claim follows.

Selection pinning cannot waive TTL, historical-source or current-policy checks.
The short final Host source-admission boundary, authenticated claim/ranges and
same-live-invocation checks remain separate requirements. Later pages, fact/group
completion, acquisition, budgets, GC/migration and ordinary Word qualification
remain open. The separate [range review](shared-producer-range-claim-independent-review.md)
does not close these limits.
