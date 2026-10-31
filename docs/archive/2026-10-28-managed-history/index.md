# Signed historical observation and expiry component

Dated 2026-10-28. This is a focused P31C1a component increment following
[typed supersession](../2026-10-28-managed-supersession/index.md). The
[plan](../../plan.md) remains authoritative. This does not complete Session
historical use, turnover, compaction of all obsolete storage, or release.
The later [expired-history capsule compaction](../2026-10-28-managed-supersession-session/index.md)
changes the anchor behavior described in this original component record.

`ObservedRead.managed_history/6` authenticates a selected historical literal,
its format, absence of an override, anchor and noncurrent live row through one
checked Collection view and the actual domain-auth capability. Its signed
retirement records the exact successor key and value hash. The successor does
not have to remain current or present for the predecessor's signed historical
edge to remain meaningful. A same-root storage status reports whether matching
successor bytes remain stored; otherwise it says unavailable. It does not return
the successor value or assert that matching bytes remain eligible for use. The
observation provides predecessor metadata and bytes;
it does not establish a current source, current consent, unexpired eligibility,
or authority to deliver the record. It is a host-internal API, with no worker
or extension SDK route. A Session historical-use caller must acquire and hold
the actual source and policy leases, recheck the root and history deadline at
use, and attach the correct dependency to later sends and deliveries.

`ManagedLifecycle.prepare_history_expiry/3` constructs exact reducing facts
for a finite elapsed historical deadline. `NormalizerV3.expire_history/3` again
opens and validates the signed historical closure under the actual Collection
owner, checks the original root and facts, removes the old public literal and
its live row, and advances the destructive floor in the same native transaction.
The original signed anchor, first admission, native choice and exact successor
edge remain intact. The successor record and shared source evidence are not
removed. This preserves same-lineage recapture and old-floor import refusals.
Pinned history has no deadline and refuses this automatic expiry. A future
caller must reserve and journal the operation under current project management
authority; this component does not grant it or add a scheduler.

## Focused evidence

The isolated `_build/lifecycle-sol-20261028` graph was recompiled for the four
affected modules without compile or runtime warnings. The native tests used the
same production-profile helper described in the [supersession record](../2026-10-28-managed-supersession/index.md)
and separate `/tmp` tmpfs stores. Original source receipts and the post-deadline
clock were explicit trusted fixtures, not live Session source authority.

- The signed-history expiry test passed with real native Identity, review,
  collection publication and protected view reads. It authenticated the old
  edge and original value, refused the current successor and a missing domain
  capability as history, and refused expiry just before the historical deadline.
- At a synthetic elapsed time it removed the historical public/live records,
  preserved the exact signed anchor record and successor bytes, advanced the
  floor, and refused same-lineage recapture and an older-floor import.
- A separate native pin control made an actual reviewed pin, superseded it, and
  authenticated the pinned historical closure. Its deadline remained nil, and
  eligibility persisted while automatic expiry refused even at a far-future
  synthetic clock. After an actual reviewed forget of its successor, the same
  predecessor value and signed edge remained, and successor storage changed from
  `matching_record` to `unavailable`. This tests signed retention policy, not
  current consent or source availability at that time.
- The existing focused ordinary-expiry native control also passed after the
  shared expiry implementation was extended for history (one test, 35 excluded).

The existing v2 managed-read mapping requires reviewed managed recipes and uses
the current-record reader, which refuses these noncurrent rows. No history
worker read was added here. Whether a legacy or alternate mapping can reach the
same managed namespace remains a separate policy audit; this component does not
claim an end-to-end worker-read guarantee.
The tests retain the old signed assertion but use synthetic source receipts, so
they do not yet verify real shared-evidence retention for multiple historical
dependents. That is required before qualifying historical use.

## Explicit CLI reclamation

The existing `knowledge expire NOTE_KEY` command now recognizes an authenticated
historical record as well as an expired ordinary record. It reuses the native
terminal and execution-mode gates, current project/management epoch, full fact
display, journal-before-effect order, bounded accounting, deferred Consent
settlement and unknown-outcome recovery. No worker operation or background
collector is added. Consent accepts only the exact ordinary/ordinary or
history/history fact-kind/category pairing and verifies the matching Core receipt.

The [focused Consent control](history-cli-evidence/consent-87235.log) passed one
case, with four excluded. It checks valid history settlement, mismatched kinds or
categories, wrong receipt kind, and refusal to replay a settled or uncertain
operation. Its supplied metadata is a synthetic control-ledger fixture, not a
signed Collection proof.

The [native CLI journey](history-cli-evidence/native-cli-87237.log) passed one
case, with ten excluded. It created actual reviewed Session assertions and used
an actual native-reviewed short retention deadline. A real native review and
atomic Core transaction then formed the historical successor relation using an
**explicitly synthetic trusted successor source**; this fixture is not the
missing Session source-lease integration. The test disabled capture, waited for
the real deadline, and ran the standalone command. A staged-publication callback
confirmed that the management intent was already journaled before root switch.
The result and protected operation settled with no model, download or cost;
the old record was removed, the successor and original Session journal remained,
and operation inspection did not replay it.

The [first instrumented attempt](history-cli-evidence/native-cli-87236.log)
successfully settled the CLI effect but failed its test assertion: the callback
wrote a process-local marker while the assertion checked a different process.
The focused retry replaced that marker with a message to the test owner and
passed. The failure log is retained, and its inputs and displayed text are
synthetic fixtures.

The isolated `_build/history-cli-sol-20261028` runtime was copied from the frozen
expiry-management graph. [Strict compilation](history-cli-evidence/compile.log)
passed with no compile or runtime warnings. The [source hashes](history-cli-evidence/source-sha256.txt)
identify the captured affected sources and test fixtures under that graph's
`evidence-source` directory; [runtime hashes](history-cli-evidence/runtime-sha256.txt)
identify the actual BEAMs, application descriptors and packaged `priv` files,
including the native helper. The Collection BEAM was frozen before the later
independent legacy-worker-read repair; the concurrently changed Collection
source is deliberately not presented as its exact build input. [Log hashes](history-cli-evidence/log-sha256.txt)
cover the recorded compile, failing control and passing controls. The separate
worker-read repair and later current-source build require their own validation.

The repository documentation checker passed once after the operator and
developer command descriptions were updated: 698 Markdown files and 5,736 local
links, zero errors. Full editorial review and final milestone checks remain.
