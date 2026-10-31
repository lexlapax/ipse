# Managed output cleanup correction

Recorded 2026-10-28 after independent read-only review. Historical correction to
[the direct-result integration evidence](managed-output-integration.md), whose
original source/log capture remains unchanged. Current instructions belong to
the [developer manual](../../developer/index.md); this is not final C0 or
milestone acceptance.

The review found two concrete defects after current publication admission.
First, unknown cleanup withdrew tool messages and context publishers but left a
command/service's live `extension_result` display unchanged. Replay correctly
withheld that display, so `Session.info` could retain raw output that reconstructed
state withheld. Unknown cleanup now replaces the live last display with the same
fixed host withheld projection. This does not retract a notification that may
already have reached the subscriber.

Second, a tool message recorded just before the final deadline check already
completed its tool call, but the expiry error left that call queued. Outer failure
handling could record it again and mark the next queued call as started. Both
post-append outcomes now consume the recorded call once. Failure settlement treats
a queued head as started only when a tool decision actually started it. The raw
journal result remains historical, the live/reconstructed message becomes a
withheld notice after unknown cleanup, and later queued calls remain `not_started`.

Strict compilation passed. Focused receipt
[46815](managed-output-cleanup-correction/_build/output-audit-correction-46815.log)
passed three cases, with 46 excluded, in 4.8 seconds:

- Actual Writer-backed owner cleanup for command and service replaces the retained
  last display and removes its publisher.
- An actual registered native-provider Session reads through its real worker,
  then the established Writer debug fixture blocks the actual tool-message
  append across its host output deadline. The full unknown-cleanup/Turn failure
  path records that call once, leaves a second queued call unstarted, emits no raw
  result notification, and restores exactly the withheld live conversation.
- Actual paged command replay with unknown cleanup withholds the last display
  and keeps its sealed result bytes unpublished.

The complete Session control narrows the existing trusted host invocation output
lifetime while its worker is held; it does not fabricate a literal source or
change saved Consent. The earlier genuine signed literal-expiry control remains
separate evidence. No aggregate suite or additional terminal/native journey was
run for this correction.

The [correction manifest](managed-output-cleanup-correction/manifest.json) records
the four changed source/test files, strict compile log, focused result log and two
actual runtime BEAM hashes. The matched helper remains
`113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550`.
The separate gate for ordinary managed-derived tool arguments waiting on approval
is still under implementation; these corrections do not claim that gate complete.

## Independent review readback

The independent storage agent reviewed the frozen original release cohort with
manifest SHA-256 `55e648238222db4daf99e26c423d4a3ea2f09adb2039e47581dfa349d9493726`.
All 58 source/fixture/log entries matched their recorded byte counts and hashes.
The review ran no native or aggregate tests and changed no production code.

It identified two concrete gaps. First, unknown cleanup withdrew messages and
publisher contributions but retained an unmarked raw command/service display in
live `Session.info`, while Actions reconstruction correctly withheld that same
display. Second, the post-journal tool deadline failure retained an already
recorded call in the pending queue; outer failure settlement could append a
second result for that call and misclassify the next queued call as started.
The earlier retained-Writer unit control stopped before that outer settlement
path and therefore did not cover the second defect.

The implementation owner confirmed both paths and repaired them separately from
the immutable original cohort. The review readback checked the new explicit live
display withdrawal, consumption of a durably recorded tool call on both deadline
outcomes, and settlement's actual-start decision. Receipt 46815 covers live
command/service unknown cleanup, paged-result privacy/reconstruction and the
complete registered Session failure path with a queued second call. Earlier
irreversible notifications are still described as possibly delivered; this
correction withdraws retained and future projections rather than claiming that
past publication was undone. No further concrete authority, causal-replay or
sealed-source privacy defect was found in the scoped original-cohort review.
