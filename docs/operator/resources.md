# Inspect usage and limit model work

Use accounting to understand what a session requested and which usage remains
unknown. Add a budget when you want Ipse to reserve a declared allowance before
dispatch. Add a report extension when you need captured totals or estimates from
your own reviewed prices. You can use each independently:

| Need | Control | What it establishes |
| --- | --- | --- |
| Inspect work already attempted | `ipse diagnose` and `ipse budget` | Recorded usage, reservations and uncertainty for the original session |
| Refuse further covered work at a declared allowance | Operator `budget` configuration | Admission against a root-session ledger, including covered child/extension requests |
| Estimate a monetary amount | A pinned rate card and report extension | An estimate from recorded usage and your configured prices |

None is an account-wide spending limit or a provider invoice. Tools and external
services can incur costs outside model accounting. Diagnostic tracing is a
separate optional facility; turning it off does not remove usage or liability.

## Inspect one session

In chat, use `/session` or `/diagnostics`. For saved work:

```sh
ipse diagnose --resume SESSION_ID --state-dir /private/path/sessions
ipse budget --resume SESSION_ID --state-dir /private/path/sessions
```

Use the original ID and store, or omit `--state-dir` for the default. These local
commands make no inference and repair nothing. Diagnosis reports request counts,
unknown outcomes, unmetered history, and the latest 16 request records. Each record
identifies the provider, requested/reported model, selected profile, billing mode,
and request kind. It omits native payloads and prompt/response text.

Null counters mean unavailable, not zero. Failed work can consume resources.
Cache/reasoning counts are breakdowns of inclusive totals; do not add them twice.
Embeddings identify their operation explicitly and have null, inapplicable output
tokens. Parent displays cover parent requests; children keep their own records.

## Reserve requests and tokens

Save this complete operator file as `/private/path/budget.json`. It selects API
billing. Set `OPENAI_API_KEY` privately before making real requests:

```json
{
  "version": 1,
  "settings": {"provider": "openai", "model": "gpt-6.1-sol"},
  "budget": {
    "version": 1,
    "max_requests": 20,
    "max_input_tokens": 100000,
    "reserve_input_tokens": 10000,
    "max_output_tokens": 10000,
    "reserve_output_tokens": 512
  }
}
```

```sh
ipse config --config /private/path/budget.json --no-project-config
ipse chat --config /private/path/budget.json --no-project-config --cwd /path/to/project
```

Configuration inspection makes no network call. During work, each covered request
reserves against the root session's ledger before dispatch. Local children and
accounted extension text/embedding calls share that ledger. Inspect used, reserved,
and uncertain dimensions with `ipse budget`; they are not an invoice guarantee.

The budget is operator-only. A project cannot replace it, even when trusted.
Omit a dimension to leave it unlimited by this policy. Zero refuses positive bookings.

| Field | Allowed value |
| --- | --- |
| `max_requests` | 0..40000 |
| `max_input_tokens`, `max_output_tokens` | 0..1000000000000 |
| `reserve_input_tokens` | 1..1000000000000, required with an input limit |
| `reserve_output_tokens` | 1..1000000, required with an output limit |

Input reservations are your declarations, not estimates derived from context
bytes. Actual usage can exceed them. Aggregate `budget.max_output_tokens` differs
from per-request `settings.max_output_tokens`. The reservation narrows supported
wire output caps along with smaller profile/provider caps. OpenAI API needs at
least 16. ChatGPT subscription does not support that public cap and refuses an
output-token budget; omit both output fields for that route. A child must support
its inherited effective cap before delegation starts.

Grok (`xai` and `xai_oauth`) also refuses an output-token budget: its wire cap
limits visible text but excludes reasoning and function calls. Use a request-count
policy, or another provider with a suitable cap. See [Grok configuration](configuration.md#use-grok-through-xai)
for explicit billing and subscription-registration prerequisites.

Embeddings reserve no generated output tokens. Their request, input, and money
liabilities still apply. Without a budget, Ipse creates no budget worker/ledger
and adds no provider cap. Tools, MCP effects, external-service costs, audio, and
out-of-band inference in trusted code are outside these reservations. A new root
has a new quota; this is not an account-wide spending limit.

## Enable a report without inference

Save this complete configuration as `/private/path/costs.json`. Its empty rate
card exercises reporting without inventing provider prices:

```json
{
  "version": 1,
  "extension_trust": [{
    "artifact": "builtin:cost-summary:1",
    "capabilities": ["invoke.command", "host.actions", "host.usage", "host.usage.scan"],
    "allow_project": false,
    "allow_children": false
  }],
  "extensions": [{
    "instance": "costs",
    "artifact": "builtin:cost-summary:1",
    "enabled": true,
    "options": {"rate_card": {
      "version": 1,
      "id": "my-rates",
      "revision": "reviewed-1",
      "currency": "USD",
      "source": "operator:my-reviewed-rates",
      "published_on": "2026-10-18",
      "rows": []
    }},
    "order": 0,
    "lifetime": "persistent"
  }]
}
```

```sh
ipse config --config /private/path/costs.json --no-project-config
ipse chat --provider demo --config /private/path/costs.json --no-project-config --cwd /path/to/scratch
```

In chat, enter `/ext ext__costs__summary {}`. Expect an own-session report with
no priced real usage. The command makes no model request. To report actual work,
choose your normal provider explicitly, complete a task, then invoke the command.
No report automatically fetches prices or starts inference.
Run later `/ext` commands individually and wait for `Finished.` between them;
they are refused as busy if another operation is still active.

| Artifact | Command for instance `costs` | Coverage |
| --- | --- | --- |
| `builtin:cost-report:1` | `ext__costs__report` | At most four own-session requests per page |
| `builtin:cost-summary:1` | `ext__costs__summary` | Captured own-session totals |
| `builtin:cost-tree:1` | `ext__costs__tree_summary` | Parent and registered direct children |

For pages, change both artifact references to `builtin:cost-report:1` and remove
`host.usage.scan`. Invoke `/ext ext__costs__report {"limit":1}`. Copy the complete
returned `snapshot` and `next` cursor into continuation calls. Null `next` ends
that range. Omit the snapshot to capture a fresh range. Overlapping pages repeat
requests; do not add them twice.

For tree totals, change both references to `builtin:cost-tree:1` and add
`host.usage.children` to the summary grants. `allow_children` controls execution
inside a child, separately from parent-side child reads. In chat:

```text
/ext ext__costs__tree_summary {}
/ext ext__costs__children {}
/ext ext__costs__child_usage {"child_id":"ACTUAL_CHILD_ID"}
```

Use the 32-hex ID returned by discovery and retain page snapshots/cursors.
Tree reports capture parent, discovery, and child cuts separately. Inspect
`child_count`, `captured_child_count`, `gap_count`, and `gap_reasons`. Locked,
missing, invalid, oversized, or legacy-unbound children are gaps, not zero cost.
Unknown child outcomes or cleanup also prevent a complete estimate.

## Configure a rate card

A card records reviewed prices and provenance. This complete card uses synthetic
prices for a model named `fixture`; it is not market pricing:

```json
{
  "version": 1,
  "id": "synthetic-card",
  "revision": "example-1",
  "currency": "USD",
  "source": "operator:synthetic-example",
  "published_on": "2026-10-18",
  "rows": [{
    "id": "fixture-model",
    "provider": "openai",
    "billing_mode": "api",
    "basis": "api_estimate",
    "model": "fixture",
    "endpoint_sha256": null,
    "from": "2026-01-01",
    "until": "2027-01-01",
    "input_min": 0,
    "input_max": null,
    "input_mode": "flat",
    "rates": {"input": "2", "output": "10"}
  }]
}
```

Put your reviewed card in `extensions[].options.rate_card`. Up to 32 nonoverlapping
rows match provider, billing mode, model, endpoint digest, admission date, and
input band. `until` is exclusive. Null opens an upper bound. Reported model
identity takes precedence over a requested alias. Default endpoints use null;
custom endpoints need the recorded digest. Keep secrets out of card URLs.

Token rates are decimal strings per million tokens. Supported search/fetch extras
are per thousand requests; duration is per second. Cache-split modes need their
component rates. [Accounting training](../developer/accounting.md) defines exact
arithmetic and selection. Missing rates remain unknown. Estimates retain the card
revision/digest and provenance, and never contact a price service.

OpenRouter uses `provider: "openrouter"`, `billing_mode: "api"` and
`basis: "api_estimate"`; its provider-reported credit `cost`/`cost_details` fields
are ignored. Local compatible servers use `provider: "openai_compatible"`,
`billing_mode: "local"` and `basis: "local_estimate"`. Cached and reasoning
counts are subsets of Chat Completions prompt/completion totals. Without a
matching reviewed row, the amount remains unpriced/null rather than zero.
Upstream is not a rate-card dimension: use prices appropriate to the pinned
routes in that session, or leave them unpriced when one row cannot express them.

For an OpenRouter row, copy the complete synthetic example above and change
`provider` to `openrouter` and `model` to the exact reported model, then replace
the synthetic prices and provenance with your reviewed rates. Gemini rows use
`provider: "gemini"`, `billing_mode: "api"` and `basis: "api_estimate"`, with the
reported model version. Gemini input includes separate prompt and tool-use prompt
counts, and output includes candidates and thoughts. If the API omits a needed
count, pricing remains partial/unpriced. Key presence establishes neither a free
tier nor zero cost.

Grok API rows use `provider: "xai"`, `billing_mode: "api"` and
`basis: "api_estimate"`; subscription rows use `provider: "xai_oauth"`,
`billing_mode: "subscription"` and `basis: "api_equivalent"`. Modern Responses
output includes reasoning. Older prompt/completion-style examples differ in
whether completion includes reasoning. Ipse uses the reported total to resolve
that distinction and counts it once; missing evidence stays partial. Mixed
counter dialects and contradictory totals refuse normalization. A valid provider-reported
`cost_in_usd_ticks` is retained with a completed native response, separately from
these configured estimates. It is not used as an invoice reconciliation or a
subscription balance, and does not supply an aggregate price when a reviewed
rate-card row is missing.

For embeddings, use version 2 and declare `operation: "text"` or `"embedding"`
on every row. Embedding rows use flat input and optionally `duration_second`;
they have no output/cache/search/fetch rates. A text row cannot price embeddings
merely by matching the model. Positive duration without a configured rate leaves
the estimate partial. `api_estimate`, `api_equivalent`, and `local_estimate` are
distinct bases. Subscription equivalence is not API spend. Use a three-uppercase-
letter currency. Changing a pinned card requires a fresh session.

## Reserve configured money

A monetary budget needs both a rate card and a `money` array inside `budget`.
The report extension's card is a separate selection; enabling a report does not
install a spending policy. This complete example deliberately names a synthetic
model and prices. Save it as `/private/path/money-budget.json` and inspect it
offline before substituting a real route:

```json
{
  "version": 1,
  "settings": {"provider": "openai", "model": "fixture"},
  "budget": {
    "version": 1,
    "max_requests": 20,
    "money": [{
      "basis": "api_estimate",
      "limit_nanos": 1000000000,
      "reserve_nanos": 50000000
    }],
    "rate_card": {
      "version": 1,
      "id": "synthetic-card",
      "revision": "example-1",
      "currency": "USD",
      "source": "operator:synthetic-example",
      "published_on": "2026-10-18",
      "rows": [{
        "id": "fixture-model",
        "provider": "openai",
        "billing_mode": "api",
        "basis": "api_estimate",
        "model": "fixture",
        "endpoint_sha256": null,
        "from": "2026-01-01",
        "until": "2027-01-01",
        "input_min": 0,
        "input_max": null,
        "input_mode": "flat",
        "rates": {"input": "2", "output": "10"}
      }]
    }
  }
}
```

```sh
ipse config --config /private/path/money-budget.json --no-project-config
```

Expect the selected `openai/fixture` route and the admitted policy; this inspection
makes no request and does not validate those prices or model availability. Before
real work, choose an available model, update its matching rate-card row and replace
all synthetic prices, dates and provenance with reviewed values. Keep the policy
fixed for that session. Use the earlier chat procedure with this configuration,
then inspect `ipse budget` using the resulting session ID and store.

The bucket reserves 0.05 toward a limit of 1 in the card currency. Nanos have nine
decimal places and cannot exceed 9007199254740991; the reservation must be positive.
At most one bucket is allowed per estimate basis. A bucket covers only its matching
billing mode; the request limit also bounds the number of covered attempts. Add
token limits or other explicit bases if the selected routes need them. A missing
price leaves uncertainty and retains liability rather than proving free work.

## Read uncertainty and recover

`enumeration_complete` means the captured requests were read. A complete cost
estimate additionally needs priced final usage, no unmetered history, and no
overflow. `known_subtotal` and `known_amount_nanos` contain only known amounts;
missing/partial totals remain null. Divide nanos by one billion for currency units.

`report_bounds` may return a retry cursor/snapshot; issue a new explicit command
with a smaller page. `summary_bounds` provides no complete total, so use pages.
`summary_incomplete` means reading failed. No result is silently truncated.
Child scans take protected journal locks and read at most 16 MiB per captured
prefix. Discovery supports 10000 children; tree accumulation supports 40000 unique
attempts, and extended accounting scans allow 10000 reads within two minutes.
Ordinary non-accounting actions retain the 16-step limit.

Known successful work releases unused reservations. Failed, cancelled, interrupted,
or unmetered work retains at least its booking and observed liability. A parallel
admission failure can cancel a sibling and leave its booking held even before
provider dispatch. Final overdraw refuses assistant/tool admission; previously
streamed text cannot be retracted. Unknown prices/counters and settlement failures
retain liability. Accounting attempts and durable budget bookings can differ.

Use `/cancel` to stop work. Idle resume neither redispatches requests nor resets
quotas or recalculates committed reports. Keep the original policy. Ledger files
live at `STATE_DIR/budgets/ROOT_SESSION_ID.jsonl`, with stable owner-only locks.
Do not delete locks, truncate records, or edit balances. Unsafe, missing, busy,
inconsistent, oversized, or torn state refuses admission/resume. Preserve it and
follow [recovery](recovery.md). A reviewed new-root handoff does not transfer or
refund the old liability. Turning tracing off deletes no usage or journal facts.
