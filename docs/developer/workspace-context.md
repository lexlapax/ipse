# Construct and reduce active context

Context is a projection of retained evidence. [`Workspace`](../../lib/ipse/workspace.ex)
owns instruction discovery and the saved skill catalog.
[`Session.Context`](../../lib/ipse/session/context.ex) constructs provider messages,
plans reductions, records runtime facts, and measures encoded context. Session
admits and commits each change. [`Session.Saved`](../../lib/ipse/session/saved.ex)
reconstructs committed projections without new inference. The journal keeps the
original evidence.

[`Session.Reference`](../../lib/ipse/session/reference.ex) owns the versioned
relationship between the admitted header, ordered tool catalog and subsequent
reference selections. Read it alongside Context; changing placement changes both
provider caching and saved reconstruction.

Workspace text tells Ipse how a project wants work done. It grants no credentials,
tools, or OS authority. Explicit operator requests take precedence; nearer project
instructions override broader project guidance, with user defaults beneath them.

## Discover instructions and observe drift

Read `Workspace.snapshot/2` and `test/ipse/workspace_test.exs`. Discovery canonicalizes
the launch directory and validates repository/worktree pointers. A Git directory
needs regular `HEAD`; outside Git, the selected directory is the boundary.
It reads `IPSE_HOME/AGENTS.md`, applicable boundary-to-workspace instructions,
and workspace README. One level of local Markdown references can contribute
`.md`, `.txt`, `.adoc`, or `.rst` text within that boundary.

No referenced script executes and no arbitrary remote link loads. Absolute/outside
references, symlinks, and sensitive path components such as `.git`, `.ipse`, `.ssh`,
`.aws`, `.codex`, `auth`, `secrets`, and `tokens` are excluded. A UTF-8 source allows
32 KiB; a snapshot allows sixteen sources and 128 KiB total. Optional absence is
normal. Invalid/inaccessible/oversized sources yield bounded diagnostics. Retain
path, scope, kind, and SHA-256. These checks do not defeat hostile concurrent replacement.

Run this complete drift exercise in `iex -S mix`:

```elixir
scratch = Path.join(System.tmp_dir!(), "ipse-context-exercise-" <> Ipse.Usage.id())
workspace = Path.join(scratch, "workspace")
home = Path.join(scratch, "operator")
File.mkdir_p!(workspace)
File.mkdir_p!(home)
path = Path.join(workspace, "AGENTS.md")
File.write!(path, "Use a scratch fixture for the example.\n")
{:ok, saved} = Ipse.Workspace.snapshot(workspace, home)
[] = Ipse.Workspace.drift(saved)
File.write!(path, "Review the changed fixture before continuing.\n")
[_] = Ipse.Workspace.drift(saved)
true = Enum.any?(saved["sources"], &(&1["content"] == "Use a scratch fixture for the example.\n"))
File.rm_rf!(scratch)
```

The saved snapshot retains original text. Drift detection adopts nothing.
Session records `workspace_context_snapshot`; malformed saved snapshots refuse
recovery. Read the Session counterpart before changing discovery, because pure
path tests cannot establish approval/intent ordering.

## Adopt deeper guidance and refresh atomically

Before file-tool execution or approval, nested-target preflight can discover new
scoped instructions. Session syncs the new snapshot, settles the old proposal
not started, and asks the model to reconsider with that context. That call gets
the specific diagnosis; later queued calls stop generically before execution.
Approval remains `not_decided`. A revised mutation needs its own approval.
Shell strings can hide targets, so this cannot certify every reachable directory.

Resume uses the saved selection and reports drift. `/context refresh` performs
owned idle work and commits instructions plus skills together. Cancellation must
not save half a refresh. Configuration and extension code are not reloaded.
The skill catalog permits 256 entries and 256 KiB of encoded names/descriptions,
canonical paths, digests, and shadowed provenance, without bodies. Loading a body
or resource rechecks path/digest. Drift refuses until explicit refresh. Older
journals acquire their first catalog at a model boundary, never idle inspection.
`/context` and `/skills` show saved values; standalone `ipse skills` discovers current files.

Discovery and loading accept bounded regular `SKILL.md` files; FIFOs, devices,
directories and leaf symlinks are omitted or refused. Prompt-time `$skill`
expansion runs in an owned task before Session commits a user message. The
owner remains available for cancellation, which settles the pending prompt
caller and stops the task without adopting partial text. Verify both the FIFO
and regular-file paths with `test/ipse/workspace_skills_test.exs` and
`test/ipse/session_test.exs`. As with instruction discovery, these path checks
do not defeat hostile concurrent replacement.

Core rules remain system text. Workspace references, skill metadata, and extension
contributions use labelled user-role reference messages. Explicitly requested
skill bodies stay in their requesting turn. Placement does not promote reference
text into a new task or authority.

## Admit a header and append current references

New sessions record `reference_layout: "turn_reference_v1"`. Session seeds the
initial rules, instruction snapshot and skill catalog before callbacks can publish
context. At the first model boundary it durably admits that two-message header
and the digest of the ordered tool definitions. Reported response identifiers
are mutable metadata, so the system header explains how to read their current
reference fields instead of freezing a last-response claim. Both identifiers
start unavailable.

Before each main dispatch, compare the runtime, workspace, skill catalog and
extension publishers with their admitted values. Changed selections append as
labelled user data after the existing history and complete native tool group.
No selection uses a system/developer role or a fabricated tool result. Unchanged
same-turn continuation adds nothing. Each later real user turn repeats the full
current selection when one is active, so retaining the latest two real turns
also retains its current references. An empty selection explicitly clears a
previous override; fields absent from that selection use the admitted baseline.
Prior selections retain their original historical positions.

`reference_admitted` binds header bytes, publisher baseline hashes, catalog hash
and epoch. `reference_envelope` binds session/turn, effective-message position,
source/policy generations, and exact content hash. Generic policy generation is
currently zero. A source generation advances only when the selected values change.
These are consistency/provenance checks, not evidence that an assertion is true
or still current. `reference_refresh` stages a reviewed `/context refresh`;
the next admission establishes a new header/catalog epoch. Compaction records a
new `reference_epoch` while retaining that epoch's header/catalog bytes.

The saved-result reader is declared from the first request even before any source
exists. A newly discovered MCP catalog that differs from the admitted digest stops
dispatch; explicit context refresh or a fresh session is required. Availability
of a fixed tool never grants approval to call it. Legacy journals without this
layout marker retain their previous header placement and conditional reader
declaration; resume does not migrate their provider history.

Saved reconstruction preserves the recorded order of completed native results,
including clarification answers delivered after another result in the same batch.
Only a genuine new user boundary, or final interrupted-history reconstruction,
adds missing unknown outcomes. A reference/checkpoint cannot manufacture that
boundary, split a group, or hide an orphan result. References count toward context
bytes and summaries but never become pinned operator requests. The admission
records are private journal records, without lifecycle-feed source projection.

`Turn.start_question` validates new batches with `Questions.validate_new` before
opening an operator wait. Questions with the same prompt, kind, ordered option
labels and descriptions return an invalid-arguments tool result to the model;
wire IDs, recommendations and omitted versus null optional fields do not change
that identity. `Questions.validate` still accepts
previously recorded batches under the original schema so saved conversations
remain replayable. The new check does not deduplicate reworded questions or
compare earlier turns. For the current visible user turn, `repeated_answer?`
also matches a validated `ask_operator` call to its recorded answer and refuses
the same question in a later round using that identity. It does not infer
equivalence between reworded prompts or establish complete history
after compaction. New dispatch uses this check without changing replay admission.

## Withdraw draft intent before ordinary work

The CLI's `--planning` option selects the Session planning ceiling at startup.
At an idle native-terminal prompt, `/plan` also requests a witnessed restrictive
entry. The Session consumes the exact staged command, refuses unconfirmed work
or cleanup, invalidates other input tickets, and writes a version-2 mode
checkpoint, a new MCP epoch when declarations exist, and an observation-bound
entry receipt before reporting success. `PlanningTransition` validates the
receipt against its checkpoint. A crash before the receipt can leave a
restrictive checkpoint without an entry receipt.
The current entry path refuses unresolved drafts or active extension feeds;
cancelled and fully consumed drafts can remain in history. Do not infer that
idle alone proves every resource was drained.
`Config.runtime` captures it with the approval origin. For a resumed Session,
`Mode.resume` retains the saved active and enclosing ceilings separately;
`Mode.inherit` still folds the parent's ceilings into a child's enclosing floor.
A changed resume mode uses a version-2 checkpoint bound to the previous mode
after the Session lock is acquired. Replay retains version-1 checkpoints, which
may already have merged those ceilings; it cannot reconstruct missing origin or
an earlier restriction that was never recorded. An older Ipse build that does
not understand version-2 checkpoints refuses that history; retain the current
runner for recovery. Neither mode field alone authorizes an in-session exit.
`/plan exit` requires a fresh observed command and replayed local-entry
provenance. Explicit CLI startup selection is bound to a new session header or
to the normal-to-planning resume checkpoint; repeating the flag after an
ambiguous historical planning selection does not reconstruct its origin. The
resulting exit record changes only the local ceiling and preserves
current approval, knowledge and enclosing floors. A version-1 checkpoint after
entry discards that provenance. Entry or exit invalidates staged input, and an
exit with declared MCP reads must commit a new epoch before dispatch resumes.
If journal capacity ends between a transition and its epoch, replay accepts the
valid terminal limit receipt for inspection while rejecting later work. The
sealed journal cannot resume; use a fresh-session handoff. A checkpoint without
its entry observation does not create local exit provenance.
`Session.info` exposes the effective active and enclosing ceilings so the
terminal describes the actual resumed policy. `Permissions.new` cannot activate
an edit grant under that ceiling. An inherited or unrecorded planning ceiling
does not by itself authorize exit.

For an operator-authored decision, `/plan decide TEXT` consumes the witnessed
command and renders a separate `accept CODE` review. `PlanningDecisions` records
the exact accepted text, both native observations and the local planning-entry
digest. The receipt is not admitted to `SourceWindow`, so it is not by itself a
saveable source or a collection mutation. Plain `/plan exit` marks the matching
local entry exited without publication. `/plan decisions` reports the retained
IDs; chronological replay checks the entry, observation uniqueness and exit.
`/plan decide-assistant EXACT_QUOTE` instead selects a unique quote from the
latest committed answer under that local entry. `SourceWindow` revalidates its
`answer.original` proof against the matching turn and request. The native
review records the assistant origin and both witnessed inputs; it does not
publish. The Session permits no managed dependencies except authenticated,
same-root metadata observations classified by the existing root-only predicate;
presentation transforms and after-turn subscriptions are refused. Replay
reconstructs that classification against the validated admission and cached
host observations. These historical facts do not grant current-use or publication
authority. A new user turn invalidates this particular selection.

After exit, `/plan save ID` for an operator-authored decision begins the existing
native assertion review for that same text and ordinary category. The Session checks its current permission and
source-window binding again when the review is confirmed. It records a one-shot
save-start intent before admitting an `operator_assertion` event that includes
the original planning acceptance. The derived source proof hashes the full
assertion event. Existing protected capture verifies that source and consent
before publication. Replay requires the earlier accepted
receipt and save intent, refuses duplicates and never starts another capture for
an interrupted attempt. A confirmed refusal before worker start is recorded
separately from an uncertain attempted save; neither automatically retries.
For an unresolved assertion, replay treats any later extension invocation as a
conservative fence against recording an unstarted refusal; it does not attribute
that invocation to the decision. A save-start status proves the intent was
recorded, not that a worker started.
Cancelling the second review before the save intent leaves the decision available
for another explicit review. The resulting record is an operator-authored literal.
For an assistant decision, the post-exit review instead journals a witnessed
one-shot staging intent with the original proof and destination. The existing
protected capture produces a pending proposal with that proof, and standalone
native knowledge review independently confirms any resulting accepted decision.
Replay authenticates the earlier selection, current source and both staging
observations; an interrupted stage is never replayed automatically.
After a resumed pending draft is cancelled or consumed, `PlanningMCP` replay
returns from the temporary draft mode to the persisted startup mode; completion
alone does not exit the draft. Check both an ordinary continuation and one that
retains an enclosing planning ceiling when changing this path.

The terminal's `/enhance` path uses the same Session and ordinary main route.
`Session.Draft` owns bounded draft/revision transitions and exact interval
projection; `DraftAcceptance` binds the proposed text to a freshly rendered
native-terminal observation. The complete `/enhance TEXT` line remains the
original witnessed input; the host removes its command prefix only when building
the effective drafting instruction. Version 2 asks the model to check available
context before material questions and to identify required missing information
when clarification is unavailable. This is guidance, not proof that retrieval
or clarification occurred. Replay recomputes the transformation using the
recorded version; version 1 retains its original instruction.
Older builds that only recognize version 1 refuse version-2 draft histories;
use a build that understands the recorded version to resume them.
Inline replacement similarly binds the complete terminal command to its input
observation. `Draft` recomputes the trimmed replacement on replay, and
`DraftAcceptance` rejects reuse of that observation. The `multi` command remains
reserved for multiline entry; a literal `multi` replacement uses the next-line
form.

Trace `start_draft_observed`, `Turn.draft_prompt`, and `consume_accepted` together.
Draft configuration narrows the active execution ceiling while retaining the
enclosing ceiling and ordered tools. It limits drafting to three model requests
while preserving the selected route's transport, reasoning and token settings.
`Provider.Transport` bounds the entire response, including SSE framing; this is
separate from `Draft.text?/1`'s 32,768-byte UTF-8 proposal bound. A successful
provider response with an empty or oversized proposal makes `Turn.finish_draft`
report a failed turn without recording `draft_completed`. The original assistant
message and completed provider accounting remain retained. A partial transport
failure instead keeps its ordinary unknown-liability accounting.
Dispatch denies mutations and external
callbacks; approval flags cannot widen it. Acceptance journals the exact revision
and provenance before submitting its proposal as a new ordinary turn. Cancellation
journals an exact message-interval digest and then a neutral host notice. A crash
between those writes blocks ordinary work until explicit cancellation completes
the notice; no inference is replayed.

`Draft.project` validates the original prefix, segment, reference occurrences and
native tool grouping before withholding the interval from later dispatch.
`Saved` repeats those checks chronologically and validates rebasing before
compaction. The original journal remains intact. ChatGPT uses the stateless
Responses isolation validator. Ollama also permits a complete no-tool draft
interval when each removed native assistant message has the exact shape checked
by `DraftNative.ollama_draft_without_tools?/1`: visible and native text match,
thinking is a bounded UTF-8 string, tool calls are empty and unknown fields refuse.
The whole interval, including thinking, is withheld; native messages outside it
are preserved unchanged. The separate `plain_text_only?/1` predicate remains
stricter for managed lineage and reference checks. Anthropic uses
`DraftNative.anthropic_draft_without_tools?/1` for exact native text blocks whose
concatenation matches the visible UTF-8 content, optionally interleaved with
bounded thinking blocks with a nonempty, structurally checked signature. The
signature is not authenticated here. Its ordinary Stream item bound still applies.
Redacted thinking, tools, unknown fields, unsigned thinking and mismatched text
refuse; the validator never strips a native field to fit. Signed thinking is
withheld with the whole draft interval and remains in the private journal.
Each policy requires complete tool grouping in the prefix, removed interval and
tail. Native messages outside the interval stay unchanged.

Live projection selects the policy through `DraftNative.policy/1`; Saved's
historical selector uses the original provider in the session metadata for both
chronological and final reconstruction. Add the corresponding historical selector
when introducing a native policy. Unsupported continuation refuses projection
instead of dropping fields. Verify cancellation, an unrelated ordinary request,
confirmed close and the same-ID continuation, checking the actual wire and strict
Saved reconstruction. A live-only check cannot establish replay compatibility.
`DraftHistory` produces bounded withheld ranges for extension history reads, and
`SourceWindow` excludes draft material from eligible evidence. Pending drafts
cannot be exposed through an ordinary history page.

`DraftLineage` conservatively retains accepted input, answer and read-evidence
links across later turns, compaction and extension requests. These links establish
intent provenance, not current knowledge eligibility or effect permission.
`DraftMCP` pins first-use discovery to the admitted tool catalog and requires
fresh matching discovery when a pending draft question resumes. Setup intent
precedes starting a configured server; an interrupted result is never replayed.
An operator-only planning-read declaration binds a selected tool to its reviewed
endpoint and descriptor. `MCP.Planning.declared?/2` checks that binding; `Turn`
separately requires the applicable approval, a current catalog and available
draft evidence tracking. The MCP adapter re-discovers the descriptor before
dispatch. Undeclared tools and extension callbacks remain unavailable in drafts.
`Session.PlanningMCP` validates restricted-start replay against the recorded
catalog, declaration and model call. Sessions with declarations record a
declaration-bound mode checkpoint at startup and resume. Before a restricted
read, `Turn` writes the checkpoint-bound planning intent and the ordinary tool
start before launching the owned task. A lost response remains unknown.
Session startup and resume compare the declaration map itself with its
configuration manifest, in addition to the existing fingerprint comparison.
In those sessions, ordinary MCP starts also carry a checkpoint-bound intent;
replay checks it against the recorded call, catalog and server selection.

Practice the complete transitions with synthetic providers and a native PTY:

```sh
mix test test/ipse/session/draft_vertical_test.exs test/ipse/session/draft_projection_test.exs
mix test test/ipse/session/draft_response_limits_test.exs
mix test test/ipse/session/draft_acceptance_test.exs test/ipse/session/draft_native_test.exs
mix test test/ipse/session/draft_lineage_test.exs test/ipse/mcp/catalog_session_test.exs
mix test test/ipse/session/planning_decisions_test.exs test/ipse/session/planning_decision_native_test.exs --max-cases 1
```

After the required build, the planning-decision tests exercise replay and
one-shot status plus synthetic PTY save, refusal and resume boundaries. They do
not establish installed or independent-human use.

To exercise the Ollama no-tool acceptance and cancellation paths against a
built package, record the expected archive hash and commit label independently.
Use a new private output directory and retain the adjacent checksum sidecar:

```sh
IPSE_DRAFT_ARCHIVE=/absolute/path/to/ipse.tar.gz
IPSE_DRAFT_PROOF_ROOT=/absolute/private/path/new-draft-proof
IPSE_DRAFT_ARCHIVE_SHA256=replace-with-recorded-64-character-sha256
IPSE_DRAFT_COMMIT=replace-with-recorded-40-character-commit
elixir dev/verification/ollama_draft_installed.exs \
  "$IPSE_DRAFT_ARCHIVE" "$IPSE_DRAFT_PROOF_ROOT" \
  "$IPSE_DRAFT_ARCHIVE_SHA256" "$IPSE_DRAFT_COMMIT"
```

The verifier needs a Linux native PTY, Rust compiler, precompiled ExUnit and
loopback access. It runs the existing synthetic terminal fixture against the
packaged Session, terminal and Ollama adapter. It checks the release inventory,
the fixture's draft-thinking canary stays out of terminal output, and the saved
continuation after an idle reopen.
The package commit label is not source-provenance proof. Preserve the private
output on failure; terminal logs contain synthetic acceptance codes. This
fixture does not run the installed chat command or establish independent human
use or live-model behavior.

Check zero file effects under existing grants, stale acceptance, exact original
command bytes, question provenance, canary absence after cancellation, changed
MCP catalogs, owner loss, truncated boundaries and inert resume. A PTY proves
the operator channel protocol, not that a person used it. These tests establish
neither live provider quality nor protected knowledge retrieval.

## Page admitted evidence without inline context

Use [Session sources](session-sources.md) to follow the committed source projection,
its native tools and explicit SDK grant, exact quotation matching, bounded coverage
and saved reconstruction. Source reads work without inline source text. Compaction
changes effective context without replacing the admitted original source bytes.
Source attribution grants neither truth nor execution authority.

For changes to managed knowledge projections, start with the pure
[`Session.ManagedReference`](../../lib/ipse/session/managed_reference.ex) contract.
It checks normalized host receipts, complete dependency unions, exact historical
projection and replay. Constructing a dependency establishes no live freshness
barrier. `ManagedReads` binds
actual committed host reads; `ManagedLineage` derives their complete downstream
union, and `ManagedUse` revalidates supported uses under current owners. Follow
[managed read and downstream use](collection-sdk.md#revalidate-reads-and-downstream-use)
for the execution path and its remaining integration gates. A valid
receipt-shaped map alone grants neither permission nor current eligibility.
For a reference producer bound to this Session, withdrawal can also replace
a valid, parseable `ipse_reference` message with a notice. The projection
preserves the reference identity and role while updating the content hash; it
leaves the original journal unchanged. Other unsupported markers or malformed
references still refuse. This historical projection does not establish current
source eligibility or grant permission for later use.

Version-2 dependencies distinguish a record from an absence selector. A record
has its exact key/revision/value digest and host-derived validity. An absence
names either one exact missing key or a genuinely empty collection. It has no
invented note lineage, source version or expiry. A filtered or truncated scan
cannot claim that the collection is empty. The collection receipt separately
binds `root_state`: `absent` requires generation/floor zero and null root/manifest
digests; `present` requires both real digests, including for a materialized empty
store. Imported destructive floors may exceed local generation.

For raw status, snapshot, partial scan or search output, a version-3 root
observation instead binds the host's exact request and committed result hashes.
It does not invent record validity or claim that a filtered result proves the
whole collection empty. Its eligibility requires the identical collection root,
manifest, generation and floor; any root change needs a new actual observation.
An arbitrary worker-supplied observation is not evidence of that read.
`ManagedReads` creates the host receipt from the actual committed result, and
Session inherits it through the registered lineage transitions. Replay verifies
that history without granting current-use authority.

For version-1 and version-2 dependencies, the pure projector likewise requires
the identical collection root. A worker can derive output from the root metadata
as well as the selected record, so an unchanged record alone cannot validate its
old output at a newer root. Direct support references must remain exact, and a
refresh cannot extend the existing expiry; a shorter current expiry is retained
for later checks. A previously suppressed or unavailable record cannot become
eligible through refresh. New observations need their own authenticated
admission. Replay verifies recorded transformations and leaves live eligibility
pending; earlier changed-root projection events now refuse replay. A version-1
null record has no selector, so do not reinterpret it as a version-2 absence or
invent a manifest for an absent root.

An internal version-4 record observation is a narrower experiment: its request
selects one non-metadata key, and its result contains only that complete record
or an explicit absence, without a Collection generation. The pure projector can
compare matching request and result digests at a later monotonic root while
checking the record's validity, supporting references and expiry. It does not
authenticate those digests or establish that the worker saw no additional data.
`Collection.ObservedRead` can produce the record-only value and a separate
same-view root witness, and its internal constructor checks the structural
binding to a supplied pin and validity. It refuses root or record bytes that do
not match their canonical re-encoding. The operation is not exposed to
extension workers, and these structural checks do not authenticate their inputs.
Reuse additionally requires Session-owned durable receipt binding, source and
suppression history, current consent, complete descendant lineage and the
applicable dispatch barrier. Follow the host integration in the Collection SDK;
the constructor supplies none of those owners. A copied or worker-supplied
version-4 object is not evidence of an observation.

For literal notes, the internal managed-record reader can additionally verify
the selected record against signed live and anchor pages through one checked
view. Its returned metadata is historical evidence, not a current eligibility
decision. It binds the supplied literal recipe to the signed live page and
checks that recipe's override key in the same view. The reader authenticates
native retention choices against signed metadata, but refuses retirement and
legacy override records until their semantics are authenticated;
source verification and current consent remain the caller's responsibility.
The managed dependency constructor can derive validity from this metadata and a
supplied exact source proof, checking recipe, lineage and expiry consistency.
It retains the signed historical publication-policy digest separately from the
current consent pin. It does not authenticate the supplied proof or establish a
current lease.
Practice the pure receipt and replay boundaries separately from host admission:

```sh
mix test test/ipse/session/managed_reference_test.exs
```

## Plan a reduction at the model boundary

Follow `Context.prepare_compaction/3`, `finish_compaction/4`, and
`restore_tool_results/2`. The default context ceiling is 400000 encoded bytes,
including system/references. After tools settle, reduction triggers above 80%.
`--context-bytes` permits 8192..16000000; `--no-compact` disables reduction while
preserving hard admission. Encoded bytes are not provider tokens.

The planner selects a complete older prefix, preserving the latest two real user
turns and all associated assistant/tool/native data exactly. It retains older
user requests verbatim in an intent ledger. The action ledger keeps exact IDs,
names, arguments, host approval/outcome, and 256-character result excerpts with
original size/digest/shortened flag. Legacy results remain unclassified; result
text cannot establish approval.

The summarizer receives normalized older transcript JSON under its separate
instruction, excluding opaque/native reasoning from that request while retaining
it in the journal. The reply has exactly three string arrays:

```json
{"decisions":["Keep changes local"],"facts":["The failure is reproducible"],"open_questions":["Which input triggers it?"]}
```

One exact outer Markdown JSON fence is accepted. Extra prose/documents, wrong
fields/types, tools, or oversized content refuse. Summary JSON allows 16000 bytes;
the request must fit context and the projection must shrink below the trigger.
Required ledgers/native data are not trimmed to force success. Structural checks
cannot establish semantic fidelity.

Summary work uses the main selected route and ordinary accounting/budgets. Ollama
summary-only options choose the schema, `think: false`, zero temperature, and a
4096-token ceiling narrowed by configured limits. Normal turns retain their own
settings. Summary deltas never display as assistant output.

## Preserve provenance when shortening tool output

One long turn may have no reducible older prefix. The deterministic fallback
retains every message, user/assistant text, argument, native continuation, and
host fact. It shortens only eligible settled results above 4096 bytes. The newest
two assistant tool batches, including parallel results, remain complete. Unknown,
denied, unclassified, unresolved, duplicate, or already-shortened calls stay full.

Eligible results become explicitly incomplete beginning/end excerpts of 256
characters each, original byte count/digest, and guidance to inspect original
evidence before repeating an effect. This loses result text. It is not complete
semantic preservation. If the whole projection cannot fit below the trigger,
nothing commits. Later summarization retains original provenance rather than
promoting an excerpt to the full result.

## Commit and reconstruct the projection

Session syncs `context_compacted` before replacing messages. Version 1 binds
checkpoint, covered effective-message count, canonical prefix digest, and sizes.
`tool_results_compacted` additionally binds original/projected digests and
deterministic indices. Original events remain durable.

`Ipse.JSON.digest/1` hashes lists with recursively sorted object keys, preserved list
order, and the maintained encoder's scalar representation. `Ipse.JSON.sha256/1` hashes
original bytes. They are different identities; changing persistent encoding is
a compatibility change, not a cleanup. Saved reconstruction validates covered
prefixes, unknown outcomes, and projections chronologically, preserving later
messages. Corruption refuses unchanged, without alternate inference. Cancellation
commits no partial summary; owner death after commit retains the checkpoint.

`compaction_failed` records stage and bounded host diagnosis, without raw provider
errors. Required recent data may still prevent reduction. A shorter continuation,
explicit ceiling change, or reviewed [handoff](../operator/recovery.md) remains an
operator decision. Handoffs transfer bounded context, not native history or approvals.
`Context.measure/3` reports encoded categories using the same trigger, without
exporting source text. Fewer bytes alone prove neither summary fidelity nor safe recovery.

## Practice a checkpoint change

Follow the fixture preserving the two latest user turns. Compare native messages
before/after `finish_compaction/4`, then explain why the fallback's denied result
stays full. Exercise a corrupt committed field and owner loss after commit:

```sh
mix test test/ipse/workspace_test.exs test/ipse/workspace_integration_test.exs
mix test test/ipse/session/context_test.exs test/ipse/session/context_tools_test.exs
mix test test/ipse/session/context_integration_test.exs test/ipse/json_test.exs
mix test test/ipse/session/reference_test.exs test/ipse/session/reference_replay_test.exs test/ipse/session/reference_wire_test.exs
```

Pure suites establish projection shape. Session fixtures establish sync-before-
replacement, usage, cancellation, and inert recovery. Keep those distinct when
reporting the evidence for a context change. The wire suite exercises each main
adapter's actual request-body builder, checking unchanged serialized history,
tool declarations, reference role/position and signed continuation preservation.
