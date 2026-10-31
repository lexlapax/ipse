# Native check-to-rename interposition and publication gate

Historical scoped receipt, 2026-10-29. This supersedes the strict final-switch
interpretation in [the preceding deadline receipt](managed-publication-deadline-followup.md).
Its positive cohort remains historical; stopping before command processing did
not establish an atomic deadline boundary. Current milestone status belongs to
[the plan](../../plan.md). This is containment, not completed P31C0 architecture.

The subsequent [independent gate review](strict-deadline-gate-independent-review.md)
identified additional forgetting, State-backend and document-stage boundaries
that are being investigated; this Collection gate does not by itself close them.

## Reproduce the actual native gap

`dev/fixtures/transaction_deadline_interposition.rs` traces its own child on Linux
x86_64. It runs the unmodified matched a51c2d helper, acquires a real transaction
lock, queues `T`, and stops at kernel `renameat` syscall entry. At that point all
userspace deadline checks have completed but rename has not executed. The root
still contains the synthetic `before` bytes. It resumes only after expiry, then
checks both actual root bytes and the helper's successful `T` reply.

```sh
rustc --edition=2021 -D warnings dev/fixtures/transaction_deadline_interposition.rs \
  -o /tmp/ipse-deadline-probe
/tmp/ipse-deadline-probe /absolute/path/to/matched/ipse-runner \
  /tmp/ipse-new-private-deadline-directory
```

The directory argument must not exist. Preserve the diagnostic directory for
inspection. The fixture needs permission to ptrace its own child and accepts no
external PID. It is an OS-specific diagnostic, not a portable runtime feature.
It intentionally succeeds when the late-rename defect is demonstrated.

46877 retained the sandbox's `Operation not permitted` refusal. The authorized
own-child diagnostic46878 reproduced the defect with the original helper:

```text
LATE_NATIVE_SWITCH_PROVED entered_ms=1793281902220 deadline_ms=1793281903718 resumed_ms=1793281903768 successful_reply=T root=after
```

No native source hook, clock substitution or helper modification was used.
The helper SHA-256 was
`a51c2d34654e21b0418b31bbe5ec2423d117230a3a8f3687803d5c1438d1c12e`.
This is stronger than stopping a helper before it processes the deadline command.

## Current refusal boundary

Collection's deadline admission and callback/profile entries now refuse.
Protected Session publication refuses before candidate intent and reservation;
the two adapters also retain an independent callback gate. Deadline-bearing
retention/supersession normalization refuses before mutation staging, with a
final pointer-switch refusal as a backstop for any inherited deadline. No
configuration flag, worker field or `--yes` can enable the blocked callback.

The fixed host dispatch in the gate deliberately keeps retained callers' result
contracts opaque to Elixir's return-type inference. A constant narrowed return
otherwise makes historical deferred/activation branches compile as unreachable.
The module and function are fixed in core; callers cannot select a backend, and
the refusal implementation never invokes the supplied callback. Those retained
branches are not accepted current publication behavior.

User-visible behavior is explicit:

- `/remember` refuses before statement review. Protected capture refuses before
  its collection effect, with the temporary deadline-gate diagnostic.
- Pin, automatic and duration retention CLI choices refuse before review;
  session-only suppression has its separate forgetting path.
- Deadline-bearing Collection document stages refuse, even with no inherited
  managed input: their stage expiry is itself a strict deadline. Fused multipart
  and prepare/seal therefore cannot be presented as currently working journeys.
- Ordinary internal no-deadline Collection operations remain available and grant
  no Consent authority. An ordinary small inline document write with neither a
  stage nor trusted deadline remains separate. It does not qualify a complete
  large-source/index workflow.
- Existing reads/inspection, forgetting and elapsed-policy reclamation keep their
  separate authority. They were not rerun or newly qualified by this section.

`Transaction.switch_before/4` remains a low-level pre-syscall check. Its corrected
docstring explicitly disclaims a strict no-late-rename guarantee. Public host
publication cannot use it to bypass the gate. Earlier uncertain operations remain
unknown until inspected; the gate does not roll back prior effects or replay them.

## Focused evidence and limits

Strict compile46881 passed 14 modules from 11 source files; final Terminal help
compile46887 also passed. Initial compile46879/80 logs retain stale history helper
APIs and the constant-refusal type warnings, which were repaired before testing.
Six history-component BEAMs were copied from the existing coherent commitment
cohort to satisfy the current standalone owner API; their history paths were not
requalified here. A candidate Session.Lock API BEAM supports compilation of the
shared Session source, but these tests use only the ordinary legacy startup path
with the matched a51c helper. The candidate was not activated in this graph.

Five focused controls passed without aggregate reruns:

- 46882: two actual Session managed/unmanaged publication attempts refused before
  mutation intent, reservation or root change and emitted actionable diagnostics.
- 46883: early non-session retention refusal and diagnostic passed. The other
  test failed because its direct Core fixture used `/tmp` as the private parent.
  Moving only that fixture's store under its owned private directory repaired it.
- 46884: only the failed compatibility case reran and passed. Strict callback and
  profile entries invoked no callback or staging; ordinary no-deadline native
  write/read succeeded.
- 46886: actual standalone retention CLI returned failure with the temporary-gate
  message, no review and no management journal.

Seven operator/developer manuals were reconciled around the current unavailable
routes, existing-data reads and recovery. CLI help and diagnostics describe the
same gate. Documentation check46885 found 12 inherited archive-navigation/log-link
errors; the parent repaired their links without modifying frozen source bytes.
46888 then checked 730 Markdown files and 6155 local links with zero errors;
final46889 including this receipt checked 731 files and 6164 links with zero errors.
Scoped formatting and whitespace checks passed. No terminal PTY, paid service,
new dependency, new native helper build or milestone completion is claimed.

The [manifest](strict-deadline-interposition/manifest.json) freezes exact source,
tests, diagnostic code, logs, manuals and the runtime inventory.
Manual byte snapshots use `.md.txt` so their historical relative links are not
mistaken for a second current navigation tree. Session source
was snapshotted before Lifecycle's subsequent independent candidate-startup
repairs; that candidate branch is not this record's acceptance scope.

A second userspace check, scheduled monitor or seccomp continuation merely moves
the scheduling gap. A timer-kill alone does not prove cancellation of a filesystem
mutation already entered in the kernel. A strict physical no-late-rename contract
needs an enforceable kernel/filesystem conditional mutation with a defensible
time/linearization definition. An eligibility-at-use or authorization-linearization
alternative requires explicit design review; it is not a silent reinterpretation
of Consent. No such replacement architecture is implemented here.

The real literal-v4 A/B control remains open. Earlier A/B evidence concerns v3
roots/proposals. Shared native lease ownership, full managed display sinks,
delegation, managed service/State execution, nested worker-result release and
disabled supersession also retain their separate limits.
