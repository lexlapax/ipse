# Shell supervisor

Build with `dev/build-native.sh` (Rust standard library only; Linux/macOS). Runner
can also build it on demand for trusted execution in a source checkout when
`rustc` is available; native mode requires a prebuilt helper outside the workspace. Package
`priv/ipse-runner` with releases/escripts, or set `IPSE_RUNNER_PATH`.

Arguments are `CWD TIMEOUT_MS COMMAND`. Stdout is a binary frame stream: one type
byte, a four-byte unsigned big-endian payload length, then that many payload
bytes. `O` carries stdout/stderr bytes (interleaving follows arrival order), `X`
carries JSON `{ "exit_code": integer, "timed_out": boolean }`, `E` carries a
known pre-dispatch setup refusal, and `U` carries an uncertain post-dispatch
failure. Output can split UTF-8 characters between frames. This shell `U` frame
is separate from the lock subprotocol's unlock acknowledgment below.

Runner returns `{:unknown, reason}` for a lost/timed-out supervisor, malformed or
incomplete frames/results, post-dispatch failure or an output-consumer exception.
A refusal following output/result evidence cannot downgrade uncertainty to a
known error. A valid final result retains the ordinary exit-code/timeout facts.
Pure validation, helper setup and explicit pre-dispatch refusals remain known
errors. Keep helper and Elixir Runner from the same installed build; an uncertain
effect must be inspected rather than replayed.

The caller keeps the helper's stdin pipe open. EOF kills the owned process group.
An explicit cancellation byte `C` also requests cleanup while retaining the Port
to observe helper exit. A private Port owner traps close-time exit races without
changing the caller's exit handling. Shell cleanup is confirmed only after a
normal helper exit after stack cleanup (status 0 or a returned error at status 1).
Forced stdio watchdog termination uses status 2; that, a timeout or abrupt helper
loss remains unconfirmed.
The helper starts `/bin/sh -c COMMAND` as a member of that fresh group and kills
it on timeout, parent-pipe EOF, failed output delivery, and shell exit.
The timeout includes the shell and its ordinary descendants. A deliberately
adversarial process can escape by creating a new session; this is **not a
sandbox**. Shell runs with the user's local filesystem and network access.
Provider credentials OPENAI_API_KEY, ANTHROPIC_API_KEY, OPENROUTER_API_KEY,
GEMINI_API_KEY, GOOGLE_API_KEY, XAI_API_KEY, TYPESAFE_API_KEY and
IPSE_CHATGPT_ACCESS_TOKEN are removed from the shell environment. Other
inherited environment values remain available.

## Process-group identity and lifetime

`ipse-process-group.rs` owns one extra inert copy of the helper per shell/stdio
invocation or native macOS signature-check command. This anchor leads the group;
the actual command joins before sandbox setup/exec. The anchor's PID is kept
unreaped through command completion, output draining and final group cleanup.
It cannot be reused for an unrelated group while signals still reference it.
All signaling threads lock the shared slot through the signal; release kills
the anchored group, clears that slot, and reaps the anchor under the same mutex.
Late input/watchdog/owner events therefore find no signaling target after release.

The supervisor restores default child-status handling before launch, including
when its launcher ignored `SIGCHLD`; automatic reaping would invalidate the guard.
The anchor has a cleared environment, null output and a private stdin lease held
by the supervisor. A child joins the group before closing its inherited copy of
that lease, before any lengthy sandbox setup. Abrupt supervisor death closes the
lease and the anchor kills its own group, including itself. `--group-anchor` is
an internal role of this same helper, not an external executable dependency or
a configurable command. Failure to create the owner refuses command launch.
The OS helper's existing trust, sandbox and detached-descendant limits still apply.

This uses Rust's stable process/pipe facilities plus the existing narrow POSIX
boundary. `Child::try_wait` [reaps an exited Unix child](https://doc.rust-lang.org/std/process/struct.Child.html#method.try_wait),
so retaining only that child's numeric ID through later cleanup was insufficient.
A retained anchor avoids a new package, platform-specific `waitid` layouts or
reliance on unstable/Linux-only process-handle APIs. Regression probes establish
unreaped ownership after command exit, refused late signals and EOF-confirmed
ordinary-child exit after abrupt owner death. They do not force PID wraparound
or certify stronger descendant containment.

## Copy a regular file through a retained descriptor

Use `ipse-runner --copy-regular ABS_SOURCE ABS_DEST EXPECTED_BYTES` for evaluation
staging on Linux or macOS. This mode copies bytes into a new destination file.
The destination's parent must already be private and have one writer.
It does not implement a filesystem sandbox or reject symlinks in every ancestor.

The source opens with `O_NONBLOCK|O_NOFOLLOW`. Its retained descriptor must name
a regular file of the exact declared length, at most 64 GiB, before reading.
The descriptor and named path must agree before and after copying, including
inode, device, length, mode, link count and nanosecond modification/change times.
A writerless FIFO therefore refuses without waiting for a writer.

The destination opens exclusively with mode `0600`. An explicit bounded loop
copies the declared bytes and checks EOF, then syncs the file and its retained
parent directory. The final destination must remain a regular file with one
link, the expected size and a different device/inode pair from the source.
The helper uses no hardlink, reflink or kernel clone. A failure leaves any partial
destination in place and never retries, removes or replaces it. The caller must
hash the new private destination against its independently selected digest.

Success prints one plain JSON line, at most 2048 bytes, with `version: 1`, `bytes`,
`source` and `destination`. Each identity contains decimal-string `device`,
`inode` and `nlink`; integer `bytes` and full Unix `mode`; signed decimal-string
`mtime_seconds` and `ctime_seconds`; and integer nanosecond fields. Paths and
hashes are absent. A direct failure emits the usual `E` frame and exits with 1.
When invoked through `Runner.open_stdio/5`, these bytes belong to the selected
child's stdout. Confirm its successful `X` result and native cleanup before
parsing a success receipt.

Run the focused OS checks without a model service:

```sh
rustc --edition=2021 --test -D warnings native/ipse-file-copy.rs -o /tmp/ipse-copy-tests
/tmp/ipse-copy-tests
```

The six active controls include a bounded subprocess for a writerless FIFO.
The child-only ignored test runs through that parent control. The
[service-owner exercise](../docs/developer/measurement.md#separate-service-work-from-cleanup-and-inventory)
checks private runtime/cache copies through the public Runner path.

## Optional exact aggregate memory scopes

The Linux-only `--measure-cgroup root|cell TOKEN TIMEOUT_MS OUTPUT -- ABSOLUTE_COMMAND ARGS`
mode measures a fresh owned cgroup with `clone3(CLONE_INTO_CGROUP)`. It is an
explicit benchmark interface, separate from shell, stdio and sandbox protocols.
It records `linux_memcg_charged_peak_bytes_v1`, the kernel's aggregate charged
memory high water, not sampled RSS, summed process RSS or GPU/device memory.
macOS and missing Linux capabilities fail closed.

`TIMEOUT_MS` accepts 1 through 1,296,000,000 ms, a finite fifteen-day maximum
shared with measured sequence stages. This ceiling permits a root to contain
fourteen serial cells whose individual model-service lifetimes remain at most
24 hours. The evaluation recipe adds cleanup and sequencing allowances and
freezes the resulting root deadline before launch. The measurement ceiling does
not enlarge ordinary shell or stdio deadlines or renew any service allowance.

The root collector must be the sole process in a new delegated user service named
`ipse-measure-TOKEN.service`. `TOKEN` is 32 lowercase hexadecimal characters.
It moves only itself into a collector leaf, enables memory accounting in that
new service and creates a fresh measured root with an application leaf. The
application is born in its leaf before exec. No existing user manager, service,
model daemon or application process is moved into measurement.

A nested cell collector must already be inside the parent identified by inherited
`IPSE_MEASURE_ROOT`. Its fresh sibling cell scope owns its command descendants.
An independent parent peak FD resets only that cell's whole-population interval;
the outer lifetime counter remains untouched. These are different subjects:
never add peaks, subtract a baseline or infer that retained cache charges vanished.

Each collector establishes a separate `--measure-anchor` process before command
admission. This internal role inherits a retained cgroup-kill descriptor and a
private stdin lease. Collector death closes the lease; the anchor kills that
owned scope even while an outer application remains alive. A command closes its
inherited lease before exec. Signaling uses the retained cgroup descriptor, not
a discovered or reusable workload PID. Owner EOF or `C`, timeout and persistent
descendants also trigger owned-scope cleanup. Owner closure is checked before
admission and again before launch. SIGCHLD normalization preserves child reaping.

A zero-exiting leader starts a fixed two-second natural population drain.
The collector continues checking authority, owner, anchor and the original
workload deadline. It accepts only an observed empty `cgroup.events` population
strictly before both deadlines. Empty process lists or closed output pipes do
not establish population exit. A nonzero leader fails immediately. A persistent
population is killed and remains incomplete, even after cleanup succeeds.
Memory counters cover the entire tail. Output continues to drain while the
population is active. After population empties, any remaining output wait ends
at the 500 ms cutoff measured from leader reap. Ownership and the original
deadline remain checked through the terminal decision. Forced cleanup has a
separate five-second bound.

The caller keeps stdin open and accepts a terminal `M` frame only with the
corresponding private `receipt.json` and normal helper exit. A normal helper exit
can carry a failed/interrupted command: inspect `complete`, `reason`, `exit_code`
and `cleanup_confirmed`. In this explicit mode an `E` frame is a diagnostic,
not proof that no application effect occurred. Missing or failed completion must
not cause automatic replay. Killing a collector can leave `started.json` without
a final receipt; that is incomplete evidence.

`OUTPUT` must be a fresh absolute directory. It has mode 0700 and immutable
started/final JSON files have mode 0600. `leader-exited.json` records actual reap
observation and elapsed microseconds; its presence does not establish population
closure. Child stdout/stderr goes only to a private
16-MiB bounded log with an explicit truncation flag, never the metric channel.
Receipts retain scope identity and separate numeric peak, command outcome and
cleanup. Empty owned scope directories are removed after receipt persistence.
The collector's own native apparatus is outside its measured root; nested
collectors and anchors contribute to the enclosing whole-run population.

Final receipts have `version: 2`, `completion_policy: "bounded_natural_drain_v1"`
and `population_drain_limit_ms: 2000`. `population_drain_ms` records the interval
from observed leader reap to natural closure or failure. For successful natural
closure, `natural_drain_us` records that interval without millisecond rounding;
it is null for a forced outcome. `elapsed_us` runs through the terminal output
decision. `population_exit` is `natural` or `forced` according to the latched
outcome. Ordinary anchor retirement after proven emptiness does not count as
forced population termination. Timings are monotonic observations, not exact
kernel task-death times. Consumers must check the declared policy and original
timeout as well as completion. Historical receipts require their matching source
and runtime; an old incomplete result cannot acquire this completion policy.

Run the real no-model controls on a Linux host with the approved systemd
user-service tools, delegated memory controller and clone-into-cgroup support:

```sh
./dev/build.sh
elixir dev/verify-memory-scope.exs "$PWD/priv/ipse-runner"
elixir dev/verify-memory-drain.exs "$PWD/priv/ipse-runner"
elixir dev/verify-memory-terminal.exs "$PWD/priv/ipse-runner"
```

The commands report ten scope controls and twelve drain controls, each with a
private evidence directory and zero inference requests. The drain controls wait
for actual collector reap before releasing a delayed allocator or inducing loss.
They cover nested peak intervals, persistent descendants, original deadlines,
owner/anchor/collector loss and bound-registry replacement. The terminal verifier
reports four controls. It compiles private diagnostic copies with a bounded
barrier at the final decision, then compares the guard with its deliberate
reversal. Only the reversed copy may accept cancellation at that boundary;
the guarded copy also refuses an expired original deadline. Production source
is unchanged, and diagnostic peaks are not experiment results. Follow the
[training exercise](../docs/developer/measurement.md#prove-ownership-and-loss-behavior-independently)
to interpret their subjects and failure records. The knowledge evaluator uses
this protocol through its optional measured-execution owner. Its complete
synthetic exercise is separate from these collector controls.

### Sequence complete measured stages

Use `ipse-runner --measure-sequence ABSOLUTE_BOOTSTRAP` only as an application
inside an admitted root collector. It executes fresh preparation, declared cells
and finalization through the same collector. All those processes, including the
sequencer, contribute to the whole-run counter. The caller owns evaluation
policy, frozen identities, approvals and nonrenewing allowances.

Descriptors are binary, at most 1 MiB, with unsigned big-endian integers. A string
is a u32 byte length followed by valid UTF-8 without NUL, at most 65,536 bytes.
Paths are absolute normalized component paths. The descriptor is opened with
`O_NOFOLLOW | O_NONBLOCK`, then checked through its FD for regular-file type,
owner UID, owner-only permissions and bounded size. A writerless FIFO refuses
without waiting for a writer. Bytes and post-read metadata must match the
admitted size; exact bytes and numeric FD identity are preserved privately.

| Record | Ordered fields |
| --- | --- |
| Bootstrap | Eight bytes `IPSEQ001`, sequence evidence directory string, future cells descriptor path string, preparation Stage, finalization Stage, EOF |
| Prepared cells | Eight bytes `IPSCELL1`, u32 count from 1 to 64, that many Stages, EOF |
| Stage | Token string of 32 lowercase hexadecimal characters, u64 timeout from 1 to 1,296,000,000 ms, fresh metric directory string, u32 argument count from 1 to 121, argument strings |

A Stage's first argument is an absolute executable; other arguments are opaque
and may be empty. The argument-byte total and complete collector argv must each
fit the existing 65,536-byte bound. The 121-workload-argument ceiling leaves the
collector's seven own argv slots. Tokens and metric paths must be distinct across
all stages; a metric path cannot equal the sequence evidence directory.

The cells descriptor must be absent before preparation and must be produced by
successful preparation. The sequencer creates the fresh mode-0700 evidence
directory itself; its parent must exist. Every stage metric directory must also
be fresh, with its parent present by launch. These are trusted caller-selected
executables, not permission grants from repository text.

The internal stage entry uses `--measure-stage cell TOKEN TIMEOUT OUTPUT --
EXECUTABLE ARGS`. It emits the unchanged `M` frame followed by one `T` frame with
a two-byte payload: complete and cleanup-confirmed, each zero or one. Both bytes
come from the same terminal booleans as the JSON receipt. The ordinary
`--measure-cgroup` interface remains `M` only. Child logs never enter this channel.

The sequencer requires exactly M then T, bounded frame bytes, an identical private
receipt and successful collector exit. A failed command with confirmed cleanup
remains failed and allows later distinct stages and finalization. Missing or
malformed status, receipt mismatch, collector loss or unconfirmed cleanup halts
the remaining sequence. No stage is retried.

Each stage has an exclusive synced `stage-NNN.claim` before launch. Its bytes are
`IPSECLM1` followed by the Stage encoding. Preparation is index zero, cells follow
in declared order and finalization is the last index. The evidence directory also
retains bootstrap/cells bytes and identities, each stage's raw protocol, receipt,
receipt identity and two-byte status. All files are private and directory entries
are synced. `sequence.json` exists only after every stage has confirmed cleanup;
its complete flag remains false if any stage failed.

Refusing an existing sequence output preserves these first attempts. The
application must separately claim its frozen comparison permanently before
opening inputs; changing outputs is not permission to renew its budget. A
finalizer cannot inspect its own later terminal receipt or the outer root receipt.
A post-exit measurement audit must reconcile those records before accepting the
comparison. This generic sequence facility does not implement that domain policy.

Run its separate no-model controls on the same supported Linux host:

```sh
elixir dev/verify-memory-sequence.exs "$PWD/priv/ipse-runner"
```

Expect six cases, including preparation/finalization allocations, an excluded
unrelated sibling, a failed stage with forged child output, retained attempts,
collector loss and both FIFO descriptor seams. The
[contributor exercise](../docs/developer/measurement.md#require-natural-population-closure-under-original-deadlines)
connects these records to the evaluator's domain claims and post-exit audit.

### Bind a measured sequence to one execution

The knowledge evaluator adds a bound root to the generic sequence protocol:

```text
ipse-runner --measure-cgroup root TOKEN TIMEOUT_MS F/native-root \
  --bound-root F/native-authority.bin -- \
  SAME_HELPER --measure-sequence F/bootstrap.bin
```

`--bound-root` is accepted only in this root position. The selected executable
must be this helper's sequencer. The ordinary root, cell and sequence interfaces
retain their existing format. `native/ipse-bound.rs` owns this additional
directory and kernel-scope authority.

The private authority file contains `IPBND001`, the registry path string, its
device and inode as u64 values, the native-root path string and the bootstrap
path string, then EOF. Strings use the sequence encoding above. The paths must
be exactly `F/attempts`, `F/native-root` and `F/bootstrap.bin`. Before launching
work, native admission retains the owner-only registry directory and checks its
named identity. It exclusively creates `F/native-root`, retains that directory
and saves the exact authority and bootstrap bytes there. An existing native-root
refuses even if its terminal receipt is missing or reports were deleted.

The sequencer creates `F/native-root/sequence`; preparation produces
`F/native-root/prepared/cells.bin`. Claims and evidence use retained directory
handles. The bound chain passes these reserved descriptors through exec:

| Descriptor | Validated environment name | Subject |
| --- | --- | --- |
| 4 | `IPSE_BOUND_ROOT_FD` | Permanent native-root directory |
| 5 | `IPSE_BOUND_REGISTRY_FD` | Original attempt registry directory |
| 6 | `IPSE_MEASURE_ROOT_FD` | Whole-population cgroup |
| 7 | `IPSE_MEASURE_SCOPE_FD` | Exact application or current cell cgroup |
| 8 | `IPSE_BOUND_SEQUENCE_FD` | Sequence evidence directory |

Environment names alone grant no admission. Native validates types, owner/mode,
distinct handles and cgroup filesystem identities before adopting descriptors.
It duplicates handles above the reserved range before remapping them, preserving
Rust's child-exec error channel. FD3 remains the anchor's private control lease.
Ordinary native dispatch removes a validated inherited bound contract instead
of passing authority handles into lock, shell or daemon commands.

The sequencer must belong to the exact application leaf of FD6. A stage
collector must enter from that leaf, then place its workload in a fresh cell
scope and replace FD7. Its started record names the scope's device/inode before
launch. Native injects the stage index and token. The stage VM compares actual
kernel membership, descriptor identities, started record and exact native claim
bytes before consuming its exclusive domain claim or opening evaluation inputs.
The VM's preparation paths name its own process in procfs so ordinary lock and
projection children resolve the retained directory without inheriting its FDs.

Registry or native-root replacement causes refusal and owned-scope cleanup;
the chain never adopts the replacement. Domain and native claims remain outside
disposable reports and the registry. A lost collector, missing terminal record
or absent cleanup confirmation leaves an incomplete attempt. Preserve its
evidence and investigate; no missing result grants permission to replay it.

Bound workloads receive only selected `PATH`, `LANG`, `HOME`, `TMPDIR` and the
validated native scope/stage fields. The launcher explicitly sets those four
values for the transient service as well. Manager bus settings, credentials,
proxies and Erlang launcher options do not flow into measured workloads.
Selected ERTS commands restore the sealed code paths directly; the system PATH
still contains ordinary OS utility directories.

Run the portable authority parser checks without starting services:

```sh
rustc --edition=2021 --test -D warnings native/ipse-bound.rs -o /tmp/ipse-bound-tests
/tmp/ipse-bound-tests
```

Linux also runs retained-directory and transfer controls. The
[complete measured exercise](../docs/developer/knowledge-evaluation.md)
adds domain execution and a read-only audit. Only that post-exit audit can join
finalizer and root receipts, first-prediction hashes, model-service evidence and
the separate lifetime, cell and whole-population interval peaks.

## Session locks

`ipse-runner --lock PATH` opens a persistent file with mode 0600 and takes a
nonblocking exclusive advisory `flock`. Linux and macOS reject symlink lock
files with `O_NOFOLLOW`. A successful lock emits an `L` frame. Sending any stdin
byte releases the lock and emits a `U` frame; stdin EOF also releases it.
Ownership follows the helper process, so an Elixir Port owner's death releases
the lock automatically. Lock files must **never be deleted**: preserving the
inode prevents concurrent owners from locking different files at the same path.

## Sync a protected publication directory

`ipse-runner --sync-directory ABS_PATH` opens an existing directory without
following its final symlink, verifies current effective-user ownership and
owner-only permissions, then calls the platform directory sync operation. It
uses no shell, creates no file and changes no permissions. Success emits no
bytes and exits zero; refusal emits an ordinary bounded error frame. Linux and
macOS are supported by the implementation; platform verification is a separate
gate. `Ipse.Runner.sync_directory/1` enforces a two-second response deadline and
resource cleanup. A failed or lost acknowledgment cannot establish whether an
earlier caller-owned rename became durable.

The protected consent ledger syncs a staged file, renames it under its retained
control lock, then uses this operation before acknowledging policy or reservation
publication. The host separately validates canonical ancestors and exact policy;
this primitive grants no filesystem, extension or knowledge permission.

## Inspect protected storage allocation

`ipse-runner --storage-allocation ABS_DIRECTORY` reports three unsigned decimal
integers, separated by spaces: logical bytes, allocated bytes and entry count.
Allocated bytes use the platform's `MetadataExt.blocks()` count multiplied by
512 with checked arithmetic. Both byte counts include directory metadata, and
the walk includes retained locks, staged files and pending root pointers. It does
not assume a filesystem block size or treat a sparse file's length as allocation.

The canonical absolute root and every entry must belong to the effective user
and have owner-only permissions. Files must be regular and have one link;
symlinks, devices, FIFOs and sockets refuse. Opens use no-follow and nonblocking
flags, retain descriptors during inspection and recheck named device/inode
identity. Traversal stops beyond four levels or 40,000 entries. The caller holds
the storage lock while inspecting: this primitive does not provide a filesystem
snapshot against other same-user programs deliberately changing the tree.

`Ipse.Runner.storage_allocation/1` validates the bounded response under a
five-second deadline. An unsupported platform, unsafe entry, changed identity,
overflow, lost helper or invalid response returns unavailable; there is no
estimated-allocation fallback. Collection publication writes and syncs its
complete staged root pointer before inspection, then checks the 64-MiB envelope
including an 18-MiB protected-control allowance before renaming that pointer.
Admission, consent, project identity and domain retention remain Elixir policy.

Run the dependency-free native controls with:

```sh
rustc --edition=2021 --test -D warnings native/ipse-storage.rs -o /tmp/ipse-storage-tests
/tmp/ipse-storage-tests
```

## Write protected staging files

`Ipse.Runner.protected_staging_write(absolute_pending_path, bytes)` creates and
syncs one exclusive staging file of 1 byte through 8 MiB. Its basename must be
`.pending-` followed by 32 lowercase hexadecimal digits. The batch form,
`protected_staging_write_many(absolute_directory, [{pending_basename, bytes}])`,
accepts at most 128 distinct files and 8 MiB of aggregate payload. Both require a
canonical, owner-only parent directory. Creation uses exclusive, no-follow
owner-only permissions from the first open; existing files are never repaired
or replaced. The caller owns admission, operation receipts, rename publication
and directory sync. A failure can leave private partial bytes and is not evidence
that a higher-level operation may be replayed.

The native `--storage-write PATH SIZE` and `--storage-write-many DIRECTORY COUNT`
channels run inside the existing owned stdio process-group supervisor. The writer
first acquires a retained `.writer.lock` in its parent and emits exactly `R` on
stdout. Only then does Runner send payload through stdin, in non-suspending
frames containing a big-endian u32 length and at most 16 KiB of bytes. Exactly
one frame is outstanding: the writer emits `A` after consuming the complete
frame before Runner sends another. This keeps the existing supervisor input
queue bounded even when the writer stops. No pending file is created before the
first positive payload read. The decoded batch stream repeats a 32-byte
hexadecimal identifier, a big-endian u32
payload length, and those payload bytes. File bytes never appear in argv or
diagnostics. The exchange deadline starts before launch and is five seconds;
the bounded native launch and confirmed stdio cleanup may add setup/cleanup
time. Invalid frames, exceeded bounds, backpressure, cancellation and lost
helpers refuse. Cleanup without terminal supervisor evidence returns an explicit
`cleanup_unconfirmed` error.

Storage owners must hold their logical lock, acquire the retained writer lease
before reclaiming pending files or measuring allocation, and retain its inode.
Release the writer lease before starting a new writer and reacquire it after
confirmed exit. This also covers owner death: a writer that already received
payload keeps the kernel lease until it exits; a writer becoming ready after
owner death receives no payload and creates no pending file. Never unlink an
unknown writer's file merely because its owner's logical lock was released.

The focused Runner controls exercise maximum input against a stopped reader,
resource cancellation, and owner death while stopped. They verify finite return,
owned-process cleanup and reacquisition of the same retained kernel-lock inode.

## Observe one actual terminal display and input

`--operator-input TIMEOUT_MS` is an internal single-prompt channel, not an approval
command. It requires matching actual terminal descriptors 0/1. OTP starts it with
`nouse_stdio`, reserving private pipes 3/4 for control. The helper does not acquire
a controlling terminal; it opens a fresh nonblocking description of the verified
terminal device with `NOCTTY` and rechecks device/inode identity. It never changes
the parent's descriptor flags or line discipline.

Before any flush/display/read, a retained regular-file `flock` serializes channels
for the OS user across terminals and VMs. The canonical root of `/tmp` must be a
root-owned sticky world-writable directory. `ipse-operator-UID/` is created with
0700 and `input.lock` with 0600; existing paths must have matching ownership,
protected modes, canonical directory identity and a regular single-link empty
file. Opens use no-follow/nonblocking flags, identities are rechecked after
acquisition, and the inode is never unlinked or replaced by this protocol. The
lock spans final input invalidation, including parent-loss cleanup. Busy or unsafe
locks refuse before terminal effects. This deliberately conservative per-user
scope also fences replacements while an old helper is stopped. OS temporary-state
maintenance must preserve active lock inodes. Terminal-device `flock` is unsuitable
on macOS's special-file backend; the regular-file fence is shared by both hosts.

Control uses the ordinary one-byte/four-byte-length frame envelope:

| Direction/type | Payload |
| --- | --- |
| Parent `D` | Fresh 16-byte nonce plus 1..8,192 display bytes |
| Helper `Y` | Same nonce after all display bytes were written |
| Helper `I` | Same nonce plus at most 8,192 UTF-8 input bytes, without line ending |
| Helper `C` | Nonce on cancellation/deadline/terminal loss; zeros before a complete request |
| Helper `E` | Bounded setup/protocol refusal text |

Control bytes cannot provide operator input: any control activity after the
display request cancels input. A single deadline covers request, display and input.
Nonblocking IO polls parent loss first, including when terminal output is full.
Prior queued input is flushed before display; partial/queued input is invalidated
after cancellation or completion. This single-card contract deliberately does not
preserve pasted future lines. An abrupt OS kill cannot acknowledge cleanup; the
next admitted channel clears prior input again.

Native display filtering rejects Cc controls except tab/LF. The host must also use
`CLI.Terminal.escape/1` for its complete Unicode control/bidi/separator policy.
`Runner.operator_input/2` enforces that escaped form and accepts an observation
only after exact nonce-bound `Y` → `I` → normal exit, without trailing frames.
Initial descriptor failures use plain stderr, never binary frames on the human
display. Missing/malformed/incomplete results supply no observation.

The wrapper accepts only the bundled helper matching its compiled binary digest;
`IPSE_RUNNER_PATH` cannot select an operator channel. Native build must precede
Mix compilation, as the source/package scripts already require. Replacement or
missing helper bytes refuse until a matching build is installed. This assumes the
same trusted installed build as the host; it is not distribution authentication.

An observation establishes real terminal IO, not a human identity or permission.
PTY automation and another process with the same user's terminal access remain
outside that claim. Session must still bind and consume a private witness against
the exact pending version, origin and ceiling. CLI saved-consent/card integration
is not implemented by this primitive.

Run the actual PTY controls and Session-bound witness cases without a model or
external terminal utility:

```sh
rustc --edition=2021 --test -D warnings native/ipse-operator.rs -o /tmp/ipse-operator-tests
/tmp/ipse-operator-tests
mix test test/ipse/runner/operator_test.exs
mix test test/ipse/session/input_test.exs
```

Tests use the existing host C library's POSIX PTY functions. Linux pipes are
atomically close-on-exec; fixture ownership serializes PTY creation/spawn, and
high control descriptors are mapped only after child exec so the spawn error
pipe is preserved. macOS's non-atomic pipe fallback is not a claim of race freedom
against other modules' test spawns. Failed first runs remain in the dated
implementation record.

## Optional native macOS workspace sandbox

`ipse-runner --sandbox macos-workspace-v1 WORKER DATA CWD TIMEOUT_MS COMMAND`
uses an immutable, ad-hoc signed App Sandbox
worker generated and validated with the built-in `/usr/bin/codesign`. The worker
entitlements grant read/write access to the canonical workspace and stable
per-workspace data directory, read-only access to `/opt/homebrew` and
`/usr/local`, and the platform's normal baseline/container access. Network
entitlements are absent. The worker clears inherited environment values and
sets `HOME` and `TMPDIR` to a random temporary directory under shared workspace data.

The signed worker and its metadata are cached under
`IPSE_HOME/sandbox/macos` (default `~/.ipse/sandbox/macos`). The cache rejects
unsafe ownership, permissions, symlinks, and unexpected entries; it validates
the helper digest, manifest, signature, and exact entitlements, and retains at
most 32 generations. The workspace cannot overlap the active helper, application,
or cache. Run from an installed bundle outside the workspace; a source checkout
inside the selected workspace is refused.

The worker applies per-process ceilings: CPU time `ceil(timeout_ms/1000)+1` seconds,
64 MiB regular-file size, 256 open descriptors, and zero core-file size. There
is no aggregate memory or disk quota. Shell and ordinary descendants inherit
the App Sandbox filesystem and network limits. A descendant that calls
`setsid` or `setpgid` may survive cancellation or timeout and retain workspace
write access; process cleanup is best effort, not an OS sandbox boundary.
Sandbox data and the app container are shared by commands for the same
workspace, so this is not per-command data isolation.

`--uid`, `--macos-entitlements CWD DATA`, and `--codesign ARGS...` are internal
cache-preparation operations. `--macos-worker CWD TEMP TIMEOUT_MS COMMAND` is the
signed worker's execution role; calling this role directly on an unsigned binary
does not activate App Sandbox. The public native Runner path always validates
the signed app and its fixed policy first. Setup commands have bounded output
and a 10-second deadline. Initial-child exit ends output draining within 500 ms
even if a detached child retains a pipe.

Actual native macOS enforcement tests passed on macOS 26.7.2 arm64. See
[verification and limits](../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#macos-native-backend-2026-10-15).

## Optional native Linux workspace sandbox

`ipse-runner --sandbox linux-workspace-v1 CWD TIMEOUT_MS COMMAND` selects a
fixed, fail-closed OS policy. The three-argument form above retains its trusted
behavior. The sandbox form never falls back to trusted execution. Unsupported
platforms/profiles, privileged callers, or failed kernel setup emit an `E` frame
without starting the requested shell. Policy is applied in the child after the
supervisor creates its process group and before `/bin/sh` executes.

The backend requires native little-endian Linux x86_64 or aarch64, enabled
Landlock ABI 6 or later (Linux 6.12+), permitted unprivileged user namespaces and
UID/GID mappings, mount/network/PID namespaces, and the `open_tree`, `move_mount`,
`mount_setattr`, `statx`, and `close_range` interfaces. Distribution security
policy can disable these facilities even on a recent kernel. Effective UID zero
and effective/permitted/ambient capabilities are rejected. `/proc` is needed by
the supervisor for bounded capability/thread inspection and namespace mapping;
it is absent from the child filesystem. Kernel setup is the capability probe:
a successful sandboxed harmless command establishes support for that invocation.

The child receives separate user, mount, network, and PID namespaces and a private
read-only filesystem root. Canonical `/usr`, `/bin`, `/lib`, and `/lib64` trees
are recursively mounted read-only when present. `/etc/ld.so.cache` and
`/etc/localtime` are optional exact read-only files. Exact devices are
`/dev/null` read/write and `/dev/zero`, `/dev/urandom`, `/dev/random` read-only.
The canonical workspace and a per-command mode-0700 data directory are writable;
the latter appears as private `/tmp` and at its original absolute path. The
read-only root is a sibling of that writable data, never inside it. Mount sources
are pinned and their inode/device identities checked after namespace creation;
replacing a source before spawn fails closed. Mounts are `nosuid`; directory
mounts are `nodev`. Capabilities and their bounding set are dropped before exec.

Bash descriptor paths use a fresh `subset=pid` procfs mounted at `/dev/.ipse-proc`
inside the private PID namespace, with `/dev/fd` and standard descriptor symlinks.
The host's procfs is never mounted. Regular procfs reads/enumeration receive no
Landlock grant. The original pre-exec child and namespace PID 1 are trusted
close-all-descriptors waiters; user code runs as an ordinary child. They forward
exit status and preserve the final command's spawn-error pipe until actual exec.
PID 1 reaps orphaned children; default command signals remain ordinary. Existing
supervisor cancellation kills the owned group and namespace. See
[descriptor design and evidence](../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/sandbox.md#observed-bash-and-dependency-visibility-limits).

Landlock additionally confines file access
 and signal recipients to the new
sandbox domain and descendants. Seccomp rejects external socket creation,
connection, binding, listening and accepting; namespace/mount changes; tracing,
process-memory and pidfd access; SysV IPC; io_uring; privilege/module changes;
and process-group/session escape. Private connected AF_UNIX **stream** and
**sequence-packet** pairs are permitted for BEAM/Rust child-spawn internals;
datagram pairs remain denied. Cross-PID resource-limit changes,
scheduling/priority changes, page migration, and process-memory advice/release
are denied; `prlimit64` accepts only current-process PID zero. Private pairs
do not allow connecting to host socket names. Ordinary forks and threads remain
available; `clone3` reports `ENOSYS` for libc's legacy-clone fallback. Inherited
nonstandard descriptors close at exec. The child environment contains only
`PATH=/usr/bin:/bin`, `LANG=C.UTF-8`, and private `HOME`/`TMPDIR` values.

Resource ceilings are: no core dumps, CPU seconds `ceil(timeout_ms/1000)+1`, address
space 16 GiB, 256 open descriptors, and regular file size 64 MiB. NPROC is the
observed real-UID thread count plus 1024, clamped to the caller's existing hard
limit; exhausted hard limits or failed bounded `/proc` scans fail setup. These
are OS resource ceilings, not an aggregate per-command memory, disk, or process
quota; NPROC is shared by the real UID and its count is a snapshot. The existing
supervisor timeout and anchored group cleanup still bound command lifetime. The guard
kills the group before releasing the private-directory owner.

The helper rejects `/`, `/tmp`, overlap with protected system roots, the real
UID's home or its ancestors, and overlap with that home's `.ipse`, `.ssh`,
`.aws`, `.codex`, or a configured `IPSE_HOME`. The caller must still validate
the selected workspace before authorizing this mode: choosing a workspace
authorizes its contents, including unknown custom credential files or other
secrets within it. System tools outside the allowlist and builds requiring
network, host home configuration, `/proc`, or other system paths can fail.

Verified on the development Linux x86_64 host: actual namespace setup, shell
forks, Rust threads, network/signal/pidfd/SysV denials, writable workspace chmod,
absent outside sentinels, read-only system chmod, Elixir version startup and
Elixir compilation, and replaced-workspace rejection. Aarch64 constants were
reviewed against kernel headers; aarch64 execution and other hosts remain
unverified. Authoritative layouts: [Landlock](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/landlock.h),
[mount APIs](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/mount.h),
[statx](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/stat.h),
[x86_64 syscalls](https://github.com/torvalds/linux/blob/v6.12/arch/x86/entry/syscalls/syscall_64.tbl),
and [aarch64/generic syscalls](https://github.com/torvalds/linux/blob/v6.12/include/uapi/asm-generic/unistd.h).

### Native enforcement tests

The default `mix test` excludes `:native_sandbox`, `:macos_sandbox`,
`:macos_filesystem` and `:memory_scope` tests. The last tag runs the optional
[aggregate-memory exercise](#optional-exact-aggregate-memory-scopes). An untagged
sandbox capability test distinguishes successful explicit execution from fail-closed
unavailability; that test alone is not evidence that enforcement was exercised.
Run actual adversarial OS tests on a suitable Linux host with:

```sh
mix test test/ipse/tools/sandbox_test.exs --include native_sandbox
```

Included enforcement tests fail if the backend is unavailable. They compile a
small Rust standard-library probe using the existing build toolchain, establish
a successful host TCP connection as a positive control, then verify network,
signal, IPC and process-group restrictions through the sandbox. File tests use
fake credentials, and lifecycle tests synchronize on child output before timeout
or owner termination. Loopback access is required for Mix and the TCP fixture.

## Direct stdio server transport

`ipse-runner --stdio CWD TIMEOUT_MS EXECUTABLE ARGS...` directly executes a
configured local server, with no shell construction or interpretation of its
arguments. The application entry point is
`Ipse.Runner.open_stdio(executable, args, cwd, selected_env, timeout_ms, opts)`, which
returns an owned Port. It removes the inherited environment before starting the
helper and supplies only `PATH=/usr/bin:/bin` and `LANG=C.UTF-8` to that supervisor.
A private initial `L` frame delivers the selected environment to the final server;
the helper never loads selected `LD_PRELOAD`/`DYLD_*` values into itself. The native
CLI itself trusts its launcher's environment; applications must use the scrubbed
entry point. Credentials belong
in explicitly selected environment values, never executable arguments or logs.

For MCP, the config's per-server `sandbox` value independently chooses `off`
(the default) or `native`; the CLI shell `--sandbox` option does not set it.
`Ipse.Runner.open_stdio/6` resolves `native` to the fixed Linux or macOS
workspace profile and passes a bounded launch frame so selected environment
values go only to the final server process, not the supervisor. The server gets
`PATH=/usr/bin:/bin`, `LANG=C.UTF-8`, its selected environment, and a fresh
private `HOME`/`TMPDIR` in native mode. Linux native stdio tests verify
workspace writes, outside-workspace denial, network denial, and supervisor
protection. The macOS stdio route uses the signed worker and exact entitlements;
its four native stdio enforcement cases passed on macOS 14 arm64 CI. See
[P7 evidence](../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#p7-expanded-local-mcp-2026-10-15)
and the subsequent [local cleanup investigation](../docs/archive/2026-10-18-before-manual-rewrite/docs/developer/testing.md#macos-stdio-cleanup-load-2026-10-15).
Native launch or capability failures fail closed and do not retry in trusted
mode. See [the sandbox policy](../docs/developer/sandbox.md) for the common
profiles and their limits.

The helper requires an initial private `L` frame: a big-endian u32 payload size,
then a big-endian u32 entry count and length-prefixed UTF-8 key/value strings.
The payload is at most 134,144 bytes and 130 unique valid environment names;
missing/invalid input fails before launch, with a five-second read deadline.
MCP configuration applies the stricter 16-variable bounds above this helper API.
Selected values are installed only in the final executable environment. On Mac,
the unsigned supervisor writes a bounded length-prefixed environment to the signed
worker's private stdin before relaying server input. The worker reads exactly
that prefix using an unbuffered descriptor and preserves stdin across exec. No
environment file is staged in the shared writable sandbox data. The existing
watchdog and owner lease cover blocked prefix writes and reads. This does not
erase retained data from older generations or establish per-command isolation.
`open_stdio` uses an empty nonblocking write probe to wait at most five seconds
for the initial launch frame to flush, handling owned cancellation while waiting.
It does not claim server readiness or sandbox activation; subsequent writes keep
their ordinary bounded backpressure behavior.

The remaining input is OS transport framing, not MCP framing: `I` followed by an
unsigned big-endian four-byte length and that many raw server bytes forwards
stdin; `C` followed by a zero length cancels the child. Input payloads are at
most one MiB. Use `Ipse.Runner.send_stdio(port, bytes)` to construct input frames
without suspending on a busy Port. `Ipse.Runner.close_stdio(port)` sends cancel,
drains output, and waits at most two seconds for supervisor exit before closing
the Port. It returns `:ok` only after an exit-status confirmation; otherwise it
returns a fixed cleanup-unconfirmed error. Do not reuse a server slot as if
cleanup succeeded after an unconfirmed result. Abrupt owner death still closes
the pipe and independently kills the ordinary process group.

Output uses the existing one-byte kind and unsigned big-endian four-byte length
framing: `O` is server stdout, `S` is server stderr, `X` contains
`{"exit_code": integer, "timed_out": boolean}`, and `E` contains a fixed transport
failure. Output chunks are at most 8192 bytes, and the combined output queue is
32 chunks. Stdout and stderr are separate streams; a chunk need not contain a
complete UTF-8 character or application message. Elixir owns MCP/JSON-RPC parsing;
the native helper interprets neither server messages nor tool schemas.

The lifetime timeout accepts 1–86400000 milliseconds. Owner pipe EOF, timeout,
failed output delivery, input overflow, and initial server exit kill its ordinary
process group. An independent watchdog enforces the deadline even when output
is blocked and allows at most one additional second before forcing supervisor
exit. After server exit, output drains for at most 500 milliseconds. Idle
five-millisecond polls repeat group SIGKILL to catch ordinary children created
during the first signal's delivery, within the original drain deadline or until
pipe disconnect. The unreaped anchor can keep the group present after ordinary
children have exited, so a successful signal does not establish remaining live work.
Retained pipes that exceed the original bound still produce a transport failure
without an `X` completion; this includes detached pipe holders. Input relay buffering
is bounded to one MiB plus the current chunks and OS pipe buffers. Overload fails
closed instead of blocking the owner-death reader. An oversized in-flight Port
write may surface as a linked `:epipe` exit before the final error frame, so the
transport owner must handle Port exits and treat them as failed exchanges.

This mode runs a trusted configured server with the user's OS permissions. Its
process-group cleanup is best effort for ordinary descendants; a deliberately
detached process can escape. It is separate from the native workspace sandbox
and makes no filesystem or network isolation claim. A transport failure never
proves that a server operation had no effects and must not automatically replay
an interrupted request.

### Observe an owned loopback listener

On Linux, an explicit `owned_listener: {:ipv4_loopback, port}` option to
`Ipse.Runner.open_stdio/6` selects:

```text
ipse-runner --stdio-listener CWD TIMEOUT_MS PORT -- ABSOLUTE_EXECUTABLE ARGS...
```

This mode uses sandbox `:off`, the same private launch environment, owned process
group, I/O queues and lifetime watchdog. It observes only literal `127.0.0.1`
with a port from 1 to 65535. Invalid options and unsupported platforms refuse
before server launch. Listener admission also requires procfs to represent the
supervisor's PID namespace. Before launching the server, a bounded 64-KiB read of
`/proc/self/status` must supply exactly one `NStgid` value equal to the helper's
process ID. An inherited ancestor procfs, missing identity or malformed status
refuses. A nested PID namespace with its own procfs is supported. Ordinary
`--stdio` keeps its existing frame stream and has no such capability requirement.

The supervisor reads its own network namespace's bounded IPv4 and IPv6 TCP tables, finds the
exact LISTEN tuple and associates its unique positive socket inode with the
retained direct child's FD links. It rereads the caller-side tuple after that
association. A child that moved into another network namespace cannot substitute
a private listener for the caller's endpoint. Wildcard bindings, ambiguous
tuples, a listener owned only by a descendant, unavailable evidence and exceeded
bounds refuse. Any IPv6 LISTEN socket on the selected port also refuses, including
an IPv6-only wildcard sharing the IPv4 port. Both table reads together are at
most 1 MiB; enumeration is at most 4096 FDs.

One background inspection runs at a time. The main wait owner keeps the child
unreaped throughout that inspection, then checks its status before publishing.
Output delivery, cancellation and the independent watchdog continue. An output
failure while inspection is pending skips direct-child reaping until helper
teardown. A missing tuple can be observed again after 25 milliseconds within
the existing lifetime deadline; this does not restart the server.

Successful observation emits exactly one `P` frame with a 15-byte payload:

| Bytes | Field |
| --- | --- |
| 0 | Version, unsigned byte `1` |
| 1–4 | Retained direct-child PID, unsigned big-endian u32 |
| 5–6 | Declared port, unsigned big-endian u16 |
| 7–14 | Observed socket inode, unsigned big-endian u64 |

The client validates this fact before opening the selected HTTP endpoint and
continues handling `O`, `S`, `E`, `X` and Port loss. A fact is an observation,
not an atomic promise of future availability. PID and inode are diagnostic
identities; retain the Port for lifecycle authority. Printed child bytes remain
`O`/`S` payloads and cannot create a native fact. After inspection fails, the caller
must retain the failed attempt and its possible effects through the owning
operation's journal. This generic protocol creates no durable attempt record.
Failure never authorizes adoption of an existing server or automatic replay.

The process-group cleanup and sandbox limits above still apply. In particular,
this observation supplies neither confinement nor detached-descendant cleanup.
Run its public API and pure native controls on a Linux host:

```sh
mix run dev/verify-owned-listener.exs
mix run dev/verify-owned-listener-regressions.exs
IPSE_LISTENER_TESTS=$(mktemp -d)
rustc --edition=2021 --test -D warnings native/ipse-listener.rs \
  -o "$IPSE_LISTENER_TESTS/listener"
"$IPSE_LISTENER_TESTS/listener"
```

Expect eight public live cases, seven parser tests and a separate causal-regression
summary with `status: passed`. The regression command compiles diagnostic copies
and compares each repair with its deliberate reversal. It leaves production
source unchanged. Three additional controls require refusal before execution
with an inherited ancestor procfs, ordinary stdio compatibility in that setup,
and an owned listener inside a nested PID namespace with its own private procfs.
Unavailable user/network/PID/mount namespaces produce incomplete coverage and
exit status 2. No model service, systemd or cgroup hierarchy is required. The
[runtime-contract exercise](../docs/developer/extensions.md)
connects the fields to source, admission and cleanup.
