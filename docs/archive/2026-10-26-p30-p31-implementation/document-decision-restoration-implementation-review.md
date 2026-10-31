# Independent document decision implementation review

Historical scoped review, **2026-10-29**, of
[ordinary document restoration](document-decision-restoration.md) against the
[accepted design](document-decision-restoration-design.md) and
[independent scope review](document-decision-restoration-independent-review.md).
The reviewer changed no implementation or runtime gate, ran no duplicate tests,
and made no model or network requests. The [plan](../../plan.md) owns milestone
status. Current manuals and their final reconciliation remain parent-owned.

## Disposition

No additional concrete blocker was identified in the inspected **ordinary,
fixed-profile document-stage restoration**. The implementation preserves the
reviewed final locked decision contract and closes the managed-input bypass at
both required host boundaries. The focused evidence supports these scoped
behaviors; it does not establish whole-source/package/platform qualification,
all failure schedules, complete document capacity or P30/P31 completion.

The new route does not promise physical completion before expiry. Each exact
stage mutation retains its original epoch/TTL and final generation/revision CAS.
The native owner checks the selected deadline after staging and immediately
before replacing the fixed root. A pre-expiry decision can finish physically
later; an expired new decision cannot select the staged replacement. Generic
post-staging failure remains unknown and never implies rollback or replay.

## Source and evidence checks

The supplied [manifest](document-decision-restoration/manifest.sha256) hashes to
`14f2296e7b87f4c36e5538a3b290317e627905f7441205b7aad446214ffcb7c3`.
The reviewer ran `sha256sum -c` on every listed artifact; all matched.
`tar -df` on the frozen [source archive](document-decision-restoration/source.tar)
also passed against the fourteen current scoped files. The
[source hash map](document-decision-restoration/source-sha256.json) identifies
the exact implementations and tests, rather than attributing all intermediate
runs to the final cohort.

The reviewer read the actual passing/failed logs and their test assertions.
The [cohort record](document-decision-restoration/cohorts.json) correctly separates
the earlier DocumentStage/classifier, final runtime and intentionally older
Invocation overlay. Both final and queued inventories use unchanged native
helper `7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`.
No native implementation change is introduced by this restoration.

## Implementation assessment

| Boundary | Source and inspected evidence | Disposition |
| --- | --- | --- |
| Fixed-profile dispatch | `Collection.execute_profile_before/6` admits only exact `Profile.documents()` and positive safe deadlines. `switch_pointer/1` selects native `switch_before` only in that profile. Notes-profile timed entry and `with_publication_deadline` still refuse; global publication support stays false. [47049](document-decision-restoration/ipse-document-decision-host-v2-47049.log) passes the actual ordinary Session and notes-gate cases. | Scope matches the accepted design. No worker profile/deadline selector, saved-consent grant or new public authority is added. |
| Deadline minimum and restoration | `DocumentStage.execute/6` validates inherited/explicit scope, takes their minimum and restores the exact prior process value. Its commit takes the minimum again with the original stage expiry. Collection composes its native switch scope independently. [47046](document-decision-restoration/ipse-document-decision-scope-47046.log) passes the trace-backed minimum/restoration control. | Omitted/nil/later scopes cannot clear or extend a trusted inherited deadline; earlier scopes win. Invalid/elapsed scopes refuse. Opening or reading a stage does not renew its TTL. |
| Final native owner and unknown | Collection stages complete immutable bytes, syncs and calls the existing retained owner's `T` root switch. After staging, any pointer/sync/cleanup failure maps to `collection_publication_unconfirmed`; final lock check/release must succeed before a known return. CollectionStore preserves unknown. [47047](document-decision-restoration/ipse-document-decision-staged-expiry-47047.log) holds the actual operation after synced staging until expiry. | The actual result is unknown; root bytes and old selected value remain unchanged. No persisted native decision timestamp is claimed: `T` returns an error code, unlike State's richer elapsed receipt. The hold is before the final native decision, not an atomic physical-time proof. |
| Stage identity, consuming CAS and reuse | [47048](document-decision-restoration/ipse-document-decision-components-v2-47048.log) passes four selected component cases. Their assertions cover prepared inline privacy, changed-owner refusal, complete multipart append/seal/consume/read, duplicate consuming commit refusal and old-epoch refusal after slot reuse. Final mutation binds expected namespace generation and exact record revisions. | Existing owner/epoch/hash/CAS and one-use selection survive restoration. Concurrent changes cannot silently rebase a prepared request. The stage transport TTL does not become later source-use authority. |
| Expired stage reclamation | The selected component fixture first proves live reclaim refuses, then deliberately writes an expired header (`expires_at_ms:0`) through a trusted setup operation, proves seal refuses, and reclaims exact epoch from a fresh owner. It verifies retained part/header deletion and stale-epoch refusal after reuse. | This is a synthetic stored-expiry/reclaim control, not an elapsed one-hour human or restart journey. Original TTL/epoch are checked in implementation; broader lifecycle schedules remain separately qualified. |
| Ordinary actual Session | [47049](document-decision-restoration/ipse-document-decision-host-v2-47049.log) passes the Session case transporting a complete value over32KiB through seven append actions, ten ordinary full-argument approvals and more than sixteen validated action results. It reconstructs the exact value, removes the consumed stage and validates Saved replay. | Required useful ordinary staging is demonstrated through the public host path with a fixture provider and real native storage. This is not installed Word ingestion or model-quality evidence. |
| Current managed pre-intent gate | Invocation refuses mutating `collection.store` when the host's invocation union is managed. [47051](document-decision-restoration/ipse-document-decision-classification-47051.log) passes actual allow and interactive cases: observed managed read, no document action intent, no approval/tool event, no effect admission and no namespace. | Ordinary allow does not bypass source authority. Read-only document operations retain their existing separate rules. |
| Missing-dictionary classification | `managed_invocation?/1` treats any nonempty/unavailable result, exception or caught exit as managed. The pure47051 case covers inherited-only dependencies, prior and newly recorded reads, unavailable lineage and a missing dependency digest; the exact empty union remains ordinary. | The repaired classifier cannot turn corrupt/unavailable lineage into ordinary authority. The earlier47049 exception remains a failed finding, not a passed negative control. |
| Execution backstop | CollectionStore refuses mutations for **every non-null** deadline supplied by trusted `ManagedToolUse.with_effect`. That helper returns nil only for the exact empty ordinary dependency union; active action snapshots union inherited and newly read dependencies. [47052](document-decision-restoration/ipse-document-decision-queued-backstop-47052.log) uses earlier Invocation to admit a managed action intentionally, then requires a failed `document_store_refused` receipt before DocumentStage/namespace creation. | This is an actual execution-boundary control for an admitted action. It does not bypass or qualify current public admission. The current gate is separately tested by47051. |

## Failed cohorts and remaining limits

The initial47041 graph's inherited-scope failure loaded an older DocumentStage;
the later47045 fixture then attempted to prepare a snapshot inside an already
expired scope. Compiling current source and preparing the request beforehand
produced the passing47046 control. These two failures remain retained. Likewise,
47049 passes two cases but fails the missing-dictionary classifier before its
47050 repair and passing47051 selection. Empty strict-compile logs establish no
claim beyond their recorded successful launch/exit and cohort provenance.

The final inventories were captured after focused executions. The record does
not claim a complete initial inventory or that all earlier tests used final
source. The intentionally queued graph differs in Invocation while retaining
the current classifier/document execution modules; its launcher and expanded
fixture are preserved and distinguishable.

This review accepts no managed document publication, saved-consent capture,
native-reviewed mutation, managed State/service call or output delivery. Their
separate gates remain necessary. Shared-generation/controller publication,
streamed finalization, full geometry/capacity, cleanup/migration and Word/PDF
fidelity remain separate work.

The unchanged native ownership/after-decision foundation can be reused only
within its recorded scope. This increment does not freshly execute every
document-specific helper/owner-loss, blocked-IO, contender, restart or sync/release
fault schedule, nor an installed or other-platform baseline. No such coverage
is manufactured from a passing staged-expiry control. Whole-manual reconciliation,
navigation checks, coherent full-source/native/package checks and final acceptance
remain required at the relevant completion boundary.
