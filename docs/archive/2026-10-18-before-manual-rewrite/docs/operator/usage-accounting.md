> Historical reference only. Snapshot of `docs/operator/usage-accounting.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../operator/usage-accounting.md).

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
main/summary/extension kind and nullable normalized counters. An approved extension
call records its actual selected profile/provider, even if they differ from the
main model; its text/native payload is excluded from accounting. Child records live in their
own journals under `sessions/subagents/PARENT_SESSION_ID` and identify the parent
request. The built-in parent display shows its own requests; the optional tree
report below combines granted child accounting. See
[subagents](subagents.md) for ownership and approvals.

## Enable the optional report

Choose the scope explicitly. All three shipped report extensions are disabled
by default, with no automatic hook, rate lookup or model request:

| Artifact | Commands for instance `costs` | Scope |
| --- | --- | --- |
| `builtin:cost-report:1` | `ext__costs__report` | Individual own-session requests, at most four per page |
| `builtin:cost-summary:1` | `ext__costs__summary` | Captured own-session totals |
| `builtin:cost-tree:1` | `ext__costs__tree_summary`, `ext__costs__children`, `ext__costs__child_usage` | Parent plus actual registered direct children, under an additional explicit read grant |

Configure operator trust and a rate card. This own-session summary example
deliberately has no price rows, so unmatched usage stays unpriced:

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
instances may enable different reports with distinct names. For the tree report,
select `builtin:cost-tree:1` in both artifact fields and add
`host.usage.children` to trust, retaining the summary's other capabilities. Keep
`allow_children: false` unless you also want this extension to execute inside
children; parent-side child reads do not require that separate execution grant.

With that tree selection, use the actual 32-hex child ID returned by `children`:

```text
/ext ext__costs__tree_summary {}
/ext ext__costs__children {}
/ext ext__costs__child_usage {"child_id":"CHILD_ID_FROM_CHILDREN"}
```

For real usage, select your normal provider/profile explicitly. No report command
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
identity itself. Discovery and child pages use the same explicit continuation
pattern; pass the returned snapshot with `next` and retain the child ID for child
pages.

The tree report uses `coverage: "session_tree"`, with separate captured cuts for
the parent, discovery and each child. These cuts are not one globally atomic
timestamp. `child_count`, `captured_child_count`, `gap_count` and `gap_reasons`
show missing coverage. Locked, missing, invalid, oversized or legacy-unbound
child journals remain gaps. `unknown_child_outcome_count` prevents a complete cost
claim when parent-side child completion/cleanup is uncertain, even if all available
request records were read. Legacy unmetered history also prevents completeness.
Group amounts cover enumerated requests; a nonzero gap does not price missing
children as zero. The child-manifest digest binds the captured cuts recorded in
action receipts without returning an unbounded list in one result.

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

Child reads require protected regular journals beneath this parent's recorded
child directory and take the child's existing lock. A live separately opened child
can therefore refuse a read or recovery check. Let its active owner finish or
cancel that work normally, then inspect the original files; do not delete lock files or alter records to force a
complete report. A captured child prefix is at most 16 MiB. Discovery supports
10,000 children; the tree accumulator supports 40,000 unique request attempts.
Its shared 10,000-read allowance may stop a larger scan with incomplete coverage.

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
Optional [shared admission budgets](budgets.md) reserve main, summary and child
requests separately in the host. Displayed counters or estimates do not supply
that authority; unknown liability remains explicit. A budget ledger must durably
accept counters before canonical accounting publishes them. Failed persistence
leaves unwritten counters unavailable and the reservation held, while preserving
earlier committed observations. This can understate actual consumption; it is
neither a zero measurement nor an invoice ceiling. See the budget guide's
[recovery procedure and limits](budgets.md#inspect-stop-and-recover).

An explicit [`max_output_tokens` setting](configuration.md) can cap individual
OpenAI API, Anthropic and Ollama requests; children retain or narrow the parent's
cap, and lower adapter limits remain. ChatGPT subscription rejects this setting
because its public interface does not support it. A per-request output cap does
not limit input or aggregate requests/costs. Truncated provider output stops
incomplete without admitting tools, retaining available partial usage. Already
streamed text remains visible; inspect the error before explicitly continuing.

Turning optional tracing off does not remove usage facts. No extra remote request
collects them. The report's own-session read grant excludes prompts,
results, credentials, raw endpoint URLs and native reasoning. The separate child
grant exposes the same canonical accounting plus child discovery, not transcripts.
Its snapshot fingerprint covers only granted accounting. The underlying
journal still contains the private conversation; protect it as described in
[usage](usage.md).

Idle resume preserves facts without reissuing requests. Invalid committed
accounting, changed cached read receipts or unavailable captured child sources refuse recovery before truncated-tail
repair. Idle resume displays cached results without recalculating costs or
initializing a report worker. Keep the original file
and inspect it rather than deleting records to make a balance look complete.
After 10,000 requests, start a fresh session with reviewed context. See
[recovery](recovery.md) and the [developer contract](../developer/usage-accounting.md).
