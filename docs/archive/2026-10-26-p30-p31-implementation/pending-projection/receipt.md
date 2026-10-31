# Pending record projection — 2026-10-29

`IpseKnowledge.Knowledge.Records.pending_projection/2` is a pure parser for
the existing `pending.` key and v1 proposal record. It checks the existing
closed `Contracts.proposal_schema`, SDK value bounds, exact integer version and
times, byte limits, existing proof shape, and rederives the existing lineage
and text-dependent ID. It returns key, record schema version, candidate ID,
lineage, exact text and SHA-256, assigned category, reason, original proof and
explicitly worker-recorded event/creation/expiry timestamps. It does not alter
capture bytes, identities, state, storage, SDK exports or gates.

This is structural parsing only: a well-shaped substituted receipt remains an
unauthenticated claim. The schema version is not a Collection revision, and
recorded times do not establish host eligibility. The host must independently
authenticate the source and exact current value/revision and signed pending
clock, check active consent and observe the exact native display/input before
any acceptance or publication. The parser deliberately does not enforce a new
relationship among the worker-recorded timestamps.

The archived test sources ran against the pinned
[`document-descriptor-inventory` runtime graph](../document-descriptor-inventory/manifest.json),
not a fresh complete runtime build. The graph's 705 listed files matched that
manifest after the run. The archived strict compiler script compiled Notes,
Contracts and Records with no warnings. The focused records suite passed
14/14; its two added tests exercise unattended/assistant provenance, stable
identity, altered record fields/proofs, numeric aliases and the deliberate
absence of authority. An initial focused run rejected the intended test because
the JSON Schema validator treats `1.0` as integer-valued; explicit strict type
checks were added before the final passing run. A valid-looking changed receipt
is intentionally returned as a claim and must be authenticated by the host.

Commands from the repository root:

```sh
elixir -pa '_build/document-inventory-sol-20261029/lib/*/ebin' docs/archive/2026-10-26-p30-p31-implementation/pending-projection/compile.exs
elixir -pa '_build/document-inventory-sol-20261029/lib/*/ebin' docs/archive/2026-10-26-p30-p31-implementation/pending-projection/test.exs
```

Source and test snapshots, scripts and output logs are pinned by the adjacent
`manifest.sha256`. The graph lives in `_build`; the linked manifest documents
its provenance and required files. Both touched files passed focused formatting
and `git diff --check`. No aggregate suite, model call or sealed data was used.
Full proposal acceptance and standalone management remain unimplemented.
