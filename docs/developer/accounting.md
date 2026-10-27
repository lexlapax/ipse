# Account for work and reserve shared liability

Follow an admitted request into measured usage, configured estimates, and shared
budget decisions. A completed provider call, an admitted answer, a known price,
and a released reservation are different facts. Keeping them distinct prevents
failed work from becoming free in saved state.

| Owner | Implementation |
| --- | --- |
| Canonical records, normalization, reducer | [`Usage`](../../lib/ipse/usage.ex) |
| Exact estimates and cumulative aggregation | [`Usage.Costs`](../../lib/ipse/usage/costs.ex) |
| Policy, pure ledger transitions, and dispatch/settlement ordering | [`Usage.Budget`](../../lib/ipse/usage/budget.ex) |
| Protected append, native lock, and filesystem completion | [`Usage.BudgetStore`](../../lib/ipse/usage/budget_store.ex) |
| Frozen own/child accounting reads | [`UsageRead` and `ChildUsage`](../../lib/ipse/extension/usage.ex) |
| Optional page/summary/tree commands | [`Bundled reports`](../../extensions/bundled/costs.ex) |

No owner fetches prices automatically. Diagnostic capture is separate. Begin with
[operator resource controls](../operator/resources.md) to see the complete user
configuration before changing its implementation.

## Trace admission through completion

Read `Usage.admission/4`, `observation/3`, `completion/4`, and `apply_event/2`.
Session syncs `request_admitted` before dispatching owned main, summary, child,
or approved extension work. Text uses version 1; embedding admissions use version
2 with `operation: "embedding"`; decision admissions use version 3 with
`operation: "decision"`, selected `service_id` and `expected_model`. A version-3
Session can contain all three operations; earlier metadata cannot admit decision
records. Fresh 128-bit hex request/attempt/turn IDs bind
session, kind, provider/model, selected profile, billing mode, admission time, and
optional explicit-endpoint digest. Records contain no prompts, raw URLs,
credentials, or reasoning. Each request has one attempt, without automatic retry.

Adapters emit cumulative snapshots. Session suppresses identical observations,
sequences distinct ones, and commits completion before assistant processing or
summary validation. Refused summaries can therefore retain completed paid work.
A successful final response with missing counters does not borrow earlier partial
counts to make its total complete.

In `iex -S mix`, exercise cumulative replacement:

```elixir
alias Ipse.Usage
session = Usage.id()
admission = Usage.admission(session, %{provider: :openai, model: "fixture"}, "model", Usage.id())
one = Usage.observation(admission, %{"input_tokens" => 100, "output_tokens" => 10}, 1)
two = Usage.observation(admission, %{"input_tokens" => 100, "output_tokens" => 12}, 2)
header = %{"type" => "session", "metadata" => %{"usage_version" => 1}}
{:ok, partial} = Usage.restore([header, admission, one, one, two], session)
[row] = Usage.snapshot(partial)["requests"]
12 = row["usage"]["counts"]["output_tokens"]
"unknown" = row["outcome"]
final = Usage.completion(admission, {:ok, %{}, %{"input_tokens" => 100, "output_tokens" => 20}}, 25, two["usage"])
{:ok, complete} = Usage.restore([header, admission, one, two, final, final], session)
[row] = Usage.snapshot(complete)["requests"]
20 = row["usage"]["counts"]["output_tokens"]
"final" = row["finality"]
```

The partial output count is twelve, not twenty-two. Exact repeated terminal facts
are idempotent. Conflicting identities, orphan outcomes, reused attempts, and
malformed bindings refuse. Owner loss leaves unknown work; failure/cancellation
retains partial observations. A session permits 10000 requests and 64 observations
per request. Inspection shows the latest sixteen plus coverage, not all rows.
Legacy history remains explicitly unmetered.

## Preserve units and missing measurements

Counters are integers from zero through 10^12. Null stays unavailable and measured
zero stays zero. Invalid types, negatives, overflow, and inconsistent totals produce
fixed issues/invalid counters. Unknown provider fields are discarded.

| Route | Meaning |
| --- | --- |
| OpenAI/ChatGPT text | Inclusive input/output/total; cache and reasoning are subsets |
| OpenRouter/compatible chat | Prompt/completion/total with cache and reasoning subsets; provider credit cost is ignored |
| Gemini text | Input=prompt+tool-use prompt, output=candidates+thoughts; cached input and thoughts are subsets; missing summands stay partial |
| Grok text | Modern Responses inclusive totals; reported legacy totals disambiguate whether completion includes reasoning; mixed dialects/contradictions invalid, missing evidence partial |
| Anthropic text | Input sums uncached/cache-read/cache-create only when all are known; TTL subsets stay separate; output includes thinking |
| Ollama | Prompt/generated evaluation counts, optional cached prompt, nanosecond duration |
| Demo | Inapplicable |
| Embedding | Output tokens inapplicable/null; known input can explicitly derive total=input |
| Decision | Inclusive input/output with nullable cache partitions; no invented non-read split or reasoning/cache counts |

`Usage.valid_usage?/2` binds normalized shape to admitted operation. OpenAI
embedding prompt/total must agree when both exist; Ollama uses prompt counts and
nanosecond duration. Duration-only metering is partial. Text and embedding rows
cannot substitute. Decision usage stays version 3 and cannot borrow text or
embedding rate rows. Own-session pages and frozen child pages preserve these
operation tags and their earlier page versions. Known text/decision input/output
may explicitly derive a missing total.
Billing modes identify subscription/API/local/none, not prices or entitlement.

## Calculate a synthetic rate

Continue the IEx exercise with this complete synthetic card:

```elixir
card = %{
  "version" => 1, "id" => "training", "revision" => "1", "currency" => "USD",
  "published_on" => "2026-10-01", "source" => "operator:synthetic-training-rates",
  "rows" => [%{
    "id" => "fixture", "provider" => "openai", "billing_mode" => "api",
    "basis" => "api_estimate", "model" => "fixture", "endpoint_sha256" => nil,
    "from" => "2026-01-01", "until" => nil, "input_min" => 0, "input_max" => nil,
    "input_mode" => "flat", "rates" => %{"input" => "2", "output" => "10"}
  }]
}
request = Map.take(row, ~w(operation provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage))
{:ok, estimate} = Ipse.Usage.Costs.estimate(card, request)
400_000 = estimate["amount_nanos"]
9 = estimate["currency_scale"]
```

One hundred input tokens at two currency units per million and twenty output at
ten per million cost 400000 nanos. Included reasoning adds no second output charge.
Arithmetic uses exact integers, sums components, then rounds upward once per request
to one billionth. Rates are unsigned decimal strings with at most nine integer
and nine fractional digits. Floats, exponents, signs, unknown dimensions, and
SDK-safe-integer overflow do not produce an invented amount.

Cards hold ID/revision, uppercase three-letter currency, publication date/source,
and at most 32 rows within 16 KiB. Sources are unfetched `operator:` references
or HTTPS URLs without userinfo/query. Matching uses exact route/billing/model,
endpoint digest, admission date, input band, and explicit operation in v2/v3. Reported model takes
precedence over requested aliases. Null endpoint means absent explicit identity.
Lower bounds are inclusive, upper bounds exclusive/open if null. Overlap refuses;
unknown input cannot select a finite band.

| Input mode | Required rate keys |
| --- | --- |
| `flat` | `input`, `output` |
| `cache_split` | `input_uncached`, `input_cached`, `input_cache_write`, `output` |
| `cache_ttl_split` | `input_uncached`, `input_cached`, `input_cache_write_5m`, `input_cache_write_1h`, `output` |

Cache components partition inclusive input. TTL writes must sum correctly.
Contradictions yield no known input subtotal; missing subsets remain unknown
unless known-zero totals establish zero. Optional search/fetch prices use thousands
of reported requests; duration prices use normalized nanoseconds. Positive unpriced
extras leave totals incomplete.

API estimates, subscription API-equivalent estimates, and local estimates are
separate bases. Missing local rates do not imply free work. Version-2 cards require
`operation: "text"` or `"embedding"`; embedding permits flat input and optional
duration without output/cache/search/fetch dimensions. Version-3 cards additionally
admit `operation: "decision"` with flat/cache-split token rates; they require
operation on every row and never repurpose a text price for advice. Unknown
cache partitions remain unpriced under a split rate. Preserve operation in
request projection. Estimates retain exact card identity, model identities,
selected row/basis, units, components, and rounding. `amount_nanos` needs fully
priced final completed usage; `known_amount_nanos` may retain a partial subtotal.
Changing a card does not rewrite request facts.

## Reserve before dispatch and settle before admission

Only operator configuration selects a tree budget. Session metadata pins its policy;
children inherit exact root/origin and cannot replace it through profiles. A
root-owned ETS checkpoint binds policy and validated ledger prefix. Owner death
removes that runtime authority. Never serialize it into workers.

After Session syncs canonical admission, `Budget.run/4` performs slow IO in the
owned request task, outside the GenServer:

1. Lock the ledger and validate root/policy/prefix. Reserve all configured dimensions
   or durably refuse admission.
2. Sync `dispatch_intent` before provider setup/inference.
3. Sync cumulative usage peaks before forwarding text observations to Session.
4. Sync settlement before returning a response Session can admit.

Request bookings never refund, even if setup fails. Known successful dimensions
can release unused booking down to observed peaks. Failure, cancellation, absent
measurement, or uncertain settlement retains at least booking/peak. Billing bases
cannot offset each other. Input/money bookings cannot guarantee actual in-flight
charges. Unsupported subscription output quotas refuse rather than simulate a cap.
Grok's Spec declares a visible-only cap: reasoning and function-call tokens are
outside it. `Budget.request_config/1` refuses total-output reservations for both
Grok billing routes. Request-count admission remains supported; no inference
fallback is a way around this restriction. A completed native response may retain
bounded provider-reported USD ticks, but canonical usage and cost estimates do
not turn that value into an invoice or subscription balance.

Embedding marks generated-output liability zero before dispatch while canonical
output remains null/inapplicable. Applicable request/input/money still share the
ledger. `Budget.request_config/1` must not turn text output reservations into
embedding wire fields. Embedding captures genuine nonstreaming final metering
before guarded writes. A failed write/settlement can retain counters but refuse
readable vectors; resume then refuses unproven liability coverage. Text keeps
write-before-forward ordering. Decisions share bounded final-result capture and
settlement while retaining applicable output liability. Since their endpoint
subset has no enforceable output cap, `Budget.request_config/1` refuses an
output-token policy before dispatch. No path interprets failure as zero.

Final-only overdraw preserves counters/completion while refusing assistant/tool
admission. Another concurrent request's overdraw can refuse this completed request
too. Already streamed text cannot be retracted; refused content has no saved
quarantine/export contract. A new independent root starts a separate quota.
Audio, arbitrary tools/MCP charges, and out-of-band trusted code are outside coverage.

### Measure local managed publication separately

Saved semantic consent uses a separate protected resource vector for local
knowledge work. These bytes describe host JSON processing, not model tokens or a
provider invoice. Follow [the Collection SDK](collection-sdk.md) for its approval,
source and publication contract.

Before a managed save, `ManagedCollectionCall.reservation/1` reserves one operation,
the encoded worker request, both maximum sidecar values and their envelopes,
2048 normalization bytes, and 16384 output bytes. The ceiling stays fixed before
effects. On a proven successful save, the host measures encoded outer-request
bytes plus normalized-commit growth plus encoded normalization-receipt bytes.
The private, callback-local measurement must match that same successful Collection
receipt and fit every reserved dimension before `Consent.publish` settles it.
The operation and output charges remain conservative; other resource charges stay
zero. Neither a worker-supplied cost nor a smaller partial measurement releases
liability. Conflict and failed-no-effect results settle the full reservation;
native loss, cancellation, uncertain publication or settlement retain it without
an automatic refund or retry.

The managed Session tests make two real protected saves under a period input
ceiling that would reject their combined full reservations. They reconstruct the
normalized commits from stored values and compare each exact debit. A separate
native-owner-loss test interrupts after normalization but before the root switch
and verifies that no measured refund or successful result escapes.

## Validate protected storage and recovery

`BudgetStore` owns closed `reserved`, `refused`, `dispatch_intent`, `observed`, and
`settled` records beneath a header bound to root/policy/digest. Unsupported fields,
versions/order, duplicate attempts/keys, foreign scope, and torn final lines refuse.
Limits are 32 MiB per ledger, 64 KiB per line, 40000 reserved and 40000 refused
requests, 64 observations per request, a five-second decode deadline, and a
one-second lock retry window plus native startup allowance.

Directories are canonical/owner-only. Files are regular, singly linked, and
owner-only. Existing missing locks are not recreated during resume. A filesystem
completion process retains the native lock through IO after caller death; Session
cleanup may time out while it settles. Never retry that interrupted append.
Checkpoints cache reducer state but each transaction still reads/hashes its bounded
prefix against rollback and same-size replacement. Fresh inspection/resume decodes
all records.

Resume cross-checks liability and historical peaks against own canonical records
and registered direct children's protected, locked, exact-origin sources. Missing,
unregistered, unavailable, or under-accounted sources refuse before journal tail
repair. A crash between canonical admission and budget decision can refuse too.
There is no automatic refund/repair. Idle resume dispatches nothing and changes no
ledger. Saved `ipse budget` inspection does not establish full resume source coverage.
A reviewed fresh handoff preserves old bytes/liability rather than transferring it.

## Read fixed accounting ranges and aggregate revisions

`UsageRead` requires `host.actions` and `host.usage`, separately from transcript
access. Its first read freezes a registered admitted range:

```json
{"op":"usage.read","cursor":0,"limit":4,"snapshot":null}
```

Later pages echo the snapshot/caller. New admissions fall outside the cut. Pages
contain canonical facts, without prompts or directory selectors. Text-only cuts
retain v1; embeddings use v2 with operation. Cursor is 0..10000, limit 1..4, and
pages allow 12 KiB within SDK bounds. At most 10000 initial snapshots are retained;
registered ranges remain readable at capacity. Recovery validates cached pages
and initial sources before tail repair, without refreshing/replaying reads.

`ChildUsage` additionally requires `host.usage.children`. Discovery returns direct
registered children, omitting tasks/results/raw call IDs. Child reads derive their
protected path, verify parent/request/call origin, and hold a native lock over a
16-MiB prefix within five seconds. Unsafe, locked, missing, malformed, or unbound
children refuse instead of becoming empty balances. No recursive traversal or
child resume occurs. Discovery snapshots bind source/identity/count; text child
snapshots v3/page v1 bind prefix/count/legacy/projection digest. Embedding child
snapshots v4/page v2 retain operation. The digest is not a transcript hash.

`host.usage.scan` extends only own/discovery/child reads through step 10000, with
no new scan after 120 seconds. Other operations remain within sixteen steps,
even when interleaved. Five-second callbacks and 64-MiB worker output remain.
The grant adds no private text, writes, or inference permission.

Bundled reports consume these interfaces. `Costs.summary/2` and `put_request/2`
key cumulative revisions by session/request/attempt and require stable admission
identity and authoritative revision order. Own summaries permit 10000 attempts;
tree summaries permit 40000. Parent, child discovery, and child prefixes are
separate cuts, not a globally atomic snapshot. Missing children remain coverage
gaps. Keep billing/basis/operation groups, known subtotals, unknowns, and overflow.
`enumeration_complete` is not a priced invoice. Bounds never turn truncation into
successful totals. Idle resume restores reports without recalculation.

## Practice a change across the complete path

For a new counter, specify units/subsets, then exercise absent, zero, contradictory,
partial, and final values. For aggregation, overlap pages and replace a cumulative
revision before checking totals. Pure arithmetic validates shape, not provenance;
host reads supply the source binding. For a budget dimension, define reservation,
overflow, known/unknown measurements, and release before storage changes.

```sh
mix test test/ipse/usage_test.exs test/ipse/usage/integration_test.exs
mix test test/ipse/extension/usage_read_test.exs test/extensions/bundled/child_usage_test.exs
mix test test/extensions/bundled/costs_test.exs test/ipse/usage/costs_test.exs
mix test test/ipse/usage/budget_test.exs
```

Follow competing bookings, cancellation between each durable stage, delayed writes,
owner death, rollback, child coverage, and inert resume in the budget suite.
These are local protocol/fixture checks, not live invoice measurements.
