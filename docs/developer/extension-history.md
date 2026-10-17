# Explicit session-history reads

`history.read` lets an admitted extension invocation or event job inspect bounded
pages of recorded lifecycle views in its **own session**. It reuses the common
[host-action protocol](extension-host-calls.md); it is not a journal replay,
automatic reindexer, cross-session search or raw transcript export. Returned text
does not become model context until separately published.

## Authority and request

Every history operation needs `host.actions` and `host.history`. Historical private
views have separate grants from live `event.*` subscriptions:

| View | Additional historical read capability | Recorded source |
| --- | --- | --- |
| `metadata` | None | Supported shared lifecycle metadata |
| `prompt.original` | `host.history.prompt.original` | Recorded original prompt boundary |
| `prompt.expanded` | `host.history.prompt.expanded` | Saved expanded user message, before prompt transforms |
| `prompt.effective` | `host.history.prompt.effective` | Recorded final-effective prompt boundary |
| `answer.original` | `host.history.answer.original` | Completed-answer original text |
| `answer.presented` | `host.history.answer.presented` | Completed-answer final presentation |
| `tool.input` | `host.history.tool.input` | Recorded admitted-tool name and original arguments JSON |
| `tool.result` | `host.history.tool.result` | Recorded admitted-tool outcome text |

Operator trust must allow all declared capabilities. A private history capability
without the base grant, or a host operation without `host.actions`, fails inert
validation. A live prompt/answer read grant does not grant historical access.
Overview `host.history.*` notation is shorthand; wildcard grants/views are not accepted.
Installation/selection alone starts no history scan. Reads need no separate
mutation approval once these capabilities are explicitly trusted; later writes,
tools, model calls or transfers retain their own admission rules.

The request has exactly these five fields:

```json
{"op":"history.read","view":"prompt.effective","cursor":0,"snapshot":null,"limit":8}
```

`cursor` is an inclusive JSONL byte boundary, initially usually zero. `limit` is
1..8 **source records scanned**, not the number of matching events. Neither path,
session selection nor project/operator scope is accepted. Children can read only
their own session under their independently permitted capabilities.

## Fixed range and continuation

For a null snapshot, Session syncs the ordinary action intent with a stable source
before execution. Its starting byte offset becomes the exclusive upper boundary.
The returned version-1 snapshot contains `session_id`, `byte_offset`, `event_id`,
`operation_id` and `view`. It contains no content digest or filesystem path.
Its range is the prefix `[0, byte_offset)`. A cursor selects a page position within
that prefix; it is not a narrower permission grant or a monotonic-cursor guarantee.

Pass that exact snapshot and the returned `next` cursor in later `history.read`
requests. Each call still needs current capability/lease admission. The host resolves
the anchor against its owned journal, checking the initial-read intent, operation,
caller identity, session and view. Changed scope/view/identity or a missing/invalid
anchor refuses. No worker-supplied reference is permission or authenticated host
provenance by itself.

The frozen range excludes its capture intent and later appends, including the
catch-up operation's own results. It can continue across explicit invocations or
an explicitly answered question in the same pinned session. This prevents a scan
from chasing its own receipts. It relies on the existing append-only owned-journal
contract; it does not retain an immutable archive or authenticate hostile same-user
filesystem changes. Prefix replacement requires corruption review, not automatic
repair, reinterpretation or migration.

## Pages, skipped views and gaps

An `ok` outcome contains exactly `version`, `coverage`, `snapshot`, `cursor`, `next`,
`scanned` and `records`. `coverage` is `recorded_views_only`. `next: null` means the
fixed range was examined, not that every conversational stage was recorded.
Every consumed source record produces one row:

| Row | Fields and meaning |
| --- | --- |
| `event` | `kind`, `event`: selected versioned lifecycle envelope retaining the original occurrence ID |
| `skipped` | `kind`, content-free `source`, `reason: "other_view"`: a known occurrence outside the requested view |
| `gap` | `kind`, content-free `source`, fixed reason: `unsupported_record`, `view_unavailable` or `page_budget` |

Metadata rows use the shared closed metadata validator and exclude text, provider
continuation, credentials, arbitrary errors and content hashes. Private event rows
contain only the selected text/view and its normal source binding. Skipped/gap rows
never include the raw record type or body. Tool views use their closed structured
`name`/`arguments_json` or `text` objects, with the same occurrence identity as
metadata; see [admitted-tool sources and bounds](tool-events.md). Their historical
grants are separate from live `event.tool.*` capabilities. Older unrecorded tool
views are not synthesized from native assistant/tool messages.

Original/effective/answer boundaries absent from older history are not invented
from adjacent records. A saved user message is the distinct `prompt.expanded` view;
it is not silently relabeled original or final-effective input. Consumers must
interpret skipped rows and recorded-view coverage before claiming complete
ingestion. An unavailable recorded private view produces a gap.

The range reader scans at most eight records and 1 MiB of raw record JSON per call,
plus one bounded anchor resolution. Page values are at most 12 KiB encoded, and the
complete action callback must fit the ordinary 16 KiB/depth/string SDK limits.
When another event would overflow a nonempty page, `next` leaves it unconsumed.
An event too large for an empty page becomes a `page_budget` gap; no text is
truncated. Syntax, cursor, oversized raw-source or read failures return a known
`failed` code instead of an unchecked partial page. Codes are `history_snapshot`,
`history_cursor`, `history_source` or `history_timeout`; no path/error prose is returned.

## Effects, context and recovery

IO runs in a linked task outside Session; after a five-second wait the host
requests brutal task shutdown under the ordinary OTP/OS limits.
Cancellation/owner death stops dependent work through the existing
owned task/worker boundaries. Reads share the 16-operation invocation budget;
there is no unbounded background scan or implicit pagination loop in core.

Action receipts bind page/snapshot, operation, caller and session namespace.
Private page data remains in the private journal. Ordinary receipt-backed context
can cite a literal selected excerpt, for example a path through
`records`, an array index, `event`, `data`, `text`. Use the **page action's** operation
ID, which may differ from the snapshot's initial capture operation. Provenance
establishes a recorded excerpt, not its truth, freshness or permission priority.

An extension implements deduplication, extraction, forget/tombstone policy,
cursor persistence and explicit catch-up/reindex commands. Subsequent storage
retains normal full approval and CAS conflict handling. The history grant supplies
no write authority; extensions must use retained revisions/tombstones to reject
stale reindex writes. Forgetting derived data does not erase original journal text
or revoke independently granted historical read access. Recovery resolves cached
anchor/source references, checks exact selected projections and contiguous spans,
and verifies that a budget gap really exceeded the page limit. It deduplicates
repeated reference checks. This validates saved evidence without rerunning a scan,
updating a cached page or restarting callbacks. An interrupted operation remains
historical incomplete/unknown, never automatically retried on idle resume.

## Verification and remaining proof

Independent-worker source fixtures cover explicit catch-up, fixed snapshots,
separate write approval, question continuation, cancellation/owner-death cleanup
and inert idle resume. Primitive source/extracted fixtures exercise the compiled
range/view API, not installed-worker execution in a release. Tests also cover
metadata exclusion, private view separation, post-boundary oversized/torn data,
page splitting, gaps, altered text/receipt rejection and omitted-span detection. See
[actual evidence](testing.md#current-evidence-and-next-checks).

The [independent frozen-core lab](extension-proof.md) adds installed-worker
catch-up, domain deduplication and tombstone/CAS rejection after forget. It does
not expose cross-session/project history or implement a production reindex manager.
Production knowledge quality remains deferred P26/P27 work after P25 research. No
database, search service, broker or new dependency is added by this operation.
