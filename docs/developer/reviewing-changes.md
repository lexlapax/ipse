# Review a change at its boundaries

A useful review traces what the change can do, who owns it and how a failure is
represented. This chapter teaches that process for Ipse contributors. Read the
[architecture](architecture.md) first, then use the
[security context](../../SECURITY.md) for attacker capabilities and private reporting.

## Establish the candidate

Start with the actual working tree and diff:

```sh
git status --short
git diff --stat
git diff
```

For a committed candidate, compare its exact revision with the intended base.
Record unrelated local edits and preserve them. Confirm that the source, tests,
manuals and dependency declarations in the diff describe the same final behavior.
Read the surrounding callers and recovery paths, not only added lines.

An extension-only change can still propose host effects. A core change can affect
every extension. Determine the authority and compatibility boundary before
judging the diff's size. [Extension authoring](extensions.md) explains when domain
behavior can remain outside the host.

## Trace one complete operation

Use this source-reading exercise on worker cleanup:

```sh
rg -n 'record_cleanup|close_helper' lib/ipse/extensions/worker.ex
rg -n 'confirm|close_claimed|await_result' lib/ipse/extensions/worker_lease.ex
mix test test/extensions_worker_test.exs test/observability_test.exs
```

Follow a callback failure through Worker termination, native cleanup and the
shared lease. The callback can fail while its OS cleanup is confirmed. Conversely,
a vanished worker without a native receipt cannot establish cleanup. Read the
journal consumer that records the result. A local `:ok` that is discarded before
that consumer sees it is not an end-to-end success.

For another change, select its equivalent complete path: input validation,
capability/approval, admitted intent, effect, result receipt, cleanup, saved
validation and idle resume. Identify every process that can exit between steps.
Ask what another process could still be doing after its caller dies.

## Test authority with positive and negative controls

Changing a boundary requires proving both the allowed operation and the refusal.
For a file action, verify that ordinary approved workspace access still works,
then check the escaped/protected path before any effect. For a provider field,
verify an ordinary valid response and the rejected malformed variant. For a
scope/binding change, exercise both a permitted namespace and an unauthorized
cross-scope request.

Do not infer refusal from missing display output. Inspect whether an intent was
journaled, a file changed, a server received the request or a worker actually
exited. Model text, repository instructions, tool results, question answers and
extension payloads do not grant action permission. Keep full approval arguments
visible and bound to the actual proposal.

## Inspect failure and recovery

A useful finding names the specific trigger and consequence:

```text
Trigger: the effect's owner exits after the write starts but before its result.
Expected: saved recovery retains an unknown outcome and does not replay the write.
Observed: the candidate reports not_started and permits an automatic retry.
Evidence: exact source/call path, synthetic fixture and before/after file state.
```

Use synthetic data for reproductions. Preserve the first failure. Do not change
production deadlines, add readiness/sleeps or accept several outcomes merely to
make a strict regression pass. A fixture coordination change needs a causal
explanation of why the product behavior was already correct.

Check saved validation before torn-tail repair. A malformed committed receipt
must not become acceptable because a later repair removed evidence. Review
configuration drift, stale CAS generations, source references and cached result
bindings. Use [persistence](persistence.md), [state calls](extension-state.md#read-a-revision-and-propose-a-write)
and the matching subsystem chapter to find the validator.

## Review dependencies and disclosures

A new parser, transport, executable or hosted service changes more than a function
signature. Check the [dependency inventory](dependencies.md), scope and required
approval. Verify TLS and endpoint/proxy authority before credential acquisition.
A project-selected setting must not impersonate an operator-approved destination
or silently choose another billing mode.

Review display and diagnostic paths as outputs. Escape terminal controls, keep
native hidden reasoning private, and check that traces omit arguments, credentials
and private messages. A content-free summary must remain content-free on its
error path too. Same-user filesystem trust limits belong in the threat model,
not in an unsupported claim of protection against arbitrary hostile replacement.

## Close the review

Run focused behavioral checks, then the [handoff baseline](testing.md) appropriate
to the change. Inspect the real artifact and exact revision. Say whether the
review was static, fixture-based, live-account or OS-enforcement work. List
coverage omissions and unresolved findings rather than converting them into an
unqualified approval.

Keep vulnerability details and raw reports private using [the reporting
procedure](../../SECURITY.md#reporting). External scans, paid inference, report
publication and deployment need the operator's applicable authorization. A review
request or a local instruction file does not grant it. Store sanitized dated
findings and verification receipts in the archive, and keep current manuals
focused on how contributors repeat the work.
