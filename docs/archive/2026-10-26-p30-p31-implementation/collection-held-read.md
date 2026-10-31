# Retain Collection ownership across bounded management preparation

Scoped implementation evidence, 2026-10-29. The [plan](../../plan.md) owns
acceptance; the [local management purpose](management-display-scope.md) requires
continuous Identity, Consent, target Collection and original journal ownership
before native display. An ordinary read view releases its native lock between
observations. The [retained Consent snapshot](management-snapshot-read.md) covers
only one of those owners. No output, capture or management gate changes here.
The original frozen candidate below has a reproduced post-publication outcome
defect. The [v2 repair](#post-publication-outcome-repair) supersedes that candidate;
both original source and counterexample remain intact.

`Collection.with_managed_read/3` supplies a trusted host callback with its actual
root witness and the existing managed read closure while retaining the native
Collection owner. The fixed notes profile admits the existing exact-key reads,
four-unit neighboring references and eight-unit pending summary within32shared
units. It reuses the publication normalizer's implementation rather than adding
a second read protocol. Closures require their original process, exact native
capability and callback token, check the actual owner around each read, and
refuse after escape, cross-process use or budget exhaustion. Exhaustion remains
sticky and invalidates a nominal successful callback. Nested Collection entry
refuses; the read callback itself publishes no root or operation receipt.

This is storage observation, not source/metadata authentication, current
eligibility, consent, operator input or display permission. The caller must
authenticate selected records and signed metadata and retain the other owners.
As with opening a view, absent storage can create protected directories and
retained lock files. It cannot establish presence or initialize a managed root.
This is not an extension SDK operation, and no Management caller selects it yet.
Callbacks are trusted Core code; a lock cannot fence arbitrary Elixir IO.

The original managed publication route still performs its exact callback-token,
normalization, CAS, source/metadata and native checks before mutation. Its
original error tags and publication gates remain. The extracted wrapper also
checks the callback token and native owner on a known return. Unknown callback
outcomes remain typed unknown; outer native check/release still runs, and a
lost owner or unconfirmed release replaces any result with lock-loss unknown.

## Focused controls and original failures

The [manifest](collection-held-read/manifest.sha256), SHA-256
`d6432213d91cc9abeebd230861ca2a4bfa9b6d898dd7129d72d1c5a54849c934`,
pins five source/test snapshots, initial compile-failure source, scripts and
chronological logs, plus the complete copied graph and unchanged helper.

-47101 failed compilation because the extraction initially omitted the local
  native-capability binding in the normalizer. That source and diagnostic are
  retained; no test was run against it.
-47104 used an unsupported `elixir --warnings-as-errors` CLI option and ran no
  source.47105 exposed the copied graph's older Directory interface and a
  launcher expectation for the older diagnostics return shape. These were
  cohort/launcher errors. Neither warning was hidden.47106 compiled current
  Collection and the already implemented Directory together and explicitly
  required empty compile and runtime warning lists.
-47102 passed five new real-native cases in2.3s: a competing writer cannot
  acquire until callback release; the exact root/selected value stays constant;
  cross-process and escaped closures and nested writes refuse;32reads exhaust
  the shared allowance; actual helper death permits a new owner to commit but
  prevents the old callback returning success; unknown/malformed results retain
  their respective unknown/refusal outcomes.
-47103 passed18existing managed publication/directory cases in2.7s. These cover
  original normalization/receipt publication, exact neighboring references,
  escaped reads, sticky unit exhaustion and existing CAS/error behavior after
  the shared-helper extraction. They are affected regressions, not an aggregate
  runtime pass or complete signed-management integration.

The graph copies the frozen management-snapshot-v2 runtime and overlays current
Collection and Directory. Its inventory includes726regular files (broader than
the earlier selected runtime inventories). This cohort excludes later tty/helper and
Session/Host changes. Native controls required the qualified `/tmp` execution
context. No model, network, native helper change, protected output or knowledge
publication ran. Source formatting is checked; independent review, actual
signed-record integration, coherent baseline/package checks and final audit
remain required.

## Post-publication outcome repair

Independent review reproduced a real regression in the extracted wrapper.
A normalizer used all32reads, returned a valid normalized commit, then an
existing synchronous `:staged` telemetry callback tried the retained read
closure. The attempted33rdread made its token exceeded after the prepublication
check. Publication still selected generation1and retained its operation receipt,
but the new wrapper's final budget check returned a known
`managed_normalization_refused`. The
[exact probe](collection-held-read-review/post-publication-budget.exs) and
[actual log](collection-held-read-review/post-publication-budget.log) preserve
the contradictory root/outcome. The original passing23controls did not cover
that schedule and are not acceptance of the failed candidate.

V2 seals the exact read token when the normalizer callback returns, before any
publication. A sealed closure refuses reads without changing the sealed token.
Checking the same exact sealed token is idempotent. An exceeded token still
refuses before publication; an ordinary read callback seals at its known return.
The native prepublication and outer final check/release remain unchanged.
Consequently, no late read-budget check reclassifies a root already selected.
Unknown callback outcomes retain their conservative handling.

The [separate v2 manifest](collection-held-read-v2/manifest.sha256), SHA-256
`36cbbcca5a594b9b63f5ecbab63aab743c459ff9616bc7711eb843bd628c3edb`,
pins the repaired Collection, seven-case test, scripts/logs and726-file runtime.
It copies v1 and changes only the Collection BEAM; the helper is unchanged.
Strict compile47110 has empty diagnostics.47111 passes25affected cases in5.3s:
the original five and18regressions plus two actual native publication schedules
with zero or32callback reads. In both added schedules,33staged-phase reads all
refuse, the API returns known success, and the selected record/revision and
retained operation agree with the actual generation2root. These are new repair
controls, not repetitions of an unchanged aggregate suite. The
[independent additive review](collection-held-read-independent-review.md#additive-v2-repair-disposition)
accepts this repair. The [held signed-target adapter](management-held-target.md)
composes these reads; actual caller/display integration remains separate.
