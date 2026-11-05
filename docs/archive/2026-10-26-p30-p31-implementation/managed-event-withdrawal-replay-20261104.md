# Reconstruct a confirmed withdrawn event result — 2026-11-04

Historical checkpoint only. Current guidance is in [recovery](../../operator/recovery.md),
[event jobs](../../developer/extension-events.md) and
[persistence](../../developer/persistence.md). This repair authenticates saved
completion; it does not fix live final-output revalidation or qualify retained recall.

## Cause and bounded change

`ManagedOutput.complete_event/3` correctly records a failed job after confirmed
withdrawal of its output, even when earlier reads succeeded. Subscription replay
instead predicted completion from action statuses alone. `Actions.restore/1`
therefore rejected the valid failed event result as `invalid_extension_action`.

The repair uses the existing ManagedOutput intent, bound-result, admission and
cleanup validators for one exact active job. Parent, Session, ordered actions,
raw result, release identity and hashes must bind chronologically. Confirmed
noncurrent output predicts failure; current output retains ordinary action
outcome rules. A decision string alone, missing/unknown cleanup, foreign job or
changed digest cannot authenticate a known result. Unknown handling, source
admission, permissions, publication and no-replay rules remain unchanged.

## Checks actually completed

- The unchanged `1af4a7c8` runtime reconstructs the constructed history through
  release cleanup, then reproduces the refusal at the next failed event result.
- The one-module candidate compiles with warnings denied. Six pure causal and
  tamper tests pass, including current/completed, withdrawn/failed and explicit
  unknown delivery, plus foreign/missing/changed/duplicate-chain refusals.
- The exact old runtime plus that one replacement module reconstructs all 207
  actual failed-read events in place. Original bytes, inode, mode, size, mtime
  and ctime remain unchanged. Access time is excluded from identity. No App,
  helper, Session resume, inference, reconciliation or journal copy occurs.
- The integrated app-backed subscriptions, event-job and managed-replay owners
  pass 36 cases in 22.2 seconds, including the six new cases. Format and strict
  compilation pass. The canonical integration documentation check reports 1,196
  Markdown files and 9,819 local links with zero errors.
- The normal native/197-source/four-bundle build, repository formatting check,
  strict compilation and credential-free demo in an isolated home pass on the
  working integration tree. The consolidated full test run remains open.

The [safe packet](managed-event-withdrawal-replay-20261104/README.md) retains exact paired patches and logs.
Its [manifest](managed-event-withdrawal-replay-20261104/SHA256SUMS) and [fixed outcomes](managed-event-withdrawal-replay-20261104/safe-result.json)
bind the evidence without publishing private history.

## Preserved failures and limits

The first synthetic fixture incorrectly inserted a question-only continuation;
its failure is retained privately, followed by the corrected causal fixture.
The first in-place check got past Saved but failed an overstrict access-time
comparison. The successful second check uses the repository identity contract;
both outcomes remain recorded. An initial `--no-start` compatibility invocation
also failed setup for App-dependent owners; the corrected 36-case run is separate.

The actual retained read remains FAILED with partial request finality. Its
unresolved service reservation and the earlier unknowns are not refunded,
cleared, replayed or reclassified by offline reconstruction. No source text is
made eligible by a saved completion receipt. Ordinary current-source output
release, a successful retained-cohort read, integrated day/annual work and the
final combined regression remain separate gates.
