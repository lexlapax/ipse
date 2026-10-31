# Scoped document-stage decision restoration — 2026-10-29

Scoped design accepted with the managed-input amendments below in its
[independent review](document-decision-restoration-independent-review.md).
This design document changes no runtime gate. Read the [requirements audit](expiry-requirements-audit.md), the
[original document contract](document-store-boundary.md) and the
[actual deadline interposition](strict-deadline-interposition.md). The
[plan](../../plan.md) owns completion. This is a narrower follow-on to the
[State restoration](state-deadline-restoration-design.md), not an extension of
its acceptance to other storage or output paths.

## Exact scope and decision

Restore only the fixed `document_graph_v1` Collection profile's trusted
`execute_profile_before` path used by `DocumentStage`. Each exact append,
seal, consuming commit or fused equivalent must pass its own final locked
clock decision after complete synced staging and immediately before the native
root replacement. Equality refuses. The minimum of the stage's original expiry
and every inherited trusted deadline applies. Opening a stage never admits a
later append or consuming commit, and reading does not renew its expiry.

The decision is not a guarantee that an already admitted rename completes
within the same wall-clock millisecond. A scheduling stop after the decision is
an in-flight operation. Preserve the stage's original TTL and exact epoch in
materialized state. An expired stage cannot be accepted by a new append/seal/
commit attempt, including after restart. Expired reclamation and slot reuse must
remain serialized by the same Collection lock and must target the exact epoch.

Leave these paths closed: notes-profile timed publication, automatic/saved-consent
capture, native-reviewed management, managed approval/output/nested delivery,
and managed State/service calls. `with_publication_deadline/2` continues to
refuse without invoking its callback. Global knowledge publication readiness
continues to report unavailable. No worker deadline/profile selector, permission
or budget is added. A documents-profile route is not a way to bypass the separate
managed-source host gate.

The independent source review identified an important distinction: the current
Invocation blanket publication branches name `collection.call` and
`collection.managed`, while `collection.store` can receive a nonempty managed
dependency set through `ManagedToolUse.with_effect`. Restoring the document
deadline route alone would therefore also open managed-derived document effects.
Before restoring it, add an explicit pre-intent Invocation refusal for mutating
`collection.store` in a managed invocation. Add a second trusted CollectionStore
execution check that refuses a mutating document request when `with_effect`
supplies a non-null managed deadline. Neither gate may depend on worker-provided
flags. Read-only document operations keep their existing current-use and output
rules. Tests must include ordinary allow/approval versus managed input under both
allow and interactive modes, and assert no managed mutation intent or root effect.

## Existing owner and minimal implementation

Reuse `Transaction.switch_before/4`, rather than adding a second file-server
rename or new helper. Its actual native process already owns the retained
Collection `.lock`, stages complete private bytes, syncs and checks the staged
inode, performs the final wall-clock comparison, renames the fixed root and
syncs its directory. Nested ProjectIdentity and Collection acquisitions use the
same Transaction owner. The fixed published pointer names immutable blocks whose
hashes and CAS are validated by Elixir under that lock; Rust remains OS-only.

The narrow implementation should:

1. Admit a bounded positive safe-integer deadline only for the fixed document
   profile, preserving profile/request validation. Other profiles still return
   the historical unavailable diagnosis before preparing a namespace.
2. Reuse `execute_selected`'s existing minimum-preserving inherited deadline and
   scoped restoration. The private final `switch_pointer` dispatch may call
   `Transaction.switch_before` only while the selected profile is documents and
   that deadline remains valid. No-deadline routes retain their existing
   behavior. The outer blanket gate must not be removed.
3. Keep snapshot/record CAS, stage owner/epoch/hash and exact-generation checks.
   The complete immutable mutation request is fixed before staging. No extension
   callback or changed body runs after the native decision. A consumed staged
   pointer cannot be reused: rename removes its private staging name; every
   later operation requires a new request and current CAS.
4. Keep actual lock ownership through replacement, sync and acknowledged release.
   A lost caller/helper or failed response after a possible mutation remains
   unknown. A native elapsed refusal can leave staged immutable data; do not
   invent rollback, exact-time deletion or replay from a generic failure.
5. Keep the existing helper/profile admission, quotas, staging/reclamation bounds,
   request schemas, intent-before-effect and approval gates. Do not relax platform
   admission or treat a private helper override as installed qualification.

The existing native elapsed reply carries an error code, not a persisted clock
receipt. This scoped restoration must not claim an independently inspectable
decision timestamp or reuse State's richer elapsed receipt. Its public document
result remains the existing closed success/refusal/unknown contract. If review
finds a required contract that cannot be established by the existing protocol,
repair that protocol before opening this path.

## Focused acceptance before opening the path

- Actual native live append, seal and consuming commit with the original fixed
  source/owner; same epoch and complete bytes selected exactly once. Include a
  public CollectionStore/Session journey with journaled intent and ordinary
  approval, not only direct trusted calls.
- Hold synced final staging before the decision until the minimum deadline
  elapses: no active-root switch, no successful consuming commit; original
  selected source remains unchanged. Include inherited earlier deadline and
  nested restoration, exact expiry and expired continuation after restart.
- Stop after a live final decision, then resume after expiry: retain the
  documented in-flight distinction, original TTL and truthful outcome. Do not
  call this an atomic physical expiry fence.
- Actual owner/helper loss and contender ordering through native IO; uncertain
  effect stops continuation, remains inspectable and does not replay. A successor
  cannot enter while an earlier native owner can still replace the root.
- Competing CAS, epoch reuse/reclamation and duplicate consuming commit refuse
  without selecting a second version. Existing immutable bytes/receipt schemas,
  profile limits and old-helper refusal remain intact.
- Explicit negative controls prove notes timed publication and the callback gate
  stay closed, readiness stays unavailable, and managed document inputs cannot
  bypass their independent source/effect checks.

Reuse valid prior focused evidence where sources/helpers match; run only changed
behavior and unresolved schedules during implementation. Whole operator/developer
chapter reconciliation, the batched documentation check and the eventual coherent
source/package baseline remain required. A working document stage does not
complete shared-generation publication, full capacity, migration, Word fidelity,
capture/recall or P30 consumer experiments.
