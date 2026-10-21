# Construct and reduce active context

Follow a conversation's context from instruction discovery to a bounded provider
request and durable recovery. `WorkspaceContext` owns discovery and source
identity. `Skills` owns its saved catalog. `Compaction` builds pure reductions.
Session decides when to adopt and commit each projection. The journal retains
the original evidence throughout this process.

Workspace text describes how a project wants work done. It never selects
credentials, grants tool permission or enforces an OS sandbox. Explicit operator
requests take precedence; nearer project `AGENTS.md` guidance overrides broader
project guidance, and Ipse-wide instructions supply defaults.

## Discover a bounded launch snapshot

Read `WorkspaceContext.snapshot/2` and its fixtures in
`test/workspace_context_test.exs`. Discovery canonicalizes the launch directory
and finds a valid repository/worktree boundary. A Git directory needs a regular
`HEAD`; a worktree pointer must resolve to a valid Git directory. Outside a
repository, the launch directory itself is the boundary.

Discovery reads `IPSE_HOME/AGENTS.md`, boundary-to-workspace `AGENTS.md` files and
the workspace `README.md`. One level of explicit local Markdown references may
load `.md`, `.txt`, `.adoc` or `.rst` resources within the boundary. It never
executes scripts or follows arbitrary remote links. Absolute/outside links,
symlink sources and sensitive components such as `.git`, `.ipse`, `.ssh`, `.aws`,
`.codex`, `auth`, `secrets` and `tokens` are excluded.

One UTF-8 source allows 32 KiB. A snapshot allows 16 sources and 128 KiB of source
text. Missing optional files are normal; invalid, oversized and inaccessible
files produce bounded diagnostics. Sources retain path, scope, kind and SHA-256.
Path validation does not protect against a hostile process replacing entries
concurrently.

Try drift detection in `iex -S mix`:

```elixir
scratch = Path.join(System.tmp_dir!(), "ipse-context-exercise-" <> Ipse.Usage.id())
workspace = Path.join(scratch, "workspace")
home = Path.join(scratch, "operator")
File.mkdir_p!(workspace)
File.mkdir_p!(home)
path = Path.join(workspace, "AGENTS.md")
File.write!(path, "Use a scratch fixture for the example.\n")
{:ok, saved} = Ipse.WorkspaceContext.snapshot(workspace, home)
[] = Ipse.WorkspaceContext.drift(saved)
File.write!(path, "Review the changed fixture before continuing.\n")
[_] = Ipse.WorkspaceContext.drift(saved)
true = Enum.any?(saved["sources"], &(&1["content"] == "Use a scratch fixture for the example.\n"))
File.rm_rf!(scratch)
```

The saved value retains its original text. Detecting drift does not adopt the
changed instructions. Session persists the bounded value as
`workspace_context_snapshot`; malformed saved snapshots refuse recovery.

## Adopt deeper guidance before admitting a file effect

Before starting a file tool or asking for its approval, Session performs nested
target preflight. Newly discovered scoped guidance is synced as a new snapshot.
The old proposal settles not started, and the model must reconsider it with the
new context. The affected call gets its specific diagnosis; later queued calls
get a generic stopped-before-start result. Approval stays `not_decided`.

A revised mutation needs its own approval. Preflight is neither a read receipt
nor evidence that an effect started. Actually started interrupted work remains
unknown. Shell strings have no reliably inferable complete target set, so this
check cannot certify every directory a shell command may reach.

Read the one-level-reference/nested-guidance discovery fixture, then its Session
counterpart in `test/workspace_session_test.exs`. Pure discovery alone cannot
prove intent and approval ordering.

## Keep instruction and skill selections stable

Resume uses validated saved instructions and reports drift without adopting new
text. `/context refresh` runs as an owned idle task and commits instruction and
skill selections together. Cancellation must not save half a refresh. Execution
configuration is not reloaded.

The skill catalog allows 256 entries and 256 KiB of encoded metadata. It stores
names, descriptions, canonical paths, digests and shadowed-source provenance,
not bodies. Loading a selected body/resource rechecks path and digest. Drift
refuses until explicit refresh. Older journals acquire their first catalog at
the next model boundary, never during idle inspection. `/context` and `/skills`
show saved selections; standalone `ipse skills` discovers current files.

Workspace text, skill metadata and extension contributions enter a labelled
user-role reference message. Core rules stay in system text. Explicitly
requested skill bodies remain in the requesting operator turn. These placements
do not turn reference text into a new task or permission grant.

## Plan a reduction at the model boundary

Read `Compaction.prepare/3`, `finish/4` and `restore_tool_results/2`. The default
encoded context ceiling is 400000 bytes, including system/reference messages.
After tools settle, automatic reduction triggers above 80% of that ceiling.
`--context-bytes` accepts at least 8192; `--no-compact` disables reduction while
retaining the hard admission bound. Encoded bytes are not provider tokens.

The summary planner selects a complete older prefix while preserving the two
latest user turns and all their assistant/tool/native data exactly. It pins
older user requests verbatim in an intent ledger. Its action ledger retains
call IDs, names, exact arguments, host approval/outcome facts, and result excerpts
with SHA-256, original size and a shortened flag. Excerpts allow 256 characters.
Unclassified legacy results stay unclassified; result text cannot prove approval.

The summary request contains normalized older transcript JSON under a separate
summarization instruction. It excludes old opaque/native reasoning from that
request, while the journal retains the original. The reply must contain exactly
three string arrays, for example:

```json
{"decisions":["Keep changes local"],"facts":["The failure is reproducible"],"open_questions":["Which input triggers it?"]}
```

One exact outer JSON Markdown fence is accepted. Extra prose, multiple documents,
wrong keys/types, tool calls and oversized content refuse. Summary JSON allows
16000 bytes; the request must fit the ceiling and the projected context must
shrink below the trigger. Required ledgers/native data are not trimmed to force
success. Structural validation cannot prove semantic fidelity.

Summary inference uses the main selected provider/model and ordinary accounting
and budgets. Ollama's summary-only request selects the schema, `think: false`,
zero temperature and a 4096-token cap narrowed by configured limits. Ordinary
turns keep their own settings. Summary deltas never enter the UI.

## Preserve provenance when shortening tool output

A single long turn may have no complete older prefix. The deterministic fallback
keeps every message, user/assistant text, call arguments, native continuation and
host metadata. It shortens only eligible settled results above 4096 bytes.
The two newest assistant tool-call batches, including parallel results, remain
complete. Unknown, denied, unclassified, already shortened, unresolved or
duplicated calls cannot be shortened.

An eligible result becomes explicitly incomplete beginning/end excerpts of
256 characters each, original byte count, SHA-256 and an instruction to inspect
original evidence before repeating an effect. This intentionally loses result
text. It is not full semantic preservation. The complete projection must fit
below the trigger or nothing is saved. A later summary retains the original
provenance instead of treating the excerpt as the original result.

## Commit and reconstruct the projection

Session syncs `context_compacted` before replacing its messages. Version 1 binds
checkpoint, covered effective-message count, canonical prefix digest and sizes.
`tool_results_compacted` binds original/projected digests and deterministic result
indices. Original message events remain in the journal.

`JSON.digest/1` hashes a JSON list with recursively sorted object keys, preserved
list order and the maintained encoder's scalar representation. It also binds
configuration, usage and extension records. `JSON.sha256/1` hashes original bytes.
Do not substitute one for the other or change a persisted encoding casually.

`Session.Saved` reconstructs unknown outcomes, verifies covered prefixes and
applies committed projections in event order. Later messages survive. A damaged
checkpoint refuses recovery unchanged; there is no alternate inference or
projection. Cancellation saves no partial summary. Owner death after commit
retains the checkpoint without replaying old effects.

`compaction_failed` records the prepare/summary/validation stage and a bounded
host diagnosis, not raw provider errors. Large recent data or pinned ledgers can
still prevent reduction. A shorter continuation, changed ceiling or reviewed
fresh session is an explicit operator decision. [Handoff](../operator/recovery.md)
exports a bounded reviewed note, not native history, permissions or calls.

## Verify the boundary you change

```sh
mix test test/workspace_context_test.exs test/workspace_session_test.exs
mix test test/compaction_test.exs test/tool_result_compaction_test.exs test/compaction_session_test.exs test/json_test.exs
```

For a compaction exercise, follow the fixture preserving two recent user turns.
Compare native messages before and after `finish/4`. Then explain why the denied
result in the deterministic fallback stays full. The pure suites check projection
and validation; Session fixtures check sync-before-replacement, accounting,
cancellation and recovery. Test a corrupted committed field and an interruption
after commit before claiming a checkpoint change safe.

`Diagnostics.context/3` reports exact encoded categories using the same trigger.
It exports counts and fixed labels, not source text. A smaller encoded context
alone proves neither faithful summarization nor safe effect recovery.
