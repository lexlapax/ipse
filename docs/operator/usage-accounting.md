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

The shipped `builtin:cost-report:1` extension is disabled by default. It registers
an operator command, with no automatic hook, rate lookup, model request or child
journal access. Configure explicit operator trust and a rate card in your operator
JSON file. This example deliberately has no price rows, so unmatched usage stays
unpriced:

```json
{
  "version": 1,
  "extensions": [{
    "instance": "costs",
    "artifact": "builtin:cost-report:1",
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
    "artifact": "builtin:cost-report:1",
    "capabilities": ["invoke.command", "host.actions", "host.usage"],
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

In chat, request a page explicitly:

```text
/ext ext__costs__report {}
/ext ext__costs__report {"limit":1}
```

For real usage, select your normal provider/profile explicitly. The report command
itself does not start inference. Set the instance's `enabled` to false for future
sessions to disable it, or use the existing `--no-extensions` flag. See
[selection and executable trust](extensions.md).

## Read a report page

Each command reads at most four canonical requests from this session, including
requests older than the latest-sixteen counter display. `coverage: "page"` means
the groups are totals for those returned rows. They are not a whole-session or
parent/child balance. Groups separate providers, billing modes and estimate bases;
API spend estimates are never added to subscription equivalents or local estimates.

The returned `snapshot` pins the admitted request range to this session and
extension instance. To continue, pass its complete object back with the returned
`next` cursor; limit can be 1–4. Null `next` exhausts that captured range. Omitting
the snapshot starts a new range including later work. Repeated or overlapping
pages are the same requests: do not add them twice. Whole-session aggregation and
an explicit child-accounting grant remain P23 work.

Reports carry rate revision/digest and provenance. Monetary integers use
`currency_scale: 9`: divide `amount_nanos` by one billion for configured currency
units. Unknown totals stay null; `known_amount_nanos` is only the priced observed
subtotal. Overflow is explicit. If a large configured report returns
`report_bounds`, issue a new explicit command at its `retry_cursor`/`snapshot`
with a smaller limit. There is no silent truncation or automatic retry.

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
