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
returns those facts without starting a Session or reading source pages. Event-job
reconstruction also validates any managed output-release chain against its exact
parent, actions and raw result. Confirmed cleanup with withdrawn output preserves
the failed job even if its earlier actions succeeded; missing or unknown cleanup
cannot authenticate that known outcome. Reconstruction does not repeat the
callback, recheck live source eligibility or settle an uncertain effect.
For new reference-layout sessions it also validates the admitted header/catalog,
reference epochs, positions, generations and turn bindings. Completed native tool
results retain recorded order. References cannot close an unfinished group by
inventing a result; unknown outcomes are materialized at a genuine next-user
boundary or interrupted-history reconstruction. Legacy reconstruction retains its
original ordering and layout. Follow the complete [context projection](workspace-context.md#admit-a-header-and-append-current-references)
before changing either path.

A fresh active semantic admission uses descriptor version 2. It retains the
original reviewed policy, whose canonical digest must equal the Session pin's
policy hash. The descriptor allows 64 KiB and 16 lexical levels; its policy and
settings retain their own narrower bounds. Pure replay derives a protected outer
invocation's read/publish class from that saved policy and its exact descriptor.
It cannot accept a worker-supplied class or promote historical approval. A
version-1 active admission remains reconstructible but cannot enter a new
protected outer invocation. Current protected permission is checked separately
before every live effect. See the [collection SDK](collection-sdk.md) for the
receipt versions and the read-only outer's categorical mutation denial.

The owner controls recovery order: acquire the session lock, reload the locked
journal, validate the saved prefix and its checked sources and budget evidence,
and verify that a pending question can receive operator input and has valid
event/subscription source checkpoints. These checks
precede recording a new release owner or repairing a permitted torn tail, so
their refusals leave the journal unchanged. Then reload and reconstruct pure
facts and recheck question source pages. Other later checks do not have the same
pre-mutation guarantee. Workspace and skill discovery and writer startup remain
owner-held IO. A successful pure reconstruction alone does not certify
those external sources or authorize a pending effect.
For a fresh Session, the release-owner marker precedes budget-ledger creation;
there is no existing recovery evidence to validate first.

New Session headers also record their original canonical directory and file
identity through `Ipse.Journal.SourceOrigin`. Creation derives that binding from
the newly opened descriptor before writing the header. Locked resume compares
it with the actual file before tail repair; Writer checks its own descriptor
before accepting appends. Pure reconstruction validates only the recorded shape.
A copied or replaced journal can remain readable for diagnosis without becoming
the original live source. A directory alias that resolves to the same canonical
location does not create a different source.

For a fresh Linux Session, the host acquires the native Session lock before
creating the header. Its lock owner exclusively creates a pending inode and
returns its identity; `Journal` checks that identity while constructing the
bounded header. The same native owner writes and syncs the record, publishes
it without replacing another journal, and syncs the directory. If startup
loses its owner before publication, the pending file is not a saved Session and
is never automatically replayed. A lost publication acknowledgment is unknown:
inspect the original state and resume an actually published journal explicitly
after the lock is free. Non-Linux fresh startup retains its earlier ordering;
the Linux tests do not establish the same guarantee there.

The fresh Linux header also records the retained lock's device and inode before
any journal work. For this layout, Writer retains JSON encoding, record and
quota admission, while the native process holding that same flock checks the
original journal identity and expected size, appends the bounded opaque line
and syncs it before replying. Torn-tail repair uses a read-only tracked peer to
derive the repair and the same native lock owner to perform and sync it. A lost
reply remains unknown and is not automatically replayed. Inactive and legacy
write/repair entry points refuse this layout; ordinary older journals retain
their legacy behavior.

Fresh Linux Sessions and framed resume use the share-capable native lock modes
`header_share_v2` and `resume_share_v2`. The original flock remains held throughout;
there is no close/reacquire upgrade. A qualified terminal operation freezes
Session state and drains its actual Writer before exporting that retained lock.
The Writer snapshot binds the active source proofs and inactive original lock
identities to the exact job and owner generation. Confirmed recipient settlement
is required before thaw. Each share timer carries that generation. Cancellation
can leave an already queued timeout, so Session discards a well-formed timeout
for another generation without changing the live barrier or cancelling its timer.
The current generation's deadline and unexpected messages still quarantine the
operation. Exercise both consecutive shares and the stalled-Writer timeout with
`mix test test/ipse/session/share_operation_barrier_test.exs`.
The
[managed approval adapter](session-sources.md#reconstruct-without-giving-old-tokens-authority)
adds the pending-call, full-payload and terminal-purpose checks; lock sharing
alone supplies no display or approval authority.

Standalone knowledge management uses the same native header and append owner.
It chooses the ID and acquires the lock before creating its journal, then tracks
Writer in `header_v1` mode. Its `native_journal_layout` marker selects native-only
mutation without claiming the Session signed-release protocol. Both this marker
and the Session release marker make legacy creation, inactive append, legacy
Writer and unfenced repair refuse. Read-only loading remains available. The
locked constructor performs no directory creation or chmod: its caller supplies
an admitted private directory and the actual retained native owner validates it.
Management refuses an existing public directory or symlink unchanged. Header or
Writer startup uncertainty and unconfirmed close/release cannot become a settled
operation result. A header alone is not a completed management action.

The host uses one monotonic admission and response deadline across the header
exchange. Synchronous host preparation and native filesystem calls can block
past that deadline; it is not a wall-clock bound on the whole operation. A
timeout is unconfirmed: a native call already in progress can finish later
while its helper still holds the lock. Close stops the Writer, obtains the
framed lock-release result, and reports unconfirmed cleanup if either is not
confirmed. Because the Writer cannot append after release, the lifecycle close
record still says `cleanup_confirmed: false`. Fresh Linux Sessions write a
separate owner-bound release intent while locked; after the exact framed release
and cleanup are confirmed, the owner signs it and a pinned native helper writes,
syncs and publishes an exclusive private sidecar. A missing publication reply
leaves the close outcome unconfirmed, even when the file later exists. Diagnosis
can report `signed_release_claim` after acquiring the Session lock and checking
the latest owner, source, lock, helper and signature. This establishes the trusted
signer's claim; it does not change an earlier lifecycle record or prove that a
lost publication acknowledgment was received. A later owner marker invalidates
current selection of the old claim. On Linux, an opted-in journal with a recorded
header lock identity or prior release intent can resume with a framed lock opened
without creating a lock file; its retained inode must match every applicable
recorded identity before startup proceeds. Its close records a new claim for the
resumed owner. Older opted-in journals missing both identities refuse active
resume; unmarked older journals retain the legacy lock protocol. A stopped lifecycle
recorder, missing sidecar or unverifiable identity leaves the claim unknown.

SourceIndex incorporates the recorded origin digest into each new source version
without exposing the private location in worker pages or proofs. The same
committed occurrence and original file reproduce its version; another origin
cannot revalidate that proof. Legacy headers keep their historical version rule
and acquire no binding during resume. They remain conversation history, but the
live collection-source callback refuses their protected publication authority.
The protected [managed reader](collection-sdk.md) can now resolve inactive
original Session sources in the consuming Session's selected state directory,
under their retained ownership locks. Locked reconstruction alone grants no
current-use authority for later inference. The trust boundary remains cooperative
storage: an arbitrary same-user writer can rewrite files and recorded facts coherently.
A live source query rechecks the retained file's identity, expected length,
canonical directory and private parent before returning cached data. Appends
repeat these checks after sync, withholding success if the origin changed.

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
resume preserves the existing journal prefix and workspace; release-receipt
layouts append a new owner marker. A saved question still
requires a fresh explicit answer. `Questions.tool_result/3` supplies the same
message shape to live question handling and saved-checkpoint validation.

## Follow an active append

Session validates configuration and recovery sources, repairs only an allowed
final torn record, and opens its writer under the session lock. Writer startup
validates the complete journal once. Successful initialization links to the owner;
Session monitors writer loss and stops dependent work if it disappears. There is
no automatic writer restart or append retry.

Only the owner may append, reserve capacity, release it, or close. For each record
Writer encodes the JSON, checks descriptor/path identity and expected length,
and admits the complete line against the journal limits. For native-only layouts,
the tracked Writer sends bounded opaque chunks to the actual lock helper, which
rechecks the identities and expected size, appends and fsyncs before replying.
For unmarked legacy journals, a private filesystem completion owner instead opens
a separate append descriptor, checks identity/protection/length again, writes,
fsyncs, closes and replies. The caller waits for confirmation before dispatching
effects or exposing a lifecycle source. A legacy completion process cannot
substitute for the native owner of a protected layout.

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

`Resources.controlled_owned_effect/2` is a separate internal primitive for a
reviewed native-controller or owned-transport operation whose complete effects
and cleanup are fenced by its child scope. It may kill that peer at the deadline;
never use it for arbitrary file-server IO that can continue after the peer dies.
A tracked request task starts the child, whose nonce-bound scope inherits the
Session lock guard and owns its registered controllers. An inactive scope
refuses before child startup. Normal completion waits for peer and guard exit
and the child cleanup receipt. After startup, timeout or an unconfirmed receipt
yields an unknown outcome; unconfirmed cleanup must stop the caller rather than
permit dependent work. Owner monitors stop the peer but are asynchronous; the
consumer still needs its own current-authority check at the effect boundary.
An outer `{:ok, value}` confirms the scoped
return and cleanup, not the success of an effect represented by `value`; retain
its own outcome classification. Ordinary nested `file_effect`
calls inside that peer remain inline; starting another controlled child refuses.
This primitive is not currently wired into inference and supplies no policy or
current-source authority on its own. Callbacks and private receipt terms remain
inside the trusted host boundary.

Read the blocked-write fixture in `test/ipse/journal/writer_test.exs`. Its FIFO delays
real IO while Session dies. A replacement session must remain locked until the
reader drains and completion returns. A monitor `DOWN` for the original caller
cannot establish that fact. A stuck completion owner can retain the lock
indefinitely; deleting the lock file would defeat ownership rather than repair it.
Unexpected loss of the helper/guardian stops Session without another append.

Stateless `Journal.append*` APIs are for unmarked inactive journals under the proper lock.
They validate history and perform synchronous completion-owned writes; repeated
inactive appends therefore have linear validation cost. Embedded callers remain
responsible for their own lock lifetime. They refuse native-only layouts, even
when the active owner has closed. Follow
`test/ipse/journal/management_owner_test.exs` for native reserved appends,
helper-loss exclusion and inactive-entry refusal; its syscall-hook case is
separate from ordinary helper execution. The standalone caller control in
`test/ipse/cli/management_journal_test.exs` uses an absent target to exercise
startup and cleanup, not successful signed-note expiry.

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
that message remains inspectable history, but cannot authorize a source read or
capture until its matching effective user message is committed. A later receipt
can replace that incomplete link, without replay. Ordinary `prompt/2` records unattended input. Old journals
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

An explicit `/remember` review instead records one `operator_assertion` event
with the exact statement, category, project/artifact/policy scope and native
confirmation. Saved reconstruction validates that scope against the original
semantic admission and rejects reused observations. SourceIndex binds the
reviewed category into the occurrence kind. The source receipt is synced before
the existing protected command starts, so its presence alone proves neither
publication nor a grant to perform other effects. A resumed owner restores the
receipt and unknown effects without repeating capture. Plain messages and
question answers cannot acquire this origin by quoting the reviewed text.

## Serialize protected consent before publication

`Ipse.Extension.Consent` is an internal host ledger, separate from conversation
history and extension-owned State. The standalone
[knowledge permission review](../operator/knowledge-permissions.md) saves a
protected selection through this ledger. Its host caller establishes native
operator origin, the exact reviewed artifact, semantic scope and mode ceilings.
It is not an SDK operation. A later Session effect also needs its own durable
intent and current protected admission; ordinary effects retain their separate
approval gate.

The caller supplies an admitted project digest and an absolute control root under
an existing owner-only operator directory. The ledger checks canonical directory
paths, ownership, regular single-link files and protection before taking the
retained native lock. Policies bind exact artifact/source hashes, operation names,
settings, expiry, headless selection and finite period limits. Policy replacement
and revocation use an epoch CAS; neither discards earlier liabilities.

For trusted local management preparation, use
`Consent.with_existing_management_snapshot/5` to retain the existing native lock
around an exact positive epoch and management fingerprint. Unlike an active
capture-policy read, this callback can inspect an expired policy or a revoked
nil policy. It creates no ledger, reclaims no pending files and authorizes no
display, capture or publication. The caller must separately retain Identity,
Collection and original journal ownership before protected native review.
A typed unknown callback result stays unknown; only a successful callback can
reach the success-only final identity checks. Native release is attempted in
either case. Follow `consent_management_read_test.exs` for contention, absent and
stale snapshots, revoked inspection and actual native-owner loss.

A generic collection mutation also needs a constrained publication mapping.
`Ipse.Extension.CollectionPolicy` checks every key prefix and value against its
reviewed closed JSON schema. A declared evidence field must contain a nonempty
subset of the host-authenticated stable source receipts, and every source in the
batch must have an allowed origin. This prevents a pending-proposal mapping from
writing a durable-note key or borrowing one native source to upgrade unrelated
input. Every replacement and deletion advances the destructive import floor;
deletion also requires its own reviewed flag and nonempty source proof. This
pure check neither authenticates proof-shaped JSON nor supplies consent: the
owning adapter must resolve proofs and recheck current permission, source and
suppression state inside the publication boundary. Its
[behavior tests](../../test/ipse/extension/collection_policy_test.exs) exercise
mixed origins, substituted evidence, open schemas and deletion refusal.

`Ipse.Runner.Transaction` makes one native process own both the retained locks and
the actual protected data reads and writes. A bounded `read/4` opens, validates,
reads and closes data files in that owner, returning chunks with a stable
size/device/inode identity. Do not substitute ordinary `File.open/3` under a
logical lease: after owner loss an independent IO process could retain an
unlinked file while a new owner measures its apparent disk use. Hash and schema
validation remain in Elixir. The native owner stages bytes, syncs files, selects the new root
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

Local source paging must not consume a durable operation identity for every
read. `with_policy/6` checks the pinned epoch, policy digest, expiry and absence
of an unresolved overrun under the control lock. Its short trusted-host callback
receives only the current epoch and policy, performs semantic/mode validation
and bounded local storage reading, and returns `{:ok, value}` or a typed error.
Data returns only after the native lease check and release. Revoked, expired,
changed or quarantined policy cannot enter the callback. Session owns read, step
and context-byte ceilings; period operation limits cover durable mutations and
selected extra effects. This helper grants neither worker access nor authority
to run inference, arbitrary file IO or network calls under the lock. Follow
[the read controls](../../test/ipse/extension/consent_read_test.exs) when integrating
a consumer.

For a managed publication enclosed by Identity, use `publish_deferred/5`. It
rechecks the epoch while holding control before storage, and durably marks
`publishing` before the short host callback runs. The callback revalidates
source/suppression and performs bounded storage IO; it must never wait for
inference, invoke extension code or take locks in reverse order. Its successful
packet is provisional host data: Consent retains the full pending reservation
with null actual/receipt until outer Identity checks and native release succeed.
Only then call `settle/4` with `{:known, packet["actual"], packet["receipt"]}`,
the exact original ticket and the host-checked measurement. Finalization accounts
for admitted work; it grants no new dispatch permission. Session receives a
successful result only after confirmed settlement.

Loss before final measured settlement leaves pending liability, including when
Collection already committed but Identity completion failed. A final settlement
write, acknowledgement or release can instead be uncertain after known actual
usage became durable. Inspect the operation rather than assuming that every such
failure retains the full reservation. Neither outcome permits automatic refund,
callback replay or another publication. The standalone `publish/5` API remains
for callers whose authority is complete at that boundary; it settles within its
own transaction and cannot substitute for deferred outer-Identity completion.
The storage owner still needs its durable operation binding to resolve an
interrupted publication. Follow [managed accounting](accounting.md#reserve-before-dispatch-and-settle-before-admission)
for reservation and measured-settlement checks.

When a trusted adapter must add host-owned validity metadata, select an explicit
internal boundary rather than rewriting a worker request under the ordinary SDK
operation:

| Host API | Normalization envelope | Metadata changes beyond the original |
| --- | --- | --- |
| `Collection.execute_managed/6` | Version 2, used by metadata-version-2 SDK requests | 1..16 nondeleted `host.validity.` records |
| `Collection.execute_managed_v3/6` | Version 3, host-private adapter for explicit metadata-version-3 requests | At most five changes, four nonnull values and one deletion |

Both check original generation/revisions,
writer fencing and duplicate identity before entering the host normalizer under
one Collection lock. The normalizer receives a version-2 witness: its existing
`root` summary and manifest/request/recipe/operation bindings remain unchanged,
while `root_state`, `root_bytes` and `root_sha256` distinguish native-confirmed
absence from the actual bounded bytes of a materialized root. Absent bytes and
hashes are nil; a materialized empty collection retains its real hashes. Raw
root bytes stay inside this trusted callback, outside SDK results and receipts.

The process-bound read closure shares 32 observation units across two forms:

| Callback call | Returned information | Units |
| --- | --- | ---: |
| `read.(key)` | One validated record value or nil | One, including a missing key |
| `read.(%{"op" => "neighbors", "request" => descriptor})` | Four positional metadata references and the current root/manifest witness | Four, including nil positions |

The neighbor descriptor and reference semantics are the same as
[read-view selection](#read-several-collection-pages-under-one-validated-index).
The ordered directory is built from the already validated current index under
the retained native lock; it opens no read view and scans no object values.
Selected values require separate charged binary reads. Neighbor selection
supports wire roots 4 and 5, without adopting legacy roots 2 or 3; binary reads
retain their existing legacy support. A neighbor reply's `witness.root` is the
actual decoded wire pointer, whereas the callback's `root` remains the version-3
summary. Neither establishes managed eligibility or authenticates a page body.

Valid requests debit before lookup or native IO. Malformed closed requests
refuse without debit, and foreign processes cannot spend the owner's allowance.
Seven neighbor calls plus four binary reads consume exactly 32 units. An
authorized over-budget attempt latches refusal: even if the callback ignores it,
the entire publication refuses. This tightens the former per-read refusal
contract. The closure expires on callback return and cannot be reused by a later
invocation in the same worker. Final native checking and release still withhold
the result after owner or scope loss. The callback can
retain the original changes exactly and add only its selected envelope's metadata.
The original request must explicitly select `advance_floor: true`; the
host never changes that choice or the original generation. Advancing the import
floor prevents an older complete backup from removing a newly admitted permanent
source clock. A refused original request cannot enter the callback.
The owning adapter must authenticate source proofs, derive semantic validity and
reserve worst-case metadata charges before calling; this seam supplies none of
those permissions and is not exposed to worker code.

The resulting receipt keeps `request_sha256` bound to the normalized commit and
adds `managed_binding_sha256`, a digest of the versioned original-request,
reviewed-recipe and normalization-receipt hashes. The returned result supplies
those fields and the bounded normalization object. Inspect/export/import retain
the durable binding even after a response is lost. A managed binding selects
explicit wire-root version 5; ordinary collections continue to emit version 4.
Version 5 retains the existing record/data/block/native quota bounds, and older
readers refuse it. The in-memory storage summary remains version 3. The ordinary
SDK call and its receipt contract do not gain this operation implicitly.

`Collection.Normalizer.normalize/3` supplies the schema-2 implementation used by
the metadata-version-2 callback. It checks the selected recipe, constraints and
authenticated host proofs, then adds two packed host pages alongside one fresh
public record. The source anchor keeps separate first-admission clocks for notes
and pending proposals.
Later publications can shorten a baseline deadline but cannot renew it, including
after the public record is removed. Only a genuinely new authenticated occurrence
starts another source clock. The current host clock determines admission; worker
timestamps grant no validity. Pending proposals always have finite expiry and
remain ineligible as current premises.

Anchor, live metadata and normalization receipt format 2 record this guarantee.
Experimental format-1 domain pages refuse adoption rather than gaining authority
through a storage-format upgrade. Packed pages have closed shapes, bounded rows,
contiguous page numbers and no duplicate identities; overflow refuses without
eviction. Live pointers share Collection's record-key grammar. Ordinary and
pending rows require finite deadlines. These checks establish structurally
consistent publication metadata. An unsigned format-2 page or imported receipt
is not an authenticated source attestation. Do not treat an imported clock or an
unchanged sibling row as trusted merely because a later operation rewrites its
page. Current-read filtering, authenticated inherited metadata, typed overrides
and their operator workflows still need their owning adapters. For the explicit
authenticated schema-3 interpreter, follow
[automatic publication](knowledge-storage.md#publish-one-fresh-record-with-authenticated-metadata).

### Exercise the explicit Core v3 envelope

Core v3 permits anchor keys `host.validity.a.` plus 64 lowercase hex digits,
and live keys `host.validity.l.` plus kind `00`, `01` or `02` and 64 lowercase
hex digits. A delete needs its exact positive retained revision. Format cannot
be rewritten or deleted. Native-confirmed absence requires exactly three new
nonnull revision-zero records: format, anchor zero fence and live zero fence.
A materialized root must already contain format; missing format refuses rather
than adopting a legacy store. Every metadata CAS runs under the same native owner
as the unchanged public change. The normalization object must fit 2048
bytes and carry integer `version: 3`.

Run this isolated Core exercise in `iex -S mix` after building on a supported
allocation profile. Its callback deliberately supplies synthetic metadata; it
tests the storage envelope and mints no authenticated knowledge authority:

```elixir
alias Ipse.Extension.Collection
scratch = Path.join(System.tmp_dir!(), "ipse-managed-v3-exercise-" <> Ipse.Usage.id())
File.mkdir!(scratch)
File.chmod!(scratch, 0o700)
project = Ipse.JSON.sha256("synthetic Core v3 exercise")
change = fn key, value -> %{"key" => key, "expected_revision" => 0, "value" => value} end
original = %{"op" => "commit", "expected_generation" => 0, "advance_floor" => true,
  "changes" => [change.("note.example", %{"text" => "exact original"})]}
extras = Enum.map(["host.validity.format", "host.validity.a." <> String.duplicate("0", 64),
  "host.validity.l." <> String.duplicate("0", 66)], &change.(&1, %{"synthetic" => true}))
id = Ipse.Usage.id()
recipe = Ipse.JSON.sha256("synthetic recipe")
try do
  {:ok, result} = Collection.execute_managed_v3(scratch <> "/collections", project,
    original, id, recipe, fn witness, _read ->
      "absent" = witness["root_state"]
      {:ok, Map.update!(original, "changes", &(&1 ++ extras)), %{"version" => 3}}
    end)
  1 = result["receipt"]["generation"]
  true = result["receipt"]["managed_binding_sha256"] == Ipse.JSON.digest([result["binding"]])
  {:existing, _} = Collection.execute_managed_v3(scratch <> "/collections", project,
    original, id, recipe, fn _, _ -> raise "duplicate callback must not run" end)
after
  File.rm_rf!(scratch)
end
```

Core authenticates neither the callback's source assertions nor its metadata
MACs. The adapter supplies those checks. Use
`mix test test/ipse/extension/collection_managed_v3_test.exs` to exercise four
writes plus one retained-revision deletion, unchanged roots on refusal and the
32-unit exhausted latch. The actual authenticated path is exercised separately
by `collection_normalizer_v3_integration_test.exs`, described in the knowledge
storage guide. Neither test selects a new SDK operation.

Exercise successful paired publication, duplicate/refused normalization, expired
read closures, actual native-owner loss and complete migration with
`mix test test/ipse/extension/collection_managed_test.exs` and the collection
block/migration suites. Run
`mix test test/ipse/extension/collection_normalizer_test.exs` for source-clock,
packed-page and old-backup controls. An internal host callback is trusted core code: do not
load extension callbacks, run inference or hand its read closure to a worker.

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
uses an inventory under the same native owner's logical and writer leases.
That inventory syncs retained pending staging files before re-reading their
allocation, so an interrupted stage is not admitted on an unsettled block count.
A sync error refuses the inventory and preserves the file; it never justifies
replaying the interrupted operation. Standalone allocation inspection remains a
read-only observation without this settling step. Write admission
requires a supported native filesystem profile; an unsupported profile refuses
explicitly. Read-only inspection remains possible. This is managed allocated-file
accounting, not a bound on volume-wide filesystem journal or allocator overhead.
See [the selected profile](../../native/README.md#publish-protected-state-through-its-lock-owner)
for its platform and kernel limits. The [compaction tests](../../test/ipse/extension/consent_compaction_test.exs)
separate seeded large-format fixtures from actual repeated writes.

The finite selector resolves the filesystem from the retained directory FD,
then checks its kernel-specific page/block and mount/global huge-page features.
Exact `7.2.11-arch1-1` x86_64 is admitted only for the qualified tmpfs combination;
its Btrfs path refuses before protected publication. The older profile keeps
its separate reviewed scope. Rebuild the helper and its compile-pinned Runner
together after changing the selector; an ambient helper path cannot replace the
protected binary. The [operator storage procedure](../operator/arch-linux.md#check-protected-storage-admission)
explains location and volatility implications. A process-restart receipt cannot
establish reboot or power-loss durability.

Exhaustion refuses before dispatch rather than reclaiming liabilities or replay
protection. This internal substrate is separate from sustainable notes storage,
Git sharing and the saved-consent user workflow. The
[plan](../plan.md#p31-usable-knowledge-and-prompt-assistance) owns those delivery
gates. Exercise separate-VM contention, revocation and VM loss before integrating
a consumer:

```sh
mix test test/ipse/extension/consent_test.exs test/ipse/extension/consent_compaction_test.exs test/ipse/runner/transaction_test.exs
```

## Keep project-domain attestations private

Storage hashes establish byte identity; they do not establish that an original
source was authenticated by the host. `ProjectIdentity` has an internal scoped
domain-authentication boundary used by the explicit metadata-v3 adapter. Its
persistent project master lives in the private top-level `domain_keys` map of
index version 2, outside the public project and binding maps. Existing version-1 indexes remain
readable and keyless. Adding a key/catalog entry changes the index revision but
preserves public bindings and their digest. Ordinary identity mutations retain
the private map. Preview, existing-binding inspection and verifier reads never
initialize or upgrade it.

The trust root belongs to admitted operator Identity, not a Collection backup.
Each project has at most one independent 32-byte master; each namespace/format
uses a derived HMAC-SHA256 key. Neither provider credentials nor volatile source
window keys are reused. No master, derived key or private index belongs in a
Session header, configuration view, SDK result, snapshot, export or diagnostic.
Opaque capabilities are callback-local, exact-owner Core terms, not JSON grants.

The internal APIs have distinct jobs:

| API | Host responsibility |
| --- | --- |
| `with_existing_domain_auth/5` | Revalidate an existing exact binding and active catalog, then use a verifier without creating or repairing state. |
| `with_domain_publication/6` | Supply an exact current-policy authorizer and journaled operation; use its signer only in the trusted authenticated publication adapter. Initialization must be explicitly selected. |
| `reconcile_domain/6` | Explicitly inspect a prepared entry using the exact expected key/fence/operation and a current-policy/root-proof callback. Never repeat the original publication. |

Select initialization and authorize it under the same retained Identity owner.
The two-argument authorizer receives `(binding, fresh?)` from that transaction's
domain selection. Selection constructs only an in-memory candidate: denial
writes no prepared entry. The new-v3 adapter checks current sources and policy,
then requires actual native absence only when `fresh?` is true. A busy or failed
separate verifier cannot establish first use. Existing one-argument authorizers
retain their original order: authorize first, then select the domain. Preserve
that order for callers that consume a one-use review permit.

After authorization releases its nested Consent lock, first use writes the
prepared namespace entry under Identity. The publication callback then receives
the volatile first-use signer. Its adapter must distinguish native absence from
a materialized empty root, recheck absence under the Collection owner, and
authenticate the first completion witness. Once child locks release, Identity
writes the active entry and checks/releases before returning success. Later
publications select the active entry without rewriting the Identity index.
Identity validates callback bindings; its trusted adapter must establish the
actual Collection witness. The
[NormalizerV3 integration exercise](knowledge-storage.md#exercise-actual-collection-and-domain-authentication)
demonstrates that check with actual Collection reads and publications. The
SDK's metadata-version-2 path retains its unsigned interpreter; an explicit
`metadata_version: 3` request selects the authenticated adapter.

An interrupted first use remains prepared. A matching durable root may be checked
by an explicit reconciliation callback; absence is not permission to reset the
entry or replay the effect. An active namespace whose store disappears must not
be treated as fresh empty history. The owning adapter must perform that root
check; the crypto helper does not inspect Collection. A new namespace is distinct
from a project that already has a master for another namespace.

The callback crypto lease lasts five seconds without renewal and permits at most
16 seals, 128 verifications and 1 MiB of page-crypto input. Each body is at most
6,144 bytes; each call charges its 64-byte canonical context digest plus body.
The call-count/body bounds are tighter than the aggregate limit. A late callback
return becomes unknown; this is not hard preemption of arbitrary Core IO. Losing
the original owner, scope or native transaction also withholds the outer result.
Nested protected operations remain inline and follow Identity → Consent →
Collection. Check the Identity capability only when it is the stack top; final
native release is mandatory. Never emit recall or start network IO inside these
callbacks.

The tag primitive binds the private project/namespace/format/key/fence scope,
closed page context and exact raw body bytes. Context version 1 selects metadata
schema 3 and binds its reserved page key, kind, operation ID and positive record
revision. It returns a 32-byte tag, not a sealed storage envelope. The
normalizer must authenticate every inherited page before update/reseal and check
the final envelope's own size and allocation. MAC verification establishes past
host authentication; it does not establish present permission, source truth,
expiry, suppression or safe import adoption. Unsigned format-2 pages remain
unavailable to the authenticated current-read path unless independently recovered from
actual validated original history. Coherent raw same-user rollback is outside
the cooperative storage boundary; supported import must retain its separate
floor and adoption checks.

All private keys/catalogs share the existing index limits: 256 masters, 256 total
namespace entries, eight per project, 192 KiB encoded private map and 1 MiB total
index. Native Identity staging retains its 3-MiB envelope inside the existing
4-MiB Identity/service control reserve. Capacity refuses without evicting a key
or widening a budget. Key rotation, missing-key regeneration and cross-host
identity-key migration have no automatic path.

After building native and Mix on a supported allocation profile, run this isolated
keyless-read exercise in `iex -S mix`. It creates no Collection and mints no tag:

```elixir
alias Ipse.Extension.ProjectIdentity
scratch = Path.join(System.tmp_dir!(), "ipse-domain-exercise-" <> Ipse.Usage.id())
home = Path.join(scratch, "home")
cwd = Path.join(scratch, "work")
for path <- [scratch, home, cwd] do
  File.mkdir!(path)
  File.chmod!(path, 0o700)
end
try do
  {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
  scope = %{namespace: Ipse.JSON.sha256("synthetic-namespace"), format: "managed-metadata-v3"}
  {:error, :project_domain_unavailable} =
    ProjectIdentity.with_existing_domain_auth(home, cwd, binding, scope, fn _, _ ->
      raise "a keyless read must not enter its callback"
    end)
  {:ok, ^binding} = ProjectIdentity.existing(home, cwd)
  IO.puts("Keyless inspection preserved the admitted binding.")
after
  File.rm_rf!(scratch)
end
```

Follow the [domain-auth tests](../../test/ipse/extension/project_domain_auth_test.exs)
for prepared/active transitions, explicit reconciliation, native loss after both
index switches, selected-state authorization, owner/scope cancellation and
separate-VM contention. Their root witnesses are deliberately trusted callback
fixtures. Use the separate actual Collection integration exercise for its
storage-root checks; neither fixture
establishes Session-source or end-user management authority.

## Read several collection pages under one validated index

Use a Collection read view when one trusted host task needs several observations
from the same immutable root. `Collection.open_view/2` performs the full protected
validation once, including manifest blocks and the receipt index. Its private
cache keeps exact root bytes, the manifest hash and current record references.
It retains no descriptor or lock between calls and creates no durable operation
identity for a read. Opening can create protected directories and retained locks;
it does not publish a root or receipt.

Choose the operation according to the information needed:

| Internal call | Returned information | Observation units |
| --- | --- | ---: |
| `view_read/2`, `get_many` | At most eight selected records, with validated values or nil entries | Requested key count |
| `view_read/2`, `scan` | At most eight records after an exclusive cursor, with validated values | Requested limit, even on a short/empty page |
| `view_neighbors/2` | Four positional metadata references, with no value reads | Four, even when positions are nil |

Every call reacquires the actual Collection native owner in the established
ProjectIdentity → Consent → Collection order. The native optional `H` read must
confirm the exact cached root: byte-for-byte equality for a materialized root,
or another kernel-confirmed absence for an absent root. Value reads then open
only the selected immutable objects in that owner and validate their lengths,
hashes and closed value shapes. A neighbor lookup reads no object or sidecar
value. Quota, final lease check, release and cache completion must all succeed
before either kind of result returns. Owner/scope loss fences the native owner
even if a paused BEAM file-effect worker survives. Closing a cache invalidates its
handle; it does not certify that other in-flight IO has finished.

A neighbor request has exactly `version: 1`, an ASCII record-key `prefix` ending
in a dot, `fence_bytes` of 32 or 33, and a lowercase hexadecimal `needle` of
64 or 66 characters respectively. The complete prefix-plus-fence key must fit
96 bytes. For a present root, the complete matching-prefix directory must contain
its zero fence, and every matching key must have the exact canonical width.
Malformed names outside the four returned positions also refuse. The lookup
selects the greatest lower fence less than or equal to the needle and returns
`predecessor`, `selected`, `successor` and `second_successor`; nil marks a genuine
directory boundary. References retain their actual key, revision, content hash,
byte length and operation ID. They contain no value and establish no source,
format, range-content or managed-record authority. The eventual caller must
validate its selected page contents, format/adoption rules and semantic policy.

Run the following credential-free source exercise in `iex -S mix`, after building
native and Mix on a supported [allocation profile](../../native/README.md#publish-protected-state-through-its-lock-owner).
It creates synthetic generic records, not authenticated knowledge pages. An
unsupported filesystem refuses explicitly:

```elixir
alias Ipse.Extension.Collection
scratch = Path.join(System.tmp_dir!(), "ipse-view-exercise-" <> Ipse.Usage.id())
File.mkdir!(scratch)
File.chmod!(scratch, 0o700)
root = Path.join(scratch, "collections")
project = Ipse.JSON.sha256("synthetic-view-project")
fence = fn n -> "demo.fence." <> String.pad_leading(String.downcase(Integer.to_string(n, 16)), 64, "0") end
selection = %{"version" => 1, "prefix" => "demo.fence.", "fence_bytes" => 32, "needle" => String.duplicate("0", 63) <> "f"}
try do
  {:ok, initial} = Collection.open_view(root, project)
  try do
    {:ok, empty} = Collection.view_neighbors(initial, selection)
    "uninitialized" = empty["state"]
    %{"version" => 2, "root_state" => "absent", "root" => nil, "root_sha256" => nil, "manifest_sha256" => nil} = empty["witness"]
  after
    :ok = Collection.close_view(initial)
  end
  changes = for n <- [0, 10, 20, 30], do: %{"key" => fence.(n), "expected_revision" => 0, "value" => %{"text" => "page #{n}"}}
  commit = %{"op" => "commit", "expected_generation" => 0, "advance_floor" => false, "changes" => changes}
  {:ok, _} = Collection.execute(root, project, commit, Ipse.Usage.id())
  {:ok, view} = Collection.open_view(root, project)
  try do
    {:ok, nearby} = Collection.view_neighbors(view, selection)
    "initialized" = nearby["state"]
    "present" = nearby["witness"]["root_state"]
    slots = ~w(predecessor selected successor second_successor)
    true = Enum.map(slots, &nearby["neighbors"][&1]["key"]) == Enum.map([0, 10, 20, 30], fence)
    false = Map.has_key?(nearby["neighbors"]["selected"], "value")
    {:ok, batch} = Collection.view_read(view, %{"op" => "get_many", "keys" => [fence.(10)]})
    [%{"value" => %{"text" => "page 10"}}] = batch["records"]
    IO.puts("Neighbor refs and selected value share the checked root.")
  after
    :ok = Collection.close_view(view)
  end
after
  File.rm_rf!(scratch)
end
```

One original task may hold one view; close it before opening another. Its actual
active file-effect worker shares that ownership. A different task, reconstructed
JSON handle or stale reference cannot reuse it. The absolute lifetime is
60 seconds, without renewal, with at most 512 calls **and** 512 observation units.
The unit counter intentionally tightens the aggregate allowance for batches:
64 full eight-key batches exhaust it, as do 128 neighbor lookups. A copied handle
shares both counters. Valid requests debit units before lookup or native IO;
short results and failed checks receive no refund. Capacity refuses instead of
evicting metadata, restarting counters or silently reducing a request.

At most 16 caches coexist. Each retains at most 8,192 references and 4 MiB of
encoded metadata, including the canonical key directory and integrity seals;
replies refuse above 64 KiB. The retained ordered directory uses the opaque
[OTP `gb_trees` API](https://www.erlang.org/docs/27/apps/stdlib/gb_trees.html),
including the reversed iterator available since OTP 27. It replaces the former
retained key list. Tree/map nodes, binary storage, process heap and temporary
installation/validation lists are additional memory. Component checks compare
tree and list term sizes separately; this is not a process RSS or peak-memory
guarantee. A tree lookup does not make the whole call
logarithmic: integrity checks still examine up to 8,192 directory keys, and a
neighbor request checks all matching-prefix references. No persisted secondary
index or whole-store value scan is introduced.

An internal classified open distinguishes a valid index exceeding the encoded
cache limit from genuine exhaustion of all sixteen slots. The ordinary open
keeps its generic capacity error. Invalid headers/references, an oversized
reference count, ownership errors and stale or expired views do not qualify for
a capacity fallback. The notes Worker-input adapter can use the existing paired
reader only after one of those two initial capacity refusals, before any borrow
or authentication. Its coalesced path plans historical neighbor references,
freshly reads selected values under matching native roots and authenticates the
result within each independent protected pass. See the
[Worker-input flow](session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
for the distinct source owners, final root check and unchanged domain/Worker
deadlines. These rules do not enlarge the separate 32-unit managed-read closure.

`Collection.Directory` owns the pure selection and observation-cost rules. Its
helpers grant no authority. The managed-publication callback uses the same
selector and costs inside its separate 32-unit owner-bound closure, described
[above](#serialize-protected-consent-before-publication). This does not adopt
metadata version 3, change the current normalizer or expose another SDK operation.

A changed root returns `collection_view_stale` and discards the view. An explicit
reopen may then revalidate selected content, lineage and expiry at the new root;
an unrelated capture does not itself invalidate every recalled record. Value
reads rehash their selected objects. Neighbor reads validate references only.
Unrelated immutable objects and cached manifest blocks are not reread on every
call, so same-root corruption outside a value selection can remain undetected
until a full open. Trusted Core and cooperative protected storage remain the
boundary, rather than containment of hostile BEAM or arbitrary same-user writers.

Wire roots 4 and 5 are supported without implicit legacy adoption. Value results,
cache and root witnesses use version 2; neighbor results use version 1 and contain
that same version-2 witness. A native-confirmed absent root has no root or manifest
hash and a zero-generation/floor summary. Its neighbor result is explicitly
`uninitialized`, with four nil positions; it is no managed absence proof. A
materialized empty collection instead retains its actual root/manifest witnesses
and refuses neighbor selection if the required sentinel is missing. Neither root
disappearance nor a generic native error can turn a present view into absent
history. The first publication invalidates an absent view.

Views grant no policy, source, Session or managed eligibility authority. Their
owning adapter must check those facts and the active job at every dispatch.
The [managed Worker-input integration](session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
adds independent protected observations and original-source ownership to its
notes view. It grants no cross-turn cache authority or generic format adoption
or withdrawal permission. Exercise the pure selector and native view suites:

```sh
mix test test/ipse/extension/collection_directory_test.exs test/ipse/extension/collection_neighbors_test.exs test/ipse/extension/collection_read_view_test.exs test/ipse/extension/collection_empty_read_view_test.exs
```

When trusted management preparation needs continuous target ownership, use
`Collection.with_managed_read/3` instead of carrying a released view into review.
It retains one actual notes Collection owner and supplies the same bounded read
closure used by managed normalization: 32 shared units, one per exact key, four
per neighbor lookup and eight for a pending summary. Reads check the native owner
before and after IO, and the closure expires with its callback. Exhaustion is
sticky; a caller cannot ignore it and return successful data. A normalizer's
token seals before publication, so a later callback cannot change its budget
and reclassify an already selected root. The root witness
and record bytes still need their domain authentication and exact target checks.
This storage callback grants no output or mutation permission. Identity, Consent,
original journal and the native writer must retain their own required ownership.
Reviewed management and managed approval compose this storage callback through
their separate typed adapters; the callback alone cannot authorize either path.
Interactive literal correction and supersession additionally bind a consumed
one-use review to the exact normalized mutation. Their `Runner.SessionSource`
adapter transfers actual Session and Writer controls and every inactive original
source lease to the existing native Collection owner through the final root
decision. A changed root followed by owner or cleanup loss remains unknown;
resuming reconstructs that history without retrying it. See the
[complete source-owner flow](session-sources.md#reconstruct-without-giving-old-tokens-authority)
before changing this admission or settlement order.
Absent storage can create protected
directories and retained locks, just as opening a view can. The focused
`collection_held_read_test.exs` exercises contention, escape, budgets and actual
owner loss; managed publication/directory tests cover the shared closure.

For a signed literal, `ObservedRead.with_managed_record/7` performs the existing
record/format/live/anchor checks inside that retained read and calls a trusted
continuation with the same observation as `managed_record/6`. It keeps the
Collection owner through continuation; the ordinary reader releases its view
before returning. Compose it inside the actual matching Identity/domain-auth
and management Consent callbacks. A revoked capture policy or expired target
can remain inspectable for this faithful local purpose, without becoming current
inference support. The `:held_target_read` controls in
`collection_normalizer_v3_integration_test.exs` exercise this three-owner stack
and substituted data. Follow the [reviewed management flow](session-sources.md#bind-a-new-terminal-choice-to-revalidated-facts)
for native journal/tty attachment and reducing-effect admission.

## Prepare a local authenticated-page repair

`Collection.ManagedPages` is the internal schema-3 codec used by the host-private
NormalizerV3. SDK requests without explicit metadata version 3 retain schema-2
metadata. Calling the codec does not select a new format, adopt an old store or
grant publication authority. Its fixed descriptor names the page syntax,
immutable geometry, authentication context and retirement encodings.

Start with a pure roundtrip after building Mix:

```elixir
alias Ipse.Extension.Collection.ManagedPages, as: Pages
lineage = Ipse.JSON.sha256("synthetic source")
row = %{"clocks" => [0, nil, nil, nil], "choice" => nil, "retirement" => nil}
{:ok, body} = Pages.pack(:anchor, Pages.zero(:anchor), %{lineage => row})
{:ok, %{entries: %{^lineage => ^row}}} = Pages.unpack(:anchor, Pages.zero(:anchor), body)
true = Pages.encoded_size(body) <= 6144
```

This parses closed bytes with a synthetic tag for sizing; it mints no tag or
choice. Live rows retain lineage, value, recipe and historical-policy hashes.
Both historical hashes are charged per row even when a page deduplicates their
actual dictionary. Anchor/live virtual capacities are 4,544/4,542 bytes, with
nonsingle minimum occupancy 2,104/2,180 and at most 128 decoded rows. Actual
complete JSON values must still fit 6,144 bytes. Compression cannot bypass
virtual-byte or row limits.

Inside the actual checked managed callback, use `Pages.open/4` with the selected
record and its actual neighbor observation. It verifies exact reference bytes,
the DomainAuth tag, canonical body, range and old minimum occupancy. Verify the
fixed format through `open_format/2` separately. `Planner.plan/4` accepts one or
two unique semantic edits and that held read closure. It authenticates every
selected/buddy page, performs bounded local splits/merges, and returns at most
three changes per edit. It reads at most four old page values; each directory
lookup still charges four of the callback's 32 shared observation units.

After revalidating semantic permission, `Planner.seal_changes/3` binds the plan to
the same root summary/state/hash/manifest. New seals use the publishing operation
and old **global generation + 1**, including when an inherited page's revision
is older. A removed page retains its exact positive old revision. A caller must
reserve the combined metadata changes and bytes before publication; the existing
two-sidecar SDK reserve cannot admit an arbitrary local repair.

Shaped record/neighbor maps cannot establish actual Collection provenance.
Native absence, Identity prepared/active state, current source/policy checks and
final completion remain the calling adapter's responsibility. Parsing a
`native_management` capsule never constructs a fresh review permit. Compact
retirement addresses only the containing lineage's fixed literal
`note.<lineage>` derivative. It cannot retire pending/history/paraphrase values
or arbitrary prefixes. There is no unsigned-schema-2 reseal/import path.

Run `mix test test/ipse/extension/collection_managed_pages_test.exs` for pure
codec checks and actual Identity/DomainAuth controls. Their Collection
observations are trusted fixtures; they perform no Collection publication.
Follow the [automatic publication exercise](knowledge-storage.md#publish-one-fresh-record-with-authenticated-metadata)
for actual held-closure tests and the remaining adapter limits.

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

Only the final paged `extension_invocation_result` publishes the saved
descriptor: version 2 for ordinary invocations, version 4 with the exact protected
outer binding for saved consent. A complete byte stream or a seal alone remains unreadable. Source
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
