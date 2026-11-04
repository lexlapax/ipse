# P30 simultaneous pending assessment: committed-preflight cohort

2026-11-04. Historical failed synthetic control; this is not a passing P30
consumer qualification. No paid model, external service or real user source was
used. The two genuine pending proposals belonged to distinct closed original
Sessions under the same project, policy, local service origin and one-call pool.

The single fresh cohort completed in 21.8 seconds with one failed outer test.
Both children returned and were collected. Every private input/runtime/pathset
postcheck passed; the global operator lock had no holder before or after the
cohort. No failed or unknown operation was replayed.

## Established boundaries

- Both exact decision operations have one matching durable preflight intent and
  one later matching result, with no matching refusal. The watcher loaded those
  actual records before publishing its barrier receipt. `Session.record` calls
  the Writer synchronously; no asynchronous append assumption is needed.
- The actual worker holds were 2,851 ms and 116 ms, within the unchanged 4,000 ms
  fixture ceiling. The production preflight call remains 5,000 ms.
- Both real reservation APIs entered. The first child's assertions established
  a rejected reservation with `fits=false` and one model call already used. The
  second established a fitting reservation with zero model calls previously
  used and a successful reservation return. These are observations of the real
  shared one-call pool, not constructed allowance records.
- The ledger retains exactly one model-call operation as `unknown`, with one
  reserved call and no known actual charge or receipt. Neither decision action
  succeeded. There are zero decision dispatch intents, responses or provider
  wire observations, and zero consumer publication intents.
- The inference service ledger has sequence 14 and 13 settled recent entries;
  all 13 recorded provider observations are ordinary main requests. The extra
  decision service request was removed before service admission. Queue and
  active counts are zero.
- Both completed consumer journals pass `Saved.restore`; both original source
  byte hashes remain unchanged. The first child's subsequent real idle reopen
  refused with `invalid_semantic_admission`, so this cohort does not establish
  idle reopen/no-replay success.

## Failure classification

The budget race itself reached both real reserve/fits paths and admitted at most
one reservation. The reserved operation then failed before dispatch and was
conservatively retained as unknown. Its exact later service-gate reason is not
persisted: the public action result is `decision_request_failed`. This evidence
does not identify a production guard defect or prove a particular busy lock.

The second child's postlude also has a fixture classifier defect: it calls an
operation the winner only when final action delivery succeeds. A reservation
winner can subsequently fail closed. Consequently it incorrectly expected a
reservation error after observing a fitting successful reservation. Correcting
that label alone would not make this cohort pass: the required known settlement,
single decision egress and completed idle reopen remain unproved.

The change in EOF timing is not established as the cause. On native EOF the
reader remains alive; the busy Terminal changes its own exit flag without
canceling the Session. The committed dispatch seal includes input, tools,
source, mode, admission and policy hashes, not the input observation entry or
operator channel. No fourth cohort or replacement barrier is authorized by this
report.

## Scope and next gate

Preserve this failed outcome and the earlier two cohorts separately. Existing
single-consumer known-settlement evidence and the observed simultaneous pool
exclusion must not be relabeled as a successful simultaneous delivery. A next
change needs a concrete explanation of the later service-gate refusal, or an
explicitly reviewed acceptance decomposition that retains the missing liveness
claim. Production locks, leases, call deadlines and budget limits are unchanged.

The retained reports expose counts, typed public failures and hashes only.
Private terminal transcripts, source text and control records remain outside
the public packet.
