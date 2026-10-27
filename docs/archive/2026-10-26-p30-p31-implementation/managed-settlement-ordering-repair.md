# Finalize managed usage after checked Identity completion

Recorded 2026-10-27. This closes the demonstrated V2
[Identity-finalization finding](identity-finalization-finding.md) for the exact
runtime below. It does not accept SDKv3, first-domain activation, a complete
current-tree baseline or P30/P31. The original before evidence and earlier scoped
accounting audit remain preserved. Current procedure and implementation guidance
belong to [Accounting](../../developer/accounting.md) and the
[Collection SDK](../../developer/collection-sdk.md).

## Ordering and uncertainty

Managed publication now uses the
[deferred Consent primitive](consent-deferred-publication.md). Current policy and
source checks, exact C receipt/operation/measurement bindings, full reservations
and the existing wire/replay contracts stay in force. Consent records publishing
before the callback and returns a validated private packet after checking and
releasing its nested native lock. Durable actual/receipt remain null.

The outer Identity transaction then completes its checks and release. Only its
successful return can reach final known settlement. A fresh private callback-local
slot records callback entry; any enclosing error after that point remains unknown,
rather than becoming a known consent denial after an effect may have occurred.
Known pre-callback refusals retain their original classification.

Finalization checks the closed packet, exact ticket project/operation/epoch/request,
all reserved dimensions, receipt status and current scope/original owner. The
Consent lookup additionally checks the exact stored ticket, including sequence.
The receipt-preserving known settlement accounts already admitted work; revocation
does not erase its liability or require another effect grant. No packet or cost
constructor is exposed through the SDK. Callback-local measurement capture remains
bound to the same successful C result.

Before final settlement begins, observed loss leaves full publishing liability,
even if C already selected its new root. Final settlement's own write, ACK or
release can become uncertain after actual/receipt persisted. Inspect that durable
row without replay; there is no claim that every unknown row is still full after
that final transition starts. Resume runs neither publication nor deferred
completion automatically. Trusted Core remains the boundary.

## Checks actually run

Root's isolated `/tmp/ipse-managed-settlement-repair-20261027-01` compiled **130
source files** with warnings as errors from its actual private project directory,
using `MIX_ENV=test`. Five-module bindings verify the exact private sources/BEAMs
and selected private d84 helper. The legacy C graph is intentional: later directory,
Core-v3, Pages and NormalizerV3 changes are excluded from this ordering proof.

- **39/39**, 22.1 seconds, seed `20261206`: five accounting controls, five managed
  request/binding controls, seventeen actual SDK/Session cases and twelve deferred
  Consent cases. The new maintained native fault test closes the retained native
  port after checked deferred return. It observes C generation one, unknown
  journal outcome, full pending/null actual+receipt, a smaller provisional
  measurement, cleanup uncertainty and unchanged liability/worker trace on inert
  resume. Existing successful saves still settle their exact measured input.
- **109/109**, 40.7 seconds, seed `20261207`: legacy Collection SDK pure/Session,
  CollectionPolicy, Normalizer, ManagedRecipe, SemanticConsent v2, Invocation and
  Resources authority. The journal-exhaustion control's expected redacted error
  remains in the raw log; the scope passes.
- The primitive author's separate **45/45** Consent regressions remain labeled
  author evidence on their own coherent graph, not combined with Root's runtime.
- Actual **Elixir 1.18.5 / OTP 29** formatted the four owned source/test files and
  compiled the two changed runtime sources/two modules with empty diagnostics.
  Current 1.20.4 formatting also passed. This is no 1.18 ExUnit or OTP-27 claim.

All **2,339** original project/build inputs and exact membership remain unchanged
after focused and broader runs. Independent execution confirms the same rows.
Its adapted old bad-state predicates now fail at settled versus actual publishing;
the explicitly separate correct-state companion passes **3/3**, including two
actual fault cases and a known-success control. The complete independent
[closure addendum](identity-finalization-finding.md#independent-repair-closure)
retains every seam/predicate change and initial private-harness failure.

Root and the independent reviewer read the whole Accounting and Collection SDK
chapters, repaired all overlapping publication explanations and distinguished
nested lock release from the shared native process's outer cleanup. Operator
resources/recovery guidance was checked against the narrower uncertainty rule.
No new operator workflow, provider/model call, paid use, PTY or platform support
was introduced or claimed.

## Exact retained graph

| Input | SHA-256 |
| --- | --- |
| ManagedCall source | `1757b4264086895baacdefca68e83b685caa864a3a74f699050aa170b00b00e9` |
| Executed ManagedCall BEAM | `4aa6bb7585c006d79ae883d91fe1d2e67e41d4c129e92df1a68cad990d211c13` |
| Consent source | `69740ca466cc4dea0f77d475d805eee4caa57eb893235638e9e55b4ea36f0d9c` |
| Original 2,339-input manifest | `57c45e85f0178cdd15dff8afa50fbfb87d21607baa299374609bc95062594492` |

Owner-only complete owner evidence is retained under:

```text
/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/managed-settlement-repair-owner
```

The copy binds all 2,339 admitted inputs and full 2,525-entry owner membership
(2,522 regular entries and three recorded aliases), plus final manual snapshots
and the exact preparation/compatibility scripts. Its **2,561 payloads** retain
all raw first logs, strict/format/compatibility outputs and original compiler
origins. Aliases were not followed; admitted private-helper target bytes were
materialized as data. Bytes/ownership were checked and files/directories synced;
original modes and bytes were untouched. Reproduce in a fresh private working
copy, never by executing or changing sealed evidence in place.

| Evidence | SHA-256 |
| --- | --- |
| Owner report | `8b2c6e485564dc51f63f8e7c9f237ed927a330e660cf4cce07e65554afca2d58` |
| Payload manifest | `94fdc4f11dc0864493ce020d52bdab48126cc731af194e8177e55f62d06f7f89` |
| Provenance | `6a192cbbc77df2da5cc659afeb09b7244821af04562562cad2db4794fb23f7a4` |
| Preservation receipt | `f8dfe38cd2bceda160cd696cf4d61c7a857b64a77106a3768d76a78d68d6cb9f` |
