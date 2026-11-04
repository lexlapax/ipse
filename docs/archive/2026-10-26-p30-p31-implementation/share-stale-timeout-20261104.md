# Completed-share timeout isolation — 2026-11-04

Historical qualification of a narrow Session timer repair against `9b1a4e5e`.
The [safe validation record](share-stale-timeout-20261104/result.json) and
[source patch](share-stale-timeout-20261104/source.patch) identify its scope.
Current ownership guidance belongs to [persistence training](../../developer/persistence.md)
and [Session source training](../../developer/session-sources.md); the
[plan](../../plan.md) owns remaining acceptance.

## Reproduced defect and repair

Each protected share schedules a timeout carrying its own generation. Cancelling
a timer does not remove a message already queued for delivery. Previously, a
well-formed timeout from a completed generation fell through to the generic
unexpected-message quarantine when another share was active.

The regression starts a real native-backed Session share, aborts it with
confirmed cleanup, then starts another share with a distinct generation and
capability. Delivering the first generation's late timeout poisons the second
armed barrier on the original runtime: zero of one selected tests pass, with
five excluded. This is a deterministic delayed-message protocol reproduction,
not a probabilistic timer-scheduling experiment.

The repair ignores only `session_share_timeout` messages whose generation and
the active generation are references and differ. It leaves the complete active
barrier and its timer unchanged. Current-generation timeout, malformed messages,
unrecognized events, native owner checks, policy/source deadlines and cleanup
requirements retain their existing behavior. No deadline, quota or permission
changes. The new test additionally aborts and closes the second share normally.

The complete share-operation module then passes **six tests in 5.3 seconds**,
including the existing current setup-timeout, unexpected-message and cancellation
controls. Strict test compilation, the PDF-free full build (197 source files and
four inert bundles), formatting and the isolated credential-free demo pass.
The concurrently running full regression uses its separately frozen `9b1a4e5e`
source and does not qualify this later repair. No release or platform claim follows.

## Separate retained-cohort failure

An ordinary untraced read of the retained 2,000-note cohort on the earlier
`09f9beb4` runtime stops after 30 delivered Worker inputs. Its 31st input is
unknown; the Session emits the fixed protected-ownership-loss message and stops.
All 33 completed action results are successful. Recorded managed reads contain
two version-3 dependencies and 29 version-4 dependencies. There is no inference
dispatch, provider request or inference-service ledger creation.

Full observation and independent regular-file checks preserve every original
record, control/accounting/artifact file and external receipt. Only the Session
directory metadata and canonical CTIME changes to 277 existing Session lock
files occur; their bytes, inode, mode and other recorded properties remain exact.
The sole additions are the new uncertain consumer's journal and lock. All four
earlier uncertain journals retain exact bytes and metadata. Cleanup verification
passes and matching processes, the fixed listener and operator holder are absent.

This failure establishes controlled WorkerInput share quarantine, but does not
identify its triggering branch. The 120-second asynchronous publication timer
does not apply to this `event.job` invocation. The final input's approximately
five-second budget and preceding elapsed time do not prove expiry. Native owner,
Writer/caller, deadline and unexpected-message paths converge on the same public
error. The separately reproduced stale-timer bug is not claimed as this run's
cause. The failed read is preserved without replay or another read attempt;
populated recall, the integrated day and annual qualification remain open.
