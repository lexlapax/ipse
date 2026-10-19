# Expiry at approved state writes, 2026-10-19

Design and investigation record for P26 remediation. Current behavior belongs in
the [memory user manual](../../operator/memory.md) and
[developer training chapter](../../developer/memory.md). This draft does not
establish implementation, verification or milestone completion.

The user selected rejection when an existing note expires while its update is
waiting for approval. A proposal prepared while the target is live must not renew
that source after expiry. Both remember and active import need this guarantee.
Fresh backup import may still restore an expired value with its original expiry.
Suppression, separate full-argument approval, CAS, journals and inert recovery
remain required. New host behavior must be generic rather than interpreting note
fields or adding a core memory branch.

## Design checkpoints

- [x] Ground the approved-write path and current ownership.
- [x] Compare at least two distinct designs and cross-judge their contracts.
- [x] Select a bounded contract without an additional human checkpoint.
- [x] Reproduce the delayed-approval failure and implement the selected design.
- [ ] Verify public remember/import, host receipts, unchanged legacy requests,
  recovery and actual expiry boundaries; redesign if evidence contradicts the sketch.

The current full suite predates this planned change. No source, runtime, test or
fixture-data edits occur until that live operation ends.

## Grounded ownership and flow

The read-only `p26_expiry_grounding` session traced Memory, Records, Host, Session,
Actions, Operation and State. It returned `ISSUES` with no runtime check or writes.

Memory owns note source/generation, retention, suppression and migration. It
captures `state.now` at invocation, reads State, validates the observed revision,
and uses `Records.build/4` or `import_note/4` to prepare an exact `state.put`.
That proposal currently contains only operation, scope, key, expected revision
and value. No temporal precondition crosses the worker boundary.

Actions validates the closed request and capabilities. Session verifies ownership
and the current extension identity. In ask mode it displays the complete request
and holds the host call pending indefinitely. Approval journals the source-bound
intent before execution and checks the extension's registry lifetime, not note
expiry. Host then calls `State.execute/4`.

State's filesystem completion owner obtains the persistent namespace lock,
reads current state, checks CAS/quota and publishes a synced temporary write by
rename. It has no time condition. A check at approval alone would leave a gap
before this locked mutation; a check after the result would be too late.

Host converts the outcome, and Session validates and journals the receipt before
resuming Memory. State's receipt validator currently supports successful values,
revision conflicts and empty denied/unknown outcomes. Actions already permits a
`failed` envelope, but State does not yet validate a known failed write.
Existing conflicts require a changed revision and cannot truthfully represent
elapsed time with an unchanged target.

The suitable enforcement boundary is inside the locked mutation path, after the
target read and before revision/generation changes. Memory must decide which
operations carry a condition and derive it from the existing target. Core must
not interpret note fields. Fresh imports of already-expired backup values remain
valid, while replacement of an expired existing target must refuse. Suppression
and migration retain their separate domain rules.

Receipts bind the exact request, digest, namespace, identity, operation ID, step
and approval. Interruption may leave an effect unknown; State retains its operation
ID for inspection. Pure journal recovery validates recorded chains and does not
replay ordinary unfinished writes. A new precondition must preserve these rules.

## Selection rubric

Candidate designs must demonstrate locked expiry refusal with CAS intact for
remember and active import; preserve live updates, fresh expired backups and
suppression; keep core generic; represent a known non-effect durably; validate
bounded inputs without a condition framework or dependency; and specify real
clock/approval tests plus legacy-request controls. Compare at least two whole
shapes and record the cost of rejected alternatives.

## Selected contract and synthesis

Two independent candidate sessions produced complete designs. Both selected a
generic locked write deadline and compared structurally distinct domain-only
expiry/candidate models and preapproval timeout/continuation models. The cross-judge
read both complete candidates and current source. Its six rubric scores totaled
28/30 for A and 29/30 for B. Root independently selects B as the base for its
more accurate proof plan and small interface.

The chosen request adds optional integer `write_before_ms` to `state.put` only.
It must be in 0 through 2^53-1. Absence retains old behavior; explicit null and
unknown fields refuse. Memory copies the existing target's expiry only for
remember or active import replacing an active value. The model cannot supply or
omit this internal condition. Fresh backup import, suppression, collection and
migration retain their existing shapes.

State checks CAS first, then samples its own wall clock under the namespace lock.
At or after the deadline it returns a known failed non-effect. A second check
after synced temporary output and chmod, immediately before rename, prevents
staging delay from bypassing the condition. The linearization point is that
locked publication decision. No clock sample can promise the physical rename
syscall completes before the same wall-clock millisecond. Existing clock-rollback
limits remain.

The exact failed value contains `code: "write_deadline_elapsed"`,
`checked_at_ms`, unchanged `generation`, and unchanged record metadata without
its value. Validation requires a deadline-bearing put, a recorded check at or
after that deadline, matching key/revision and a valid previous operation ID.
The failed operation must not claim it wrote the old record. Recovery compares
recorded values, never today's clock. Existing Host, Actions, Operation and Session
already carry exact requests and `failed` envelopes; do not add forwarding code.

Memory maps this failure to `source_expired` only for remember/import in write
phase. Retain details, do not retry, and refresh its clock after target reads so
an already-expired target refuses before asking approval. Records additionally
retains the explicit migration gate on active imports over legacy targets.

Root grafts A's explicit preservation of an elapsed staging return through
`write` cleanup and its narrowly scoped Memory failure handler. B correctly
rejects A's proposed lock-queue test: current advisory lock contention refuses
immediately. Keep that behavior. No production IO adapter, injected public clock,
callback under the lock or condition language is justified for a staging test.
Actual delayed-approval and State failure tests establish the selected behavior;
review the final check's placement and report any unexercised forced-staging case.

Rejected alternatives either prohibit currently allowed live renewal, retain a
clock/write gap, add domain candidate/reader coordination, or bypass host storage
ownership. The only added host field expresses a generic publication constraint;
core does not interpret note schemas. No dependency is added.

## Implementation sketch

Existing public function arities remain unchanged. These sketches state the
contract and are not implementation:

```elixir
State.validate(request) # accepts bounded optional write_before_ms only on put
State.execute(root, namespace, request, operation_id)
# CAS conflict retains its old shape.
# elapsed => {:failed, %{code, checked_at_ms, generation, record_summary}}
# live or unbounded => existing {:ok, %{generation, record}} shape
State.valid_outcome?(request, status, value, operation_id)
# Closed failed shape; compare checked_at_ms with the approved request deadline.

Memory.write(record, replacement, state) # private existing helper
# remember/import + active old/new => attach old.expires_at_ms to exact request
# host failed/write_deadline_elapsed => source_expired with details, no retry
```

Implementation belongs in Memory and State. Existing generic action/journal
machinery must prove it carries the request and failure unchanged through actual
Sessions and idle resume. Focused tests cover invalid fields, CAS precedence,
unchanged stored bytes, receipt tampering, live renewal controls, delayed approval
for remember and active import, fresh expired backups, and explicit legacy
migration. The full baseline currently running predates this contract.

## Local implementation evidence

The preceding full baseline completed before implementation: 1,153 passed,
32 excluded, 676.9 seconds. Both actual delayed-approval regressions then returned
`stored` after the target expired. The legacy import regression also returned
`stored` rather than `migration_required`. The two live controls separately exposed
the absent approved deadline field. That run passed 21 of 26 tests in 18.8 seconds.
Before adding the State contract, its two new tests failed, with five existing
State tests passing in 0.3 seconds.

After implementation, State plus memory/Session/binding/scan passed 40 tests in
20.5 seconds. An additional deterministic delayed-read regression covers both
remember and active import without a scheduling sleep. The final focused run
passed 41 in 19.6 seconds. Real Session tests wait for the observed record expiry,
check the target is live when approval is proposed, approve after that boundary,
and verify `source_expired`, exact unchanged State, a known failed journal receipt,
continued recall and unchanged idle resume. Separate before-expiry controls renew
successfully. The Elixir 1.18 formatting check also passes.

No forced delay inside temporary staging was exercised. Source inspection checks
the second deadline test occurs after sync/chmod and before rename, with explicit
elapsed propagation and temporary cleanup. The public approval-boundary and
generic State tests are executed evidence; they are not a claim of a forced slow
filesystem experiment. Full refreshed gates and another internal review remain
open before external review.
