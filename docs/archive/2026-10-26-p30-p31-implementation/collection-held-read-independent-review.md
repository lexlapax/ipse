# Independent review of held Collection reads

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the implementation receipt](collection-held-read.md), manifest SHA-256
`d6432213d91cc9abeebd230861ca2a4bfa9b6d898dd7129d72d1c5a54849c934`,
against the retained normalizer/read implementation and
[management snapshot review](management-snapshot-read-independent-review.md).
No runtime/native source or gate edits were made. One explicitly authorized
focused counterexample ran against the frozen graph; no passing aggregate was
repeated.

## Initial disposition: acceptance held

The extraction introduces one concrete regression: its final read-token check
can convert an actual successful publication into a known normalization refusal.
The mutation path executes `managed_mutation` inside the new shared callback,
then `with_managed_reads` checks the budget token again after that mutation.
A token failure becomes `managed_read_refused`, then
`managed_normalization_refused`, even if the native root already switched and
the native owner/release remain valid.

[The focused probe](collection-held-read-review/post-publication-budget.exs)
and [its result](collection-held-read-review/post-publication-budget.log) show
this using an existing synchronous `collection/staged` telemetry event. A
trusted normalizer consumes exactly32allowed reads and registers a handler
retaining its read closure, then returns valid normalized data. During native
publication, after the normalizer returns and its pre-mutation check passes,
the handler calls that still-open closure once. The33rd read is refused and
marks its token exceeded. Publication nevertheless completes. The extracted
postcheck then returns `{:error, :managed_normalization_refused}`.

The same isolated native probe reads the actual generation-one root, selected
`note.a` revision-one value and stored generation-one operation receipt. Its
log retains that physical root, its hash, the selected value and returned error.
It uses no direct private-token tampering, actual protected knowledge, model,
network, production record or gate. No replay exploit is claimed; the defect is
the contradictory known-refusal outcome after an observed durable publication.
The original snapshot and evidence remain unchanged.

The narrow repair direction is to close the exact read-token lifetime at the
existing successful pre-publication check, then accept only that same closed
token idempotently at the final wrapper check. A read after closure must refuse
without altering the closed token. Actual callback budget exhaustion must remain
sticky and refuse before publication. Read-only callbacks should seal on return;
all native checks and confirmed outer release must remain. This prevents later
read-budget activity from reinterpreting an already observed mutation result.
A separately frozen repair and narrow recheck are required before acceptance.

## Remaining source assessment

No additional concrete scoped blocker was found. `with_managed_read/3` selects
the fixed notes profile, retains the real Collection native owner and passes the
actual root witness plus the existing managed read closure to trusted host code.
It adds no SDK operation or production Management call site. As documented,
absent storage may create protected directories and lock files, but no root or
operation receipt is published by this read path. Presence and signed metadata
must still be authenticated by the caller.

The extracted read closure requires its original process and exact native
capability. Every accepted read debits the same opaque callback token and
checks native ownership before and after observation. Exact-key reads cost one,
neighbors cost four and pending summary costs eight within the shared32units.
Over-budget state stays exceeded. Cross-process, escaped and nested Collection
entry refuse. The directory contains validated metadata keys, not eligibility
or source truth. Exact root bytes/hash, manifest binding and generation remain
available to the callback without turning its result into authorization.

Known read-only callback results are checked before return and the outer locked
path checks ownership and confirmed release for every outcome. Native owner
loss overrides data or errors with lock-loss unknown. Typed unknown callback
results remain unknown; malformed results refuse. Unknown is not an instruction
to retry. Host callbacks remain trusted and cannot use this lock as a sandbox
for arbitrary Elixir IO or untrusted code.

The normalizer still checks original CAS and reserved-key policy before entering
the callback; after it returns, it checks the token, normalized request,
normalization shape/size and actual native owner before mutation. Existing
publication gates and exact error tags remain. Those pre-publication checks are
sound; the newly added post-mutation budget check is the regression above.

## Frozen evidence and limits

[Verification](collection-held-read-review/review-manifest.exs) and
[its output](collection-held-read-review/review-manifest.log) validate all17
manifest entries, five archived source/test files and726 runtime files. The
670 inherited inventory entries are present; only Collection and Directory BEAMs
change within that set, and56 additional expanded files are independently
pinned. Helper
`a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995`
is unchanged. The overlay includes current Directory's already implemented
interface; this does not newly qualify every Directory feature. Later tty and
Session/Host integration graphs are excluded.

The recorded47102 five new native controls and47103 eighteen affected normalizer/
directory controls passed, but they do not exercise a read after normalizer
return during publication. They establish continuous competing-writer exclusion,
exact stable observations, closure/process/nesting refusal, sticky budget,
actual helper-loss/new-owner behavior, unknown/refusal results and the existing
publication/receipt/CAS paths under their own schedules. Those passing tests were
inspected, not repeated.

The archived47101 missing local-capability binding was a compile defect and ran
no tests.47104 rejected an unsupported launcher flag.47105 encountered the
older copied Directory interface and launcher diagnostics shape; neither is a
passing source qualification.47106 compiles the current Collection and Directory
with explicitly empty compile/runtime warning lists. The exact historical
sources, launchers and logs remain retained.

Even after repair, actual signed target/metadata integration, independent
Identity/Consent/journal owners, native display and all-copy closure, Review and
live one-use effect revalidation, a coherent baseline/package build and final
audit remain open. This read helper provides neither current-use authority nor
management/output gate activation.

## Additive v2 repair disposition

The [post-publication repair](collection-held-read.md#post-publication-outcome-repair),
manifest SHA-256 `36cbbcca5a594b9b63f5ecbab63aab743c459ff9616bc7711eb843bd628c3edb`,
closes the proved regression. Accepted for the held-read/extraction scope;
no signed-target, caller, display or management gate is activated. The original
failed cohort and exact root/outcome probe remain unchanged.

[Repair verification](collection-held-read-review/review-repair-manifest.exs)
and [its result](collection-held-read-review/review-repair-manifest.log) verify
all nine additive manifest entries, both source/test snapshots and726 runtime
files. The complete inventory differs from v1 only in Collection BEAM. Directory,
all other runtime files and helper remain unchanged. No broader runtime or
native contract is requalified.

The private check now changes only its exact open token to closed at successful
check, and accepts only that same closed token idempotently. In the normalizer
path, the existing check immediately after callback return therefore closes the
read lifetime before normalized validation and publication. The unchanged debit
function rejects closed state without changing it. Staged-phase telemetry can
no longer spend another unit or mark that token exceeded, and the later wrapper
check preserves the observed publication result.

Actual exhaustion inside the callback still marks the open token exceeded and
fails the pre-publication check. An escaped or cross-process closure still fails
its original process/capability/token checks. An ordinary read callback seals its
open token on its known return; typed unknown retains its conservative path.
Native pre-publication checks and the outer final ownership check/confirmed
release remain. Thus the repair strengthens closure lifetime without extending
the budget, weakening CAS, changing publication gates or treating owner loss as
known success.

The retained47110 strict compile reports empty warning diagnostics.47111 reports
25 affected passes, including the earlier five held-read and18 normalizer/
directory controls plus two new actual native publication schedules. The new
schedules use zero or32 callback reads, then attempt33 reads from the retained
closure during the existing staged event. Every staged-phase read refuses;
the API returns known success matching actual selected revision/generation2
and its retained operation receipt. The zero-read case also proves closure
lifetime itself is sealed, rather than merely relying on exhaustion. These
source and log controls were inspected, not rerun. No additional counterexample
was warranted.

No scoped blocker remains after this additive repair. All signed metadata,
actual held-target adapter, other management owners, native display/all-copy
closure, Review/one-use effect admission, coherent whole-source/package checks
and final audit requirements above remain open.
