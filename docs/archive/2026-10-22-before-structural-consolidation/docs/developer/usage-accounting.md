> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/developer/accounting.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Account for requests and calculate configured estimates

Follow one admitted request into provider observations, a durable completion,
source-bound accounting pages and an optional cost estimate. `Usage` owns the
content-free reducer; `Usage.Normalizer` owns units and subset relations.
`Usage.Costs` and `Usage.CostSummary` own pure arithmetic and aggregation.
Bundled reports consume these facts. [Budgets](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/budgets.md) separately own shared
admission and reservations. No price lookup or enabled default rate is involved.

## Trace admission through completion

Read `Usage.admission/4`, `observation/3`, `completion/4` and `apply_event/2`.
Session syncs `request_admitted` before dispatching an owned model, summary or
approved extension request. Text uses version 1; embeddings use version 2 with
`operation: "embedding"`. Fresh 128-bit hexadecimal request/attempt/turn IDs bind
session, kind, provider, requested model, selected profile, billing mode,
admission time and optional explicit-endpoint SHA-256. No prompts, raw URLs,
credentials or reasoning enter these records. Each request has one attempt;
there is no automatic retry.

Adapters send cumulative snapshots to the owned job. Session suppresses exact
duplicates and sequences distinct observations. Completion commits before
assistant processing or summary validation. A rejected summary can therefore
retain completed paid work. Final successful metering comes from the actual
final response, including missing fields; a partial count cannot fill its gaps.

Try cumulative replacement in `iex -S mix`:

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
{:ok, ledger} = Usage.restore([header, admission, one, two, final, final], session)
[row] = Usage.snapshot(ledger)["requests"]
20 = row["usage"]["counts"]["output_tokens"]
"final" = row["finality"]
```

The partial observations total twelve output tokens, not twenty-two. Abrupt
owner loss leaves an unknown outcome; cancellation/failure preserves the latest
observation as partial. A successful response with absent final counters remains
unavailable rather than borrowing earlier counters. Failed work may consume
resources.

Budgeted text covers an observation in the shared ledger before forwarding it
to Session. Embeddings capture genuine final nonstreaming metering before guarded
observation and settlement. Failed writes can prevent readable vectors while
Session still records actual final counters. Resume refuses unproven coverage;
neither path repairs a ledger or interprets missing measurement as zero.

## Preserve units, missing values and operations

Counts are integers from zero through 10^12. Missing/null remains null; measured
zero remains zero. Invalid types, negatives, overflow and inconsistent totals
produce fixed issues and invalid counters. Unknown provider fields are discarded.
Normalized records separate counts, derived fields, quality and issues.

| Provider | Normalization |
| --- | --- |
| OpenAI/ChatGPT | Inclusive input/output/total; cache and reasoning are subsets |
| Anthropic | Input sums uncached, cache-read and cache-create only when all are known; TTL creation subsets remain separate; output includes thinking |
| Ollama | Prompt/generated evaluation counts, optional cached prompt, nanosecond duration |
| Demo | Not applicable |

Embedding v2 metering marks output tokens inapplicable and leaves output null.
OpenAI prompt/total counts must agree when both exist. Ollama uses prompt counts
and nanosecond duration. Known input can explicitly derive total=input; missing
input stays missing and duration-only metering is partial. `Normalizer.valid?/2`
binds the normalized form to the admitted operation. Text and embedding rows
cannot substitute for one another.

For text, known input/output may derive a missing total explicitly. Billing mode
records subscription, API, local or none according to route; it is not a price
or entitlement. Native provider prose never becomes a counter.

## Calculate a synthetic rate

Continue the IEx exercise with a complete synthetic card:

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

One hundred input tokens at two units per million cost 0.0002 units; twenty
output tokens at ten per million cost another 0.0002. Their sum is 400000 nanos.
Reasoning tokens already included in output do not add another charge. The
calculator uses exact integer intermediate products and rounds up once per
request, after adding components, to one billionth of the configured currency.
Rates are nonnegative decimal strings with at most nine integer and nine
fractional digits. Floats, signs, exponents and unknown dimensions refuse.
Overflow beyond the SDK-safe integer bound returns no amount.

A card contains ID/revision, three-letter uppercase currency, publication date,
source and at most 32 rows within the 16 KiB SDK object bound. Sources are
`https:` without userinfo/query or `operator:` references; neither is fetched.
Rows match exact provider, billing mode, model, endpoint hash, admission date
and input band. Reported model takes precedence; aliases are not inferred.
Null endpoint matches only absent explicit identity. Interval lower bounds are
inclusive and upper bounds exclusive; null upper bounds are open-ended.
Overlapping rows refuse. Unknown input cannot select a finite token band.

API rows require `api_estimate`, subscription rows explicit `api_equivalent`,
and local rows `local_estimate`. Demo is inapplicable. Subscription equivalents
are not API charges, absent local rates do not imply free work, and one billing
mode cannot fall back to another mode's price.

| Input mode | Required rates |
| --- | --- |
| `flat` | `input`, `output` |
| `cache_split` | `input_uncached`, `input_cached`, `input_cache_write`, `output` |
| `cache_ttl_split` | `input_uncached`, `input_cached`, `input_cache_write_5m`, `input_cache_write_1h`, `output` |

Use the exact rate keys in `Costs.schema/0` and the cache fixtures in
`test/extensions_costs_test.exs`. Cache quantities partition inclusive input;
TTL subsets must sum to aggregate writes. Unknown subsets stay unknown unless
known-zero totals establish zero. Contradictions contribute no known input
subtotal. Optional web-search/fetch rates use thousands of reported requests;
duration rates use normalized nanoseconds. Positive unpriced extras keep totals
unknown.

Version-1 cards cover text. Version-2 rows require `operation: "text"` or
`"embedding"` as part of exact matching and overlap identity. Embedding rows
allow flat input and optional duration rates for OpenAI/Ollama, with no invented
output count. Preserve operation when projecting requests into `estimate/2`.
Estimates retain card digest/revision, rated/requested/reported model, row,
basis, currency/scale, components and rounding. `amount_nanos` requires a fully
priced final completed snapshot; `known_amount_nanos` may retain a partial
subtotal. A changed card creates a new estimate without rewriting request facts.

## Read source-bound accounting pages

`Extensions.UsageRead` needs `host.actions` and `host.usage`, separately from
transcript access. Its first successful read freezes the admitted request range:

```json
{"op":"usage.read","cursor":0,"limit":4,"snapshot":null}
```

Later pages echo the exact registered snapshot and caller. New admissions fall
outside that cut. Pages expose canonical request facts, not prompts or directory
selectors. A snapshot with embeddings uses v2 pages and retains operation;
text-only cuts retain v1. Cursor is 0..10000 and limit 1..4. Pages allow 12 KiB
within SDK bounds and refuse overflow. At most 10000 initial successful snapshots
are retained; registered ranges remain readable at that ceiling. Recovery checks
cached pages and resolves initial sources before tail repair without refreshing
or replaying reads. Failures distinguish snapshot, cursor, bounds and capacity.

`Extensions.ChildUsage` additionally requires `host.usage.children`.
`usage.children` enumerates registered direct children; `usage.child.read` takes
their 32-hex child ID and reads canonical requests. Both use cursor, limit 1..4
and nullable snapshot. Discovery omits tasks/results/raw call IDs. Its v2
snapshot binds source, operation, identity and child count. A text child cut
uses snapshot v3/page v1, adding child ID, request count, legacy flag, byte prefix
and accounting-projection digest. Embedding cuts use snapshot v4/page v2.
This digest is not a private transcript hash.

The child reader derives a protected path, holds its native lock, reads at most
16 MiB within five seconds and verifies parent/request/call origin. Unsafe,
busy, missing, malformed or unbound children refuse instead of becoming empty
balances. It never resumes children or traverses recursively. Initial discovery
and child snapshots each have a 10000 ceiling. Recovery checks frozen prefixes
before parent repair; later appends stay outside the cut.

`host.usage.scan` extends only these three reads through steps 17..10000.
Other operations remain within the first sixteen steps, including interleaved
reads. No new scan call starts after 120 seconds; five-second callbacks and
64 MiB worker output still apply. The grant adds no content, inference or write
permission.

## Aggregate revisions without double counting

`Builtins.CostReport` reports one explicit page, at most four requests.
`Builtins.CostSummary` adds scanning over one fixed snapshot and uses the pure
`Usage.CostSummary` accumulator. It keys by session/request/attempt and replaces
cumulative revisions. Admission identity must stay fixed; callers provide
authoritative revision order.

`Builtins.CostTree` separately reads a parent cut, frozen direct-child list and
each child's fixed accounting prefix. These are not one global atomic timestamp.
Unavailable children remain coverage gaps. Own summaries allow 10000 attempts;
tree summaries allow 40000. Billing/basis/operation groups retain their own
known subtotals, unknown counts and overflow. Inapplicable embedding output is
not a missing measurement.

`enumeration_complete` describes the captured range, not a fully priced invoice.
Complete cost coverage also needs no unmetered history, unknown outcomes,
missing rates or overflow. Bounds/incomplete failures never turn truncation
into a successful balance. Interrupted commands are not replayed on resume.

## Verify facts, coverage and arithmetic separately

```sh
mix test test/usage_normalizer_test.exs test/usage_test.exs test/usage_session_test.exs
mix test test/extensions_usage_read_test.exs test/extensions_child_usage_test.exs
mix test test/extensions_costs_test.exs test/embedding_costs_test.exs test/extensions_cost_report_test.exs test/extensions_cost_summary_test.exs
```

Each session allows 10000 requests and 64 observations per request. Inspection
shows the latest sixteen rows plus coverage counts; it does not show every row.
Legacy journals remain explicitly unmetered. Recovery rejects orphan outcomes,
reused attempts, conflicting scope and malformed bindings, while exact repeated
admissions/latest observations/terminal records remain idempotent. Idle resume
dispatches nothing and invents no settlement.

For a new counter, specify units and subset relations before testing missing,
zero, contradictory, partial and final values. For aggregation, test overlapping
pages and a revised request before totals. Pure estimates validate their input
shape, not provenance; host accounting reads supply the validated source binding.
