> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/operator/resources.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Limit admitted model work for a session tree

Configure a budget when you want Ipse to reserve a finite allowance before
covered model requests. One root session and its local children share a ledger.
The budget covers main requests, summaries, child requests, and accounted
extension text and embedding calls. It does not create an operator-wide account or guarantee
a provider invoice ceiling.

## Start with request and token reservations

Save this complete example as an operator file. It selects OpenAI API billing;
supply `OPENAI_API_KEY` privately before making real requests. The model must be
available to your account.

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

Inspect it without inference, then start work:

```sh
ipse config --config /private/path/budget.json --no-project-config
ipse chat --config /private/path/budget.json --no-project-config --cwd /path/to/project
```

The first command shows policy without authentication or network calls. In chat,
ask for a small task. `/diagnostics` shows request accounting; inspect the separate
reservation ledger with the session ID:

```sh
ipse budget --resume SESSION_ID
```

Add the original `--state-dir` if customized. Ledger inspection is local and
makes no model request. Expect used/reserved dimensions and uncertainty, rather
than a promise of exact billed cost.

## Choose dimensions that fit your provider

`budget` is operator-only. Projects cannot set or replace it, even with project
trust. It requires version 1 and at least one limit. Omit a dimension to leave
it unlimited by this policy. Zero is valid and refuses positive reservations.

| Field | Range and requirement |
| --- | --- |
| `max_requests` | 0..40000 |
| `max_input_tokens`, `max_output_tokens` | 0..1000000000000 |
| `reserve_input_tokens` | 1..1000000000000; required with an input limit |
| `reserve_output_tokens` | 1..1000000; required with an output limit |

Input reservations are declarations you choose, not a token count inferred from
context bytes. Pick them for the task and growing conversation. Actual input
usage may exceed the booking.

Aggregate `budget.max_output_tokens` differs from per-request
`settings.max_output_tokens`. The output reservation also narrows each supported
provider cap, alongside smaller settings/profile/adapter limits. OpenAI API needs
a resulting cap of at least 16. ChatGPT subscription does not support that public
cap and refuses an output-token budget. For subscription use, omit both output
fields and use request/input or separately configured equivalent-money policy.
Ipse never drops an unsupported cap or changes billing mode to proceed.

An [embedding request](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/embeddings.md) has no generated-output-token dimension.
It uses zero output liability under this policy, with a null, explicitly
inapplicable canonical output count. Output reservations never become embedding
wire caps. Its request/input/money allowances still share the same tree, and
missing applicable counters or unknown prices retain reservations.

Routed children inherit the tree policy. Their provider must support the effective
cap before delegation starts. With no budget configured, no budget worker,
ledger, directory, or extra provider cap is created.

## Add configured money estimates when needed

Money limits require `budget.money`, an array of buckets, and its sibling
`budget.rate_card`. This complete configuration uses a synthetic model and prices
so you can inspect the policy without inference. Save it as
`/private/path/money-budget.json`:

```json
{
  "version": 1,
  "settings": {"provider": "openai", "model": "fixture"},
  "budget": {
    "version": 1,
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

Expect one money bucket and the embedded card in the inspected budget. Before
using it for real work, replace the model, rates, dates and provenance with your
reviewed values as described in [Usage accounting](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/usage-accounting.md#configure-a-rate-card).
No price service is queried. This bucket reserves 0.05 toward a limit of 1 in the
configured card's currency. Integers
use nine decimal places and cannot exceed 9007199254740991. `reserve_nanos` must
be positive. Configure at most one bucket each for `api_estimate`,
`api_equivalent`, and `local_estimate`. A bucket applies only to its matching
billing mode. API-only policy does not restrict subscription/local estimates;
use a shared request/token quota or configure those bases explicitly.

Endpoint/model identity, date/input bands, currency, and rates all come from your
card. Missing rates, ambiguous identity, or missing counters retain the booking
and mark uncertainty. A subscription equivalent is not API spend. Known monetary
overflow is overdraw, never zero.

## Interpret refusal and unknown liability

Admission reserves before provider dispatch. Fully known successful requests
release unused reservations. Failed, cancelled, interrupted, or unmetered work
retains at least its booking and observed liability. A parallel child's admission
failure can cancel a sibling whose booking remains held conservatively, even
when it never reached the provider.

A live overdraw stops the provider path. Overdraw discovered only in final usage
refuses assistant/tool admission while preserving observed usage. Another child
can overdraw the shared tree and cause an otherwise within-reservation response
to be refused. Already streamed text cannot be retracted; refused final/native
content has no saved quarantine export. Future admission refuses while a limit
is exhausted or the tree is overdrawn.

The text path durably covers usage before forwarding it to canonical accounting.
Embedding can retain genuine final counters after a guarded write fails, while
refusing readable vectors. Resume refuses unproven ledger coverage. A busy or
unwritable ledger can leave a reservation held; unavailable metering never means
zero. Budget request counts count durable reservations; accounting may also
include attempts refused before dispatch, so counts can differ.

Tool/MCP effects, audio, external-service costs, and out-of-band
inference from trusted code are not covered. A new root gets a new quota. Fixed
reservations cannot bound actual unmetered consumption.

## Stop and recover without rewriting balances

Cancel with `/cancel`, or exit with `/exit`. Cancellation does not refund unknown
work. Idle resume neither redispatches requests nor resets quotas. Keep the
original operator policy to resume; changing/removing it is a compatibility error.
After a temporary lock is released, a consistent session can resume idle without
replay. This does not repair corrupt state.

Ledger files live at `STATE_DIR/budgets/ROOT_SESSION_ID.jsonl` with an owner-only
stable `.lock`. Never delete locks, truncate ledgers, or alter records to free
quota. Missing, unsafe, busy, inconsistent, or oversized state refuses admission
or resume. Torn tails also refuse; there is no automatic forgiveness or repair.

If the tree cannot be resumed, preserve ledger and journal. Export a reviewed
[handoff](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/recovery.md#continue-in-a-fresh-session) from the validated conversation
and inspect unknown effects before starting fresh. The new root has a separate
quota. It neither releases nor transfers old liability.
