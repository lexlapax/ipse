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

## Page admitted evidence without inline context

Use [Session sources](session-sources.md) to follow the committed source projection,
its native tools and explicit SDK grant, exact quotation matching, bounded coverage
and saved reconstruction. Source reads work without inline source text. Compaction
changes effective context without replacing the admitted original source bytes.
Source attribution grants neither truth nor execution authority.

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
