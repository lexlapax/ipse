# Public first-page route — independent reopening direction

Read-only source/design direction, 2026-10-29. **Reopening the production Corpus
page route is supported after acceptance of the actual guarded Host cohort.**
It should delegate directly to the existing guarded Producer rather than retain
permanent private-artifact-only access. This is a bounded candidate integration,
not a public release or complete producer/capacity acceptance. No implementation,
test, replay, model call or effect was performed here. The [plan](../../plan.md)
owns acceptance.

The [temporary containment](shared-producer-public-gate.md) addressed a concrete
missing final source-admission boundary. Selection pinning and worker TTL checks
alone could not close that gap. The new [Host implementation review](document-source-admission-initial-implementation-independent-review.md)
covers the actual operator selection, live claim/batches and final short-lock
wire gate; native qualification must remain tied to its exact eventual evidence
freeze. Source-only acceptance is not an actual transport receipt.

The minimum feature change is only the `page` branch in `Corpus.collection_produce`:
replace the containment refusal with `Producer.start` and the existing
`collection_producer` advance/state path already used by inspect. Keep exact
arguments, version, dense preset, collection profile and embedding selection
validation. The current production Producer supplies the guarded selection pin,
actual pending claim key/revision/hash and sequential batch ordinal. Preserve
its current source/anchor checks, original one-use/no-adoption behavior and
bounded first-eight-input/first-page result. Selection setup and inspect remain
read-only.

The operator must explicitly select documents binding v2 with fixed
`source_use: shared_producer_v1`, and a matching registered embedding route.
The actual Host remains the authority owner: a missing/foreign guard, old binding,
unregistered route, stale source, mismatched live claim or unknown prior batch
refuses. No ordinary embedding fallback is permitted. Mixed managed-note inputs
remain refused by the current integration; do not silently drop recall roots to
make a document invocation pass. These prerequisites should be explained in the
SDK/operator procedure without inventing a new readiness language or worker
policy engine.

An unsupported v1 setup may get as far as explicitly approved inert pending-claim
storage before the first guarded embedding is refused. The worker need not gain
a new Host discovery interface solely to avoid that UX. Explain the possible
pending record and inspect-only/no-retry outcome; do not relabel the whole page
attempt zero-effect or replay it automatically. A later pre-claim usability
improvement is separate from final dispatch safety.

Word's pending 47213/47214 evidence uses a privately copied package whose only
Corpus difference is this delegation. If the freeze confirms that exact relation,
production adoption can reuse those actual boundary observations with strict
package/catalog validation, direct source comparison and a focused public-entry
protocol check. Do not repeat the four-body native positive merely to promote
an identical route. Conversely, do not claim the subsequently built production
artifact itself ran natively unless it did: retain the exact tested private
artifact/runtime identity and state the adoption evidence honestly.

Keep old selection unchanged and distinguish `page_ready` from group completion
or final generation selection. The proposed native positive's old selected root
is absent; do not call that observation retention of a populated prior selected
generation. Actual nil-expiry positive and captured-source expiry refusal are
separate observations; they do not silently qualify a finite-TTL positive or
every changed-source/race/owner-loss interleaving. Full maximum workload, operation/
journal/storage/peak budgets, acquisition, later pages/facts/group completion,
GC/migration and representative Word quality remain open. Those open limits are
not a reason to redefine first-page functionality as permanently unavailable.
