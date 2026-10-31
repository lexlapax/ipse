# Session-owned supersession: working evidence

Dated 2026-10-28. This is an in-progress P31C1a integration record. The
[plan](../../plan.md) remains authoritative; this record does not qualify the
milestone, historical-use delivery, endurance, installed use, or release. It
extends the [signed Core component](../2026-10-28-managed-supersession/index.md).

**Current restriction:** the Session correction and supersession handoff is
temporarily disabled. A subsequent review found that a separate terminal owner
could continue a queued display after the process holding the source and policy
leases died. The earlier Session/terminal successes below qualify only their
recorded historical cohorts. The current handoff reports an unconfirmed outcome
and does not fall back to ordinary publication. Restoring it requires a native
display/lease ownership design and its own owner-loss controls.
The later [Linux shared-lock descriptor experiment](../2026-10-29-native-shared-lease/index.md)
is a development-only building block and does not restore this path.

The disabled-path Session, Host and Review cohort passed
[strict compilation](evidence/display-disabled/compile-disabled-retry.log) after
matching newer MCP dependency BEAMs; the earlier
[stale-dependency diagnostics](evidence/display-disabled/compile-disabled.log)
are retained. The [affected source](evidence/display-disabled/source-disabled.sha256)
and [runtime](evidence/display-disabled/runtime-disabled.sha256) hashes identify
`_build/coordinated-supersession-sol-20261029`. A draft proxy design is preserved
under that graph's `design-snapshot` with its [hashes](evidence/display-disabled/design-snapshot.sha256);
it is not active or qualified. A [focused native Session/PTY control](disabled-pty-46977.log)
then passed on that disabled cohort: after two actual native reviewed note saves,
an actual witnessed correction returned an error, displayed no relation review,
created no relation intent or review, left the Collection generation unchanged,
and restored and resumed without replay. The matching test and driver sources
are captured under `evidence-source-disabled-pty` in that graph. Their SHA-256
values are `00341286c6bb1a8558fed08d1aea7abb26a390313c174cd6f14a6ba03b79a955`,
`36cb564b424c279d5f24c788bf3cf04596568279fed8684df38585bd53704358` and
`45c053d2148eb89294db18a718c9db23c8fe17625123663af62bdef61014cc13`.
A [strengthened repeat](disabled-pty-46978.log) additionally checked that the
prepared relation was present and the candidate action was recorded with the
expected failed outcome. Its revised fixture is captured under
`evidence-source-disabled-pty-46978`; its SHA-256 is
`1d48825b1052461611af9464516548d83385d7f6ddebb7ca35dcd8b196c0255d`.
An earlier attempted filter was wrong, started old positive scenarios, and was
interrupted after they failed against the disabled path. It is not a successful
baseline. The new control proves refusal only, not corrected publication or a
solution to the ownership race.

A native Session assertion can select an exact predecessor and ordinary correction
or temporal supersession before the existing Knowledge capture command runs. The
worker produces its usual uncommitted candidate. The host intercepts that candidate
under the Session-owned purpose; the worker does not choose the old key or mode,
and its original one-record action is recorded as failed rather than as a fabricated
capture success. A distinct host outcome binds the original candidate, actual
native review, two-record publication and protected settlement. The consumed review
receipt is journaled while its one-use permit remains live.

The relation preview revalidates both original source proofs, the exact signed old
observation, project Identity and the pinned current capture policy before native
display. Short source/Identity/Consent leases cover the display acknowledgement;
they are released before waiting for the operator's response. The publication path
reacquires and rechecks the sources and capture policy before consuming the permit.
The native final switch is fenced by the applicable old, new, history and capture
policy deadlines. A cancellation or authority loss never falls through to ordinary
publication. Replay validates the actual assertion, exact immediately following
capture invocation, candidate, ordered lifecycle records and failed worker action;
incomplete prefixes remain inert.

## Focused controls and retained failures

The first combined build copied the guarded-review graph and its pinned native
helper, then overlaid the Session and lifecycle changes. An initial
[compile attempt](evidence/compile.log) failed because that graph did not contain
third-party dependency ebins. Those already-built ebins were copied from the frozen
history-CLI graph; [strict retry](evidence/compile-retry.log) passed. Later focused
[stale-purpose](evidence/compile-stale.log) and [handoff-cleanup](evidence/compile-cleanup.log)
compiles passed without warnings. The parser control [passed](evidence/parser-87254.log)
one test with seven excluded.

On the Operator v4 cohort, genuine native Session tests passed individually for
[relation cancellation](evidence/cancel-87261.log),
[capture revocation after preview](evidence/revoke-87262.log), and
[unavailable original source](evidence/old-missing-87263.log). They checked that
no review was consumed, no collection generation changed, and no model ran. The
unavailable-source case also checked that the relation prompt was never displayed.
The [first cancellation fixture attempt](evidence/cancel-87260.log) failed before
review because its test driver called a changed helper at the old arity; that
fixture call was repaired. All displayed content in these test logs is synthetic.

A direct genuine Session control on the preceding Operator v3 cohort passed both
ordinary correction and temporal supersession, including distinct host outcomes,
failed original candidate actions, replay validation and inert resume. It is
provisional because the Operator was subsequently hardened. The v4
[actual terminal-loop attempt](evidence/terminal-87264.log) found a real integration
failure: the terminal's next input reader still owned the channel while the separate
relation review tried to open it. The operation remained unconfirmed. The terminal
now retains exclusive native relation ownership until the Session reports confirmed
task and native cleanup. On the revised cohort, an actual terminal correction
[passed](evidence/terminal-87266.log); a separate terminal cancellation
[passed](evidence/terminal-cancel-87268.log), including the restored input prompt
after confirmed cleanup. The current-cohort direct Session journey for both relation
types and replay tampering also [passed](evidence/current-87267.log). A separate
[legacy marker control](evidence/legacy-87265.log) passed. The focused terminal
tests use synthetic values and no model service.

The exact tested v4 source snapshots are retained under
`_build/supersession-session-sol-20261028/evidence-source-v4/`; their
[hashes](evidence/source-v4.sha256), the actual [runtime hashes](evidence/runtime-v4.sha256)
and [log hashes](evidence/logs-v4.sha256) identify the cohort. The native helper
SHA-256 is `6fbc519033aafaf1718386ef4ef1f91e55724b6d1cffe2bc82ad192280b3098f`;
the v4 Operator BEAM hash is
`87c42e664100572d7d3b369981d19412dd7c97c0736664bb240a77fc4522c3c6`.

The handoff cohort uses that same v4 Operator and helper; its changed Session and
Terminal modules passed [strict compilation](evidence/compile-handoff.log).
The snapshots are retained under
`_build/supersession-terminal-sol-20261028/evidence-source-final/`, with
[source hashes](evidence/source-final.sha256), [runtime hashes](evidence/runtime-final.sha256),
and [log hashes](evidence/logs-final.sha256). The terminal positive and current
journey ran before adding the terminal cancellation fixture branch; that later
fixture-only addition is included in the final snapshot. The earlier v4 snapshot
preserves the original test fixture. The terminal's unknown-cleanup case has not
been directly tested; the separate v4 native owner-loss control covers a different
boundary.

## Shared original Session storage

A [focused native control](evidence/shared-87271.log) created three real assertions
in one Session, corrected one, superseded a temporal assertion, and gave the
corrected predecessor a reviewed 15-second deadline. After the actual deadline,
the standalone management caller expired that history and separately forgot the
third current note. After each effect, `StoredSources.with_verified` revalidated
the remaining temporal history's source and its current successor's source under
the retained original Session lock. Signed history and current observations kept
their metadata, and the original journal bytes remained unchanged. The test used
genuine assertion receipts and native reviews; it ran no model.

These are distinct evidence occurrences in the same retained Session journal.
Direct literal capture maps one exact proof to one lineage, so this does not test
multiple claims sharing an identical proof, future source compaction, or a complete
historical-use delivery authorization. The first [attempt](evidence/shared-87269.log)
used an older Management BEAM without `expire/3`; the second
[attempt](evidence/shared-87270.log) used the wrong expected forget receipt label
after the effect. Both failures are retained. The current Management module passed
[strict compilation](evidence/compile-management.log); the exact test cohort is
identified by its [sources](evidence/source-shared.sha256),
[runtime](evidence/runtime-shared.sha256), and [logs](evidence/logs-shared.sha256).
Source snapshots are under `_build/shared-support-sol-20261028/evidence-source-shared/`.

## Historical-use component

The host-only history selector obtains project Identity, current read consent,
the original Session source lease and a signed history observation. It rechecks
the exact observation under those leases and checks the earlier of policy and
history deadlines before handing it to the trusted callback. Its version-5
dependency identifies a historical record and binds the signed successor key
and hash. Later `ManagedUse` barriers can reacquire the same authority, reobserve
the history at a compatible root and refuse an expired or changed dependency.
Successor content may be unavailable and is neither reconstructed nor authorized.
This component adds no worker route or Session selection/admission. A future
caller must journal the selected producer, propagate the dependency through
inference and delivery, and fence any delayed external effect at the real deadline.

On the first component cohort the [native control](evidence/native-87273.log)
used genuine assertions and source receipts, checked subsequent use, forgot the
successor and observed its storage as unavailable, and refused use when the
original source or current consent was removed. The [initial compile](evidence/history-use-compile-v1.log)
reported two clause-order warnings despite its harness returning zero; the order
was repaired. The [first strict harness](evidence/compile-v2.log) then incorrectly
matched the diagnostic return shape and exited nonzero, even though its output
showed zero warnings. The [corrected harness](evidence/compile-v2-retry.log) and
[focused reference control](evidence/reference-87274.log) passed. The v1 source
snapshot was reconstructed by reversing that clause-order-only edit. The actual v1
[runtime hashes](evidence/runtime-history-use-v1.sha256) and reconstructed
[source hashes](evidence/source-history-use-v1.sha256) are retained separately.

The final v3 dependency additionally validates predecessor lineage and successor
key shape. Its [zero-diagnostic compile](evidence/compile-v3.log),
[focused reference control](evidence/reference-87275.log), and
[native control](evidence/native-87276.log) passed. The tested source snapshot is
under `_build/history-use-v3-sol-20261028/evidence-source-history-use/`; its
[source](evidence/source-history-use-v3.sha256),
[runtime](evidence/runtime-history-use-v3.sha256), and
[log hashes](evidence/logs-history-use-v3.sha256) identify this cohort.

## Interrupted expired-history compaction

The first [interruption attempt](evidence/compaction/compact-87280.log) killed the
management caller during staged publication and failed its assertion that the
file-effect process would terminate within five seconds. Its original temporary
fixture was removed by that test's cleanup, so its final storage state cannot be
recovered from that attempt. A separate diagnostic retained the synthetic store,
captured the real effect, controller and native port identities, killed the outer
caller at the same staged boundary, then released the paused effect without retrying
the operation. Its [first run](evidence/compaction/diagnostic-87281.log) captured
[the report](evidence/compaction/report-87281.json), then failed because the test
incorrectly expected no result event. The surviving effect had journaled an
unconfirmed result. A corrected [run](evidence/compaction/diagnostic-87282.log)
passed after checking its exact intent, operation, action and result bindings.

In both diagnostic runs the transaction controller terminated and its native port
closed after owner loss; the held file effect remained alive until released and
then exited normally. Before and after root bytes matched. Inspection reported an
unconfirmed journal result and a still-publishing protected control operation; no
automatic replay occurred. This establishes the observed native fencing at this
staged boundary, not immediate termination of the file-effect process or a general
guarantee for every interruption point. The original retained stores remain under
`/tmp/ipse-supersession-session-34bb33ee4193e66543f4dccdb0644f70` and
`/tmp/ipse-supersession-session-b9d80cbb46174ad1ed48f6413fc62ddf`.
Read-only evidence copies are under `_build/history-compaction-v2-sol-20261028/` as
`diagnostic-store-87281` and `diagnostic-store-87282`; copied lock files are evidence
only and must not be reopened as live stores. The [87281](evidence/compaction/diagnostic-store-87281.sha256)
and [87282](evidence/compaction/diagnostic-store-87282.sha256) manifests hash those
copies. The [runtime](evidence/compaction/diagnostic-runtime.sha256), captured
[affected sources](evidence/compaction/diagnostic-source.sha256), and
[artifact hashes](evidence/compaction/diagnostic-artifacts.sha256) identify the
corrected cohort. The earlier 87281 fixture differed only in its result-event
assertion and retained several unused-variable warnings; its exact source snapshot
was not captured.

## Bounded history compaction and clock trace

The initial compaction described below was found unsafe by the
[independent audit](compaction-independent-audit.md): it removed the only signed
commitment to the prior choice. Its measurements are historical evidence for that
superseded implementation, not a qualification of the current repair.

Finite, elapsed history expiry now journals the authenticated native retention
capsule in its exact intent before effect. Under the same native Collection owner,
Core checks that capsule against the signed anchor and may replace it with a signed,
versioned digest while deleting the elapsed public/live rows. The original admission clocks and signed successor
retirement stay in the anchor, and the destructive floor advances. If local page
repair cannot fit the existing read/change limits, expiry retains the capsule and
the receipt reports that it was not compacted. This is not compaction of forgotten
lineages, and no later standalone reclamation is supplied for a skipped capsule.

The prior [real-deadline native control](evidence/compaction/compact-87283.log) verified
the original reviewed choice against its consumed-review digest, durable capsule
intent before root switch, preserved signed clocks and edge, other dependent
history/current sources, same-lineage recapture refusal, and old-floor import
refusal. Its specific small page used 13 actual read units and reclaimed 248 bytes
from that anchor page; the management operation took 346 ms. This page-byte figure
is not a net total-store measurement. A [pinned-history control](evidence/compaction/pin-87284.log)
confirmed refusal of automatic expiry even at a far-future fixture clock, and the
[history-use regression](evidence/compaction/history-use-87285.log) passed with
the changed authenticated metadata. The captured affected sources are identified
by the [final source manifest](evidence/compaction/source-compaction-final.sha256),
the same [runtime manifest](evidence/compaction/diagnostic-runtime.sha256), and
[log hashes](evidence/compaction/logs-compaction-final.sha256).

The development-only [clock trace](evidence/compaction/turnover-87277.log) runs
actual native one-use reviews for ordinary correction and temporal supersession,
then an actual signed history expiry with an explicit synthetic future as-of time.
Its output records the actual native review timestamp and review digest, separate
real/virtual clock anchors, the mapped 365-day temporal deadline, and synthetic
fixture source hashes. Its [source snapshot](evidence/compaction/turnover-source.sha256)
is under `_build/history-use-v3-sol-20261028/evidence-source-turnover/` and the
runtime is the earlier [history-use v3 cohort](evidence/runtime-history-use-v3.sha256).
It does not alter the production clock, simulate the annual workload, or establish
full suppression compaction.

### Signed choice commitment repair

The repaired anchor stores the canonical full capsule's SHA-256 digest in a
distinct version-1 native-management commitment, authenticated by the existing
project-domain page MAC. The new closed IMB2 choice tag is distinct from both nil
and a full capsule. The previous frozen decoder [accepts](evidence/compaction-commitment/compat-old-positive.log)
an unchanged legacy page and [refuses](evidence/compaction-commitment/compat-old.log)
the new tag; the new decoder [accepts](evidence/compaction-commitment/compat-new.log)
the same new wire bytes. A [focused syntax control](evidence/compaction-commitment/choice-87286.log)
checks exact capsule binding, tampering, wrong lineage and version.

The [native post-GC control](evidence/compaction-commitment/compact-87288.log)
observed actual collection of the old signed anchor object, opened the current
domain-authenticated anchor, and verified its commitment against the capsule in
the original journaled expiry intent. It wrote and reloaded a separate altered
intent copy with a recomputed unkeyed action digest; the signed commitment refused
that altered capsule. The original journal and control ledger were not rewritten.
The same run refused same-lineage recapture and stale-floor import, retained other
source proofs and records, and measured 13 managed read units, 206 bytes reclaimed
in the affected page and 387 ms elapsed. A separate
[pinned-history control](evidence/compaction-commitment/pin-87289.log) passed.
These are focused controls, not a full adversarial review of all restore paths or
the annual workload. `knowledge operation` does not yet compare a retained capsule
with the authenticated commitment; the test makes that comparison in a trusted
host callback. The [strict compile](evidence/compaction-commitment/compile-commitment.log),
[source](evidence/compaction-commitment/source-commitment.sha256),
[runtime](evidence/compaction-commitment/runtime-commitment.sha256), and
[artifact hashes](evidence/compaction-commitment/artifacts-commitment.sha256)
identify the isolated cohort; captured affected sources are under
`_build/history-commitment-sol-20261028/evidence-source-commitment/`.

The remaining work includes further owner-loss and stale-source adversarial controls,
historical-use authority and source-compaction retention, durable lifecycle
status/recovery, full documentation review, and the 30/90-day and annual turnover
workload.
