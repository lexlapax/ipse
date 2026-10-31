# Literal-source inheritance after an upgrade

Dated 2026-10-29. This is scoped, local adversarial evidence for the inherited
source-union check. It does not qualify current note publication, the final
output ownership boundary, or P31 completion. The [current plan](../../plan.md)
owns acceptance. The earlier [two-source repair](managed-audit-repairs.md) used
a collection-root dependency; this control exercises a real literal version-4
dependency from a separately reviewed historical note.

## Historical seed and current consumer

The [seed fixture](literal-v4-source-union/source/test/support/managed_literal_ab_seed.exs)
ran against the retained, matched pre-gate
`_build/retention-cli-final-switch-20261028/lib` runtime. A real native PTY
completed identity and consent review, then exact `/remember ordinary` statement
and category review. The seed journal contains an `operator_assertion`, its
source proof and a successful managed publication at generation 1. No inference
was dispatched. The Session closed while its explicitly reviewed consent was
still valid; the fixture records that time and the exact original journal hash.
The [seed log](literal-v4-source-union/logs/ipse-literal-ab-seed-46915.log) contains
only synthetic fixture data. This is historical-upgrade input, not an override
of the current publication gate.

The [consumer test](literal-v4-source-union/source/test/ipse/extension/managed_collection_call_session_test.exs)
imports a test extension and explicitly replaces fixture consent to admit that
artifact, preserving the historical namespace, literal recipes and source
categories. This setup is trusted test configuration, not an operator review
journey or an authority granted to the extension. A fresh real Session then:

1. Reads the genuine note through `collection.call/get`, receiving an authenticated
   version-4 dependency whose record and native-assertion source match the seed.
2. Holds the extension worker after that read. The controller renames only the
   original source-A journal, leaving the collection root unchanged.
3. Lets the worker obtain a fresh quote from the independent current input B and
   request a proposal citing B while retaining the earlier A read causally.
4. Observes `ManagedToolUse.publication_prerequisites?/3` return `false` in the
   real Session. The invocation fails before any `collection.managed` intent.

The [passing run](literal-v4-source-union/logs/ipse-literal-v4-ab-current-46921.log)
finished **one test passed, 109 excluded**, in 1.8 seconds. The quote of B succeeds;
the ordinary blanket publication gate is not the reason this test passes. The
collection generation remains equal to its pre-attempt baseline. The original
source text is absent from drained subscriber notifications, `Session.info/1`
and restored messages. Saved reconstruction succeeds. Finally the controller
restores A's journal and checks its hash byte for byte. The
[retained synthetic journals](literal-v4-source-union/runtime.json) identify the
final consumer and preserve the actual journal events.

The deliberate rename models an unavailable original source; it is not a
revocation or retention-expiry test. The subscriber assertions cover the observed
completion interval, not every downstream sink or owner-death ordering.

## Cohort error and provenance correction

Runs 46916–46919 stopped at fixture setup or continuation errors: namespace
mismatch, omitted source category, recursive single-record conversion and a
map access on an unrelated string outcome. Their logs are retained. Run
[46920](literal-v4-source-union/logs/ipse-literal-v4-ab-current-46920.log) reached
the literal read and fresh B quote but unexpectedly published a pending record
at generation 2. Its purported current runtime had copied the header-audit2
graph with a **stale Invocation module**: that BEAM imported neither
`publication_prerequisites?/3` nor `managed_invocation?/1`. This invalid cohort
is not evidence that the current source-union repair failed. Its publication
remains in the isolated store; it was not undone or replayed. Consequently the
corrected control starts at generation 2 and proves it stays there, rather than
claiming a pristine generation-1 consumer baseline.

The [corrected launcher](literal-v4-source-union/source/_build/run-literal-v4-ab-current2.exs)
copies eight exact gate BEAMs from the already tested strict-lifetime graph onto
a separate header-compatible graph. It asserts the guarded prerequisite import
before starting the application. The [runtime inventory](literal-v4-source-union/runtime.json)
records all host BEAMs and top-level helper files for the seed, stale consumer,
corrected consumer and overlay donor, plus exact equality of all eight overlays.
The subsequently performed [strict two-module source check](literal-v4-source-union/logs/ipse-literal-v4-ab-source-verify-46922.log)
compiled current `Invocation` and `ManagedToolUse` into a separate directory with
no warnings and compared their BEAM code MD5s to the tested modules. Both match.
This validates executable code correspondence while allowing debug metadata to
differ. No production code changed for this follow-up; the new behavior is a
fixture and evidence addition for the already implemented prerequisite check.

The passing log was found terminal during the handoff; it was inspected and
preserved instead of rerunning the test. The scoped [manifest](literal-v4-source-union/manifest.json)
binds the source snapshots, logs, synthetic journal evidence and inventories.
The retained local runtime paths are not a fresh-checkout build recipe; the
historical seed requires its historical helper/artifact cohort. No aggregate
suite, package, installed-user, external service or platform qualification ran.

The strict-deadline and managed-output gates remain unchanged. An enforceable
effect lifetime, worker/source ownership, full recall and withdrawal journeys,
and combined-source qualification remain open.

The [independent scoped review](literal-v4-source-union-independent-review.md)
verified all26manifest artifacts and inspected the assertions and runtime
provenance without repeating the native test. It found no additional concrete
defect in this control's stated scope.
