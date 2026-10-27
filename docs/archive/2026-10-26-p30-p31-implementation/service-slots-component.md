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
refuse before a worker starts. A dedicated resource scope and independent
watchdog enforce the deadline even when a handle is never awaited. Cancellation
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

## Verification and pending review

The current author checkpoint passed strict compilation and **22 tests**, seed
**379046**, in **6.7 seconds**, using the unchanged native helper SHA256
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
Receipts are `/tmp/ipse-service-slots-owner-07/strict.log` and
`/tmp/ipse-service-slots-owner-07/tests.log`. The separate exact three-MiB
identity-capacity regression passed in 2.2 seconds, with 20 unrelated tests
excluded: `/tmp/ipse-service-slots-identity-budget-01/capacity-repaired.log`.
Its trace confirms the exact capacity test. An initial line filter selected a
different test, followed by a first correctly selected run that lacked its
isolated runtime's protected helper copy; both logs remain beside the final log.
The existing resource-scope, workspace file-effect and scope-authority regressions
also passed: **12 tests**, seed **808578**, in **3.4 seconds**, logged at
`/tmp/ipse-service-slots-owner-07/resources-regression.log`. These include retained
Session locks during actual blocked workspace IO. Actual Elixir 1.18.5 formatting
checked all seven directly affected source/test files with no differences; the
documentation checker passed 488 Markdown documents and 4,433 local links with
no errors.

The supported branch ran on this host. The checks include independent Elixir
VMs sharing a service across main/embedding/model aliases; foreground priority
across projects; cancellation and deadlines without await; owner/native-controller
death, including a deliberately suspended resource scope; a late terminal
callback after native-owner loss; exact reconciliation CAS; persistent alias conflicts; distinct services
running concurrently; full-tree allocation/preflight and unsafe file refusal.
All callbacks are synthetic: no HTTP, model, daemon or paid-account request ran.

Initial compiler/fixture failures are retained under
`/tmp/ipse-service-slots-pure-01` and `/tmp/ipse-service-slots-runtime-01..03`.
They include an illegal dynamic guard, uppercase synthetic IDs, missing test
capabilities, notification-shape expectations and an isolated runtime missing
its protected helper copy. Self-review repaired classification after releasing
the service lease, and cancellation that formerly required awaiting a handle.
These checks are authored by the implementer and do not replace independent
adversarial review.

Further self-review found that the original caller reached the native controller
only through a resource scope, which could delay owner death if suspended. The
direct upstream-owner binding and independent worker termination described above
repair that path. Both owner death and cancellation now have actual suspended-
scope regressions. This is an author-discovered repair awaiting independent audit.

Before integration, independently audit the service/ledger lock order, late
publication after actual native death, owner/scope/watchdog lifecycle, foreground
races, never-awaited cancellation, alias changes, closed persisted state and the
entire 1 MiB allocation tree. Main/child/model/embedding/decision dispatch still
needs verified host integration; live daemon cancellation/quiescence and operator
recovery require qualification. No remote concurrency, local-model quality,
source/installed parity or complete milestone acceptance is claimed here.
