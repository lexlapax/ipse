# Coalesced notes Worker-input observations

2026-11-04. Historical implementation and verification record. Current ownership
and bounds are taught in [Session sources](../../developer/session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
and [persistence](../../developer/persistence.md#read-several-collection-pages-under-one-validated-index).
The [plan](../../plan.md) owns remaining milestone acceptance.

## Problem and scope

The paired reader reconstructs the complete protected Collection index once per
pair of literal dependencies. A 32-literal protected observation therefore
reconstructs that index sixteen times. The retained 2,000-note ordinary read
still failed before inference, with thirty delivered Worker inputs and the next
input unknown. Its precise protected-share failure trigger remains unresolved;
the separate [stale-timeout repair](share-stale-timeout-20261104.md) does not
establish the cause. No failed Session is resumed or replayed by this work.

The candidate reuses the existing bounded ReadView behind the host's managed
reader. It changes version-4 notes observations in Worker-input preparation;
other dependency versions and managed-use paths retain their existing behavior.
It adds no dependency, service, permission, persisted index or SDK operation.

## Implementation and authority

Each independent protected pass opens one view, reads the literal/format/override
values, plans live/anchor neighbors from sealed historical references, and
freshly reads each distinct selected page. Those plans confer no current
authority. All native value reads must match the same root and summary. The
unchanged domain reader authenticates each record, followed by a fresh format
and root check and confirmed view close. Source-journal IO remains outside the
Collection owner. The second independent observation, source retention and final
held Collection/root check still precede the actual Worker frame write.

Existing limits remain: 32 literals per group, eight values per raw request,
64 KiB replies, 8,192 references, 4 MiB encoded cache, sixteen simultaneous views
and a nonrenewable 60-second/512-unit view. The pass retains at most 160 raw
records and bounds the sum of encoded reply sizes to twenty 64-KiB replies;
32 literals use at most
417 units and 85 calls. DomainAuth's 128 verifications, 1 MiB input and five-second
lifetime, along with Worker/current-use deadlines, are unchanged.

Only an initial validated encoded-index overflow or genuine exhaustion of all
sixteen registry slots can use the existing paired reader before any borrow or
domain verification. Invalid references, more than 8,192 references, owner loss,
expiry, corruption and failures after borrowing refuse. The ordinary view API
keeps generic capacity errors; the trusted adapter uses classified errors.
Documents retain their paired route and profile-specific bounds. The notes pair
retains its separate native 32-unit allowance. A failed initial open adds work;
identical fallback timing or failure behavior is not claimed.

## Disposable component evidence

The preserved private candidate patch is
`472088d8b8023575d608394b0c6814c22284ac53c7a72276daae467b91ee4027`;
its four core sources are unchanged from the independently reviewed draft.
The qualified component union contains **33 distinct passing cases** across
separate runs, not one all-green aggregate. Cases cover signed equality and
ordering across 32+1 literals, long source quotes, maximum raw replies, root
changes before/after planning and final checking, selected-byte/cache corruption,
actual owner loss, copied handles, expiry and both genuine capacity fallbacks.

The final native capacity case seeded 7,804 valid references, within the unchanged
8,192 native limit. Actual native view open and install returned the classified
encoded-cache overflow. The fallback returned the exact paired signed observation
and root. **One selected case passed, 85 excluded, in 33.8 seconds**, with all
three integrity postchecks passing. The safe receipt hash is
`39712c135831215d507771d9f588ba37553f01ca6c2e243ee464d01db67d38a5`.

A separate instrumented component with 32 selected signed literals and 2,000
additional entries produced identical observations/order/root. Pairs measured
776,426 microseconds, sixteen quota inventories and sixteen index reconstructions;
coalescing measured 242,706 microseconds, twelve quota inventories and one index
reconstruction. This is one instrumented storage sample while a separate
regression was running, not Session latency, retained recall, peak memory or
annual-throughput qualification.

Earlier failed setup and fixture attempts remain preserved: missing support
closure; a copied clock-specific Runner without its required environment;
expecting a close after a capacity refusal had already stopped the view;
counting the wrong index-loader MFA; and malformed long-literal fixture options.
Their failures are not rewritten as passes. Corrected cases provide separate
evidence. The final component receipt augments the original 32-case summary,
whose SHA is `709a881c97c36afdf0ca491873327fc786bf7326c605b9bf3f7d6c2b2a39121b`.

## Current-source qualification and remaining gates

Seven reviewed source/test files are integrated after `d7034eca` and formatted.
A fresh private source/Git/dependency copy compiles all **197 host source files**
with warnings as errors and builds all four normal bundles. The complete App
contains 241 declared modules; every bundle payload hash and internal runtime
link is verified. The credential-free demo passes. PDF is explicitly disabled
for this build. The embedded commit is parent `d7034eca` plus the seven pinned
dirty files, not a clean release identity.

On that frozen current-source runtime, **33 backend cases pass in 52.6 seconds**,
with 53 excluded and no failures or skips. A separate fresh native-approved
eight-original-source Worker case passes in **18.5 seconds**, with 201 excluded.
It exercises actual context allocation and a synthetic loopback shadow decision,
both independent coalesced passes, exact interleaved v3/v4 dependency/proof
equality, root-only observations and unchanged stale-root, changed-policy,
missing-source, expiry and revocation refusals. Strict Saved reconstruction and
confirmed Session close pass. It does not test idle reopening or populated recall.
All source/runtime/driver/path postchecks pass, no matching processes remain,
and the operator lock has no holder.

The first build attempt stopped before compilation because sandbox policy denied
Mix's local TCP filesystem lock. A host continuation on the same pinned copy
retained locking and passed; the original failure remains. A first current
backend entry also stopped before ExUnit because its added Input check named a
nonexistent API. The corrected fresh entry checks the actual Session.Input state
before and after. Its failure and all passing integrity checks remain preserved.
No product behavior or timeout was changed for either correction.

The [compact result](coalesced-worker-readview-20261104/main-result.json) and
[seven-file source hashes](coalesced-worker-readview-20261104/main-source.sha256)
bind current-source qualification. Independent source, test and whole-manual
review accepted this bounded integration. Formatting and the canonical
documentation/link check pass. The [477-file regression](source-regression-477-20261104.md)
is frozen on `9b1a4e5e`; its preserved failed aggregate cannot qualify this change.

A successful ordinary retained-store read still requires a complete frozen
current runtime, matching legitimate activation and one fresh reviewed consumer.
Then measure the complete populated day and resource peaks before annual
workload feasibility. Installed behavior, annual workloads and P30/P31 acceptance
remain open. No retained operation, provider call or terminal input was used by
these disposable component tests.
