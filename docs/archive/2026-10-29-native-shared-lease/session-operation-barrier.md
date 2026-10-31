# Session operation seal: inactive pre-export section — 2026-10-29

This is a focused checkpoint, not guarded-output acceptance. The prior
[Session sharing candidate](session-share-candidate.md) and its independent
review retain their exact source, binaries and evidence. The user-facing
supersession and managed-result output gates remain closed. This checkpoint adds
no native descriptor export caller, native terminal guardian, Session/Host EOF
control or supported end-to-end guarded display.

A private Session message now admits a seal only for the current task, job,
active action and matching selected extension identity in a share-capable
candidate Session. It installs its state before asynchronously asking the Writer
for its source-window and journal checkpoint. While the seal exists, other
Session calls, including source/proof queries and mutation requests, fail before
they reach the Writer. Matching Writer and Lock replies arm the existing native
share guard; the task receives an opaque capability, transport binding and
snapshot. A matching task can request pre-export cancellation and asynchronous
thaw. Unexpected Session events, a five-second setup timer, task loss or either
cancellation entry quarantines the operation. Cancellation kills the active task
and returns an unconfirmed result without waiting for a suspended Writer. A
quarantined Session rejects further operations and close is unconfirmed. Its
actual resources remain subject to their existing cleanup mechanisms; no
already queued IO is declared absent. The timer is handled by the Session
mailbox, not a hard preemption bound on unrelated prior synchronous work.

`close_confirmed` also tolerates a refused observation-drain query so that a
quarantined Session reaches its unconfirmed close rather than raising a match
error. No successful closure or signature is inferred from this path.

## Evidence and scope

The private fixture starts a real native-lock candidate Session and its real
Writer. It injects a synthetic action/task into that Session using
`:sys.replace_state`; the task is owned by the Session's actual Task supervisor
relationship. This tests Session mailbox ordering and native guard arming, but
is not a genuine extension Host invocation or a worker authorization proof.
The tests cover sealed source and prompt calls before Writer drain, a foreign
abort refusal, pre-export abort/thaw, both cancellation entry points while the
Writer is suspended, unexpected-event quarantine and the real setup timer.
The final focused run reports **5 passed**. Strict compilation of the changed
Session and latest Journal succeeded. The helper and rest of the runtime are
inherited from the prior frozen candidate; the final runtime inventory records
all files in `_build/session-operation-barrier-sol-20261029/lib`. The Journal
and Writer sources include the independently developed Management native-owner
predicate; the later Journal overlay is separately logged. No network, model,
aggregate or terminal test ran.

The [evidence directory](evidence/session-operation-barrier/) contains the final
source tar, runtime inventory and logs, including the first close-path failure
and earlier synthetic-task-owner failures. In the latter, assertions passed but
Session teardown logged a Task ownership error; those runs do not establish
clean teardown. The final fixture creates the task from the Session itself, and
its final run has no such termination errors.

Reproduction for the final focused test, after compiling the snapshot into its
matching isolated graph:

```sh
ERL_FLAGS='+S 4' ERL_LIBS="$PWD/_build/session-operation-barrier-sol-20261029/lib" \
  elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/share_operation_barrier_test.exs")'
```

Still required before activation: a genuine Host/job entry and adversarial
identity/control tests; native export and authenticated all-copy close/thaw
bound to the sealed operation; actual Session and Host EOF fences; bounded
full setup and quarantine with owner-loss controls; the matched tty's native
writer and forked-reader quiescence; fixed non-sensitive prompt; all retained
lease and revocation ordering tests; and the later effect-side revalidation and
live one-use approval. This seal does not prove those boundaries, nor does it
make asynchronous BEAM task death proof that a native write has stopped.
