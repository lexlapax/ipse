# Following a request through durable accounting

Accounting answers which model work Ipse admitted and what the provider measured.
It must remain available when tracing is off and after a failed request.
`Ipse.Usage` owns the content-free reducer; `Ipse.Usage.Normalizer` owns provider
counter semantics. Reports and [cost estimation](costs.md) consume these facts.
They do not reconstruct usage from visible text.

## Trace admission, observations, and completion

Read `admission/4`, `observation/3`, `completion/4`, and `apply_event/2` in
`lib/ipse/usage.ex`. Session syncs `request_admitted` before starting the
owned model, summary, or approved extension task. Text retains version 1;
embedding uses version 2 with `operation: "embedding"`. The record contains fresh
128-bit hexadecimal request/attempt/turn IDs, session, kind, provider, requested
model, selected profile, billing mode, admission time, and optional explicit
endpoint SHA-256. Raw URLs, credentials, prompts, and reasoning are excluded.
There is one attempt per request and no automatic retry.

Adapters emit cumulative snapshots to the current owned job. Session suppresses
identical observations and assigns consecutive sequences to distinct ones.
Completion commits before assistant processing or summary validation. A rejected
summary can therefore retain completed paid work. A successful response uses its
actual final usage, including missing fields; an earlier partial count cannot
be promoted into exact final usage.

The reducer exercise in `test/usage_test.exs` uses growing snapshots. If a request
reports 10 output tokens and then 12, the latest output is 12, not 22. Read the
fixture "snapshots replace cumulative observations and exact duplicates do not
double count", then follow the interrupted version. Cancellation/failure keeps
the last observation with `finality: partial`; abrupt owner loss leaves an unknown
outcome. Failed work may still have consumed resources.

[Budgeted text requests](budgets.md) cover an observation in the shared ledger
before forwarding it to Session. Embeddings capture genuine nonstreaming final
metering before the guarded observation and settlement. Failed writes prevent
readable vector publication; Session can still retain the actual final counters.
Resume refuses unproven ledger coverage. Neither path repairs a ledger or treats
missing measurements as a zero balance.

## Normalize units without inventing measurements

Counts are integers from zero through 10^12. Missing/null remains null; reported
zero remains zero. Invalid types, negatives, overflow, and inconsistent totals
invalidate counters with fixed issue codes. Unknown provider fields are discarded.
The closed normalized record separates counts, derived fields, quality, and issues.

| Provider | Interpretation |
| --- | --- |
| OpenAI/ChatGPT | Inclusive input/output/total; cache and reasoning are subsets |
| Anthropic | Input is uncached + cache reads + cache creation only when all are known; TTL creation subsets remain separate; output includes thinking |
| Ollama | Prompt/generated evaluation counts, optional cached prompt, nanosecond total duration |
| Demo | `not_applicable` |

Embedding normalization has a closed v2 form with `operation: "embedding"` and
`not_applicable_fields: ["output_tokens"]`. Output stays null rather than a
reported zero. OpenAI maps `prompt_tokens` and `total_tokens`; both must agree
when present. Ollama maps `prompt_eval_count` and nanosecond `total_duration`.
Known input can explicitly derive total=input. Missing input stays missing;
duration-only metering is partial. `Normalizer.valid?/2` checks the admitted
operation so an embedding measurement cannot satisfy a text admission.

If input/output are known and total is absent, their sum is explicitly derived.
Billing modes are subscription, API, local, or none according to route. These are
routing facts, not prices or entitlements. Native continuation and private provider
prose never enter accounting.

## Teach an extension to read facts

`Ipse.Extensions.UsageRead` implements a separately granted `usage.read` action.
It requires `host.actions` and `host.usage`, independently of transcript access:

```json
{"op":"usage.read","cursor":0,"limit":4,"snapshot":null}
```

A first successful read captures the admitted request count and registers a
version-1 snapshot containing source, operation ID, identity digest, request count,
and legacy flag. Later pages must echo that exact registered snapshot and caller.
New admissions fall outside the cut. A cut containing embedding rows uses
snapshot/page version 2 and retains each row's operation. Old text-only cuts
retain their exact version-1 shape. Cursor is 0–10,000; limit is 1–4. Pages use
`scope: "session"`, `coverage: "canonical_requests"`, cursor/next cursor and
latest cumulative request rows. They expose no directory selector or prompts
and grant no provider or mutation operation.

Pages are prepared from the validated in-memory reducer, not a filesystem scan
inside Session. Each page is at most 12 KiB within the SDK's 16 KiB object bound.
Overflow refuses. At most 10,000 initial successful snapshots are retained.
Existing registered ranges remain readable when fresh snapshot capacity is full.
Recovery compares cached pages to their original canonical facts and physically
resolves each initial source before tail repair; it never refreshes or replays a
read. Fixed failures include `usage_snapshot`, `usage_cursor`, `usage_bounds`,
and `usage_limit`.

## Read registered children without reading their conversations

`Ipse.Extensions.ChildUsage` requires `host.usage.children` in addition to
`host.usage` and `host.actions`:

| Action | Additional fields | Returned scope |
| --- | --- | --- |
| `usage.children` | cursor, limit 1–4, nullable snapshot | `children`, registered direct children |
| `usage.child.read` | same plus 32-hex `child_id` | `child`, canonical requests |

Discovery rows retain child ID, recorded parent request/turn, status/cleanup, and
origin availability. They omit tasks/results/raw call IDs. A version-2 discovery
snapshot pins source, operation, identity, and child count. A version-3 child
snapshot also pins child ID, request count, legacy flag, byte prefix, and SHA-256
of accounting projections. The digest is not a private transcript hash.

A child cut containing embedding rows uses snapshot version 4 and page version 2.
Discovery keeps its existing version 2. Frozen text-only child cuts retain
snapshot version 3 and page version 1. Recovery rejects operation-bearing rows
presented under legacy page semantics.

The host derives a protected child path, acquires its native lock, reads at most
16 MiB within five seconds, and verifies exact parent/request/call origin. The
reader rejects unsafe paths/files, incomplete/duplicate-key/oversized records,
and unrelated admissions. Missing, busy, malformed, or unbound older children
refuse; none becomes an empty successful balance. No child resume or recursive
traversal occurs. Parent discovery/initial child snapshots each have a 10,000
ceiling. Recovery checks frozen prefixes before parent tail repair; later child
appends remain outside them.

`host.usage.scan` permits only these three reads in invocation steps 17–10,000.
Other operations remain in the first 16 steps, including interleaved reads. A
scan admits no new call after 120 seconds; five-second callbacks and the 64 MiB
worker-output limit remain. The grant adds no child, content, model, or write
permission.

## Change and verify the reducer

Children record originating parent session/request IDs. Extension kind `extension`
uses the action operation ID as request ID and a fresh attempt, bound to the
approved helper route. Assistant messages and checkpoints bind their actual
requests. Recovery rejects orphan outcomes, reused attempts, bad order, conflicting
scope, malformed versions/fields, and missing bindings. Exact repeated admissions,
latest observations, and terminal records are idempotent.

A session admits at most 10,000 requests and retains at most 64 observations per
request. Inspection shows only the latest 16 rows plus total/unknown counts; it
must not imply those rows are full coverage. Legacy journals are explicitly
`legacy_unmetered`. Idle resume dispatches nothing and invents no settlement.

```sh
mix test test/usage_normalizer_test.exs test/usage_test.exs test/usage_session_test.exs
mix test test/extensions_usage_read_test.exs test/extensions_child_usage_test.exs
```

The first command checks normalization, state transitions, and Session bindings.
The second checks real worker paging, private exclusion, child-source validation,
and cached recovery. For a new counter, specify its unit/subset relation first,
then test missing, zero, contradictory, partial, and final measurements.
