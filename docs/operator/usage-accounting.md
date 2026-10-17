# Inspect request usage and configured costs

## Recorded counters

Interactive `/diagnostics` and `/session` include mandatory `accounting`, whether
or not an extension or tracing is enabled. Inspect a saved session without
starting a model or repairing its journal:

```sh
./bin/ipse diagnose --resume SESSION_ID --state-dir /path/to/sessions
```

Accounting shows total request count, unknown-outcome count, whether historical
usage is unmetered, and the latest 16 request records. Records identify provider,
requested/reported model, selected profile where configured, billing mode,
main/summary kind and nullable normalized counters. Child records live in their
own journals under `sessions/subagents/PARENT_SESSION_ID` and identify the parent
request. The parent display does not yet sum child usage. See
[subagents](subagents.md) for ownership and approvals.

## Enable the optional report

Two shipped extensions provide explicit operator commands: `builtin:cost-summary:1`
summarizes a captured session range, and `builtin:cost-report:1` shows individual
requests in pages. Both are disabled by default, with no automatic hook, rate
lookup, model request or child-journal access. Configure operator trust and a
rate card. This summary example deliberately has no price rows, so unmatched
usage stays unpriced:

```json
{
  "version": 1,
  "extensions": [{
    "instance": "costs",
    "artifact": "builtin:cost-summary:1",
    "enabled": true,
    "options": {"rate_card": {
      "version": 1,
      "id": "my-rates",
      "revision": "2026-10-17",
      "currency": "USD",
      "source": "operator:my-reviewed-rates",
      "published_on": "2026-10-17",
      "rows": []
    }},
    "order": 0,
    "lifetime": "persistent"
  }],
  "extension_trust": [{
    "artifact": "builtin:cost-summary:1",
    "capabilities": ["invoke.command", "host.actions", "host.usage", "host.usage.scan"],
    "allow_project": false,
    "allow_children": false
  }]
}
```

Use your reviewed rate rows for the exact provider, billing, requested/reported
model, endpoint identity, admission date and input-token band. The
[rate-card contract](../developer/costs.md#rate-identity-and-selection) defines
fields, decimal rates, units and supported pricing dimensions. No default service
supplies prices. A card revision changes the pinned extension configuration;
start a fresh session after edits instead of silently repricing a resumed one.

For a credential-free configuration check, launch with your actual file path:

```sh
./bin/ipse chat --provider demo --config /path/to/operator.json --no-project-config
```

In chat, request the summary explicitly:

```text
/ext ext__costs__summary {}
```

For individual request pages, select `builtin:cost-report:1` in both artifact
fields and remove `host.usage.scan` from trust. Its command is
`/ext ext__costs__report {}` or `/ext ext__costs__report {"limit":1}`. Separate
instances may enable both with distinct names.

For real usage, select your normal provider/profile explicitly. Neither command
starts inference. Disable an instance for future sessions with `enabled: false`,
or use `--no-extensions`. See [selection and executable trust](extensions.md).

## Understand scope and totals

The summary reads all canonical requests in its captured range, including those
older than the latest-sixteen display. `coverage: "session"` excludes child
journals. `enumeration_complete` says the captured requests were all read;
`cost_estimate_complete` additionally requires priced final usage and no unmetered
history or monetary overflow. A completed scan can therefore have unknown costs.
The snapshot includes `legacy_unmetered`; it must remain visible when old work
has no canonical records. Starting another summary captures later work anew.

Groups separate providers, billing modes and estimate bases; API spend estimates
are never added to subscription equivalents or local estimates. Counter `total`
is null for missing, partial or overflowing usage; `known_subtotal` retains only
known observations. Cache and reasoning counters are breakdowns of inclusive
token totals. Do not add those fields to inclusive totals.

The page command reads at most four canonical requests. Its `coverage: "page"`
means its groups cover only those returned rows, with per-request rate attribution.

The returned `snapshot` pins the admitted request range to this session and
extension instance. To continue, pass its complete object back with the returned
`next` cursor; limit can be 1–4. Null `next` exhausts that captured range. Omitting
the snapshot starts a new range including later work. Repeated or overlapping
pages are the same requests: do not add them twice. The summary handles request
identity itself. An explicit child-accounting grant and combined parent/child
reporting remain P23 work.

Reports carry rate revision/digest and provenance. Monetary integers use
`currency_scale: 9`: divide `amount_nanos` by one billion for configured currency
units. Unknown totals stay null; `known_amount_nanos` is only the priced observed
subtotal. Overflow is explicit. If a large configured report returns
`report_bounds`, issue a new explicit command at its `retry_cursor`/`snapshot`
with a smaller limit. A summary returning `summary_bounds` supplies no complete
total; use page reports for inspection. `summary_incomplete` reports a failed
read. Cancellation, deadline, worker failure or an exhausted action allowance can
leave an unknown invocation; inspect its receipts before explicitly trying again.
There is no silent truncation or automatic retry.

The summary's `host.usage.scan` grant raises only accounting-read steps to 10,000
per invocation. It admits no further host call after two minutes; an already
admitted call and cleanup retain their own deadlines. Existing per-callback,
traffic and object bounds still apply. Other operations remain limited to the
first 16 steps, with their ordinary capabilities and approvals. This grant adds
no content, child or mutation access.

## Unknowns and recovery

**Unknown is not zero.** Failed/cancelled work can consume tokens. Partial usage
retains only recorded observations; owner crashes leave unknown outcomes.
Successful requests can omit counters too. Sessions predating canonical
accounting stay `legacy_unmetered`, including after new measured turns. Cached
input and reasoning output are breakdowns, not extra totals to add. Anthropic
input is derived only when all uncached/cache components are known. Invalid or
inconsistent counters are labelled invalid.

Subscription usage is not API spend. API usage is not an invoice; local usage
does not mean hardware/electricity costs nothing. Subscription equivalents require
an explicit subscription row; local estimates require explicit local rates.
The report does not enforce monetary/token budgets or promise an invoice ceiling.
Host reservation/admission remains P23 work; displayed counters or estimates do
not provide that protection.

Turning optional tracing off does not remove usage facts. No extra remote request
collects them. The report's own-session read grant excludes prompts,
results, credentials, raw endpoint URLs and native reasoning. The underlying
journal still contains the private conversation; protect it as described in
[usage](usage.md).

Idle resume preserves facts without reissuing requests. Invalid committed
accounting or changed cached read receipts refuse recovery before truncated-tail
repair. Idle resume displays cached results without recalculating costs or
initializing a report worker. Keep the original file
and inspect it rather than deleting records to make a balance look complete.
After 10,000 requests, start a fresh session with reviewed context. See
[recovery](recovery.md) and the [developer contract](../developer/usage-accounting.md).
