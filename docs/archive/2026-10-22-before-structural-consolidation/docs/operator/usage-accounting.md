> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/operator/resources.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Inspect usage and configured cost estimates

Use built-in accounting to inspect recorded requests. Add an optional report
extension only when you want broader totals or configured cost estimates.
Accounting is always recorded; tracing and reports are separate choices.

## Read the recorded usage

In chat, enter `/session` or `/diagnostics`. For a saved session:

```sh
ipse diagnose --resume SESSION_ID --state-dir /private/path/sessions
```

Use the original ID and state directory. Omit `--state-dir` for the default store.
Diagnosis is local: it does not start inference, activate extensions, or repair
the journal.

Accounting shows request count, unknown-outcome count, historical unmetered status,
and the latest 16 records. Each identifies provider, requested/reported model,
configured profile, billing mode, main/summary/extension kind, and nullable
normalized counters. Accounted extension inference records its actual selected
profile/provider. Text and native payloads are excluded from accounting views.

Embedding records explicitly identify their operation and selected embedding
profile. Their output-token count is null with output marked inapplicable.
Input/total/duration counters still distinguish reported zero from unavailable
metering. A failed result can retain genuine final counters and conservative
budget liability.

Parent displays cover parent requests. Children keep their own journals; a
separately granted tree report can combine registered direct children. Unknown
or absent counters remain unknown. Failed or cancelled work can still consume
resources, and cache/reasoning counters are breakdowns of inclusive totals.
Do not add them twice.

## Enable an explicit summary command

Save this complete configuration as `/private/path/costs.json`. The empty card
is deliberate: it exercises reporting without inventing provider prices.

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

Inspect and try it without a real service:

```sh
ipse config --config /private/path/costs.json --no-project-config
ipse chat --provider demo --config /private/path/costs.json --no-project-config --cwd /path/to/scratch
```

In chat:

```text
/ext ext__costs__summary {}
```

Expect a captured own-session report, with no priced real usage. The command
makes no model request. To inspect real requests, select your normal provider
explicitly, perform a small task, then invoke the command. A report has no
automatic hook, price lookup, or inference call.

## Configure a rate card

A card records your reviewed prices and provenance. This complete card uses
synthetic prices for a model named `fixture`; it is a schema example, not current
market pricing. Replace identities, dates, rates, and source with your reviewed
values before using estimates for decisions:

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

Put a reviewed card at `extensions[].options.rate_card` for the report. Up to 32
nonoverlapping rows select exact provider, billing mode, model identity,
endpoint digest, admission date, and input-token band. `until` is exclusive;
null leaves the end open. Provider-reported model identity takes precedence over
the requested alias when available. A default endpoint uses null identity;
custom routes need the matching recorded endpoint hash.

Rates are decimal strings. Token rates are per million tokens; supported
search/fetch extras use per-thousand-request rates, and duration rates are per
second. Flat input uses `input`; cache-split modes need their distinct component
rates. Do not invent missing dimensions or apply an unrelated model's rate.
See [the rate reference](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/usage-accounting.md#calculate-a-synthetic-rate) for cache variants and exact
selection rules.

Version-1 cards cover text requests. To price embeddings, use card `version: 2`
and put `operation: "text"` or `"embedding"` on every row. An embedding row has
`input_mode: "flat"`, an `input` rate and optionally `duration_second`. It has no
output/cache/search/fetch rates. A text row never prices an embedding by matching
model names alone. Positive reported duration needs its configured rate for a
complete estimate. Without one, the total stays partial and a budget retains
its unknown money allowance. Keep synthetic examples separate from reviewed
prices for the actual selected route.

Currency has three uppercase letters. `api_estimate`, `api_equivalent`, and
`local_estimate` remain separate bases. Subscription equivalence is not API spend;
a local request needs an explicit resource estimate. Prices are never fetched
automatically. Editing the card changes pinned configuration; start fresh rather
than silently repricing an existing session.

## Choose page or tree reports

All three bundled report artifacts are disabled unless explicitly selected.

| Artifact | Command for instance `costs` | Coverage |
| --- | --- | --- |
| `builtin:cost-report:1` | `ext__costs__report` | At most four own-session requests per page |
| `builtin:cost-summary:1` | `ext__costs__summary` | Captured own-session totals |
| `builtin:cost-tree:1` | `ext__costs__tree_summary` | Parent plus registered direct children |

To use page reports, change both artifact references in the complete configuration
to `builtin:cost-report:1` and remove `host.usage.scan`. Invoke
`/ext ext__costs__report {"limit":1}`. Pass the complete returned `snapshot` and
`next` cursor for continuation. Null `next` ends that captured range. Omit the
snapshot to capture a new range. Repeated/overlapping pages contain the same
requests; do not add them twice.

For a tree report, use `builtin:cost-tree:1` in both references and add
`host.usage.children` to the summary grants. Keep `allow_children: false` unless
you also intend the extension to execute inside children. Parent-side child reads
are a different permission. Use:

```text
/ext ext__costs__tree_summary {}
/ext ext__costs__children {}
/ext ext__costs__child_usage {"child_id":"CHILD_ID_FROM_CHILDREN"}
```

Replace the placeholder with the actual 32-hex child ID returned by discovery.
Discovery/child pages retain their returned snapshot and cursor too.

## Read completeness and uncertainty

`coverage: "session"` excludes children. `enumeration_complete` means the captured
requests were read; `cost_estimate_complete` also requires priced final usage,
no unmetered history, and no monetary overflow. A complete scan can therefore
have incomplete costs. `coverage: "page"` covers only that page.

Tree coverage uses separate cuts for parent, discovery, and children, rather than
one atomic timestamp. Check `child_count`, `captured_child_count`, `gap_count`,
and `gap_reasons`. Missing, locked, invalid, oversized, or legacy-unbound journals
are gaps, never zero-cost children. Unknown child outcomes/cleanup also prevent
a complete cost claim.

Missing/partial/overflowing totals remain null. `known_subtotal` and
`known_amount_nanos` cover only observed known values. Monetary results use
`currency_scale: 9`: divide nanos by one billion for currency units. Keep providers,
billing modes, and estimate bases separate. Reports include card revision/digest
and provenance so you can inspect the assumptions.

A `report_bounds` result can supply `retry_cursor`/`snapshot`; issue a new explicit
command with a smaller page. `summary_bounds` supplies no complete total; use
pages. `summary_incomplete` means the read failed. No result is silently truncated.

## Recover and respect reporting limits

Child reads require protected registered journals and take the child's lock.
Let active ownership finish/cancel normally; never remove locks or alter files
to force completeness. A captured child prefix is at most 16 MiB. Discovery
supports 10000 children, tree accumulation 40000 unique attempts, and extended
accounting scans 10000 reads within a two-minute admission deadline. Ordinary
non-accounting actions still have the 16-step bound.

Idle resume displays committed report results without recalculation or worker
startup. Changed/corrupt read receipts can refuse recovery. Preserve originals
and use [Recovery](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/recovery.md). After 10000 requests, deliberately continue in
a fresh session with reviewed context.

These reports do not enforce budgets or calculate invoices. Use the separate
[admission budget](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/budgets.md) for covered reservations. Budget persistence
failures can leave counters unavailable and liability held; neither means zero
consumption. Turning tracing off removes no mandatory usage facts. Underlying
journals still contain private conversation even when report grants expose only
accounting and selected child discovery.
