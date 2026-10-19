# Calculating and reporting configured costs

Cost reporting is extension behavior. `Ipse.Extensions.Costs` is a pure calculator
that receives a validated rate card and one canonical cumulative request record.
It performs no IO, pricing lookup, inference, mutation, subscription, or admission.
No rates are enabled by default. [Shared budgets](budgets.md) enforce separately.

Begin with `lib/ipse/extensions/costs.ex` and the synthetic `card/0` and `request/2`
helpers in `test/extensions_costs_test.exs`. These helpers make the entire pricing
input visible. Avoid using a live price service to test arithmetic.

## Calculate one request by hand

The flat-rate fixture prices 100 input and 20 output tokens at synthetic rates of
2 and 10 currency units per million tokens:

```text
input:  100 × 2  / 1,000,000 = 0.0002
output:  20 × 10 / 1,000,000 = 0.0002
amount: 0.0004 = 400,000 nanos at currency_scale 9
```

Seven reasoning tokens in the output breakdown do not add another charge. They
are already included in the 20 output tokens. Follow this case through
`Costs.estimate/2`, then change the input mode to `cache_split` in the next fixture.
Cached input and cache writes partition inclusive input; they do not increase it.

The calculator uses exact integer intermediate products and adds components before
rounding up once per request to one billionth of the configured currency. Rates
are nonnegative decimal strings with at most nine integer and nine fractional
digits. Floats, signs, exponents, and unknown dimensions refuse. Overflow beyond
the SDK-safe integer bound produces an explicit overflow and no amount.

## Match a rate row deliberately

A version-1 card has ID, revision, uppercase three-letter currency label,
publication date, source, and up to 32 rows, within the 16 KiB SDK object limit.
The currency label is not an exchange-rate lookup. Sources are `https:` without
userinfo/query or `operator:` references; neither is fetched.

A row matches exact provider, billing mode, model, endpoint hash, admission date,
and input-token band. Reported model takes precedence over requested model; no
alias is inferred. Null endpoint matches only absent explicit endpoint identity.
Date and token intervals include their lower bound and exclude their upper bound;
null upper bounds are open-ended. Overlapping rows for the same identity refuse.
Unknown input cannot select a finite token band.

| Billing mode | Required basis |
| --- | --- |
| API | `api_estimate` |
| Subscription | explicitly configured `api_equivalent` |
| Local | `local_estimate` |
| Demo | Not applicable |

Subscription equivalents are not API charges. Missing local prices do not imply
free computation. A card cannot price another billing mode by fallback.

| Input mode | Required rates |
| --- | --- |
| `flat` | `input`, `output` |
| `cache_split` | `input_uncached`, `input_cached`, `input_cache_write`, `output` |
| `cache_ttl_split` | `input_uncached`, `input_cached`, `input_cache_write_5m`, `input_cache_write_1h`, `output` |

TTL subsets must sum to aggregate writes. Unknown subsets remain unknown unless
known zero totals establish zero. Contradictory partitions cannot contribute a
known input subtotal. Optional `web_search` and `web_fetch` rates use thousands of
reported requests; `duration_second` uses normalized nanoseconds. Positive extras
without a rate keep the total unknown.

## Keep estimates tied to accounting

`estimate/2` accepts exactly `provider`, `billing_mode`, `model`, `reported_model`,
`endpoint_sha256`, `admitted_at_ms`, `outcome`, `finality`, and normalized `usage`.
It validates those values but does not authenticate their provenance. Host
[accounting reads](usage-accounting.md) provide authenticated session projections.

A result retains card digest/revision, row, rated/requested/reported model,
source/date, basis, currency/scale, components, and rounding rule.
`amount_nanos` exists only for a fully priced final completed snapshot.
`known_amount_nanos` can preserve a partial subtotal. Missing data never becomes
zero, and a changed card creates a new estimate without rewriting request facts.

## Follow the report family

`Examples.CostReport` reads at most four requests per explicit page using
`host.actions` and `host.usage`. It has no model tool, transcript grant, or write
permission. Its totals describe that page, not the whole session.
`Examples.CostSummary` adds `host.usage.scan`, follows one captured snapshot, and
uses the pure `Ipse.Extensions.CostSummary` accumulator. The accumulator keys by
session/request/attempt and replaces cumulative revisions instead of adding them.
Admission identity must remain fixed; callers supply authoritative revision order.

`Examples.CostTree` separately requires `host.usage.children`. It combines a
parent cut, a frozen registered-child list, and each child's fixed accounting
prefix. These are separate captured cuts, not a globally atomic timestamp.
Unavailable children remain gaps. The tree accumulator permits 40,000 attempts;
own-session summaries permit 10,000. Billing/basis groups retain known subtotals,
unknown counts, and overflow independently.

`enumeration_complete` means the captured request range was read. Complete costs
also require no unmetered history, unknown outcomes, missing rates, or overflow.
Neither flag certifies an invoice. `report_bounds`, `summary_bounds`, and
`summary_incomplete` refuse or report incomplete coverage rather than truncate a
successful balance. Interrupted commands are never replayed on resume.

```sh
mix test test/extensions_costs_test.exs test/extensions_cost_report_test.exs test/extensions_cost_summary_test.exs
```

Use the arithmetic suite for row selection and units; use worker suites for actual
read capabilities, stable pages, bounded results, and saved receipts. When changing
aggregation, test overlapping pages and a revised request before testing totals.
