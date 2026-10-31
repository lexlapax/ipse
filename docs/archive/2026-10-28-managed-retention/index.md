# Native retention and authenticated current reads

Historical implementation record, 2026-10-28. Current scope belongs to
[the plan](../../plan.md); this extends the separate
[literal-forget increment](../2026-10-28-managed-turnover/index.md) and its
[management integration](../2026-10-26-p30-p31-implementation/managed-forget.md).
The accepted [retention contract](../2026-10-26-p30-p31-implementation/baseline.md#evidence-retention-forgetting-and-migration)
remains the authority for endurance requirements. This component record does
not mark annual turnover, installed use or P31C1a complete.

## Representation and native boundary

The host now supports an exact native-reviewed `pin`, ordinary 90-day policy,
or positive user duration for an existing signed literal. Session-only policy
uses the existing atomic forget/suppression path. Literal public bytes, source
identity, original recipe and publication policy remain unchanged. A typed
same-value CAS advances the public record's revision and the native root;
the anchor's original admission/baseline clocks remain separate from the new
effective choice. The native capsule records the exact target, lineage,
display/challenge/input hashes, policy and actual native confirmation time.

`ManagedLifecycle.prepare_retention/4` builds immutable facts and an owner
journal intent. Facts include the previous effective deadline, requested policy,
exact new-deadline rule and any historical-coverage reduction notice. A future
confirmation timestamp cannot be known while displaying its prompt: ordinary
and duration previews explicitly say **native confirmation time + duration**;
pin has no deadline. The publication receipt supplies the exact resulting
timestamp. Nothing presents an estimate as a fixed expiration.

`NormalizerV3.retain/3` and `forget/3` share the locked management normalizer.
They authenticate the actual old anchor/live pages and original literal,
revalidate the exact preview/root/CAS, and consume the actual same-owner native
permit. Non-session changes require the old effective policy to remain eligible
at publication; an expired unchanged claim cannot become live through pinning
or a fresh duration. Positive duration uses the existing safe-integer contract;
timestamp overflow refuses before permission is spent. After consumption,
any refused repair or unconfirmed cleanup withholds success. Original automatic
clocks are not reset by the choice, reads, paraphrase or recapture.

The authenticated current reader uses a shared pure `ManagedRetention` contract
after opening the actual signed pages. Automatic metadata retains its existing
six-field shape. A native choice adds the authenticated capsule as `choice` and
supplies its effective category/deadline. The policy interpreter itself grants
no authority: current Identity, consent and original-source checks remain with
the owning host. Pending/history/retired and unsupported choices do not become
current notes. Session-only retirement remains suppressing after deletion.

Old managed dependencies cannot borrow an extended lifetime. Their old root and
record revision differ after typed CAS; a fresh authenticated read creates the
new dependency. The public capture's older category/expiry fields do not select
current eligibility. Recall implementations must use the current host verdict
and may structurally validate the unchanged public record without applying its
old worker timestamps as a second retention policy.

The original-source category stays ordinary/preference/current. This does not
introduce a worker-selected literal `pin` origin or widen automatic recipes.
Notes/Records stay pure extension policy; the host does not load extension
domain modules to authorize the effect. Prior saved choices are read from the
signed anchor and compared with the full preview, so a caller cannot silently
omit an earlier choice or change another lineage's policy.

## Focused verification

Four pure policy/metadata controls passed in 0.09 seconds. They cover exact
ordinary day-90 expiry, explicit relative policy deadlines, pin persistence,
malformed or mismatched capsules, duration overflow and historical-gap flags.
Their capsules are explicitly syntax fixtures, not permission or signed-state
proof. See [the focused policy log](policy-first.log).

One actual native PTY scenario passed in 2.9 seconds with the qualified
tmpfs production-profile helper
`6407e40e96498029ff7e13d96215a263812732aad1979b4c3e5f4b867b5a4d56`.
It creates three synthetic signed literals and exercises five successful typed
publications: ordinary → pin → ordinary → duration → session-only forget, plus
a separate current assertion → ordinary reduction. It also verifies:

- Exact authenticated effective deadlines and unchanged literal bytes/first
  admission across choices, with historical-gap disclosure for reductions.
- A fresh dependency is current while the pre-choice dependency is rejected.
- A fresh native review of an expired claim refuses before permit spend.
- Changed job facts invalidate the actual native permit and leave the stored
  target exact; no serialized origin/permit claim grants permission.
- Signed suppression blocks same-support automatic recapture after removal.
- Every actual locked normalization stays within the existing 32-read budget.
  A real owner-only Journal.Writer persists intent before each mutation.

The passed [native log](native-second.log) uses a new private graph
`_build/retention-sol-20261028`. Four changed modules were strict-compiled:
ManagedRetention, ManagedLifecycle, NormalizerV3 and ObservedRead. Current
unchanged Review and ManagedReference were also compiled into this graph for
their existing permit-check and dependency-current APIs. The pinned Runner and
production-profile helper were copied from the qualified
[native profile graph](../2026-10-28-native-profile/index.md). No shared helper
or earlier graph was changed.

The first native attempt successfully published/read the first pin, then failed
because the older base graph lacked `ManagedReference.current?/3`. Its
[original log](native-first.log), store and known publication remain retained.
After loading the current unchanged dependency module, only this one native
fixture was rerun with a new isolated store. No unknown operation was replayed.
An intervening automatic approval review timed out before process creation; its
explicitly allowed single retry started the passed case. That timeout is not
treated as a native effect or a safety finding.

Source members and past admission clocks are trusted synthetic fixtures. The
expired note uses a frozen past admission clock; actual terminal input, tags,
Core transactions and readbacks are native. This does not establish live model
quality, genuine product Session source provenance, standalone retention Consent
or CLI integration. Those owning paths must independently retain current
management epoch/fingerprint, mode ceiling, exact native command, finite
reservation, intent-before-mutation, checked release and deferred settlement.
Capture-disabled reduction must remain available without reviving an expired
claim or borrowing a capture grant.

## Remaining endurance work

No aggregate suite, profile batch, 4,000-publication replay or simulated annual
native workload ran here. Correction/new evidence, temporal supersession and
history, expiry collection, bounded suppression compaction and complete domain
adoption/import remain separate required increments. The proposed 30/90/365-day
schedule and 10,000-cycle target are not counted as executed by these policy
controls. Actual storage, authority, installed-user, quality and resource gates
retain their own receipts and scope.

`provenance.json` binds the exact source cohort, helper and private runtime;
`manifest.json` binds every artifact. The reader's generic metadata-index
select/value additions are preserved; its retention clauses were updated in
coordination with their owner. Whole manuals and final milestone status remain
the root integration's responsibility.
