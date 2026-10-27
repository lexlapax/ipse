# Keeping session evidence durable

The journal is the recovery authority for conversation and admitted effects.
`Ipse.Journal` creates/reads JSONL and handles inactive appends and allowed tail
repair. `Ipse.Journal.Writer` owns an active append descriptor. The same `Journal` module
decodes bounded records and enforces finite growth. The independent
`Ipse.Session.Lock` guardian retains the Rust advisory lock until owned work has
actually quiesced. Lock files remain in place to preserve inode identity.

Start with `lib/ipse/journal.ex`, `journal/writer.ex`,
`session/resources.ex`, and `session/lock.ex`.
Follow a synced tool intent into execution before attempting a storage refactor.
The timing of the receipt is part of correctness, not an implementation detail.

## Separate reconstruction from recovery IO

`Ipse.Session.Saved` rebuilds facts from an already loaded event list. Its
`context/1` function retains the narrow message-list contract exposed by
`Ipse.Session.restore_context/1`. It validates durable context records and restores
unknown tool outcomes without executing a tool. `Saved.restore/2` additionally
reconstructs accounting, extension action state, saved-result indexes, research
validation, pending questions and the last recorded model/request facts. It
returns those facts without starting a Session or reading source pages.
For new reference-layout sessions it also validates the admitted header/catalog,
reference epochs, positions, generations and turn bindings. Completed native tool
results retain recorded order. References cannot close an unfinished group by
inventing a result; unknown outcomes are materialized at a genuine next-user
boundary or interrupted-history reconstruction. Legacy reconstruction retains its
original ordering and layout. Follow the complete [context projection](workspace-context.md#admit-a-header-and-append-current-references)
before changing either path.

The owner still controls recovery order: acquire the session lock, reload and
validate the locked journal and its sources, repair only a permitted torn tail,
reload, then reconstruct pure facts. Afterward, event/subscription question
recovery resolves its source pages. Workspace/skill discovery and writer startup
remain owner-held IO. A successful pure reconstruction alone does not certify
those external sources or authorize a pending effect.

Try the boundary in `iex -S mix` with a synthetic empty journal:

```elixir
scratch = Path.join(System.tmp_dir!(), "ipse-saved-exercise-" <> Ipse.Usage.id())
File.mkdir_p!(scratch)
{:ok, id} = Ipse.Journal.create(scratch, %{"provider" => "demo", "model" => "scripted"})
{:ok, events} = Ipse.Journal.load(scratch, id)
path = Path.join(scratch, id <> ".jsonl")
before = File.read!(path)
{:ok, []} = Ipse.Session.restore_context(events)
{:ok, saved} = Ipse.Session.Saved.restore(events, id)
nil = saved.question
true = before == File.read!(path)
File.rm_rf!(scratch)
```

Then follow the interrupted-write case in `test/ipse/session/recovery_test.exs` and the
pending-question cases in `test/ipse/tools/questions_integration_test.exs`. Verify that an idle
resume preserves the journal and workspace, and that a saved question still
requires a fresh explicit answer. `Questions.tool_result/3` supplies the same
message shape to live question handling and saved-checkpoint validation.

## Follow an active append

Session validates configuration and recovery sources, repairs only an allowed
final torn record, and opens its writer under the session lock. Writer startup
validates the complete journal once. Successful initialization links to the owner;
Session monitors writer loss and stops dependent work if it disappears. There is
no automatic writer restart or append retry.

Only the owner may append, reserve capacity, release it, or close. For each record
the writer encodes the JSON, checks descriptor/path identity and expected length,
and admits a private
filesystem completion owner. That process opens a separate append descriptor,
checks identity/protection/length again, writes, fsyncs, closes, and replies. Session
waits for confirmation before dispatching effects or exposing a lifecycle source.

Checks include device/inode, owner, regular-file type, single link, permissions,
and length. Replacement, foreign append, truncation, or protection changes close
the writer. This avoids rereading history per append, but it is not a live prefix
hash proof: a same-size in-place rewrite is not revalidated each time. Exclusive
advisory ownership and full resume/source validation remain necessary.

Active acknowledgment has a five-second deadline. An unconfirmed call reports
`journal_write_unconfirmed`, and mandatory Session paths stop as
`journal_unavailable`. A timeout proves neither presence nor absence of the write.
Never retry the same append merely because its caller timed out.

## Keep the lock longer than the caller

A BEAM process can die while ordinary file-server or dirty IO continues.
`Ipse.Session.Resources.file_effect/2` starts a completion owner before dispatch
and retains it until synchronous IO returns. Cancellation does not kill that completion owner.
The lock guardian waits for writer, root/nested workers, scopes, registered
resources, child guards, and filesystem completion owners before unlocking,
including after an untrappable Session death.

A file-effect worker inherits its caller's cleanup scope and remembers the
original caller. Protected transactions monitor both that caller and their
immediate capability owner. Losing either closes the actual native writer;
cancelling the scope reaches that same controller. Keeping a completion worker
alive to finish ordinary file IO must not keep its protected publication authority
alive. These are separate obligations: ordinary file-server IO needs completion
waiting, while protected publication uses the native transaction described below.

Read the blocked-write fixture in `test/ipse/journal/writer_test.exs`. Its FIFO delays
real IO while Session dies. A replacement session must remain locked until the
reader drains and completion returns. A monitor `DOWN` for the original caller
cannot establish that fact. A stuck completion owner can retain the lock
indefinitely; deleting the lock file would defeat ownership rather than repair it.
Unexpected loss of the helper/guardian stops Session without another append.

Stateless `Journal.append*` APIs are for inactive journals under the proper lock.
They validate history and perform synchronous completion-owned writes; repeated
inactive appends therefore have linear validation cost. Embedded callers remain
responsible for their own lock lifetime.

## Bind an actual operator observation before recording origin

An ordinary user-role message, argv value or `interactive: true` field cannot
establish verified origin. The internal `Runner.operator_input/2` primitive
displays an escaped prompt and reads one bounded line through matching actual
terminal descriptors, using the bundled helper pinned to its build digest.
It ignores `IPSE_RUNNER_PATH` for this channel. Build native before Mix so a source
checkout or package embeds the corresponding helper identity.

For a local source exercise in a real terminal, after `./dev/build.sh`, run this
single-reader command:

```sh
mix run -e 'prompt = Ipse.CLI.Terminal.escape("Synthetic observation only. Enter one line> "); {:ok, observation} = Ipse.Runner.operator_input(prompt, 60_000); true = observation["text_sha256"] == Ipse.JSON.sha256(observation["text"]); IO.puts("Observed matching terminal input; no task submitted.")'
```

This performs no publication or approval. Redirected/mismatched streams refuse.
The observation binds displayed bytes, input hash and a fresh event ID; it is
data, not a transferable grant. A host client uses `Session.observe_input/3` to
obtain `{text, witness}` for its idle Session, then `Session.prompt/3` to submit
those exact bytes. The supervised `Session.Input` service admits the read inside
the owning Session's call, binding its ID, canonical workspace and volatile input
generation before IO starts. The client awaits IO outside Session. Only the target
Session can consume the opaque reference, once, within five minutes. Changed text,
cancel, another prompt, owner/client death, service loss and resume invalidate it.
Empty input produces no witness. At most 64 completed observations can remain;
only one active read runs. Existing Session resource scopes retain cleanup and the
session lock through reader loss. Internal host code is trusted; extension workers
and JSON clients cannot manufacture a VM reference or submit an observation map
as proof. This API establishes input origin, not acceptance of a knowledge card.

Turn durably writes `input_received` version 1 before admitting the user message.
It preserves original bytes and their hash separately from the skill-expanded
hash. Reconstruction validates source/turn/observation uniqueness and links the
effective hash to the first following user message. A receipt interrupted before
that message remains source evidence; a later receipt can replace that incomplete
link, without replay. Ordinary `prompt/2` records unattended input. Old journals
retain unverified origin. Private origin records have no public lifecycle-feed
projection, so they use ordinary durable appends and preserve the existing source
limits and serialization of lifecycle user-message events.

The native deadline covers request/display/input and observes parent cancellation
even with a full terminal output buffer. A fresh nonblocking terminal description
preserves the parent's flags; incomplete input is invalidated. A retained native
regular-file lock under canonical `/tmp/ipse-operator-UID/input.lock` fences reads
across VMs and terminals for that OS user. The root must be root-owned and sticky;
the private directory/file must have safe ownership, modes and identity. The
helper holds the lock through its final flush. A stopped or closing old helper
therefore makes replacement reads refuse even after the service restarts. Leave
the lock inode in place while channels may exist. Full Unicode
escaping stays in the host. [Native protocol and PTY controls](../../native/README.md#observe-one-actual-terminal-display-and-input)
explain the descriptor boundary. PTY fixtures are automated observations, not
independent human evidence. Clients must own terminal reading and quiesce their
other readers before calling it. The single-prompt helper intentionally discards
queued future lines.

The interactive CLI uses the version-2 native channel. Its non-reading preflight
selects it only for matching terminal input/output; explicitly nonterminal input
uses the visibly unattended pipe reader. Other setup failures refuse. The native
reader preserves bounded queued input, while each approval and question render
requires its fresh displayed code. It retains a restoration guardian and worker
through terminal cleanup. Closing either BEAM consumer or the whole VM exercises
actual OS cleanup, not just task supervision. See the [operator procedure](../operator/usage.md#approve-a-small-task)
and [native protocol](../../native/README.md#observe-one-actual-terminal-display-and-input).

Session binds each channel to its subscribed client and a volatile generation.
`stage_input/4` changes an observed prompt into a one-use host ticket before the
client queues it. The queue permits 16 prompts and 1 MiB combined UTF-8 bytes;
the ordinary observation still expires after five minutes. Submitting an accepted
queued ticket must match its exact original bytes and channel binding. Explicit
cancel, client death, channel replacement and close invalidate tickets. EOF while
answering a question cancels that read and question, preserving only already
accepted queued prompts; it cannot preserve an unfinished answer or grant approval.

Question answers use an atomic version-2 `operator_answer` record containing the
effective user message and its complete original-input receipt. Session validates
the whole `answer CODE VALUE` line against the current question/render, preserves
each original answer payload separately from choice normalization, and commits
the complete bundle before continuation. Saved reconstruction checks ordered
question bindings and observation uniqueness before exposing the ordinary message.
Version-1 answers and ordinary user-role text retain unverified origin. An answer
does not accept a knowledge proposal or grant action permission; those consumers
still require their own semantic admission.

## Serialize protected consent before publication

`Ipse.Extension.Consent` is an internal host ledger, separate from conversation
history and extension-owned State. It is not exposed as an SDK operation or wired
to CLI approval. Its caller must first establish operator origin, reviewed
artifact identity, semantic scope, mode ceilings and a durable Session intent.
Existing extension writes still use their ordinary separate approval gate.

The caller supplies an admitted project digest and an absolute control root under
an existing owner-only operator directory. The ledger checks canonical directory
paths, ownership, regular single-link files and protection before taking the
retained native lock. Policies bind exact artifact/source hashes, operation names,
settings, expiry, headless selection and finite period limits. Policy replacement
and revocation use an epoch CAS; neither discards earlier liabilities.

`Ipse.Runner.Transaction` makes one native process own both the retained locks and
the actual protected writes. It stages bytes, syncs files, selects the new root
with a same-directory rename, then syncs the directory before acknowledging.
`IPSE_RUNNER_PATH` cannot replace its child or stdio supervisor: both use the
bundled helper bound to the build digest. The host rechecks and releases before
returning read data. A lost helper, upstream caller or scope invalidates further
publication and leaves any interrupted effect unknown. No automatic retry can
infer whether a root switch reached disk.

Acquire locks in the order ProjectIdentity → Consent → Collection; a nested
acquire shares the same native process. Domain entry guards reject reverse order
before spawning a file-effect worker. Capabilities belong to their supported host
API caller and lock-stack position. They are trusted-core BEAM terms: never pass
their references or Port to untrusted same-VM code. They do not authenticate an
adversarial raw BEAM message sender or fence arbitrary Elixir file IO. Follow the
[native contract](../../native/README.md#publish-protected-state-through-its-lock-owner)
and [transaction tests](../../test/ipse/runner/transaction_test.exs) before adding
a protected writer. Sync promises follow the selected filesystem's contract;
they do not establish remote cancellation or physical-media failure immunity.

Trace `reserve` → `admit` → `settle` in the
[consent tests](../../test/ipse/extension/consent_test.exs). Each reservation binds
an operation ID, request/policy/source hashes, source generation, monotonic
sequence and complete resource vector. Duplicate IDs return inspection data,
never a new admission. Pending/unknown work retains liability across period
boundaries. Cancellation releases only known-unstarted work. Reconciliation is
an explicit trusted-host action, not a timer or automatic recovery retry.

For storage, `publish/5` rechecks the epoch while holding control before the
storage lock. It durably marks `publishing` before the short host callback runs.
The callback must revalidate source/suppression and perform bounded storage IO;
it must never wait for inference, invoke extension code or take locks in reverse
order. A lost callback or failed receipt remains unknown and cannot enter that
callback again. Settlement retains its bounded receipt before Session records
the result. The storage owner still needs its own durable operation binding to
resolve an interrupted publication.

A measured overrun is saved as `overrun`, retaining actual usage and blocking
new reservations plus admission/publication of already-reserved work. Inspection,
revocation and unrelated known-unstarted cancellation remain usable. Explicit
reconciliation cannot reduce observed amounts; its terminal record retains actual
period charges. Malformed measurements never become a settled success.

The version-2 ledger keeps the 64 most recent terminal receipts in full. Older
terminal rows retain their operation ID, sequence, epoch, request digest, original
accounting timestamp, actual resource vector, terminal status and receipt digest.
Duplicate inspection marks `receipt_compacted: true`; it cannot reconstruct the
old receipt body or authorize another admission. Unknown work and unreconciled
overruns always retain their complete rows. Period accounting includes compact
rows using their original timestamps even after policy changes.

The format allows 128 unresolved operations and 32,768 lifetime IDs. The reader
accepts at most 8 MiB; new writes have a smaller byte ceiling with reserved space
for recent receipts, pending settlement and policy maintenance. The ID ceiling
can therefore be reached later than the byte ceiling. No ID is silently evicted
or reset. Closed version-1 ledgers remain readable and upgrade only on a successful
mutation. Inspection does not rewrite a file.

Native staging reserves an 18-MiB allocated-file envelope for control state,
including old and pending roots, before accepting payload bytes. Write admission
requires a supported native filesystem profile; an unsupported profile refuses
explicitly. Read-only inspection remains possible. This is managed allocated-file
accounting, not a bound on volume-wide filesystem journal or allocator overhead.
See [the selected profile](../../native/README.md#publish-protected-state-through-its-lock-owner)
for its platform and kernel limits. The [compaction tests](../../test/ipse/extension/consent_compaction_test.exs)
separate seeded large-format fixtures from actual repeated writes.

Exhaustion refuses before dispatch rather than reclaiming liabilities or replay
protection. This internal substrate is separate from sustainable notes storage,
Git sharing and the saved-consent user workflow. The
[plan](../plan.md#p31-usable-knowledge-and-prompt-assistance) owns those delivery
gates. Exercise separate-VM contention, revocation and VM loss before integrating
a consumer:

```sh
mix test test/ipse/extension/consent_test.exs test/ipse/extension/consent_compaction_test.exs test/ipse/runner/transaction_test.exs
```

## Understand sealing and recovery bounds

| Resource | Host ceiling |
| --- | --- |
| Journal bytes | 128 MiB |
| Events | 100,000 |
| Encoded JSON record, excluding newline | 16 MiB |
| Reserved terminal receipt | 512 bytes and one event |

Operator-only `journal` configuration can lower ceilings. Children inherit that
policy across profile routing. These are per-file admission/work bounds, not an
aggregate disk, memory, retention, or billing quota.

Normal admission retains space for both the proposed record and a terminal
`journal_limit_reached` receipt. Without an outstanding group reservation,
exhaustion makes the writer sync that receipt once, refuse the proposal, and stop
before further dispatch. The receipt binds limits,
reason, prior offset, and prior event count without rejected content. Nothing may
follow it. Confirmed exhaustion is `journal_limit_reached`; unconfirmed quota IO
still has the ordinary unknown-write behavior.

For a group of related records, the owner can call `Writer.reserve/2` with
`%{bytes: jsonl_bytes, events: count}` before writing the first record. Include
each newline in the byte total. A successful call returns a writer-local token;
`append_reserved/3` charges the actual encoded bytes and one event against it.
Every record still has to fit the record ceiling. Ordinary appends can use only
unreserved capacity. If one would consume the reservation, it refuses with
`journal_reservation_unavailable` and leaves the file writable and unchanged.
Reservation admission also retains the terminal receipt's byte and event space.

Call `Writer.release/2` before recording cancellation or another ordinary control
outcome. Release returns unused capacity; it does not erase written records.
Tokens disappear when the writer closes and cannot authorize writes after a
restart. Reservation is capacity admission, not an atomic multi-record commit or
a guarantee that later IO succeeds. A partial group retains its written prefix
and the caller's existing unknown-outcome rules.

Trace an SDK-2 saved result through this mechanism. Session reserves the begin,
every fixed-size fragment, the seal, and the final invocation receipt before
writing `extension_output_begin`. `ResultSource.reservation_size/2` computes
their JSONL capacity from the declared byte count and the original final-receipt
template. Written prefixes remain charged even when the invocation is abandoned.
There is no rollback or automatic attempt to finish a partial producer.

Only the final version-2 `extension_invocation_result` publishes the saved
descriptor. A complete byte stream or a seal alone remains unreadable. Source
records use plain reserved appends and are not offered as private content to
observers or feeds. The bounded final descriptor can use
`append_reserved_observed/3`; Session releases unused capacity before offering
that receipt to consumers, whose own intents require ordinary capacity.

During resume, `ResultSource.restore/1` checks identity, fragment order and hashes,
complete schema validation at a seal, and the exact final descriptor. Session
does this before tail repair. A legal unsealed prefix stays diagnostic even if
its complete bytes contain invalid JSON. A malformed record or invalid sealed
source refuses recovery unchanged. Follow [invocations](extension-invocations.md)
for a worked publication and read example.

Reader, restore, repair, and writer initialization decode incrementally with size,
line, and event bounds. They retain decoded recovery history within those bounds;
streamed reading is not a claim of constant RAM. Session listing and CLI resume
first read only a bounded header, which does not certify the rest of the journal.
Over-ceiling legacy files and overlong torn tails refuse unchanged. Source paging
has a separate 1 MiB record ceiling and cannot export every valid large record.

A valid sealed journal remains available for read-only diagnosis and reviewed
handoff. It cannot reopen for work under a larger policy. Ask unanswered questions
again in the fresh session and inspect unknown effects first. Compaction reduces
model context, not retained evidence. Automatic rotation, deletion, redaction, and
secure erasure are not implemented.

```sh
mix test test/ipse/journal_test.exs test/ipse/journal/writer_test.exs test/ipse/journal/reservations_test.exs
```

Use writer tests for ownership/IO races and limits tests for sealing and strict
recovery. A meaningful storage change must preserve intent-before-effect,
confirmation-before-success, lock retention after owner loss, and unknown outcomes
without replay. See [budget storage](accounting.md) for its stronger live-prefix check.

Follow the reservation test with a 1,024-byte journal policy. It reserves every
remaining nonterminal byte, rejects an ordinary append without changing the
file, writes the reserved record, then releases the token. The next ordinary
append seals the journal with a valid quota receipt. Repeat the cancellation
case: the orphan record stays on disk while the released capacity admits the
cancellation record. These controls distinguish capacity protection from rollback.
