# Read admitted Session evidence

Use the source interface when a tool or extension needs exact, attributed bytes
already admitted in its own conversation. It provides bounded discovery, evidence
pages and host-computed quote offsets without placing every source in the prompt.
It does not authorize capture, note publication, service egress or any other effect.
Knowledge eligibility, consent, exclusions and managed retraction have separate
owners. The [protected collection adapter](collection-sdk.md) rederives original
source proofs and current permission before publication; source reading alone
cannot establish those conditions.

Read [workspace context](workspace-context.md) first for frozen headers, native
tool groups and compaction. [Persistence](persistence.md) owns journal integrity,
locking and interrupted-effect recovery. This chapter owns source selection and
the read protocol.

## Follow the commit before the read

[`SourceIndex`](../../lib/ipse/session/source_index.ex) is the pure admission and
UTF-8 paging contract. It accepts specific host-validated receipts, never an
arbitrary text/origin map. [`SourceWindow`](../../lib/ipse/session/source_window.ex)
pairs those receipts chronologically. The existing Session-owned
[`Journal.Writer`](../../lib/ipse/journal/writer.ex) caches this projection and
advances it only after a successful durable append, including reserved appends.
A refused or failed append cannot create a source.

During saved-history projection, `ManagedReference` reuses up to 128 exact
dependency hashes and `ManagedLineage` reuses the encoded sizes of unchanged
capacity fields, retaining at most 64 field signatures and 4 MiB of signature
bytes. The scratch caches are local to one replay and cleared on
return or failure. Exact term bytes distinguish values before reuse, and the
same serialized byte and entry limits still apply. These caches neither retain
source leases nor attest current permission: `StoredSources` must still check
the original journal and current owners for each protected use.

For an inactive original journal, a task can also reuse a reconstructed source
index after `Saved.restore/2` has validated the complete decoded event list. The
task-owned cache computes its own digest of the exact events and Session ID; it
never accepts a caller-supplied index. It retains at most 128 indexes and 8 MiB
of their encoded representations, with retained binaries detached from journal
read buffers. Inputs over 8 MiB and simultaneous cache requests use the ordinary
uncached reconstruction path. This is an encoded-size bound, not a bound on total
BEAM heap or transient copies. The original admitted task's cleanup scope owns
and closes this cache. Its inference-slot and controlled-child scopes borrow
the same pure cache through authenticated resource entry and registration.
A borrower drops its reference at close and refuses a dead borrowed cache.
Independent scopes and scopes without a parent cache retain their own cache
lifetimes. The full Session ID and event-list digest
remain the reuse key, and each restored index gets fresh query handles.
Each use still opens and locks the original source,
checks its origin and project, validates source pages, resolves the requested
proofs and rechecks the owners. The cache dies with its cleanup scope; a cache hit
does not retain a lease or authorize a later display, write or provider request.

Run `mix test test/ipse/session/source_replay_cache_test.exs` when changing this
ownership path. Its controls cover cache identity, fresh handles and borrowing
across both resource scopes, including owner closure and refused registrations.

Session remains the conversation and permission owner. Only that owner can install
or query the writer cache. Native model reads additionally require the exact active
task PID, job reference, phase, selected source tool and original arguments. Public
`Session.sources/3` calls require the registered subscriber. An extension goes
through its current invocation, artifact capability, activation lease and ordinary
action chain. A valid cursor alone cannot cross any of these boundaries.

| Committed records | Available projection |
| --- | --- |
| `input_received` plus its matching committed effective user message | Immutable original bytes with verified terminal or unattended origin; orphan input remains unavailable |
| Native question checkpoint plus atomic `operator_answer` v2 | Assistant question and exact original answer payload, linked by host question/render/input hashes; parsed answer text alone supplies no origin |
| `operator_assertion` after a native statement/category review | Exact endorsed statement and category, with project/artifact/policy scope; effect permission remains separate |
| Admitted visible original assistant answer | Assistant proposal; presentation and hidden reasoning are excluded |
| Typed native tool intent/outcome plus the actual matching tool message | Separate host outcome facts and attributed `read`, `shell` or MCP text; `write`/`edit` publish outcome facts only |
| Successful MCP/embedding action plus its bound private source | Attributed MCP text or typed vector metadata; source-only/interrupted prefixes grant no read |
| Successful decision action, response and completed final metering | Separate operation facts and advisory content; durable response before settlement/result grants no read |

Legacy roles and unverified older answers are coverage gaps, not newly attested
operator input. Other event prose, presentations, arbitrary journal paths and
hidden reasoning never become sources. Tool stdout is an attributed reference;
the typed outcome attests only the host-observed status, approval and timing.
Neither establishes the truth of output prose. A terminal event also does not
establish that a human supplied the bytes: automated PTYs exercise the same channel.

`/remember` can obtain a fresh native statement/category confirmation and request
one new v3 capture under the separately selected saved permission. The terminal
client, an explicit authorized-client headless typed-outcome save, and a
synthetic model-selected pending-proposal save have focused positives. A bounded
host cache distinguishes authentic CAS prerequisites from metadata-only index
observations; scans remain outside both historical classifications. The cache
does not grant current use. Model-selected source tools preserve the complete
selected-source union through the preflight described below. After a known
capture, the own-write transition can preserve earlier metadata as historical
while keeping every signed-record dependency for fresh eligibility checks.
This does not establish full automatic-capture quality. Follow the
[publication flow](collection-sdk.md#follow-one-capture-across-its-owners) rather
than treating statement confirmation as a general capture grant.
Source-dependent new-v3 capture has a separate native publication handoff:
after a current literal read, a new unattended-input proposal can publish while
retaining that literal in the complete conversation union. The publication owner
must match the provisional current root, retain every original source and enforce
their deadlines. The newer candidate's own proof cannot replace earlier reads.
Its pending status supplies no current-note eligibility or tool permission.
`operator_assertion` records carry the original endorsed text/category and
project/artifact/policy scope. SourceIndex exposes category-specific
`input.assertion.ordinary`, `input.assertion.preference` and
`input.assertion.current` kinds when those records validate. Plain
input and question answers cannot acquire that origin by repeating their text.
These receipts prove recorded endorsement, not external truth or current effect
permission. Reading one never bypasses current source, recipe or Consent checks.

## Bind a new terminal choice to revalidated facts

A saved quote describes past input. A new effect-specific choice needs a fresh
review of the complete proposed facts. The internal
[`Runner.Review`](../../lib/ipse/runner/review.ex) primitive supplies that native
observation and a one-use permit. It has no worker/SDK endpoint and does not
implement a knowledge-management command or grant ordinary effect permission.
The calling storage adapter must establish current target and policy authority
separately.

The trusted caller first reads its target, policy and proposed change, then
releases all locks before terminal IO. `with_review/3` displays the complete
JSON facts with escaped controls and an independent eight-byte random challenge.
It requires exactly `command SPACE lowercase_challenge`, without trimming, and
the actual native-v2 restoration/exit receipt, event ID and input/display hashes.
EOF, cancellation, a mismatched challenge or bare yes enters no callback.

For facts whose display itself depends on current protected sources, the internal
`with_review/4` variant accepts a host-owned display guard. The guard acquires and
rechecks the required source and policy leases, calls its one-use same-process
display continuation with the earliest applicable wall-clock deadline, and holds
those leases until the native helper acknowledges the complete display. It then
releases them before the owner sends the native input-release frame; the helper
does not enter its input wait until that frame arrives. The final callback must
reacquire and rederive the facts and authority before consuming the permit; a
display acknowledgement is not a publication grant. The native helper checks the
deadline before its display writes, but a clock check and OS write are separate
operations, so this is not a kernel-atomic deadline guarantee. Guard failure,
an expired deadline or an unconfirmed display grants no review permit. A guarded
Port is owned by the lease-holding BEAM process. An enclosing file-effect process
can outlive its Session caller, so direct Port ownership alone does not establish
upstream-owner cancellation; that separate integration boundary still needs proof.

The callback receives an opaque same-process permit. Reacquire the effect's
Identity/Consent/Collection locks and rederive the complete current facts before
calling `consume/3`. Its first actual-owner attempt spends the permit, including
when the facts changed; no silent rebase is permitted. A foreign process or
forged reference cannot spend the genuine owner's permit. The permit expires
30 seconds after the native input returns, without renewal, and disappears on callback exit.
Its resource scope, upstream owner and deadline must remain live through final
callback completion. The remaining lease bounds each blocking resource query;
deadline and owner checks repeat after that query returns. After consumption,
only `:ok` or `{:ok, value}` is a successful callback result. Errors, other return
values, exceptions or loss remain unconfirmed; inspect effects before any fresh
review, without replay.
An explicit callback error before consumption grants nothing.

These checks detect expired callback results; they do not undo an effect after a
permit expires. A real stopped transaction demonstrated late forgetting followed
by outer Review `unknown`. The trusted forget normalizer admits one bounded
reducing attempt when it consumes a live permit under fresh effect locks; it
does not promise physical completion before permit expiry. Its private caller
must preserve unknown outcomes through effect settlement and journal cleanup.
Public `knowledge forget NOTE_KEY` uses that reducing path after a complete native
review; its [operator procedure](../operator/knowledge-permissions.md#forget-a-selected-native-note)
requires inspection of the printed management journal after uncertainty.
The public session-only retention choice uses this same reviewed reducing path.
Persistent retention uses a separate claimed review and timed final root switch.
Interactive correction and supersession use the Session-owned path below;
retained data formats alone supply no executable permission.

Ordinary new-v3 capture has a different clock contract. Its native owner checks
the earliest policy/lineage deadline at the final locked root-switch decision.
An admitted switch may finish physically later without invalidating an otherwise
confirmed ordinary result. Review additionally requires a live confirmed callback
result, so a reducing forget can have happened while its outer Review returns
unknown. Neither result permits automatic replay or promises physical rollback.

Facts retain the existing JSON limits: 16 KiB total, eight KiB per string,
twelve levels and 128 members per collection. The complete escaped display has
a separate 64-KiB ceiling. Oversized input refuses rather than truncating the
review. The returned host-private `native_review` receipt commits the observed
command, event, display, input, challenge, time and fact digest. It is neither a
SourceIndex proof nor a stored retention choice. Parsing or replaying its JSON
cannot construct a permit, establish current eligibility or certify human identity.
Trusted Core/cooperative storage remains the boundary.

This synthetic developer exercise observes a terminal choice and writes no effect:

```elixir
facts = %{"target" => "synthetic example", "choice" => "pin", "reason" => "Exercise only"}
Ipse.Runner.Review.with_review("pin", facts, fn permit ->
  # A real adapter revalidates its target and permission under their locks here.
  {:ok, receipt} = Ipse.Runner.Review.consume(permit, "pin", facts)
  {:ok, Map.take(receipt, ~w(kind command facts_sha256))}
end)
```

Use `review_test.exs` for the clearly labeled simulated-IO state machine and
real resource-scope controls; `review_native_test.exs` exercises actual native
PTY receipts separately. A Session effect must still journal its intent before
execution. Standalone review does not manufacture a conversation or source entry.

## Move a completed reply into native decision review

The bundled Knowledge tool can nominate one exact sentence for a decision card
without saving or accepting it. Trace this host-owned continuation separately
from ordinary source tools and native statement endorsement:

| Boundary | Owner and required evidence |
| --- | --- |
| Main-model nomination | `PendingNomination` binds the admitted tool descriptor/artifact, same turn, actual call and successful invocation result, exact text/category/reason and any confirmed current output-release chain |
| Completed original answer | `Turn.finish/2` commits the original answer before `Session.start_post_reply_capture/2` resolves its unique quote through Writer's owner-only `answer_request` query |
| Capture attempt | Session appends `pending_chat_capture_started` before invoking capture; its identity binds that turn, final request, nomination and exact answer proof |
| Pending capture | `Session.Invocation.invoke_export/4` runs the real protected capture command with its ordinary saved-consent and action checks |
| Confirmed capture result | `ChatReviewHandoff.prepare/3` binds the actual invocation/result and selected pending key to the original proof, semantic pin and registered client/channel generation |
| Durable handoff | Session appends `pending_chat_review_handoff` with a real Writer source receipt; the client receives only an opaque one-use reference |
| Terminal ownership | `CLI.Input.stop_confirmed/3` stops and observes the reader, then obtains the actual Session's native input-release acknowledgement before `ChatReviewHandoff.close/1` confirms Session closure |
| Native decision review | The existing management actor owns its own Writer and retains the now-inactive original source, current Identity, Consent and Collection owners |
| Return to chat | A confirmed result or known refusal permits a new process for the same saved conversation; uncertain cleanup, review or reopening stops without retry |

A worker's `saved` or `existing` key selects a candidate only. Before showing
the card, management reopens the original journal under its retained source
lock, validates the full Saved chain and exact handoff source receipt, then
reauthenticates the signed pending value. Text, category, reason, source proof
and current semantic pin must match the handoff. Publication repeats those
checks under fresh current owners. An unchanged key or matching text alone
cannot substitute for that comparison.

`ChatReviewHandoff.take/2` accepts only the actual registered client and live
Session reference. Its private handle records confirmed close and spends its
management attempt once; JSON reconstruction supplies no handle. The ordinary
management facts retain `session_id: nil`. The header stores the exact chat
event and Writer source receipt, and the operation ID commits their digest.
The native code therefore selects those exact facts and original client, while
the acceptance receipt continues to describe a management operation. Saved
Consent reservation, admission, measured settlement and unknown liability use
the same path as explicit `knowledge review`.

Claiming the handoff also captures the actual validated live Mode. The private
owner/ref checked handle projects only `Mode.config/1` into the retained CLI
configuration, checks the Mode roundtrip and clears startup planning and
session edit flags. Management review repeats that projection, and same-ID
reopening uses it. Provider and billing choices do not change. The CLI's original
startup mode is not authority for a conversation that has since completed a
witnessed `/plan exit`.

The ordinary assistant reply keeps its normal terminal delivery. Native card
display and exact fresh input remain independently required before a Review
permit exists. No second model extracts or accepts the decision. The original
Session has released its Writer and lock before this management transaction
starts; the existing inactive-source publication guard remains unchanged.

The automatic path attempts one capture and review per completed nominated answer, a unique
quote of at most 1,024 UTF-8 bytes and an available original answer within the
existing 8-KiB bound. It refuses protected-note record dependencies; an exact
union of cached root-only prerequisites is supported without dropping lineage
or replacing the capture's current-use and publication gates. It also refuses presentation
transforms, selected text consumers, after-turn delivery, active drafts,
nonempty nomination references, planning and headless acceptance. These refusals
do not upgrade a historical selection into authority. The bounded attempt ledger restores spent
answer identities, including attempts whose capture result is unknown. Later
completed answers have separate identities; they cannot reuse the earlier
operation or make its outcome known. Legacy capture-start records reconstruct
the same inert fence from their preceding nomination and committed answer.
Resume reconstructs no handoff reference,
code or old capture. An explicit interactive resume without an initial task
may create a fresh review of an existing pending candidate. This separate
startup path runs synchronously after registering the waiting native reader,
before `Terminal.refresh_reader/1` can arm its first read or print `you>`.
It uses the existing confirmed reader stop and Session close before management
review; it adds no Input protocol or background preflight process. An authorized
`observe_channel` request invalidates the idle snapshot before any read dispatch.
Foreign requests cannot invalidate that snapshot or activate review.

The original version-1 handoff and source receipt stay unchanged. A version-2
management wrapper includes a fresh `pending_chat_review_reoffered` record and
its actual Writer receipt, binding a new client/channel generation, review ID,
opaque focus ID, chronological normal mode and render revision. An idle resumed
Session need not have a current turn or request; the original pair remains
provenance rather than invented live focus. Structural receipts create no
capability. Original and reoffer byte receipts are checked under the existing
source ownership at display, publication and later use.

Preflight reads only bounded current metadata and earlier management journals.
`Consent.with_policy_operations/7` projects selected existing operation rows,
including compacted receipts, under the existing pinned policy transaction.
It creates no ledger or grant and preserves the old `with_policy/6` callback.
Every earlier review of that original candidate must have an authenticated
known disposition. Hashes without the required matching journal cannot turn an
uncertain attempt into a cancellation. Accepted candidates are not offered
again; unresolved, missing or contradictory accounting stops review. The allowed
path repeats selected-row and current-source checks under held policy before
reserve, display and publication. A known permission denial is reported
separately from uncertainty and cannot authorize another review.

Each review receives a new operation, reservation and native code; it never
recaptures the original answer. Internal same-ID reopening disables this startup
check, so a cancellation does not cause an automatic review loop.
Native edit and command grants end on the internal close;
same-ID reopening does not renew an initial `--accept-edits` grant.
The separately configured ordinary approval policy remains in force, including
an explicit `--yes`; closing session grants does not revoke that choice.

For a worked native exercise, build the matching bundle and run:

```sh
mix test test/ipse/cli/chat_review_test.exs --only chat_review --max-cases 1
```

The synthetic loopback main route nominates in one tool call and completes the
same reply in its ordinary continuation. Inspect the actual card, exact input,
capture and management receipts, unchanged conversation ID, current provider
configuration and final accounting. After same-ID reopening, ask a followup
and inspect its actual model request for the currently authenticated version-6
accepted-decision Reference. Ordinary retained answer text alone cannot prove
current recall. Then close the conversation and retrieve the decision from a
fresh chat to exercise a separate consumer. Cancellation must leave the proposal
pending and create no acceptance intent. Neither mode establishes installed,
live-model or human qualification.
The native synthetic journeys cover both normal startup and startup planning
followed by a witnessed exit before nomination. The latter verifies the live
normal/enclosing mode, native acceptance, same-ID normal reopening with ended
session grants, and current recall from a fresh chat. Planning itself remains
ineligible for nomination, capture and acceptance. Sparse mode replay separately
rejects missing, future, forged and cross-Session exits while preserving the
original planning header.
The per-answer ledger's focused replay controls separately check duplicate,
foreign-answer and unknown-prefix refusal; they do not establish a native
multi-card journey by themselves.

Run the explicit-resume exercise separately:

```sh
mix test test/ipse/session/chat_reoffer_test.exs
mix test test/ipse/extension/policy_operations_test.exs
mix test test/ipse/cli/chat_reoffer_test.exs --only chat_reoffer --max-cases 1
```

The two-card synthetic native control cancels the first card, closes the
internally reopened conversation, explicitly resumes the same ID, accepts a
different fresh code and retrieves the accepted decision from a fresh chat.
It checks one capture, distinct management operations, preserved original
provenance, actual source receipts, ended session grants and a version-6 current
read. It also checks that no ordinary `you>` prompt appears before the startup
card. This qualifies the pre-first-read flow; it does not promise to preserve
typeahead entered before an input prompt, accept a pending card after an
uncertain reservation, or establish installed, human or live-model behavior.

## Read through a real synthetic Session

Run this fixture in `iex -S mix` from a built checkout. The provider override is a
development fixture, not a configurable service or fallback. It uses no account:

```elixir
defmodule SourceExample do
  def complete(_, _, _, _),
    do: {:ok, %{"role" => "assistant", "content" => "Synthetic visible answer."}, %{}}
end

root = Path.join(System.tmp_dir!(), "ipse-source-example-" <> Ipse.Usage.id())
File.mkdir_p!(root)
{:ok, session} = Ipse.Session.start_link(
  config: %{provider: :demo, model: "synthetic", provider_module: SourceExample,
            home: Path.join(root, "home"), approval: :deny},
  cwd: root, state_dir: Path.join(root, "state"), subscriber: self())
:ok = Ipse.Session.prompt(session, "Record café 雪 exactly.")
receive do
  {:ipse, ^session, {:done, :ok}} -> :ok
after
  5000 -> raise "synthetic Session did not complete"
end
{:ok, page} = Ipse.Session.sources(session, "source.list", %{"limit" => 32})
[original | _] = page["sources"]
{:ok, evidence} = Ipse.Session.sources(session, "source.read",
  %{"handle" => original["read_handle"]})
"Record café 雪 exactly." = evidence["text"]
{:ok, quote} = Ipse.Session.sources(session, "source.quote",
  %{"handle" => evidence["handle"], "quote" => "café"})
7 = quote["start_byte"]
12 = quote["end_byte"]
:ok = Ipse.Session.close_confirmed(session)
File.rm_rf!(root)
```

The original input is unattended because this fixture did not observe a native
terminal. A subscriber cannot choose a stronger origin. Repeat the read from a
different process and require refusal, even with the actual handle.

Fresh sessions pin `source_layout: "session_sources_v1"` and declare `source_list`,
`source_read` and `source_quote` from their first model request, including an empty
index. Existing sessions without this marker retain their admitted catalog. The
three tools use the same argument objects shown above, without the operation name.
Normal native tool intent/results, turn call limits, model steps and context bytes
apply. Source reads do not imply another model or embedding call.

Before **every** model-selected `source_list`, `source_read` or `source_quote`,
Session obtains a one-use preflight bound to the exact task/job/call and arguments,
even when its original dependency list is empty. Writer privately resolves the
actual SourceIndex query and derives provenance for every selected row; a list
cannot classify just its first result. Known empty producer lineage differs from
a missing producer mapping. Markers for known-empty effect sources follow the
same host classifier that admits MCP, embedding and decision sources into
SourceWindow. Internal file snapshot pages and Collection actions with empty
lineage create no quotable source occurrence; their protocol history remains
recorded, and every nonempty action dependency stays in the causal union.
The complete original-plus-selected union must be
canonical and use supported dependency versions 3–6. This structural check grants
no read: the actual query reacquires current policy, roots, signed records and
original source owners through `ManagedToolUse.with_effect`. Result release
independently revalidates the same complete union. Missing producer mappings,
unsupported dependencies and unavailable current owners refuse. The exact
admitted call consumes its task/job/argument-bound preflight once.

After a confirmed new-v3 capture advances the root, Session can retain earlier
payload-free metadata as explicitly historical. Authenticated nonempty or later
metadata-only index pages qualify for this history classification, alongside
the narrower snapshot/nil-get/initial-empty-index CAS prerequisites. Neither
classification includes scan payloads. Session authenticates the complete old
write union, exact own operation and adjacent successor receipt under fresh
Identity/Consent/Collection checks. Original messages, dependency objects and
provider envelopes stay unchanged. A bounded host notice explains that the old
root or absence does not establish current record eligibility; the notice has
its own current guard. Only version-3 metadata receives the successor mapping.
Every literal, historical or accepted-record dependency remains attached to its
producer and Reference occurrence and must pass its separate current-use checks.
Missing metadata classification, mixed metadata roots, unknown actions and
intervening writes refuse instead of receiving this projection.

A settled Worker input can already have authenticated that same adjacent
successor before model preparation. Model projection may then combine the
original cached metadata with that exact successor guard. It requires the
recorded mapping for every metadata member of the complete causal write union
and the known successful own action, reacquires the current root, and adds the
same historical notice. Signed records remain separate obligations, including
their original source journals and deadlines. Another metadata root or an
unrecorded fresh guard cannot join this case. Worker transition requires all
original metadata members to describe the same old root.

Decision acceptance can advance the root again while the chat is closed.
`ManagedLineage.management_root_candidate/2` selects only the cached capture
prerequisites tied to that exact handoff, original parent/result commitments
and pending key. `ManagedUse.management_root_transition_observation/3` retains
the committed acceptance journal, verifies its original source and matching
capture-to-acceptance generation chain, and checks the current native root and
capture operation. The version-2 `managed_root_transition` records that evidence
for chronological replay. Matching a root hash alone is insufficient: unrelated,
missing or uncertain management evidence cannot classify an old observation.
Only those payload-free metadata prerequisites become historical. Every record
dependency remains in the complete union, and original messages, opaque provider
calls and tool-call/result pairs stay unchanged. The next model request still
requires fresh current-use checks over the full union.

Result preparation independently rederives the actual returned query and selected
provenance before its dependencies and version-2 observation are committed.
Saved repeats that relation chronologically against the original source window;
historical token rebinding supplies no new live authority. Starts suppress source
arguments and subscriber results use the fixed status-only message
`Source tool result withheld from terminal preview.` Complete authenticated content
remains in the journal/model continuation with its full lineage; this is not
protected terminal payload rendering. The
[reviewed preflight](../archive/2026-10-26-p30-p31-implementation/managed-source-tool-preflight-independent-review.md)
owns the bounded implementation evidence.

Exercise that whole path with the shipped artifact:

```sh
mix test test/extensions/knowledge/recall_capture_session_test.exs --max-cases 1
```

The fixture creates a genuinely reviewed literal, recalls it through the actual
Knowledge artifact, performs a main-model source lookup and saves a separate
unattended-input pending proposal. Inspect the final model request for both the
literal and historical metadata notice. Strict Saved reconstruction must keep
that literal in its output and Reference dependency sets without a version-4
root mapping. Altered or missing own-write transition evidence must reject replay.
The paired source-withdrawal and revocation cases hold the next preparation
before its reply, after the capture is known and settled. They require an unknown
input for that exact result, no final model request and inert idle resume with
unchanged storage/accounting. These synthetic local-provider controls establish
neither model quality, compaction nor all provider continuations. Dated results
and earlier failures remain in the [implementation record](../archive/2026-10-26-p30-p31-implementation/shipped-recall-capture-20261102.md).

## Grant an extension source access explicitly

Declare and trust both `host.actions` and `host.sources`. This grants current-Session
source access, including private admitted input; an effect-result or history grant
alone does not. It gives no parent/child transcript access and adds no child grant.
[`SourceRead`](../../lib/ipse/extension/source_read.ex) validates the closed requests.
An independent worker returns this ordinary continuation:

```json
{"api_version":1,"kind":"host_call","request":{"op":"source.list","limit":32}}
```

On an `ok` result, retain the actual returned `read_handle` and submit
`{"op":"source.read","handle":HANDLE}`. Continue with its actual `next` handle.
For a quote, submit `{"op":"source.quote","handle":HANDLE,"quote":"exact bytes"}`.
`HANDLE` is a string copied from that response, not a path or constructed ID.
No request accepts origin, session ID, byte offset, provider or journal location.
An unavailable/stale read returns `source_refused`; list again for the current
window rather than replaying old effects to recreate evidence.

Session syncs the action intent before preparing the read and compares the exact
prepared outcome before committing its result. Reads use at most 512 action steps
within the invocation's two-minute read deadline. They do not enlarge other call
families. Explicit `host.actions.mixed` permits 512 reads plus sixteen other calls
under their individual grants. Cancellation closes the worker; resume reconstructs
the receipt and never starts its old continuation automatically.

## Interpret bounds and incomplete coverage

List requests accept `limit` 1..32 and an optional opaque `cursor`. A page may
contain fewer rows to stay within **4096 rendered JSON bytes**. Evidence pages fit
**8192 rendered JSON bytes**, including escaping, metadata, coverage and tokens;
UTF-8 codepoints are never split. Follow the actual `next` until `complete: true`.
The complete SDK object remains bounded independently. Each row carries occurrence,
version and chunk IDs, kind, origin, coverage, reason and read handle.

`available` means the selected immutable view is readable. `partial` identifies an
attributed tool/external-text view with limited host meaning. `unavailable` supplies
no invented bytes. Visible answers retain the existing Lifecycle 8-KiB admission
bound: a larger answer has unavailable original text and a recorded size/hash,
even if other journal records still contain its provider response. Original input
retains its separate 1-MiB bound. A large Journal source wrapper does not truncate
or prevent reading that admitted original input.

The index retains at most **1024 occurrences**, **8 MiB** of text and **1 MiB** per
source. It refuses capacity without eviction. Pending receipt pairs separately
allow **128 entries/4 MiB**; the full journal is not cached. Coverage counters expose
indexed/observed projections, unavailable/legacy views, refused capacity and
pending-pair gaps. `complete` finishes pagination of the indexed window; it never
claims that missing journal views became available. New source/coverage changes
fence old tokens. A compact status summary uses the existing 16-KiB rendered
reference allowance after selected extension contributions reserve their bytes;
it is omitted whole when it does not fit. Readers still work with zero inline
source allocation. Ordinary context reduction retains the original source index.

Exact quotes must match globally and uniquely in the immutable UTF-8 source and
lie wholly within the referenced evidence page. Repeated or normalized text,
overlapping matches, stale versions, redactions and unavailable bytes refuse.
The host computes absolute byte offsets and quote/content hashes. This proves
source support, not entailment, current eligibility or truth.

## Reconstruct without giving old tokens authority

`Saved.restore/2` validates the complete owning prefix before building SourceWindow.
Actual source references validate before permitted torn-tail repair. Startup may
resolve bounded source pages; source list/read/quote operations themselves never
repair a journal or run an effect. Idle resume preserves the existing journal
prefix and may append the current release-owner marker; it starts no model or
old effect. The new window and source-driven lifecycle epoch are admitted only
when actual work starts.

Each live window uses a volatile secret and authenticated tokens bound to Session,
window, source generation, policy generation, kind, version and offset. Resume
creates a fresh window/secret, so previous tokens refuse while immutable occurrence
and version IDs remain stable. A durable `source_window_opened` record binds the
historical window before token-producing model/SDK work.

Saved read results are recomputed at their chronological source boundary. Replay
checks closed canonical historical token claims and the admitted historical window,
then compares exact source/result bytes after replacing only obsolete window/MAC
framing. This replay-only structural operation cannot authorize a live read.
Future occurrences/generations and mixed historical windows refuse. This is
consistency checking of a protected journal, not a cryptographically signed
transcript resistant to coherent rewriting by arbitrary same-user code.

Chat handoff validation uses that same replay-only operation. Reconstruct the
window immediately before the original capture intent and resolve its recorded
`source.quote` request with `saved_query_provenances/4`. Compare the singleton
occurrence/version/kind/origin, original turn/request/receipt and exact stored
proof. A fresh `answer_request` handle cannot reproduce the old token: every
SourceIndex restore creates a new volatile secret. Rebinding checks historical
consistency and supplies no current read or publication capability.

Stored managed-note proofs use a separate host path. `StoredSources` resolves
only the consuming Session's selected state directory. The current owner checks
its Writer descriptor and exact committed proof under the active collection
action lease. An inactive source Session must have its original protected
journal and retained lock; the reader holds that lock while validating the full
Saved prefix and checking the proof. Copies and legacy origins refuse, as do an
active other owner, incomplete tail, changed version or different protected
project/namespace. This path never repairs, relocates or resumes the source.

For a chat-derived accepted decision, the retained management-journal resolver
also supplies its exact chat handoff provenance. `ManagedUse` carries that
selection into `StoredSources`; while the original source is locked, the reader
checks the real handoff source page and complete historical chain before the
use callback. The operation digest binds this metadata to the signed acceptance
facts. A readable original quote with a missing or altered handoff cannot supply
current accepted-decision evidence. This adds no new source-lease type or effect
permission.

For historical preflight of a version-6 reference whose original source is the
consuming Session itself, `ManagedUse.inspect_accepted_reference/2` uses the
existing job/snapshot-bound Writer queries through `StoredSources.with_verified`.
It checks the exact active proof before and after inspection and verifies the
original chat handoff chain. It creates no transferable source lease. The
returned inspection is historical: Worker delivery, model dispatch and effect
use must separately retain and revalidate their complete current dependency
union through their existing owner adapters. Another active Session's source
still cannot be borrowed through this path.

Inactive-source resolution monitors the actual retained native lock and refuses
after ownership loss, even if the journal and lock path did not change. Writer rechecks its full
recorded origin and private parent on cached queries and append boundaries.
The private transferable-source API can verify distinct proofs from inactive
original Sessions while retaining one lock per Session. Its grouped form returns
owner-bound lease tokens in Session-ID order and refuses active-source and
duplicate proofs. Each native recipient still imposes its own lease-count limit;
the tokens alone do not authorize display or publication. Callers must bind all
owners and deadlines and settle every exported lease.
For a mixed active/inactive set, the source-union scope checks the active
Session's exact proofs before and after the callback while retaining the
inactive Session locks. Its callback receives lease tokens only for inactive
Sessions. A separate active-Session share is still needed through any native
display or effect; a successful source-union callback does not supply it.
The private management terminal adapter can transfer a verified group into a
native review display and input operation. This does not identify which proofs
an effect requires: the caller must bind the complete proof set to the reviewed
facts and revalidate current sources after input.
The active-Session bridge also retains separate fixed-text synthetic controls;
their results do not qualify another protected purpose or payload.
The private transaction helper can retain up to 128 source leases through one
native root decision, alongside one journal lease. An isolated current-source
native control exercises that capacity; the shipped helper must be rebuilt to
match the host before using it. These leases do not by themselves admit a
supersession.
## Deliver a managed export input under its original owners

The same transaction owner supplies the Linux stdin handoff used by
`Session.WorkerInput` for protected export calls, committed host-action
continuations and complete-result page requests. An explicitly protected `Worker`
can prepare an opaque pending
input using its ordinary schema checks, next request ID and exact JSON encoder.
Preparation starts the original callback timer without sending bytes. Its binding
includes the artifact, owner, preparer, actual supervisor PID and immutable frame.
Only its owner or tracked file-effect publisher can prepare it; a configured
Session can query that exact pending stage/payload but receives no authority from
the transport itself. Ordinary workers retain their existing transport behavior.

The stdio supervisor reserves its actual write description and pauses ordinary
input. Worker verifies its PID against the actual Port. The authenticated transfer
compares the operation, original expiry and complete prepared frame before lending
the descriptor; the importer also rejects a substituted write. The request sequence
advances monotonically without a separate 256-handoff ceiling. The importer retains
the three lock owners, Session and Writer
controls and original source descriptions through each bounded pipe write.
The complete frame is limited to 32 KiB plus its four-byte worker prefix.
An attempt is consumed once; partial delivery and failed ownership checks remain
unknown. Both sides complete the existing retained-description close handshake
before ordinary stdin returns. Worker buffers an early callback response until
the trusted preparer explicitly releases it after settlement; buffering does not
advance the result producer or renew its timeout. Owner/preparer loss or expiry
closes the actual owned group.

Session independently reconstructs the actual request from its committed parent,
last action result or current output cursor. It derives the complete inherited
dependency union, including explicit reads, and matches the actual Worker,
artifact, publisher, stage, payload, request ID and immutable frame. A durable
`worker_input_intent` binds these hashes before delivery; it does not duplicate
the payload or lend the worker a journal handle.

Paged output reserves its managed input records together with the source
transfer. Intent, optional root transition and delivery result use that actual
output token; unrelated reservations cannot consume their allowance. Other
initial/action inputs keep ordinary journal admission. This resource budget
supplies no source authority: the same fresh dependency, owner and immutable-frame
checks still precede every page request. See
[publication capacity](extension-invocations.md#reserve-capacity-and-commit-publication)
for the distinct source-byte and journal limits.

Keep that union when the newest result is independent evidence. If an invocation
first reads managed note A, then quotes fresh input B, its next `host.actions`
frame still inherits A. Losing A's original journal after B commits must withhold
that frame; B's known successful quote remains recorded. A separate invocation
that never reads A can capture current B while A's journal is unavailable. A
metadata-only root observation supplies its own guard without asserting current
eligibility for every stored record or requiring their unused source journals.

The original tracked file-effect publisher acquires current source and policy
owners through `ManagedUse.with_worker_dependencies/3`. `Runner.SessionSource`
transfers the consuming Session's retained flock, Session control and drained
Writer control, together with every inactive original source group, into the
same native transaction that receives Worker stdin. Active proofs remain bound
to the Writer snapshot. Even a metadata-only request retains the consuming
Session owner. No synthetic terminal or approval is involved in this typed
input purpose. Ordinary effect approval remains separate.

Within each of its two independent protected observations, the Worker-input
path groups version-4 literal dependencies in their original relative order,
including those separated by other versions. It requests at most 32 at a time,
using `ObservedRead.managed_record_pairs/5` to read two literals per actual native
Collection owner. Each pair closes before the next; all pair roots must agree.
It closes these scopes before observing other versions and reconstructs the
complete result and proof union in the original dependency order. Every selected
read still checks the exact current native root and each record's signed metadata,
recipe and source policy. The second observation reacquires current authority
and must reproduce the first; the final retained Collection owner must match
every observed root before the input can be delivered. Other managed-use paths
retain their per-dependency observations.

Grouping changes internal read and failure order while preserving current-authority
checks. Each pair retains the native 32-unit ceiling: two 13-unit literal reads
fit within it. This path uses native Blocks limits and does not use ReadView's
4-MiB encoded cache or the document reader's 512-unit allowance. The
DomainAuth capability remains shared across all records and versions in a
protected pass, with its existing 128-verification, 1-MiB input and five-second
limits. The separate 128-source-owner bound does not imply that 128 signed
records fit within those limits. Owner loss or unconfirmed cleanup still
withholds the input; no batch or cached view grants a later use.

After pipe settlement, every source/control scope must close and Writer must
thaw before Session commits `worker_input_result: delivered` and the publisher
awaits the buffered callback response. Computation runs outside those locks,
under the original callback timer. Failure after preparation remains unknown;
an acknowledged write alone does not establish successful scope settlement.
A source change before a nested model or decision helper dispatch sends no helper
request. Its failed action is still committed, but returning that action to the
Worker requires the same inherited source union. If that input cannot settle,
the turn stops with an unknown input; neither a callback nor a later main-model
request follows. Request admission can already exist without network dispatch,
so preserve partial accounting rather than inferring zero liability from zero
helper requests. When the Worker has already completed, the separate model-history
projection can instead withdraw its historical content and continue with a notice.
That projection cannot authorize another input to the unfinished Worker.

Saved validates the parent, action chain, exact reconstructed request and complete
dependency commitment chronologically. An interrupted intent marks lineage
unavailable and reconstructs no handle, timer, permit or automatic delivery.

The narrow own-write metadata transition described above also applies here.
`worker_input_root_transition` binds the original input intent and unchanged
deadline to its authenticated own successful capture and exact adjacent root.
It preserves original payload/dependency records and only resolves their
historical root mapping for a freshly reacquired guard. Only authenticated
metadata members receive that mapping; signed-record members remain unchanged
and are revalidated before the actual frame write. A new pending proposal cannot
discard an earlier recalled literal. Source loss or revocation after a known
publication can therefore leave the capture settled while its next input remains
unknown. Mixed metadata roots, scans and unclassified metadata cannot acquire
the transition.

The Worker-input path supports dependency versions 3–7. Version 7 identifies a pending
proposal only for the separately admitted shadow-assessment path; it does not
make that proposal a current note. For accepted decisions,
`PendingAcceptance` authenticates the immutable acceptance links and retains
each original committed management journal outside the policy owners. Its
same-process tokens are bound to those exact links. The sink imports all of
those journal descriptions alongside the original Session sources, consuming
Session flock and controls; journal settlement precedes source/control close
and Writer thaw. Duplicate links share one journal owner; conflicting identities
for one journal refuse. Inactive original Session groups and management journals
share the existing 128-entry reserve and native bound, in addition to the one
consuming Session description. Missing owners or unconfirmed close withhold
delivery. Worker input and ordinary native tool approval use separate retained-owner
adapters; each preserves the original journals and leaves effect permission separate.

Other Worker entry points have no admission through this export adapter.
Managed presentation refuses before transform intent/start; private notifications
remain known unstarted, private tool feeds close before queue admission, and
selected text consumers stop the dependent managed model request. Their ordinary
and metadata controls remain separate; see [event delivery](extension-events.md)
and [text ownership](lifecycle-events.md#enroll-visible-text-consumers-before-dispatch).
Nested managed service calls retain their effect gate. A pinned
export's committed native-tool and MCP results can use its ordinary
`host.actions` continuation: effect permission stays separate, the full inherited
union remains attached, and this adapter fences the exact result before stdin.
Native-tool progress previews use the fixed status-only message
`Managed tool result withheld from terminal preview.`
A root change or revocation after the effect can therefore leave a known
successful action and an unknown input without another VM callback. Inspect the
effect before deciding on new work; idle resume repeats neither. Managed
document-store result delivery and other unqualified purposes remain gated.
The [native protocol](../../native/README.md#direct-stdio-server-transport) owns
its frame details; [verification](testing.md#exercise-actual-os-policy-and-native-protocols)
distinguishes component faults from actual Session qualification.
The [managed read adapter](collection-sdk.md) checks current consent, recipe,
deadline and signed collection root while those source locks remain held.
Its result becomes historical after return; later use needs revalidation.

## Retain sources through a protected display or review

For a strict display adapter, `ManagedUse.with_display_dependencies/3` first
rederives the complete current dependency/proof union, then retains transferable
inactive source locks and the actual Identity, Consent and Collection owners.
Its final held Collection root must equal every authenticated observation; a
root precheck followed by an unlocked callback is insufficient. The callback
receives the three owner-bound capabilities, exact proofs/group tokens, whether
active sources need the separate Session share, and a deadline bounded by policy,
source validity and five seconds. Callback failure, owner loss or a late result
after entry stays unknown. Opaque tokens cannot be used after callback cleanup.
Accepted-decision dependencies refuse this generic preparation path. The narrow
`ManagedUse.with_approval_dependencies/3` entry additionally authenticates and
retains their original committed management journals, as does the separate
Worker-input adapter. Other displays cannot acquire that support by selecting
dependency version 6.

This callback displays nothing and grants no approval. `Session.ManagedApproval`
binds an ordinary model's pending call or an extension's pending action, complete
arguments, dependency union and full escaped payload to a private terminal purpose.
For an extension it additionally commits the original parent and action digests.
The original Host task performs the native wait inside tracked file-effect work;
only that same task/job can return its private completion to Session. Public
approval references and worker JSON cannot supply that completion. Session chooses the payload and native Port; workers cannot select them.
Its actual Writer drains and seals active proofs and inactive source-lock
identities before the original Session lock, all three policy owners and every
inactive source group reach the same native display. For accepted decisions,
Session derives required management-journal IDs from its pending dependency
union. Writer snapshots those private lock inodes together with inactive Session
locks; Session requires the manifest's exact combined count and inode set.
`LeasedTerminal` binds each actual journal token to its immutable acceptance link,
exports it to that same native receiver and settles it alongside the source
groups. The combined set stays within 128 original-owner entries. The complete
display is limited to 64 KiB and refuses rather than truncating.

Writer remains frozen under its owning Session through display and settlement.
The native Session/Host control descriptors guard the display; the separate
export/root-decision path described above also transfers a Writer control.

`Runner.LeasedTerminal.begin_approval/5` confirms native display completion,
every exporter settlement and the Session notice before thawing Writer. It returns
an opaque same-process handle inside an enclosing file-effect owner that remains
alive through input. Only after the source and policy scopes release does
`finish_approval/2` release native input. The helper watches Session/Host controls
through that bounded 120-second phase; settled source exporters may now exit.
The host reserves one millisecond when translating quantized BEAM remaining time
to each native display and overall deadline. That prevents the demonstrated
rounding excess when the clocks advance compatibly; it does not establish equal
clock rates or suspend behavior between BEAM and the native helper.
Only the exact fresh `allow CODE` confirms one attempt. `/cancel` and `/exit`
use the ordinary Session cancellation path and discard queued prompts; exit also
closes the terminal interaction. Other text denies the proposal;
unconfirmed display, input or cleanup grants nothing. A poisoned exported share
stops the owning Session. The eventual tool still reacquires current managed
authority through `ManagedToolUse`; displayed bytes and an answer are historical
by that point, and resume never reconstructs an approval grant.

When the consuming Session also owns an original source, approval's post-display
check runs after Writer thaw under the exact pending approval binding. It must
return the same selected proofs. Later, publishing the bound tool result adds
outcome sources to that same index. `StoredSources` permits the global generation
to advance only for `tool.result`: every selected proof, window identity and
policy generation must still match after fresh resolution. Redaction, a policy
fence, window replacement or generation rollback withholds the result. Approval
and effect scopes still require exact index-generation equality. The active-source
native journey checks successful result continuation as well as the physical write.

For interactive `/correct` and `/supersede`, `OperatorAssertion.parse_intake/1`
first prepares a new statement/category endorsement. `ManagedSupersession` then
records its exact relation intent and performs the full-facts review inside the
actual tracked file-effect publisher. There is no proxy process supplying review
authority. Session's typed relation ticket rederives the pending purpose, facts
and complete active/inactive proof union, chooses its own payload and fresh
challenge, and issues the native v13 terminal. `LeasedTerminal.begin_relation/6`
retains the same source and policy owners through display and settlement as
ordinary approval. Its opaque handle survives their release; only the same
process can finish input. `Review.with_session_input/4` checks the actual native
observation and mints the one-use relation permit. The 30-second lifetime begins
when native input returns, before terminal cleanup, without renewal.

The publication callback reacquires sources, Identity, Consent and Collection,
rederives the old signed record and exact root, and journals the fresh review.
The trusted supersession normalizer consumes the permit. Collection's private
`execute_reviewed_supersession/7` then claims that consumed permit for the exact
intent, original request, normalized mutation and normalization receipt. A
second claim refuses. Its finite deadline is the earlier of remaining review
time and the normalized publication deadline. The host converts the remaining
BEAM-monotonic review lifetime to a wall cutoff for the later switch; that
conversion does not establish strict BEAM-monotonic expiry at the switch if the
wall clock moves backward. Treat interrupted or uncertain outcomes as unknown,
and do not interpret this cutoff as a proven cross-clock lifetime guarantee.

`Runner.SessionSource` transfers the actual Session control, original Session
flock and drained Writer control into the existing native transaction owner.
Every inactive original source group must match Session's authoritative proof
set and reach that same native root decision. The final effect rechecks the
claim under these retained owners; no serialized receipt or worker-selected
lease can substitute. Settlement closes the sources and controls before Writer
thaw. Ownership or cleanup loss remains unknown, including after a physical
root switch, and a poisoned exported share stops Session. Saved reconstructs
the historical intent/review but never replays the mutation or mints a permit.
An explicitly reopened Session can remain idle after such loss.

Expiry after staging can refuse the native root decision while the transaction
is still live. The overall attempt remains unconfirmed because staged storage
already changed. Its full publishing liability stays retained; read-only inspection
does not settle it, and reconciliation requires an explicit trusted-host decision.
The native deadline control requires the exact elapsed
reply and unchanged selected root, then checks idle recovery without replay.
It pauses before the decision and establishes no physical completion deadline
for a switch already admitted before expiry.

Run `managed_supersession_session_test.exs` for actual statement/relation reviews,
ordinary and temporal replacements, cross-session source locks, cancellation,
revocation, missing originals, shared lifecycle and no-replay recovery. Its
`pin_history` case performs public native pin, temporal replacement and successor
forgetting, then authenticates the retained persistent history. Its far-future
eligibility check is an explicit pure as-of calculation, not elapsed-time or
annual native qualification. Its
post-switch owner-loss case uses an explicitly instrumented child host installed
before permission review; this gives deterministic fault timing, not independent
production or quality qualification. Accepted-decision v6 targets remain outside
this literal-record adapter. Follow the
[operator procedure](../operator/knowledge-permissions.md#correct-or-supersede-a-native-note)
for the two distinct confirmation commands.

The ordinary reader keeps its input generation across the handoff. `Session.Input`
cancels its prior read and confirms native restoration before display begins;
registered-reader retries receive busy while approval owns the terminal. Release
tickets are one-use, expire after five seconds and are bounded to 64 globally and
one per target. A cancellation that completes before its client starts awaiting
retains a bounded cancellation acknowledgement, rather than becoming a channel
failure. No full approval arguments go through subscriber status events.

Delegation, managed question displays and clients without the native channel
retain their refusal paths. Nested action approval reuses the same native display
and owner settlement, then commits its approved or denied action through Invocation.
MCP discovery remains separately fenced before approval. A current effect can
continue through the export-input adapter. Root change or revocation during input
can refuse an MCP or inference request, then leave its failed action's next input
unknown. An unknown native write instead stops Host before another input is
prepared: retain that unknown action without inventing a delivery attempt. These
are separate uncertainty fields, and neither permits automatic replay. Run the
`managed_display_owner` cases in `managed_collection_call_session_test.exs` for
held root/policy owners, `save_display_owners` for actual reviewed sources, and
the `managed_approval` controls in `operator_assertion_integration_test.exs` for
the production adapter. The latter use native statement sources and a synthetic
local model route: they cover fresh/active/resumed writes, denial/stale code,
cancellation/exit, delayed input, changed source, revocation and Session loss,
with Saved and request accounting checks.
The separate accepted-decision fixture in
`knowledge_session_test.exs` covers native approval/denial, actual source and
management-journal descriptors at display, and journal-owner loss before display.
The loss must stop the poisoned consumer with no tool start; strict Saved and a
fresh idle resume must preserve its history without replay. These synthetic
source controls establish no independent human, live-model or installed result.

A resource scope reserves 128 source-lock entries, shared by inactive original
Session journals and acceptance-journal reads, including transferable ones.
Bound the complete set when combining them. These locks have a separate reserve from the ordinary
32-resource registration limit, so source verification does not itself consume
the slots needed for the protected transaction or other live resources. The
existing controlled-child path can add up to 32 child entries separately;
those entries count against subsequent ordinary registrations. These limits are
per scope, not a machine-wide concurrency guarantee. When a source lease or its
owner is lost, current use refuses and cleanup releases the retained locks.

## Construct a candidate proof without granting authority

An independent worker can call the public SDK helper after a successful read and
quote:

```elixir
{:ok, proof} = Ipse.Extension.source_proof(evidence, quote, "café")
14 = map_size(proof)
```

This continues the synthetic example above. The helper checks exact page/quote
identity, bytes, offsets and hashes; it returns stable evidence JSON, not a token
granting an effect. Protected publication independently rederives each proof from
the current writer window. Original input, native operator answers, reviewed
operator statements, visible assistant answers and typed tool-outcome metadata qualify for this
generic proof step. Source stdout, file/external content, decision advice and
legacy text refuse capture proof resolution even when public reading succeeds.
File capture requires an original validated path receipt, not a path inferred
from output prose. See [the collection workflow](collection-sdk.md#build-evidence-with-the-public-sdk)
for its closed proof and request shapes.

## Verify a changed source boundary

```sh
mix test test/ipse/session/operator_assertion_test.exs test/ipse/session/operator_assertion_integration_test.exs
mix test test/ipse/session/source_index_test.exs test/ipse/session/source_window_test.exs
mix test test/ipse/extension/source_read_test.exs test/ipse/extension/source_read_session_test.exs
mix test test/ipse/journal/source_window_test.exs
mix test test/ipse/journal/source_origin_test.exs test/ipse/session/stored_sources_test.exs test/ipse/session/managed_reads_test.exs
mix test test/ipse/session/source_lock_capacity_test.exs test/ipse/session/source_lock_resource_budget_test.exs
mix test test/ipse/cli/operator_input_test.exs test/ipse/session/question_eof_test.exs
```

The native CLI tests use serial synthetic PTYs and actual restoration receipts;
they establish no human attribution or untested-platform guarantee. Session/SDK
fixtures cover 64 typed receipts without inline source text, cancellation, exact
Unicode/repeated quotes, capacity, append refusal, caller leases and inert resume.
For an admission change, remove a successful publication record while retaining
its private source and require no readable content. For a reader change, alter
returned source bytes and superficial hashes; replay must still reject the page.
Run the existing reference wire/history/lifecycle suites alongside the source
owner's regressions. [Testing](testing.md) owns the complete handoff baseline.
