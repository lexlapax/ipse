# Keep publication provisional until outer authority returns

Dated **2026-10-27** on `codex/p30-p31`. This is the internal Consent substrate
for the separately reviewed managed-publication ordering repair. It does not
claim that an SDK consumer has adopted the new API or that a milestone is complete.
The [plan](../../plan.md) remains authoritative for acceptance.

## Why settlement needs a separate final step

The original `Consent.publish/5` settles a successful short callback before its
caller returns through any enclosing Identity transaction. A later outer check
or release failure can therefore withhold publication success after measured
usage was already persisted. This component supplies an explicit deferred path;
the host adapter must use it and perform its outer authority checks before
finalization. It preserves the existing `publish/5` behavior and wire format.

`publish_deferred/5` shares the existing current-policy checks, native control
transaction, durable `publishing` transition and single callback invocation.
A callback returning valid `{:ok, actual, receipt}` produces this provisional
trusted-host packet:

```elixir
%{"version" => 1, "ticket" => ticket, "actual" => actual, "receipt" => receipt}
```

The durable operation remains `publishing`, with its original full reservation,
null actual and null receipt. The packet passes the nested native lock's final
check and release before returning; the outer Identity retains their shared
native process until its own completion. It is not an SDK grant, origin proof or
permission; a caller must still withhold it until all enclosing authority checks
and releases succeed.

After that successful outer return, the host can call
`Consent.settle(root, project, ticket, {:known, actual, receipt})`. This additional
outcome is accepted only for exact admitted or publishing tickets. It preserves
the receipt and uses the existing vector, within-reservation, safe-integer and
8192-byte bounded JSON validators. Finalization needs no fresh policy approval:
it settles already admitted work without dispatching or replaying an effect.
The existing two-element known outcome remains unchanged.

Malformed actual or receipt returns unknown without recording a smaller debit.
Measured overrun uses the existing durable overrun quarantine and retains its
larger measured liability. Callback failure, exception, repeated publication,
unstarted cancellation after publication, and observed owner loss cannot refund
pending work. Direct publication from a reserved ticket remains supported for
compatibility with the existing host API.

**Final settlement uncertainty has a narrower guarantee:** a failed final write,
ACK or lock release may already have persisted known actual. Inspect the durable
operation without replay. Full pending liability is guaranteed before measured
settlement begins; it cannot be promised after that final transition starts.

## Exact executed source and checks

The final author graph is `/tmp/ipse-consent-deferred-20261027-02`. Its coherent
base is the completed NativeReview final graph, overlaid only with Consent and
the new test file. Concurrent Collection and normalizer changes were excluded.
Compilation ran from that private project's working directory and compiled
**131 source files** with warnings as errors. The copied private native helper
was not rebuilt; the shared helper and builds were untouched.

| Input | SHA-256 |
| --- | --- |
| Consent source | `69740ca466cc4dea0f77d475d805eee4caa57eb893235638e9e55b4ea36f0d9c` |
| Executed Consent BEAM | `5252671a7b4b4bfb4064e5a9511dfa1293fe4466b97e3651c859e7baf8d0f5b4` |
| New owning tests | `973e7b9811a1343c657d5d844a09cbccbcebc680c3c32b5570b359f6be3a9afb` |
| Complete 2345-row project/build manifest | `29351550fd201af1a07b48029529277a199f9df36f553037db6795ea79a423d7` |
| Five-module runtime origins and helper binding | `902304149bf49769414c0f7e3301822ce1569848514510d08ee05c9164f10f1c` |
| Actual selected private helper | `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b` |

Elixir **1.20.4 / OTP 29** checks passed **45/45** tests in 101.1 seconds, seed
`20261205`: twelve new deferred-publication cases, fourteen legacy Consent cases,
four policy-read cases, seven existing-read cases and eight compaction cases.
Counts were parsed from the exact test ASTs. All 2345 project/build inputs were
checked unchanged after execution. Symlink aliases are not independent manifest
rows; actual targets and helper bytes are preserved separately. The declared Mix
execution cache is excluded.

The new tests exercise actual protected native transactions: full period budget
before finalization, exact known receipt settlement, finalization after revocation,
reserved compatibility, strict tickets, expired/denied callback exclusion,
malformed and oversized receipts, malformed vectors, overrun quarantine,
repeated/unknown/unstarted refusal, raised or failed callbacks, actual native
Port loss and original caller death. No source-derived replacement runtime or
simulated native helper is used in these twelve cases.

Actual **Elixir 1.18.5 / OTP 29** checks formatted both owned files unchanged and
compiled the one changed runtime source, producing one module with diagnostics
`[]`. This is not an ExUnit run on 1.18 or an OTP-27 claim. No provider, model,
credential, qualification data or PTY was used. Existing supported filesystem
quota restrictions remain; this change qualifies no additional platform.

The initial author graph `01` passed its first ten native tests, seed `20261204`,
in 3.5 seconds with its own unchanged 2345-row manifest. Final `02` adds two
boundary tests without altering Consent. Both complete graphs and their logs are
preserved; no executed compile or test failure occurred in either scope.

## Review and handoff limits

The accounting and Collection SDK publication/settlement explanations were
rechecked against this internal API. Their coordinated rewrite belongs to the
adapter integration: success must remain provisional through outer Identity
completion, and final settlement uncertainty may already have persisted known
usage. This receipt does not substitute for that reader-facing integration or
its independent execution audit. It also adds no worker endpoint, authority
minting path, automatic retry, replay, imported provenance or managed-read grant.

The owner-only evidence base is
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification`.
Both snapshots verify source/destination bytes, lengths, hashes and ownership,
all admitted runtime rows before/after copying, data mode `0600`, directory mode
`0700`, and file/directory fsync. Alias paths are omitted rather than followed;
actual admitted targets and helper bytes remain regular preserved files.

| Durable subtree | Payload manifest | Provenance | Preservation receipt |
| --- | --- | --- | --- |
| `consent-deferred-initial`, 2354 files | `0285bc6415b62289b17ede839be63f2bf2e8037214ec48102882eda119a8ed19` | `1dff67870e43fef87f3e7c6a5667b4c73c7ee2998188b287dc3ff061c98ff322` | `cb29994aa0cd20eb7a4968c4cf65fa67bd14938bc74297cdd9090913d8d6cb74` |
| `consent-deferred-final`, 2532 files | `8530f1f257f7f91fb31c179254126c6e6eb5c28ee9dcffb7abc3ee9598f47c4f` | `23e586c001b502b977db32fe874c47d2a07bbe20fcf89f9e98bdb1159172cc95` | `11501f7b4e7d52f4da59fa2f59bedb3e886bb2bb81930232bdfdbbfb4ecfb5fa` |

The final preserved `working-copy/REPORT.md` is
`e8bb22d4b67714e39fb7e9012be013d3ce63894a46c0f1aae6bda89e1ca36632`.
The adapter's source-bound ordering audit remains separate. Reproduce evidence
only in a new private working directory; preserved helper files are owner-only
data, not executables to run in place. The scoped documentation check passed
553 Markdown files and 4817 local links with zero errors before these preservation
hashes were added; final checkpoint checks must cover the finished record.
