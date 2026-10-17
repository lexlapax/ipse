# Inspect request usage

Interactive `/diagnostics` and `/session` include `accounting`. Inspect a saved
session without starting a model or repairing its journal:

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

**Unknown is not zero.** Failed/cancelled work can consume tokens. Partial usage
retains only recorded observations; owner crashes leave unknown outcomes.
Successful requests can omit counters too. Sessions predating canonical
accounting stay `legacy_unmetered`, including after new measured turns. Cached
input and reasoning output are breakdowns, not extra totals to add. Anthropic
input is derived only when all uncached/cache components are known. Invalid or
inconsistent counters are labelled invalid.

Subscription usage is not API spend. API usage is not an invoice; local usage
does not mean hardware/electricity costs nothing. This increment has no prices
or monetary/token budget enforcement. P23 adds configured estimates/admission.

Usage facts are mandatory local records; turning optional tracing off will not
remove them. No extra remote request collects them. Inspection excludes prompts,
results, credentials, raw endpoint URLs and native reasoning. The underlying
journal still contains the private conversation; protect it as described in
[usage](usage.md).

Idle resume preserves facts without reissuing requests. Invalid committed
accounting refuses recovery before truncated-tail repair. Keep the original file
and inspect it rather than deleting records to make a balance look complete.
After 10,000 requests, start a fresh session with reviewed context. See
[recovery](recovery.md) and the [developer contract](../developer/usage-accounting.md).
