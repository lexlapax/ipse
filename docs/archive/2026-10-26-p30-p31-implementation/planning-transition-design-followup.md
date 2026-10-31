# Planning transition implementation notes

2026-10-27. This records a proposed implementation sequence and subsequent
partial entry implementation, not a security review or P31I acceptance. The active contract remains
the [frozen baseline](baseline.md#clarification-editing-and-planning); the
[CLI record](planning-cli-followup.md) describes the existing startup ceiling.

## Current constraints

The Session owner serializes its calls, but a native terminal prompt can be
staged in `Ipse.Session.Input` while another turn runs. Its binding uses the
operator channel generation, not `input_generation`; changing only the latter
does not invalidate staged prompts. A transition must therefore consume its own
observed command and invalidate all other observations and staged tickets before
acknowledging success. The terminal must also discard queued entries and explain
that the user must submit them again. A stale queued command must not acquire the
authority of the mode after exit.

An idle Session phase alone is not established proof that all detached or child
resources are finished. Before acknowledging entry, the implementation needs a
defined owner-checked quiescence predicate covering active work, delegation,
pending approvals and cleanup, and must refuse when completion or cancellation
cannot be confirmed. It must not interpret an interrupted effect as undone.
In particular, a child already running with an earlier ceiling cannot be made
safe merely by changing its parent's configuration.

`Saved.execution_mode/2` validates monotone version-1 and version-2 resume
checkpoints, and `PlanningMCP` validates separate epoch and call-start records.
Adding a new event that old readers silently ignore can leave an old reader
with a weaker view of the mode. Entry therefore needs a restrictive checkpoint
that every supported reader recognizes or a demonstrated fail-closed protocol
version. Exit needs a separately versioned, witnessed transition whose replay
validation cannot be confused with a monotone resume checkpoint. Compatibility
must be tested with actual old readers, not inferred from the event name. The
new reader must validate exact previous mode and session binding, and refuse
malformed, reordered or duplicated transitions.

The transition must not infer local ownership solely from the current ceiling:
an old version-1 checkpoint could already have collapsed local and inherited
provenance. A durable entry must identify the local restriction and the prior
floor. Exit may restore only that floor, preserving enclosing, approval and
knowledge restrictions; ambiguous legacy histories must remain restricted.
Child inheritance remains distinct from same-owner resume.

A host-state Session regression now checks the existing channel replacement
behavior: staged and unstaged observations from the former channel refuse,
while a freshly staged input on the new channel is accepted and reconstructed.
The Session input, execution-mode and planning-MCP replay selection passed 18
tests with seed 46383, including an attempt to reuse the old observation on the
new channel. This uses synthetic observations, not a native terminal;
it does not implement a planning transition or demonstrate resource quiescence.

## Subsequent entry implementation

The working tree now exposes `/plan` at an idle native-terminal prompt. Session
consumes the exact staged observation, checks its current restrictive-entry
preconditions, invalidates the remaining inputs, writes a version-2 restrictive
checkpoint, rebinds a declared-read MCP epoch if present, and writes a receipt
bound to the checkpoint and observation. `Saved` checks that receipt, and the
observation uniqueness validator includes it. A crash after the checkpoint but
before the receipt leaves a restricted mode and does not establish witnessed
entry provenance. Existing version-2 readers retain the restriction; readers
that do not understand that checkpoint must refuse rather than widen.

The current guard refuses retained drafts, active feeds and listed unconfirmed
work or cleanup. It does not establish that every possible detached resource is
quiescent. Synthetic controls include wrong-client, reused and busy tickets,
queued input invalidation, resume, declared-read epoch order, tampered receipt
and a native PTY command. The selection passed 39 tests, seed 46390. An initial
post-cancellation test found that an open lifecycle epoch was being treated as
active work; the guard now checks for an outstanding lifecycle wait instead.
These are local tests, not crash-injection, old-reader, human or final safety
qualification. Entry does not provide exit or deferred-decision publication.

A broader CLI, Session, draft, permissions and MCP selection initially failed
one of 152 tests (seed 46391): a normal resumed-draft epoch differed from the
persistent mode even though no entry receipt followed it. The validator now
discards that possible receipt binding rather than rejecting the old history;
a receipt after the mismatched epoch still refuses. The same selection then
passed all 152 tests, seed 46392. This is not a full repository regression or a
substitute for the remaining crash, resource and compatibility checks.

## Subsequent local exit implementation

The working tree now accepts `/plan exit` as a separate observed native-terminal
command after a witnessed local `/plan` entry. The exit record binds the entry,
current mode and observation. Replay changes only the local ceiling, retains
approval, knowledge and enclosing restrictions, and discards local-entry
provenance after a version-1 checkpoint. A startup or inherited ceiling alone
does not authorize exit. Session invalidates other staged input before appending
the exit; a declared-read MCP epoch must follow before new MCP work. The exit
does not publish decisions. These implementations remain subject to the resource,
actual-crash and final audit work below.

The synthetic Session test truncated its own closed test journal immediately
after exit and before the new MCP epoch. Replay rejected a tool start in that
prefix, and a new Session resumed with a fresh epoch and no replayed exit. This
is a constructed prefix, not an actual crash or power-loss test. Tests also
cover local exit across resume, preservation of a newly inherited read-only
ceiling, denial without an entry, tampering, queued input invalidation and a
native PTY entry/exit. The focused selection passed 41 tests, seed 46396; after
the added inherited-floor and prefix controls, 14 selected tests passed with
seed 46398.

The subsequent affected CLI, Session, draft, permissions and MCP selection
passed 155 tests, seed 46399. A further three-test focused replay run, seed
46400, checked a version-1 checkpoint that retains both active and enclosing
planning while invalidating local-entry provenance. Neither run is a full
repository regression.

The previously built isolated reader from `_build/available-host-corrected.9kdxAhKx`
ran the synthetic [compatibility probe](planning-legacy-reader-probe.exs): its
mode reconstruction retained planning after ignoring the new exit record, and
its declared-MCP replay refused the later ordinary-mode epoch. The probe SHA-256
is `307eb597a1760ff13645a5229b71c0e6c59e4c72b1c6f753ea78629434d03413`;
the older Saved and PlanningMCP BEAM hashes are
`bf3317f28e351e280466ffd59badd74cbc07ce5ed59d1c47e122175ccaa73bfa` and
`f98b92ebc946ab8c070b680e0624a579ec89e01136d8224aa3b3ec9dfd1a8d0e`.
This checks one prior build and synthetic histories, not all released versions.

## Explicit CLI startup provenance

The CLI now passes an explicit startup-selection bit into the host runtime.
A fresh local `--planning` selection writes a session-bound marker in the
header; selection on resume from a known normal floor writes a marker bound to
the new restrictive checkpoint and, when declared reads exist, its MCP epoch.
Child, inherited and nonplanning configurations cannot attach that marker.
Re-selecting `--planning` on a history already in planning does not invent an
entry for an ambiguous legacy floor. A crash before a resume marker can leave
the restriction active without exit provenance; it does not authorize exit.

Tests cover fresh and resumed selection, malformed and child provenance,
ambiguous legacy refusal, declared-read MCP replay and an observed native PTY
exit. The CLI/Session/replay selection passed 65 tests (seed 46403), and the
additional Session, mode, MCP and PTY selection passed 36 tests (seed 46404).
The PTY uses synthetic input; this is not a human journey, actual crash test or
full P31I acceptance.

The affected CLI, Session, draft, permissions and MCP selection then passed
158 tests, seed 46405. After that run the entry guard was narrowed to allow
cancelled and fully consumed drafts while still refusing unresolved drafts;
the current Session, mode, MCP and PTY selection passed 37 tests, seed 46406,
including a cancelled-draft entry and exit. The earlier 158-test run predates
that guard change. A synthetic [prior-reader startup probe](planning-legacy-startup-probe.exs)
confirmed that the same older reader retains the startup planning ceiling after
ignoring the new marker and exit record. Its SHA-256 is
`3edb602693342f4417d5df04fe0a593a7b3dbbcf811f4db77538a1c2d746ddc6`.

A later continuation also retains the CLI selection marker when an interrupted
draft is restored under its temporary MCP epoch. The draft-derived epoch may
carry startup-selection provenance but cannot stand in for a witnessed `/plan`
entry. The affected synthetic MCP, mode and Session selection passed 15 tests
with 32 unrelated cases excluded, seed 46407. This does not itself exercise an
actual native exit after that interrupted draft.

The affected CLI, Session, draft, permissions and MCP selection then passed
159 tests, seed 46408. A separate child-configuration test exposed that the new
startup flag was copied into delegated configuration (13 of 14 tests passed,
seed 46409). The Session's delegated-origin check would refuse that combination,
but the copy also prevented legitimate child startup. `Delegation.child_config`
now drops the parent-only flag while retaining the enclosing planning ceiling;
the child and mode selection passed 14 tests, seed 46410. The 159-test run
predates this last delegation repair.

After the repair, the combined CLI, Session, draft, permissions, MCP and
delegation selection passed 166 tests, seed 46411. A further 45-test Session,
configuration and delegation run, seed 46412, includes a new check that a fresh
CLI startup marker remains usable after closing and resuming without the flag.
These selections do not establish full repository or milestone acceptance.

The commands for seeds 46409–46411 included a nonexistent
`test/ipse/tools/delegation_session_test.exs` path. Mix silently omitted that
path; those totals cover the existing files named by the commands, not a
delegation-session suite. Run the actual integration, parallel and lifecycle
files separately before claiming those paths were exercised.

The actual integration, parallel, lifecycle, child-policy and mode files passed
45 tests, seed 46413. A new actual child-Session test then exercised delegation
after a synthetic witnessed exit from startup planning and checked the child's
configuration and saved header. Its first run passed 38 of 39 tests but looked
for the child journal in the parent directory; the fixture was corrected to use
the nested child directory. The four delegation files passed 39 tests, seed
46415. The witness is synthetic; this is not a human terminal journey.

For a Session with planning-read declarations, the checkpoint and the new MCP
epoch form a crash-sensitive sequence. No tool work may run between a committed
mode change and its matching epoch. Recovery must allow a valid durable prefix
without granting the old epoch's authority, and must handle repeated recovery
without replaying a tool call. Both the declared-read and no-declaration
reconstruction paths need controls, including draft cancellation and consumption.

## Required execution and verification

1. Use a native observation bound to the subscriber, channel, exact command and
   current generation. Reject non-native, forged, reused, stale and wrong-client
   observations. Require a distinct explicit observed exit; accepting a draft or
   an ordinary model message is not an exit.
2. Establish the quiescent state and fence queued inputs. Append the transition
   and, where applicable, a mode-bound MCP epoch using checked journal writes.
   Define failure and crash behavior for every boundary before acknowledging the
   new mode. No automatic effect replay or deferred-decision publication is
   permitted. Preserve already recorded unknown outcomes.
3. Verify the actual Session and terminal with queued prompts, pending approval,
   child work, active MCP work, failed cleanup, owner loss and interrupted writes.
   Test replay from every durable prefix, tampered provenance, multiple
   enter/exit/resume cycles, legacy version-1 history, explicit denial and
   inherited read-only/planning floors. Exercise both old and new readers.
4. Implement deferred accepted-decision capture separately. An explicit later
   save must revalidate current source, permission and authority; exiting alone
   never publishes it. Cancelled or unaccepted proposals are not decisions.

The source inspection above does not establish that this sequence is sufficient
for implementation or that an available host qualifies protected storage. It
identifies constraints that must be resolved and tested along the complete path.

## Journal exhaustion at a transition boundary

On 2026-10-27, an actual Session and Journal.Writer control narrowed the
available event allowance after staging a synthetic input. With declared MCP
reads, the checkpoint was committed but the following epoch could not fit; the
writer appended its terminal limit receipt and the Session stopped without an
acknowledgment. Before the repair, MCP replay rejected that otherwise valid
sealed history (seed 46438). The same boundary exists after an exit record.

MCP replay now accepts a valid terminal journal-limit receipt while an epoch is
pending, after validating the limit record sequence. It does not treat the old
epoch as authority for a subsequent operation. Real Session/Writer controls for
entry and exit pass with seed 46441: each sealed history restores for inspection,
an attempted Session reopen refuses, and forged receipt fields or a later tool
event refuse. A no-declaration entry control also passed (seed 46437), retaining
the planning ceiling without inventing an entry witness. These are induced
resource-limit failures with synthetic input, not power-loss or native terminal
crash tests; a sealed journal still requires an explicit fresh-session handoff.

The same replay issue also affected a structurally valid seal before the first
declared-read epoch (synthetic pre-fix seed 46442) and after a pre-start intent.
The rule now handles terminal limit receipts before those boundaries as well:
the enclosing validation checks the receipt and its final position, and no
missing epoch or start is inferred. Synthetic replay and real Session controls
passed 16 tests on seed 46443. An earlier ten-file selection passed 142 tests
on seed 46440 before this extension; it does not cover the final rule. The
updated ten-file Session, MCP, CLI and draft selection passed 143 tests on seed
46444, with platform-specific tags excluded.

## Controlled Session death at journal boundaries

On 2026-10-29, a [focused native-terminal control](planning-native-crash-46979.log)
fed `/plan` through the real PTY/operator path, held the entry receipt after the
real Writer synced the restrictive checkpoint, and killed the actual Session.
The terminal reported failure and its original mode was restored. The saved
history retained planning without a witnessed entry, and reopening preserved
that restriction without replaying the entry or exit. The checked fixture had
no declared MCP reads. Like the controls below it used a test-only Writer proxy
as the Writer's authorized caller, so this is a controlled Session-process
death, not an uninstrumented process crash or power-loss test. Input was
synthetic, not a human journey.

The fixture and driver snapshot is `_build/planning-native-crash-20261029`;
the test, driver and script SHA-256 values are respectively
`6a9e76efec0549a743b3e6ed65d67d747e35225c7d00b2ff482cc008fe250c18`,
`8597e14f0459153c59c452dc447dd207f7943c2725c0bca4587191a9d48cf841` and
`013dc59fbc49ec3d62a8ebc635ffef6ab01b718cdd6e9ae50b8a54cb0f2543dc`.
It used the frozen `_build/coordinated-supersession-sol-20261029` runtime with
the native helper identified in the [supersession record](../2026-10-28-managed-supersession-session/index.md).
This control does not qualify all transition boundaries, resource quiescence or
the current combined source tree.

The [extended native-terminal control](planning-native-crash-46980.log) passed
four actual Session-death cases: immediately before and after the Writer synced
the entry receipt and immediately before and after it synced the exit record.
Before entry, recovery kept planning without entry provenance. After entry or
before exit, recovery kept planning with the entry; after the exit record, it
restored normal mode. Each case checked no transition was replayed, and the PTY
driver checked terminal restoration. The snapshot is
`_build/planning-native-crash-46980`; the test, driver and script SHA-256 values
are `f3adcb537e958702c3dcc52818146b47b60585e8b29233a8fc727f6a120ae65f`,
`bf7234169f1da00a242a1b53187e56ddab594814d48cf037ed5d39505a34686f`, and
`82031026043c4e44f99fd82f654f3708db211fe18507a3b93a4493275f435dca`.
These use the same frozen runtime and test-only proxy as the first case; they
do not include declared MCP reads, an uninstrumented crash or power loss.
The [strengthened repeat](planning-native-crash-46981.log) passed the same four
cases with explicit retained-entry provenance assertions. Its changed script is
captured under `_build/planning-native-crash-46981` with SHA-256
`b279b792ab240d50b3c4a676a37263f362a545d9dc62ce08e2824ba0cdc3f7f4`;
the test and driver match the 46980 snapshot.

The matrix was extended with declared planning-MCP reads and two controlled
Session deaths before the newly required entry and exit epochs. The first
[attempt](planning-native-crash-46982.log) mistakenly armed the exit fault
during the entry epoch; its fixture stopped too early and failed. The proxy was
changed to arm that fault only after the entry receipt. The corrected
[six-case run](planning-native-crash-46983.log) passed: both incomplete epoch
prefixes reconstructed, resumed with a fresh epoch and did not replay a tool
start or planning-MCP read intent. This is a declared-read metadata fixture; it
does not start an MCP server or prove in-flight MCP cancellation. The source
snapshot is `_build/planning-native-crash-46983`; test, driver and script hashes
are `19293f44786f9d0cd1f435a6b6dbf567f80c670b306ffe3e5d44bf346c6d3add`,
`bf7234169f1da00a242a1b53187e56ddab594814d48cf037ed5d39505a34686f`, and
`e433b9d782e249bbc24665c89f8288cbeef0bc545fcc809f1c54cd97e170b4c8`.
The failing fixture source was not separately frozen. All cases retain the
controlled proxy, synthetic-input and frozen-runtime limitations above.

A later test kills the actual Session after its restrictive checkpoint has been
written and synced, holding the following entry receipt. Recovery preserves the
planning ceiling and refuses an exit without entry provenance (seed 46456).
A later run also verified that an input staged before the interrupted transition
cannot be submitted to the recovered Session (seed 46460).
Three declared-read controls kill the Session before the new MCP epoch, before
the entry receipt after the new epoch, and after the exit record before its new
epoch. They restore the durable prefix, resume twice with newly linked epochs,
and check that no MCP intent or tool start was replayed (seed 46458).

The tests use synthetic staged input and a test-only writer proxy to hold a
specific append. The real writer retains its file, Session monitor, lock guard
and sync behavior, but its authorized caller is changed to the proxy for the
test. These are controlled Session-process deaths, not uninstrumented native
terminal crashes, power loss, in-flight MCP cancellation, or proof of the
production native-storage profile.

The declared-read matrix was later extended to hold the response immediately
after the real Writer synced `planning_exited`, kill the Session before its
acknowledgment, and check restoration and two linked recovery epochs without a
replayed tool or MCP intent. The expanded control passed one selected test
(15 excluded, seed 46679). Its log SHA-256 is
`2fb6ab3eae866288829999da92472485fc7ed8779a6ca3b9950b668efa6b97e5`; the
test source SHA-256 is
`13c07a039c504f4787a2496af00fb013698a94755b76b779ed4d7fd61a5ca269`.
The question, planning transition, planning MCP and execution-mode suites also
passed 38 tests together (46680), with log SHA-256
`531dbb0ff1f552858ec485d9e2a076a52ee4a837965c7fee260d2fc58e8f93d1`.
This synthetic proxy and process-death control does not establish power-loss,
human terminal or production native-storage qualification.

The complementary declared-read case now kills the Session while the Writer
holds the exit append before writing it. Recovery retains the planning ceiling
and entry provenance; a fresh witnessed exit is required. The same four-file
selection passed 38 tests (46682), log SHA-256
`ba7f324897cf0668c9523c30145bb9194ec12f77b26379869cad6fdaa54dd746`, with
test source SHA-256
`8094116c7641ce9976d36943d8f8480796ad7cf8a6c467623daf0f4b0b26646b`.
This retains the controlled-proxy limits described above.

The affected ten-file Session, MCP, CLI and draft selection passed 145 tests
(seed 46459), excluding platform-specific tags. It began before the additional
stale-input assertion, which passed separately on seed 46460.

Another controlled process-death test holds the response after the real Writer
has synced a `planning_exited` record, then kills the Session before it can
acknowledge the exit. Without declared MCP reads, restoration retains normal
mode, a queued input from the dead Session is rejected, and only one exit record
exists after reopening and closing. The focused control passed (seed 46516),
and the planning, MCP and execution-mode selection passed 39 tests (seed
46517). As above, the test uses synthetic input and a proxy admitted as the
Writer caller; it is not a power-loss or native-terminal qualification.

The complementary no-declaration boundary now kills the Session after the
real Writer syncs the observed planning entry but before acknowledgement.
Recovery retains planning mode and witnessed exit provenance, rejects an old
queued input, permits a newly witnessed exit and leaves one entry and one exit.
The focused control passed (seed 46547); the planning, MCP and execution-mode
selection passed 40 tests (seed 46548). It uses the same synthetic input and
test-only writer proxy, not power-loss or native-terminal qualification. The
full diagnostic snapshot completed at that point predated this test.

The declared-MCP control now also kills the Session after the entry receipt is
synced. Two resumes link fresh epochs; a newly witnessed exit then links its own
normal-mode epoch without replaying a tool start or MCP intent. The focused
control passed (seed 46549), as did the 40-test planning/MCP/mode selection
(seed 46550). It has the same synthetic-input and writer-proxy limitations.
