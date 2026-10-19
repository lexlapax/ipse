# Read recorded session views for explicit catch-up

`history.read` gives an admitted invocation or event job bounded pages of recorded
views in its own session. A scan captures a fixed prefix, so catch-up cannot chase
its own later receipts. The extension owns pagination, deduplication, extraction,
and any subsequent approved writes. Reading history neither replays the journal
nor automatically publishes it into model context.

The lab's `catchup` export in `examples/extension-lab/src/memory.ex` demonstrates
a bounded domain scan. Follow its `history` phase through page collection and
then the separately approved CAS update.

## Authority and request

Every read needs `host.actions` and `host.history`. Private historical views have
separate capabilities from live event subscriptions:

| View | Additional capability | Recorded source |
| --- | --- | --- |
| `metadata` | None | Supported lifecycle metadata |
| `prompt.original` | `host.history.prompt.original` | Original prompt boundary |
| `prompt.expanded` | `host.history.prompt.expanded` | Saved expanded user message before transforms |
| `prompt.effective` | `host.history.prompt.effective` | Final-effective prompt boundary |
| `answer.original` | `host.history.answer.original` | Completed original answer |
| `answer.presented` | `host.history.answer.presented` | Completed final presentation |
| `tool.input` | `host.history.tool.input` | Recorded admitted tool and original arguments JSON |
| `tool.result` | `host.history.tool.result` | Recorded admitted-tool outcome text |

Operator trust must cover the exact set. Wildcards are unavailable. Live private
read grants do not imply historical ones. Reads need no separate mutation approval
once trusted, while later writes, tools, and model transfers keep their own rules.
Children can read only their independently permitted own sessions.

Return an outer `host_call` with this exact five-field request:

```json
{"op":"history.read","view":"prompt.effective","cursor":0,"snapshot":null,"limit":8}
```

`cursor` is an inclusive JSONL byte boundary. `limit` is 1–8 source records scanned,
not matching events returned. Paths, another session, and project/operator scope
are not accepted.

## Fixed range and continuation

With `snapshot: null`, the ordinary action intent's starting byte offset becomes
the exclusive upper boundary. The returned version-1 snapshot includes
`session_id`, `byte_offset`, `event_id`, `operation_id`, and `view`, excluding
private content digest and filesystem path. Its range is `[0, byte_offset)`.

Pass the exact snapshot and returned `next` to continue. Each page still needs
current capability and lease admission. Host resolves the capture intent and
checks caller identity, session, operation, and view. Changed or missing anchors
refuse. A worker-supplied reference is not permission or authenticated provenance.

The range excludes its capture intent and all later appends. It can continue
across explicit invocations or an answered question in the same pinned session.
A cursor selects a page position rather than granting a narrower scope or
promising monotonically persisted progress. The fixed range relies on the owned
append-only journal, not an immutable archive against hostile same-user changes.

## Pages, skipped views and gaps

An `ok` page contains exactly `version`, `coverage`, `snapshot`, `cursor`, `next`,
`scanned`, and `records`. Coverage is `recorded_views_only`. Each consumed source
record produces one row:

| Row kind | Shape |
| --- | --- |
| `event` | `kind` and selected versioned `event`, retaining occurrence ID |
| `skipped` | `kind`, content-free `source`, and `reason: other_view` |
| `gap` | `kind`, content-free `source`, and `reason`: `unsupported_record`, `view_unavailable`, or `page_budget` |

Null `next` means the captured range was examined, not that every conversational
stage was recorded. Metadata excludes text, credentials, native continuation,
arbitrary errors, and content hashes. Skipped/gap rows contain neither raw record
type nor body. Private rows contain only selected content and its source binding.
Tool views use their closed `name`/`arguments_json` or `text` data and require
recorded [tool sources](tool-events.md); old native messages are not relabeled
as those views.

Missing original/effective/answer boundaries are not invented from neighboring
records. `prompt.expanded` remains a distinct saved-user-message view. Record gaps
and skipped rows before claiming complete ingestion.

Each call scans at most eight records and 1 MiB raw JSON plus bounded anchor
resolution. Page values are at most 12,288 encoded bytes, and the complete action
callback must fit SDK 16 KiB, string, and depth limits. If another event overflows
a nonempty page, `next` leaves it unconsumed. A single too-large event becomes a
`page_budget` gap without truncation. Syntax, cursor, raw-source, or IO failures
return known `failed` codes `history_snapshot`, `history_cursor`, `history_source`,
or `history_timeout`, without path/error prose or unchecked partial pages.

## Effects, context and recovery

History IO runs in a linked task outside Session, with a five-second wait before
brutal task shutdown. Reads consume the ordinary 16-action budget. There is no
unbounded host pagination loop or implicit background reindexing.

Receipts bind page, snapshot, operation, caller, and session namespace. Private
pages stay in private journals. To publish a recorded excerpt, use the page
operation's ID in a [receipt source](extension-context.md#assertions-and-recorded-evidence),
with a path such as `records`, array index, `event`, `data`, `text`. The page's
operation ID can differ from the original snapshot capture ID. Provenance verifies
a recorded excerpt, not its truth or instruction priority.

Keep revisions/tombstones captured before delayed extraction so forgetting can
reject stale writes. Historical read authority survives deletion of derived data;
forgetting notes cannot erase source journals or independently revoke history
access. Extension policy owns suppression and explicit reindex commands.

Recovery validates cached anchors, actual source projections, contiguous spans,
and page-budget gaps without rerunning scans or updating pages. Idle resume starts
no callback or catch-up loop. Interrupted operations remain incomplete/unknown.
Missing, altered, or coherently omitted source spans refuse before tail repair.

## Exercise a fixed snapshot

Find the fixture that captures a range, appends more history, and continues with
the saved snapshot. Confirm that later source events stay outside the page and
that zero matching events can still advance the cursor. Then follow the
question-continuation case: its next page is explicit work, not idle replay.

```sh
mix test test/extensions_history_test.exs
```

These tests cover private-view separation, page splitting, gaps, torn tails after
the boundary, malformed cursors, source tampering, cancellation, and cached
recovery. The [installed lab](extension-proof.md) combines these primitives with
domain deduplication and stale-write rejection after forget.
