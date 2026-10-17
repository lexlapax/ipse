# Configurable usage estimates

P23 starts with `Ipse.Extensions.Costs`, a pure extension-side calculator over
explicit data. It validates a versioned rate card and estimates one canonical
cumulative request snapshot. It performs no IO, pricing lookup, model request,
state mutation, subscription or request admission. No rates ship enabled and no
provider/model price is embedded. Default-off report and summary extensions
use the granted accounting-read SDK for explicit own-session pages and captured
session totals. See
[operator selection](../operator/usage-accounting.md#enable-the-optional-report).
Child aggregation, accounted model operations and budget enforcement remain P23
delivery work.

## Rate identity and selection

`schema/0` returns the closed schema; `validate/1` reuses the existing bounded
JSON Schema adapter plus semantic date, decimal and overlap checks. A card has
version 1, ID, revision, uppercase three-letter currency label, publication date,
source and up to 32 rows. The existing SDK object bounds apply, including 16 KiB
per object. Currency is an explicit label, not an exchange-rate or ISO-registry
lookup. A source is `https:` without user information/query, or an `operator:`
reference; neither is fetched.

Each row selects exact provider, billing mode, model and endpoint hash, a UTC
admission-date interval and an input-token interval. Dates use `YYYY-MM-DD`;
intervals include the lower bound and exclude the upper bound, with null upper
bounds allowed. Intersecting date/token bands for the same identity refuse.
Unknown input cannot select a finite token band. A reported model takes precedence
over the requested model; aliases do not silently match. Null endpoint matches
only a request with no explicit endpoint hash, never an arbitrary custom endpoint.

The basis must match billing: API → `api_estimate`, subscription → explicitly
configured `api_equivalent`, local → `local_estimate`. An API row cannot price
a subscription/local request. Missing subscription pricing says it is not API
spend; missing local pricing remains unconfigured, not free. Scripted demo usage
is not applicable. These are estimates of configured measured dimensions, not
account charges or invoices.

## Units and arithmetic

Rates are nonnegative decimal strings, with at most nine fractional digits and
nine integer digits. Floats, exponents, signs and unsupported dimensions refuse.
Token rates are currency per million tokens, web-search/fetch rates per thousand
reported requests, and duration rates per second against normalized nanoseconds.

| Input policy | Required token rates | Interpretation |
| --- | --- | --- |
| `flat` | `input`, `output` | Operator-selected approximation applying one rate to all input tokens |
| `cache_split` | `input_uncached`, `input_cached`, `input_cache_write`, `output` | Inclusive input minus known cached/write subsets; no double counting |
| `cache_ttl_split` | `input_uncached`, `input_cached`, `input_cache_write_5m`, `input_cache_write_1h`, `output` | Aggregate writes must equal the sum of known TTL subsets |

Reasoning tokens are already within output and have no additional rate dimension.
Unknown cache breakdowns do not become zero. Zero inclusive input or zero aggregate
writes can mathematically establish zero subsets. Contradictory partitions are
excluded from the known subtotal. Optional `web_search`, `web_fetch` and
`duration_second` rates need their corresponding counts; a positive reported extra
without a rate keeps the total unknown. Unreported, unconfigured extras are outside
the stated `text_tokens_and_reported_extras` scope, not certified zero charges.

OTP integers retain exact intermediate products with a common denominator.
The calculator adds components before rounding up once per request to one
billionth of the configured currency (`currency_scale: 9`). It never uses binary
floating point for money. A result above the SDK-safe integer bound is an explicit
overflow with no amount. This fixed precision and bounded decimal syntax need no
general decimal-arithmetic package; the schema adapter, normalized counters,
canonical digest and OTP arithmetic are already dependencies.
[Decimal 3.1.1](https://decimal.hexdocs.pm/readme.html), Apache-2.0, was evaluated
for its arbitrary decimal precision and bounded parsing. This contract deliberately
accepts only a fixed nonnegative nine-place format and performs exact integer
products before one rounding step, so no decimal context, arbitrary exponent or
additional package is needed. Reevaluate Decimal if that numeric contract expands.

## Input and result

`estimate/2` requires exactly these request fields, selected from validated host
accounting: `provider`, `billing_mode`, `model`, `reported_model`,
`endpoint_sha256`, `admitted_at_ms`, `outcome`, `finality`, `usage`. Usage must be
a valid normalized record. The calculator validates data; it does not authenticate
a caller's claimed accounting or read a private Session/journal.

An estimate identifies provider/billing, requested/reported/rated model, endpoint
hash and admission time, plus card revision/digest, source/publication date,
selected row/input policy, currency/scale, basis, components and rounding rule.
`amount_nanos` is present
only for a fully priced final completed snapshot. `known_amount_nanos` can retain
the priced subtotal of partial/unknown work; it stays null when nothing is known.
Missing rates/counts, invalid partitions, incomplete requests and overflow have
explicit reasons. A known observed zero is different from an unknown total.

Recompute from the latest cumulative snapshot, not by adding successive provider
observations. The calculator has no mutable ledger or deduplication state; the
report caller must retain request/attempt identity, replace revisions and avoid
counting a child twice. Card changes produce a different digest and estimate;
they do not rewrite saved request facts or retrospectively certify a bill.

## Reports, cumulative aggregation and evidence

`Ipse.Extensions.Examples.CostReport` declares one operator command and no model
tool or lifecycle subscription. `host.actions` plus `host.usage` permits a bounded
`usage.read` operation; it grants no prompt/history, write, model or child access.
The [accounting-read contract](usage-accounting.md#extension-accounting-reads)
owns snapshot identity, canonical records, paging and recovery validation.

Each explicit report prices at most four returned requests. Its groups are page
totals separated by provider, billing and estimate basis. Unknown costs do not
become zero, and a summed amount can overflow even when individual quotes fit;
both cases keep the total null. Request/attempt/parent/profile identities remain
available for future aggregation. The configured rate card is identified once
per report, with row/input policy, components and model attribution per request.
Repeated/overlapping pages must not be added blindly. The report never claims a
whole-session or child balance, and old cached reports do not reprice on resume.

`Ipse.Extensions.Examples.CostSummary` supplies the separate
`builtin:cost-summary:1` command, with the explicit `host.usage.scan` capability.
It follows every page of one snapshot and passes each canonical row to the pure
`Ipse.Extensions.CostSummary` accumulator. The accumulator keys contributions by
session/request/attempt identity, replacing a cumulative revision instead of
adding it. Admission identity must stay unchanged. Callers supply revisions in
authoritative order; token values or timestamps do not establish revision order.
Repeated or overlapping pages do not multiply a request. Separate attempts remain
separate liability. Each command starts a fresh accumulator and one rate card;
rate revisions are never mixed in a total.

Groups retain billing/basis separation, known monetary subtotals, unknown-cost/
outcome counts and normalized counter summaries. Each counter has `total`,
`known_subtotal`, `unknown_count` and `overflow`; partial outcomes prevent a final
total even when their observed counts are known. Each dimension is summed
independently, preserving cache/reasoning subsets without double counting them.
Exact intermediate integers may exceed SDK-safe precision; overflowing output
totals/subtotals become null with an explicit flag.

`enumeration_complete` requires the entire captured own-session request count.
`cost_estimate_complete` additionally excludes unmetered history and unknown or
overflowing monetary totals. Neither is an invoice guarantee or a child-journal
claim. A result too large for the SDK returns `summary_bounds`, without a
truncated success; a failed read returns `summary_incomplete`. Deadline,
cancellation or worker interruption retains the ordinary unknown invocation
semantics and never causes automatic replay.

Semantic card errors return `invalid_rate_card`; malformed snapshots return
`invalid_arguments` or the host's fixed failure code. A report exceeding the SDK
object bound returns `report_bounds` with an unchanged retry cursor and snapshot,
without silently dropping requests. Bundled artifact identity pins the report
and calculator BEAM files; the summary also pins its accumulator. Host identity
pins the read implementation. All pricing/grouping behavior stays in extensions.

Fifteen focused fixtures cover exact arithmetic/rounding, cache/TTL partitions,
reasoning inclusion, missing/zero/contradictory counters, partial work, subscription/
local/demo distinction, request/duration extras, dates/bands, exact model/endpoint
matching, revision provenance, invalid schemas/decimal inputs and overflow. They
use synthetic rates and no service/account. Independent-worker reader fixtures
cover private exclusion, stable pages beyond sixteen requests, caller/session
refusal, unknown/legacy usage, snapshot limits, source/page forgery, cancellation
and inert resume. Report/summary fixtures cover real callbacks, separated billing
groups, unknown totals, cost/counter overflow, cumulative replacement, immutable
admission and known invalid-card results. A 70-request worker scenario reads 18
pages and validates byte-identical idle resume; it crosses the ordinary 16-step
limit under a separate read grant. The credential-free `priv/cost-report-demo.exs`
also runs both extensions in extracted-package verification. See
[actual checks](testing.md#current-evidence-and-next-checks).

P23 next needs explicit parent/child aggregation. Atomic covered
request reservations, partial/unknown liability and provider-enforceable output
bounds belong in host admission. Generic accounted extraction/embedding requests
are required for P25. A calculator or event observer cannot supply those guarantees.

## Primary-source review

Reviewed on 2026-10-17; no published numeric rate is copied into runtime defaults:

- OpenAI pricing varies by model, cache category, context band and processing
  mode. Those dimensions require explicit configured rows; a model string alone
  cannot establish an invoice. [API pricing](https://developers.openai.com/api/docs/pricing).
- OpenAI output includes non-visible generated tokens; the output limit applies
  beyond displayed text. Meter output once, retaining reasoning as a breakdown.
  [Reasoning and cost control](https://developers.openai.com/api/docs/guides/reasoning).
- Anthropic separates cache reads and TTL-specific writes and documents additional
  context/geography/tool modifiers. A configured scope must not silently promise
  coverage of unsupported charges. [Pricing](https://platform.claude.com/docs/en/about-claude/pricing).
- Ollama reports token counts and nanosecond durations. Those measurements do not
  determine hardware/electricity prices. [Usage metrics](https://docs.ollama.com/api/usage).
