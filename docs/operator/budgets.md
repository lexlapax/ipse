# Shared admission budgets

An optional operator policy limits reservations for one session tree: main and
summary requests, local-child requests and accounted extension model calls from
any session in that tree. Parallel children use the same ledger. The host enforces
admission before the provider path. It works independently of
cost-report extensions and diagnostic capture. With no policy, no budget worker,
directory, ledger or provider cap is created.

This is a session-tree quota, not an operator-wide spending account or an invoice
ceiling. A new root session gets a separate quota. Input usage and configured
cost estimates can exceed their reservations; unsupported or missing metering
cannot establish an exact charge. Tool effects, MCP services, embeddings, audio
and direct external inference are not covered. Reviewed extensions use the
[accounted model operation](extensions.md#accounted-model-calls) to share admission;
trusted executable code making out-of-band calls is not confined by this API.

## Configure the operator policy

Put `budget` at the top level of the operator JSON file, selected with `--config`
or discovered under `IPSE_HOME`. Project configuration cannot set it, even with
project trust. This example uses no credentials or price service:

```json
{
  "version": 1,
  "settings": {"provider": "openai", "model": "gpt-4.1-mini"},
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

Inspect it locally before starting work:

```sh
./bin/ipse config --config /path/to/budget.json --no-project-config
./bin/ipse chat --config /path/to/budget.json --no-project-config
```

The model name is illustrative, not a claim of account eligibility. Starting a
real API request uses separate API billing. No inference occurs during `config`.

Every policy needs version 1 and at least one limit. Omit dimensions you do not
want to limit; zero is a valid limit and refuses positive reservations. Request
limits range from 0 to 40,000. Input/output totals range from 0 to 10^12; each token
limit requires its corresponding positive `reserve_*_tokens`. Input reservations
are operator declarations, not tokenization or estimates derived from context
bytes. Pick values that account for the actual task and accumulated context.

`budget.max_output_tokens` is the **aggregate** output quota.
`budget.reserve_output_tokens` also narrows the supported **per-request** provider
cap, together with any smaller `settings.max_output_tokens`, profile cap or adapter
limit. Output reservations range from 1 to 1,000,000; OpenAI API requires a resulting
cap of at least 16. See [provider limits](../developer/provider-limits.md).

ChatGPT subscription does not support the public output-cap field and refuses
an output-token budget. Request-count, input-reservation and separately configured
subscription-equivalent money policies remain usable. Ipse never drops an
unsupported cap or changes provider/billing mode to satisfy the policy. Selected
child profiles inherit the same tree policy and private root authority; their
different provider must support its effective cap before delegation can proceed.

## Configure estimated-money reservations

Optional `money` and `rate_card` must appear together. Reuse the versioned rate-card
format from [cost reporting](usage-accounting.md#enable-the-optional-report).
Each money bucket has exactly `basis`, `limit_nanos` and `reserve_nanos`:

```json
{"basis": "api_estimate", "limit_nanos": 1000000000, "reserve_nanos": 50000000}
```

The example reserves 0.05 toward a limit of 1 in the card's currency; it is a bucket
fragment, not a complete configuration. Integers use nine decimal places and
cannot exceed 9,007,199,254,740,991. Reservations must be positive. Configure at
most one bucket for each of `api_estimate`, `api_equivalent` and `local_estimate`.
Each applies only to its matching billing mode. An API bucket alone does not
restrict subscription or local resource estimates; configure those explicitly
or use a shared request/token quota. Subscription equivalence is not API spend.

Rates, model/endpoint identities, validity bands, currency and provenance are
operator supplied. Missing rates, ambiguous identities or missing counters retain
the booking and mark uncertainty. There is no lookup or silent price fallback.
Known amount overflow remains an overdraw, never a zero balance.

## Inspect, stop and recover

```sh
./bin/ipse budget --resume SESSION_ID --state-dir /path/to/sessions
```

This local JSON inspection reads the saved policy and protected ledger without
auth, inference, quota changes or journal repair. It reports root identity,
reserved/refused request counts, unsettled/partial/unknown counts, dimensions,
overdraw, configured currency/scale and policy digest. Overflowed booked amounts are null with `overflow:
true`; they are not zero. Inspection validates ledger structure, not a complete
cross-check against all conversation journals. Actual session resume additionally
validates own and registered-child accounting before repairing a torn journal tail.

Budget request counts count durable reservations. Canonical usage reports also
include attempted requests refused before provider dispatch, so their request
counts can differ. Reports and budget inspections are separate views.

Successful fully known requests release unused reservations. Failed, cancelled,
interrupted or unmetered requests retain at least their booking and observed
liability. Parallel delegation's existing failure policy can cancel a reserved
sibling when another child refuses admission; its booking remains conservative
even if it never reaches the provider. A live overdraw stops the provider path; an overdraw discovered only
in final usage refuses assistant/tool admission and preserves the counters.
Already streamed text cannot be retracted. Future admissions refuse while the
tree is overdrawn or another configured dimension is exhausted.

Cancellation and `/quit` use ordinary owned shutdown. Resume is inert: it does
not refund unknown work, redispatch requests or reset quotas. Keep the original
operator configuration to resume; changing/removing its policy is a mismatch.
For new work, choose a new session deliberately, understanding its separate quota.

State lives in `STATE_DIR/budgets/ROOT_SESSION_ID.jsonl` with an owner-only stable
`.lock`. Do not delete lock files or edit/truncate the ledger to free quota.
Missing, unsafe, inconsistent, oversized or busy state refuses admission/resume;
there is no automatic repair or forgiveness command. A crash between canonical
request intent and its budget decision also requires inspection rather than
guessing whether quota can be released. Preserve all original files for diagnosis.
Same-user filesystem control is not an adversarial security boundary.

See [the developer contract](../developer/budgets.md) for durability, bounds and
verification, and [troubleshooting](troubleshooting.md#session-locks-and-interrupted-work)
for session ownership and unknown effects.
