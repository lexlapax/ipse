# Worker-input cancellation at completion — 2026-11-02

Dated **2026-11-02**. Author-run synthetic diagnosis and focused runtime repair
from `e40fe07` plus the changes described here. This is not an independent audit,
installed qualification or a replacement full-suite result. Current ownership
guidance belongs to [architecture](../../developer/architecture.md); verification
procedures belong to [testing](../../developer/testing.md). The [plan](../../plan.md)
owns milestone status.
The [receipt](worker-input-cancel-20261102.json) binds source and raw-log hashes.

## Failure and controlled reproduction

The [frozen source baseline](full-suite-20261102.md) ended with one failure:
protected-outer cancellation returned `cleanup_unconfirmed`. An unchanged
isolated pass did not explain it. A later optional argument-free trace reproduced
that result: Worker native cleanup returned `ok`, but task-scope cleanup waited
4,000 ms and remained unconfirmed. Its retained synthetic root is
`/tmp/ipse-collection-sdk-c2c4812253456eb6f1f4c92ea9201024`; the original input
intent has no completion result. The raw log is
`/tmp/ipse-protected-outer-cancel-probe-20261102.log`.

The controlled regression uses the existing independent artifact's explicit
barrier. A Session system-debug hook arms only for the snapshot's protected
`host.actions` input. It holds the next writer-thaw response, queues cancellation
in the actual Session mailbox, then allows thaw to complete. The publisher can
now request input completion while Session is already waiting for task cleanup.
No hook fabricates a response, receipt, source, permission or journal event.

Before the runtime repair, seed `791767` exited **2**: **zero of two passed,
189 excluded**, 22.1 seconds. The new controlled test returned exactly
`{:error, :cleanup_unconfirmed}` from cancellation. The unchanged original test
also exposed its separate timing assumption: `Session.info/1` correctly refused
with `session_share_frozen` after the independent VM had emitted its marker.
Raw log: `/tmp/ipse-protected-outer-cancel-controlled-before-20261102.log`.

## Repair and positive observations

The tracked publisher previously used a blocking `GenServer.call` to commit its
input completion after all native source/policy scopes returned. Session's
cancellation path could wait for that same publisher, producing a circular wait.
The completion request now uses an OTP request alias with the original five-second
deadline and an interruption bound to the exact Session, job reference and input
ID. Cancellation sends that notification before closing task resources. The
publisher checks it only after the native scopes return; ordinary file effects
are neither killed nor declared settled. An abandoned request alias is removed.

The pre-settlement test still requires `:ok` cancellation and confirmed close.
It observes the tracked publisher and Worker exit, verifies native-helper exit,
and requires the exact input intent to have no invented completion result. The
outer invocation also has no result. Strict reconstruction and idle resume make
no callback replay. The settled test uses the existing matching delivered-input
receipt check instead of treating a VM marker as host settlement. A third test
supplies mismatched Session/job/input identifiers; genuine delivery must still
settle before cancellation.

The initial repair passed both controls, seed `791768`, terminal **0**, 11.9
seconds. The stronger exit assertions first found a test-only Registry alias
mistake at seed `791769` (terminal **2**, one of two passed); correcting that
alias passed both controls at seed `791770`, terminal **0**, 11.9 seconds.
After adding the mismatch case, the final focused selection was:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only protected_outer_cancel --max-cases 1 --seed 791771
```

Terminal **0**: **three passed, 189 excluded**, 13.0 seconds. Raw log:
`/tmp/ipse-protected-outer-cancel-final-controls-20261102.log`.

The broader resource/file-effect/recovery/Worker/native-pipe/controlled-peer/probe
selection, seed `791772`, exited **0**: **61 passed**, 39.2 seconds. Its raw log is
`/tmp/ipse-worker-input-cleanup-regressions-20261102.log`. These checks preserve
blocked-file-effect ownership and native cleanup requirements; they do not prove
all managed transport boundaries.

The required source build, global format check, warning-free compile and
credential-free demo each exited **0**. Documentation validation exited **0**:
1,038 Markdown files, 8,595 local links, no errors. Its Git enumeration warnings
for private staging directories do not establish their inspection. Architecture
now explains the interruptible completion boundary, and testing teaches both
orderings. The operator recovery chapter already distinguishes transport
settlement, callback completion and unknown effects; its recovery procedure
remains applicable.

## Scope and remaining checks

This repairs the demonstrated post-native-scope completion wait. It does not
qualify every earlier transfer/cancellation boundary, broaden a supported Worker
purpose, turn an unfinished input into delivered transport or establish callback
success. The optional trace instrumentation was removed from the candidate;
production tracing behavior is unchanged. The original failed aggregate and
diagnostic failures remain evidence rather than being recomputed as passes.
Broader ownership/recovery checks and a new complete candidate baseline retain
their separate results. Whole P30/P31 integration, quality, workload, installed
acceptance, final adversarial audit and reviewer handoff remain open.
