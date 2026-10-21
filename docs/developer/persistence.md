# Keeping session evidence durable

The journal is the recovery authority for conversation and admitted effects.
`Ipse.Journal` creates/reads JSONL and handles inactive appends and allowed tail
repair. `Ipse.Journal.Writer` owns an active append descriptor. `Journal.Reader`
decodes bounded records; `Journal.Limits` enforces finite growth. The independent
`Ipse.Session.Lock` guardian retains the Rust advisory lock until owned work has
actually quiesced. Lock files remain in place to preserve inode identity.

Start with `lib/ipse/journal/writer.ex`, `file_effect.ex`, and `session/lock.ex`.
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

Then follow the interrupted-write case in `test/tool_recovery_test.exs` and the
pending-question cases in `test/question_session_test.exs`. Verify that an idle
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
`Ipse.FileEffect` therefore owns admitted writes until synchronous IO returns and
is tracked before dispatch. Cancellation does not kill that completion owner.
The lock guardian waits for writer, root/nested workers, scopes, registered
resources, child guards, and filesystem completion owners before unlocking,
including after an untrappable Session death.

Read the blocked-write fixture in `test/journal_writer_test.exs`. Its FIFO delays
real IO while Session dies. A replacement session must remain locked until the
reader drains and completion returns. A monitor `DOWN` for the original caller
cannot establish that fact. A stuck completion owner can retain the lock
indefinitely; deleting the lock file would defeat ownership rather than repair it.
Unexpected loss of the helper/guardian stops Session without another append.

Stateless `Journal.append*` APIs are for inactive journals under the proper lock.
They validate history and perform synchronous completion-owned writes; repeated
inactive appends therefore have linear validation cost. Embedded callers remain
responsible for their own lock lifetime.

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
mix test test/ipse/journal_test.exs test/journal_writer_test.exs test/journal_limits_test.exs test/journal_reservations_test.exs test/inactive_journal_test.exs
```

Use writer tests for ownership/IO races and limits tests for sealing and strict
recovery. A meaningful storage change must preserve intent-before-effect,
confirmation-before-success, lock retention after owner loss, and unknown outcomes
without replay. See [budget storage](budgets.md) for its stronger live-prefix check.

Follow the reservation test with a 1,024-byte journal policy. It reserves every
remaining nonterminal byte, rejects an ordinary append without changing the
file, writes the reserved record, then releases the token. The next ordinary
append seals the journal with a valid quota receipt. Repeat the cancellation
case: the orphan record stays on disk while the released capacity admits the
cancellation record. These controls distinguish capacity protection from rollback.
