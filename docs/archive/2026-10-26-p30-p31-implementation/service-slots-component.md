# Protected inference-service slot component

Dated **2026-10-26**. This is an internal component receipt, not dispatch
integration, operator setup instructions or P31D/F acceptance. The
[frozen baseline](baseline.md#optional-local-embeddings-and-rag) and
[coordination contract](contracts.md#consent-commit-order-and-process-coordination)
remain authoritative; the [plan](../../plan.md) owns milestone status.

## API and actual ownership

`Ipse.InferenceSlots.run/5` accepts admitted configuration, a closed
SemanticRoutes selector, host Session/project/request digests, explicit wait and
dispatch deadlines, and one trusted callback. It derives endpoint/model/service
identity from the admitted configuration; caller-provided endpoint fields refuse.
`start/5`, `await/1` and `cancel/1` expose an owner-bound, one-use volatile handle.
JSON cannot reconstruct a handle, and a different caller cannot await or cancel
one. The callback receives the derived route and reservation ID. No SDK operation
or ordinary approval bypass is added by this component.

The caller must supply the actual selected dispatch owner's deadline, without
taking a silent minimum. Waits above 60 seconds or dispatches above 100 seconds
refuse before a worker starts. Before either startup receive, the child monitors
its caller, original upstream owner and scope. A bounded readiness handshake waits
for the watchdog's explicit monitor-ready acknowledgement before work starts.
A dedicated resource scope and independent watchdog enforce the deadline even
when a handle is never awaited. Cancellation
also reaches that watchdog without needing `await`. Status notifications contain
bounded waiting/admitted facts, with no prompt, transcript or provider credentials.
The worker preserves the captured original file-effect owner with the narrow
`Resources.bind_effect_owner/1` API, so the native controller directly monitors
that upstream owner. The watchdog also monitors the immediate caller and kills
its callback worker before asking the resource scope to clean up. A suspended
scope cannot postpone those ownership fences. Before settlement, the callback
owner checks the actual deadline, pending cancellation and both captured owners;
the native owner still performs the final marker switch.

One native Transaction process retains the service lease throughout the callback.
For queue, admitted and terminal state changes, that same process briefly pushes
the shared ledger lock and performs native staging, rename and directory sync.
It releases the ledger lock before invoking inference. It retains no project
identity, Consent or Collection lock during inference. Reverse acquisition and
recursive inference calls refuse before another worker starts. The native service
lease is released before a successful return, allowing a subsequent embedding
tool to acquire the same service without deadlocking.

A separate logical lease plus an independent marker writer was rejected: loss
between a liveness check and the final marker rename would recreate a stale
publisher. Here the actual marker publisher holds both relevant OS locks. A
worker cannot switch a marker after that native owner dies. Controller/worker
death still does not establish remote daemon quiescence.

## Durable uncertainty, queue and identity

The durable admitted marker precedes the callback. Only the trusted host
classification `{:settled, value}` means a known terminal provider result. Other
returns, exceptions, cancellation, timeout, owner death or native-owner loss leave
unresolved admitted state. The callback result itself is never persisted here.
Transport adapters and their owning host must validate terminal responses before
constructing this classification; worker-shaped JSON is insufficient.

A subsequent caller may queue while another native lease is busy. Once it
acquires that service lease, an existing admitted marker refuses dispatch as
unknown. Releasing a local lock, killing a local socket or waiting out a timeout
does not clear it. `reconcile/6` requires the exact service ID, reservation ID,
current ledger revision and a closed receipt repeating those exact three fields
and naming owned-service quiescence or
explicit shared-service reconciliation. It acquires the service lease before
changing the marker. This API does not authenticate operator interaction; a
future protected operator UI owns that boundary. It does not reissue inference.

At most eight persistent service identities share 64 queued references and 32
recent terminal/reconciliation receipts. Unknown active reservations are stored
separately and never evicted. The finite recent list is diagnostic history, not
global exactly-once request storage; the Session journal still owns no-replay
intent. A queue entry is known-unstarted, has a nonrenewing deadline of at most
60 seconds, and may be cancelled or pruned when expired. Clock regression refuses
eligibility rather than extending stale authority. Among current waiters for one
service, foreground precedes background and arrival sequence orders each class.
Eligibility is rechecked under the ledger lock after obtaining the service lease.

Only an initial native lock-acquisition busy refusal retries, yielding 20 ms within
the original absolute wait or dispatch deadline. Each attempt checks owners,
cancellation and, for nested ledger acquisition, the retained service capability.
Once the ledger capability is active, its native stack check covers all held
locks. Enqueue computes the remaining lifetime after acquisition. Later read,
reclaim, quota, publication or unknown failures never enter this retry loop.

Canonical origin aliases bind persistently to the service ID, independently of
model, project and API path. A changed alias list or overlapping new ID refuses,
including after configuration renaming. This component has no automatic rebind
or removal path. Explicit future operator recovery is required when the eight
identity slots need reassignment. It schedules Ipse clients only and cannot
prevent another program from using the daemon concurrently. Coordination applies
to clients using the same protected operator home; separate homes do not share
this admission ledger.

## Allocation and supported filesystem boundary

One protected `home/inference-services` tree contains `control.json`, fixed
`objects/slot-0` through `slot-7` lease directories, an empty `manifests`
allocator directory, retained locks and temporary staged ledger files. Its whole
tree is inventoried and preflighted by the existing native collection allocation
profile before payload. It has one 1 MiB ceiling, rather than eight independent
unaccounted allowances. The closed ledger is at most 64 KiB. No per-request file
persists; old staged files are reclaimed only after a fresh native read of the
durable ledger. Private payload reads also go through the retained native owner.

The shared four-MiB operator-control reservation is now divided into three MiB
for the entire project-identity root and one MiB for the entire service-slot tree.
Together with 18 MiB for Consent and 42 MiB for collections, the conservative
project envelope remains 64 MiB. The identity-capacity regression uses the new
three-MiB ceiling. All shared metadata is charged conservatively per project.

The initial empty-tree bootstrap first admits the native filesystem profile under
the flat root lock, then constructs only the fixed empty private directories.
A partial bootstrap refuses and remains explicit recovery work. Existing modes,
symlinks and hardlinks are not repaired into trusted state. The current finite
profile remains Linux `7.2.10` with its reviewed Btrfs/tmpfs rules. Unsupported
filesystems visibly refuse dispatch. Test output distinguishes that negative
branch from supported runtime journeys; it does not qualify macOS or ext4.

`PrivateFile` uses host renames and cannot supply actual-native-owner fencing.
The adapter therefore reuses Transaction, existing resource scopes, bounded JSON,
Provider destination validation and SemanticRoutes. Local protected-directory
checks mirror the existing private ledger boundary; no new dependency, process
framework, credential interface or custom wire protocol was added.

## Author checks and preserved failures

The initial owner-fenced checkpoint passed strict compilation and **22 tests**,
seed **379046**, in **6.7 seconds**, using native helper SHA-256
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
Its receipts remain `/tmp/ipse-service-slots-owner-07/{strict,tests}.log`.
The exact three-MiB identity-capacity regression passed in 2.2 seconds with
20 unrelated tests excluded, at
`/tmp/ipse-service-slots-identity-budget-01/capacity-repaired.log`. Its trace
confirms the selected test. An initial filter selected a neighboring test, and
the first correctly selected run lacked the private protected helper copy;
both failed or misselected logs remain beside the final result.

Existing resource-scope, actual blocked workspace file-effect and scope-authority
checks passed **12 tests**, seed **808578**, in **3.4 seconds** at
`/tmp/ipse-service-slots-owner-07/resources-regression.log`. These preserve the
retained Session lock while legacy workspace IO actually completes. Seven affected
source/test files passed actual Elixir 1.18.5 formatting. The documentation check
at that checkpoint passed 488 Markdown documents and 4,433 local links.

The supported runtime branch ran on the tested host. The controls include separate
Elixir VMs sharing aliases and model routes, foreground priority across projects,
cancellation and deadlines without await, native-controller death, suspended-scope
owner loss, late callbacks, exact reconciliation, alias conflicts, concurrent
distinct services, whole-tree allocation and unsafe-file refusal. They use
synthetic callbacks rather than HTTP, daemon or paid-account requests.

Initial compiler and fixture failures remain under
`/tmp/ipse-service-slots-pure-01` and `/tmp/ipse-service-slots-runtime-01..03`.
They include a dynamic guard rejected by the compiler, uppercase fixture IDs,
missing fixture capabilities, notification-shape assumptions and an absent private
helper copy. Self-review repaired release-result classification and cancellation
that previously required awaiting the handle. It also exposed upstream owner loss
being delayed by a suspended scope; direct native-controller owner binding and the
independent watchdog repaired that path. These author checks are distinct from the
independent evidence below.

Independent review of checkpoint 07 then reported two P2 findings:

- A 150 ms shared-ledger hold defeated a configured 2,000 ms wait: enqueue failed
  after 21 ms; cold bootstrap failed after 34 ms. A trusted terminal callback
  encountering the same short hold became durable unknown despite remaining
  dispatch time. No callback replay occurred; unrelated services sharing the
  ledger could cause this availability failure.
- Killing the caller after child creation but before resource attachment left the
  unattached child waiting forever. A scheduling-only private Resources fixture
  reproduced it without any callback, native lease or ledger IO.

The repaired author snapshot `/tmp/ipse-service-slots-contention-10` passed strict
compilation and **27 tests**, seed **379046**, in **8.4 seconds**. Receipts are
`strict.log` and `tests.log` in that directory. The five added controls cover short
ledger contention during enqueue and settlement, cold bootstrap, cancellation
before enqueue, the original settlement deadline, and pre-attachment owner death.
The failed first repair run at `contention-08/tests-first.log` exposed an incorrect
outer-capability check while the nested ledger capability was active. Snapshot 09
then passed 26/27 behavior tests; the new child-VM fixture source had been truncated
by default `inspect`, and strict compilation rejected a redundant fallback clause.
The corrected source and fixture passed in snapshot 10. All three logs remain
under their full `/tmp/ipse-service-slots-` paths; none is relabeled as a pass.
The repaired three source/test files also pass current formatting and actual
Elixir 1.18.5 formatting without changing their independently tested bytes.
The final documentation check passed 490 Markdown documents and 4,448 local links.
These receipts are `format-current.log`, `format118.log` and `docs.log` in the
same snapshot directory.

The post-durable-admit, pre-callback cancellation cleanup still makes one ledger
attempt. A fresh collision may leave an admitted marker unknown although no
callback ran. This conservative refusal conforms to the no-replay contract;
it does not imply an effect occurred. Operator reconciliation remains necessary
before a fresh dispatch. No automatic retry or timeout clears that marker.

## Independent adversarial review and closure

The complete independent closure receipt follows, with heading levels and typesetting adjusted
for this chapter. Its original private file is
`/tmp/ipse-independent-slots-closure10.md`, SHA-256
`598198c662d4f52ec51b89202d3ed23b0b5c5e0ab4e03c482b6313aab29bbfb7`.
The earlier report is `/tmp/ipse-independent-slots-audit.md`, SHA-256
`153721e0454527ff387a372752e0a62c5224961326ee589c0557b0642a15ba81`.
The reports and raw receipt locations identify synthetic fixtures only; no private
transcripts, credentials or held-out qualification inputs are reproduced.

Dated 2026-10-26. Both P2 findings in
`/tmp/ipse-independent-slots-audit.md` are independently closed for the exact
source checkpoint below. This permits further host integration review; it does
not establish complete P30/P31 acceptance or live inference qualification. The
reviewer changed no repository source or index.

### Bind the disposition to the tested source

The author supplied `/tmp/ipse-service-slots-contention-10`, copied privately to
`/tmp/ipse-independent-slots-closure10`. Its two repaired source files are:

| Source | SHA-256 |
| --- | --- |
| InferenceSlots | `c550baf672e25a8d04d7251e0ca9cefbd31a8088e607d96cc34e68ae7501d3ce` |
| Store | `2ec28693529f3e5a861469ee3adc8608962f64dc447660c17913199d80e645de` |

Ledger, Resources and ProjectIdentity source remain those from the earlier 07
snapshot; the current snapshot's Resources BEAM exactly matches 07 at
`abe690b2237cfc5baa635769c957ed42012af171f66f5e1ea2a2eba5aeaa86d2`.
The executed InferenceSlots BEAM is
`efdac901dd8cad746824530a0b5290fa09726a0bca3e146d9dd6fb1f3bc193a8`,
Store BEAM `b9e23064fc284be01024239d26a5c5b556cfe5f333137a057c1bb0394b2aac13`.
The actual private helper remains
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
The tested host is Linux 7.2.10-arch1-1, tmpfs with 4096-byte units, two BEAM schedulers.

All five relevant modules independently compile with `elixirc
--ignore-module-conflict --warnings-as-errors`, using the complete frozen
dependency graph and a separate output directory. Exit 0, zero output bytes.
The unchanged six ledger controls plus 21 runtime controls pass independently:
**27 passed**, seed 214282, **8.4 seconds**.

### Short ledger contention now respects the existing deadlines

The exact unchanged before-reproduction script now returns successful admission
after 193 ms for the automatically released 150 ms ledger hold. Its trusted terminal
callback also settles successfully, leaving active=nil. Its final callback was
written for the failing version and intentionally raises if redispatched; that
last artificial unknown is not interpreted as a repaired-component failure.
The separate assertion companion verifies that a normal fresh callback succeeds
after terminal settlement without reconciliation.

The unchanged cold-bootstrap probe now succeeds after 223 ms under its 150 ms lock
hold, followed by a successful fresh control. The assertion companion observes
196 ms initial waiting, exactly one callback, the exact settled reservation ID,
and a successful subsequent request. A 50 ms original wait under 150 ms ledger
contention expires in 60 ms without executing a callback, creating an active marker
or leaving a queued entry. No deadline is renewed.

Source review confirms retry is restricted to native Transaction.acquire's
definite busy refusal, before ledger IO. It does not retry a normalized later
read/reclaim/quota/write error or an unknown outcome. Queue remaining time is
computed after acquisition. Guard checks cover deadline, owners and cancellation;
the retained outer service capability is checked before nested ledger acquisition,
and after acquisition the native owner's complete held stack validates the
service and ledger locks together.

Additional independent probes verify cancellation while initial ledger acquisition
is busy never enqueues or dispatches. A trusted terminal response cannot cross
its original 100 ms dispatch deadline while the ledger is held 250 ms; its admitted
marker remains unknown after release, rather than settling late.

### The unattached startup child now exits

The exact unchanged startup repro and the identical scheduling-only Resources
fixture now observe owner=false, scope=false, child=false and no current function
after the caller dies before attachment. The fixture source still hashes to
`8065c51b7c432408af719311cd832da1a868560708408830d0e609755ab990f5`.
Only that scheduling pause is injected; the tested InferenceSlots source is the
author's unchanged 10 snapshot. No callback, native lock or ledger is invoked by
this startup probe.

Source review confirms the child monitors the immediate owner, original upstream
owner and scope before either bootstrap receive. Readiness is bounded by the
original wait deadline and requires the actual watchdog's acknowledgement before
work begins. The formerly unbounded unattached receive is gone.

### Ownership and uncertainty still hold while retrying

The earlier independent actual-native SIGKILL, late terminal callback, alias,
reconciliation, corrupt-control-before-GC and nested upstream-owner probes all
pass against 10.

A stronger new probe returns a trusted terminal response while its ledger is
busy, suspends the cleanup scope and kills the original upstream owner while
the immediate legacy file-effect caller stays alive. By 300 ms the native
controller is dead. The active marker is not settled. A fresh request positively
reacquires the actual service lease while the old immediate caller and suspended
scope still live, then refuses the same durable unknown reservation without
invoking a callback.

An initial version of this extra probe incorrectly required both native controller
and dormant result-ack worker to die within 3 seconds. It failed. Diagnosis showed
the native controller already dead by 300 ms; the worker was only waiting for its
deliberately non-awaiting immediate caller's result acknowledgement. It then
terminates through the bounded releasing/ack watchdog (about 5 seconds). The final
probe separately asserts native fencing and bounded dormant-worker cleanup. This
failure and diagnostic are preserved, not described as an immediate all-process
termination pass.

### Preserve harness failures and remaining limits

The first 10 startup-fixture compilation attempted to read Resources source from
the author's narrow 10 source directory; that directory contains only the two
changed modules. The corresponding first maintained-test command similarly
referenced a ledger test omitted from that narrow directory. Neither executed
the intended check. Resources source and the unchanged ledger test were copied
from 07 after verifying the exact matching Resources BEAM. The corrected runs
are identified explicitly below. A deprecated Code.compiler_options flag in that
first fixture harness also emitted warnings; the corrected strict command uses
the supported compiler flag and produces no warnings. No runtime check was
weakened.

Residual conservative behavior: the post-durable-admit cancellation branch still
uses a single unguarded cancel_unstarted ledger transaction. A fresh collision
there can retain unknown state even though the callback was never invoked. This
is a static integration/recovery note, not a newly reproduced replay or ownership
defect; the exact two reported P2 findings are closed. The author and root were
notified. The dormant result-ack cleanup delay described above also remains.

No live HTTP transport, daemon cancellation/quiescence, provider classification,
operator-channel authentication, main/child/SDK dispatch integration, source and
installed parity, other-kernel/APFS support, annual individual workload or final
milestone acceptance is established. Native filesystem support remains narrow.
All callbacks, receipts and retained fixture stores here are synthetic; no
model calls, credentials or qualification/gold inputs were used.

### Raw closure receipts

| Artifact | SHA-256 |
| --- | --- |
| `/tmp/ipse-independent-slots-finite-contention-after10.log` | `0a4ac41e2530bbfc044168ccc23b7940f665e065189aa20f4f7972e70a6c1e58` |
| `/tmp/ipse-independent-slots-bootstrap-contention-after10.log` | `d385481e4e9914b6d16de52678f7ea15c8612429edb3a024dc314c90d2945042` |
| `/tmp/ipse-independent-slots-contention-closure.exs` | `b3f035282022894c4ec21f5610fc0a313bc81902eb9b268902be99dbd8aef7c8` |
| `/tmp/ipse-independent-slots-contention-closure-after10.log` | `011e53687531c1adc47766b098d27c85f4d9df5272e26cfa99716261b9c03a41` |
| `/tmp/ipse-independent-slots-startup-orphan-after10-repaired.log` | `b88525e48acc81c213a577da83bdf432482cd562e02594b534da2f7e587580b9` |
| `/tmp/ipse-independent-slots-maintained-after10-repaired.log` | `a864734acb5eec144d993e6b5833f678f2b330ff31fea31e94eeee51617007e1` |
| `/tmp/ipse-independent-slots-closure10-full-strict.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-independent-slots-audit-after10.log` | `979f9f693d8fd70239284cced8905ef335819c7d3390acdb3f1311a2c48ff33c` |
| `/tmp/ipse-independent-slots-busy-lifecycle-fenced.exs` | `003c39ca4581f21e4a7d889d6e7590738873c976149a24dd9253b00edaf151b4` |
| `/tmp/ipse-independent-slots-busy-lifecycle-fenced-after10.log` | `bc1e4810ef1003b4e9e02dc36d364921b13986655bc55f5820c3c4b33f3d387c` |

Earlier diagnostic paths are `/tmp/ipse-independent-slots-busy-lifecycle-after10.log`,
`/tmp/ipse-independent-slots-busy-lifecycle-diagnostic-after10.log`,
`/tmp/ipse-independent-slots-startup-fixture-after10-compile.log`,
`/tmp/ipse-independent-slots-startup-orphan-after10.log` and
`/tmp/ipse-independent-slots-maintained-after10.log`. Corrected fixture compilation
is `/tmp/ipse-independent-slots-startup-fixture-after10-compile-repaired.log`.
All completed evidence and source snapshots should be preserved by the root
evidence owner; fixture paths are printed in their logs.

### Original finding receipts

These unchanged before probes remain paired with the after receipts above.
The earlier report retains the initial source and BEAM hashes and all diagnostic
controls; it is superseded only for the two findings' disposition.

| Original artifact | SHA-256 |
| --- | --- |
| `/tmp/ipse-independent-slots-finite-contention.exs` | `2220b1a027adcfad8fc846ebcd8f7da10b9874911b5bc143df21dbc8908616a5` |
| `/tmp/ipse-independent-slots-finite-contention-timed.log` | `754ff804b91bead39d004a389a4c4071dec458fd4faaed550014e76ceab4275e` |
| `/tmp/ipse-independent-slots-bootstrap-contention.exs` | `c4c1dedfa76c89d93b437a47c728d65e90b7f1caac94d0f9a934f2c23eb49a0d` |
| `/tmp/ipse-independent-slots-bootstrap-contention.log` | `1f1b05f1509b28c4404eecfc1866385a23dd45b77e960beab5ab78438b131ac8` |
| `/tmp/ipse-independent-slots-startup-orphan.exs` | `bd49843d8d595a53e8dc7e9a7ad882bd29666a004a81c44042def53ca518b75f` |
| `/tmp/ipse-independent-slots-startup-orphan.log` | `39ac800198f290a94e55fdb9ba6604748e4486253ead4420a07523670c38e89c` |

## Integration boundary

Both reported P2 findings are independently closed for the exact source hashes
above. Main, child, model, embedding and decision dispatch integration remains
separate work. Live provider classification, daemon quiescence, operator recovery,
source/installed parity and supported-platform qualification also remain open.
This component receipt establishes no remote concurrency guarantee or complete
P30/P31 milestone acceptance.

A later [registered dispatch component receipt](inference-dispatch-component.md)
records actual Session/provider wiring and new deferred-gate/completion boundaries.
Its author checks do not extend the independent source-bound closure above; that
new component requires its own independent audit.
