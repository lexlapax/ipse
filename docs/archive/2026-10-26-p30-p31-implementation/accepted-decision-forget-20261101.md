# Forget an accepted decision under native management authority

Dated **2026-11-01**, based on `41c6388` plus the fixed source recorded below.
This is source implementation and bounded synthetic integration evidence, not
an independent audit, installed qualification or P30/P31 completion. Current
procedures belong to [knowledge management](../../operator/knowledge-permissions.md#forget-a-selected-native-note)
and [Collection training](../../developer/collection-sdk.md#manage-a-retained-note-through-native-review).
The [plan](../../plan.md) owns remaining acceptance.

## Reproduce the missing lifecycle path

The existing genuine pending/acceptance/recall journey was extended after its
two independently accepted decisions reached registered-provider current recall.
The added public CLI stage disables capture and asks to forget one accepted
decision. The first attempt failed in fixture setup because its peer key was
incorrectly taken from the public receipt rather than the actual immutable link:
**0/1, 7 excluded, 42.9s**, log
`/tmp/ipse-accepted-forget-baseline-20261101.log`.

After correcting that selector, actual native disable succeeded, but public
forget refused before review with `collection_observation_refused`:
**0/1, 7 excluded, 43.6s**, log
`/tmp/ipse-accepted-forget-baseline-second-20261101.log`. The existing target
reader and normalizer accepted only literal records, although the decision's
distinct signed representation already supported recall. The positive expectation
remains successful native removal, rather than accepting that refusal.

## Reuse the existing owners and retirement format

`PendingAcceptance.retained_decision_metadata/5` checks the exact accepted value,
immutable link, original proof identity, operation/revision pair, signed anchor
and type-3 live row. The selected literal recipe supplies category retention
limits, not a new literal origin. The owning caller must authenticate those rows
and the same-root link; this pure consistency result grants no source freshness,
review permit or current-use authority. Expired targets remain removable.

`ObservedRead.with_managed_forget_record/7` selects this historical target only
inside the existing retained Identity, management Consent and Collection path.
Ordinary `managed_record` and version-6 current-use readers retain their original
contracts. Literal retention/relation preparation refuses the accepted shape.
`ManagedLifecycle.prepare_accepted_forget/3` supplies a distinct complete fact
kind and one-deletion request to the existing native management display/input,
owned journal reservation and `Consent.forget_deferred/8` state machine.

`NormalizerV3.forget_accepted/3` rederives the exact target/link and authenticated
rows at the actual native mutation boundary before consuming its same-owner
Review permit. It deletes the public/live derivative and records signed
suppression using the already supported exact-target retirement key/value hash.
The immutable acceptance link and original clocks/journals remain. No storage
descriptor, codec, native ABI, global limit or dependency changes. The same public
forget route also serves the CLI's session-only retention choice; other accepted
retention, correction, supersession and ordinary approval displays remain gated.

This core change closes an existing typed management gap: the extension SDK
cannot manufacture native review authority or sign arbitrary lifecycle metadata.
It adds no workflow framework, external service or worker-selected effect.

The usability review found that successful acceptance printed only a mutation
receipt, omitting the new note key. Successful public results now include
`accepted_note_key`, and acceptance-journal inspection derives that same intended
key from its validated native event. The shared lineage function preserves the
existing identity formula. Key reporting does not establish publication/presence
or current eligibility; journal/control status remains separate. The original
settled accounting packet is unchanged. The genuine journey correlates the
printed and inspected key with the actual note, then uses public keys for its
forget and peer targets instead of selecting those through raw storage.

## Require cancellation, removal and retained suppression

Four pure controls cover canonical key prefixes, closed target/link identities,
wrong signed eligibility tags, changed original proof, prior choices/retirement,
recipe mismatch and separation from literal retention. Their shaped rows are
explicit trusted consistency fixtures, never publication authority.

The genuine journey uses actual main-model capture on a synthetic registered
route, public native acceptance, single/two-decision recall and current Worker
input ownership before its added lifecycle steps. A cancelled forget must leave
the target, immutable link, peer and control unchanged without lifecycle intent.
Then native disable revokes capture. Under the original source lock, the positive
temporarily renames the original Session journal and releases that lock; public
forget must still remove exactly the selected historical decision. The original
journal is restored under its retained lock in `after`, preserving its identity.

The test requires a settled one-operation zero-model/download/cost receipt,
committed exact intent/result, no Session-journal changes, an unchanged immutable
link and other accepted decision, and settled no-replay operation inspection.
It authenticates the retained anchor with actual DomainAuth and checks its
native management capsule and exact-target retirement. Reacceptance retention
planning from that authenticated retired anchor must refuse. This does not erase
already delivered answers or original evidence, and performs no automatic retry.

The first implementation passed **4 pure controls** and **1 genuine journey,
7 excluded, 43.8s**. A broader build and existing literal/storage/Consent/read
cohort passed **83 tests in 103.4s** before the final canonical-prefix guard and
module-documentation refinement. The expanded cancel/source-unavailable journey
then passed **1 test, 7 excluded, 44.3s**; strict operation/suppression inspection
passed in a further **44.0s** run, with **16 CLI/retention tests in 28.1s**.
These are separate development receipts, not a complete-suite aggregate.

## Final source verification and remaining work

The final public-key/forget journey passed **1 test, 7 excluded, 45.1s**, terminal
exit zero, in `/tmp/ipse-accepted-forget-key-native-20261101.log`; its four pure
controls passed in **0.1s**. The accepted journey uses:

```sh
IPSE_TEST_GENUINE_PENDING_ACCEPTED_RECALL=1 mix test test/extensions/knowledge/knowledge_session_test.exs --only genuine_pending_accepted_recall --max-cases 1
```

The accepted lifecycle steps now belong to that ordinary opted-in journey; the
temporary extra development switch is removed. Retained synthetic roots print
as `ACCEPTED_RECALL_ROOT`, with separate `accepted-cancel.log` and
`accepted-forget.log` and the original Session/management journals.

The complete source build passed, compiling 183 host files and three inert
bundles; formatting, strict compilation, CI policy and the credential-free demo
also passed. Final logs use `/tmp/ipse-accepted-forget-build-complete-20261101.log`,
`/tmp/ipse-accepted-forget-{format-key,compile-key-final,ci-complete,demo-complete}-20261101.log`.
Before the final key-reporting addition, the frozen implementation also passed
**16 CLI/retention tests in 27.8s** and **11 genuine approval tests, 12 excluded,
174.2s**. The native management file passed **17 tests, 1 skipped, 290.5s** after
generalizing the session-only message; `--include native_sandbox` selected the
whole module despite the narrower `--only` tag. Its switch-hook case remains
unrun, and the inclusion tag alone establishes no OS-confinement result.
These separate logs are `...-cli-qualified-...`, `...-approval-qualified-...` and
`...-session-retention-...` under the same prefix/date. The final native journey
additionally verifies the new key reporting; the earlier cohorts do not imply
that they exercised that field.

Operator and developer chapters were reviewed as whole documents. The storage
chapter's stale schema-2-only dispatch and two-sidecar claims now match the actual
versioned adapter; the retained-target chapter owns management, and the archive
map points to its updated heading. Documentation checks passed **1008 Markdown
files, 8378 local links, zero errors**, with pre-existing inaccessible private
ledger-directory warnings retained separately.

`/tmp/ipse-accepted-forget-inventory-20261101.json` records 19 exact source,
helper/build/dependency inputs, all development/final log hashes and 15 retained
synthetic Session/management journals. This inventory was made after the runs;
it is not a pre-launch freeze or whole-source qualification. Its SHA-256 is
`dca132b289c379a0c181428b91f9919f001c92185d045606424e124a7fdc7424`.
The final root is
`/tmp/ipse-native-knowledge-session-c542377f40244e1df18af441eb8c38c2`.
The unchanged native helper remains
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.

No real account, paid/local inference or model download was used. A new package
has not been built. Whole-source baseline, accepted-specific post-effect loss
cases and other accepted
lifecycle choices, sustainable turnover, installed workflows, quality, adversarial
audit and reviewer handoff remain open. The prior complete full-suite failures
retain their original aggregate; focused passes do not replace that result.
