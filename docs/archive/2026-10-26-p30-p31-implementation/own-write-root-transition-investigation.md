# Own-write root transition — source investigation

2026-10-29. This is a source-only proposal for independent review. It grants no
new authority, changes no runtime gate and does not qualify the full turn. The
[retained source-tool controls](managed-source-tool-preflight.md) committed and
settled a real generation-one capture, then refused the next model preflight;
the final turn failed. That known write and the later refusal are separate facts.

## Existing evidence and unresolved predecessor identity

A root-only dependency includes the complete old Collection root, original
request/result hashes, project, namespace, pin and policy generation. The
causal cache is populated only by authenticated committed payload-free reads.
`ManagedUse.observe_all` currently requires the live root to equal that old root;
`ManagedReference.current?` likewise requires exact equality for version 3.
`ManagedLineage.historical_write` records action, normalization and receipt
hashes, generation, operation ID, record key and category. The validated managed
receipt binds the original request, recipe and normalization and establishes
`expected_generation + 1`, but does not itself repeat the complete old root.

The normal managed publication loads Collection state under its native retained
lock, checks expected generation and revisions, inserts its receipt in the next
operation ledger, and switches the root. Valid state requires the generation to
match the operation count and operation generations to be unique. The present
root witness authenticates the exact root and manifest bytes selected by the
Collection view; the operation ledger binds its operation ID and receipt. An
independent audit must establish whether all permitted recovery, imports,
profile/identity operations and the supported filesystem trust boundary make a
generation uniquely name the original complete root across the whole interval.
A compliant CAS alone does not by itself prove that assumption. The observed
old root in the retained example was absent; a generation number alone should
not be treated as proof of absence. If uniqueness is insufficient, the narrow
fallback is a versioned publication binding that commits the complete prior
root witness already available inside `Collection.normalize_managed`, with its
digest retained in the existing managed operation receipt. Its format, bounds,
legacy replay and first-publication proof require separate review. No extra
binding should be added merely because the current receipt omits a repeated
root hash.

## Candidate scope

Only the exact current Session's already committed, successful new-v3-capture
action may qualify. Its real action intent/result, validated managed receipt,
operation ID, request and normalization must match, and the entire inherited
union must consist of the same authentic cached payload-free root observations
under the exact same project, namespace, pin and policy. Missing or false cache,
unknown or interrupted publication, changed source or policy, mixed roots,
record/content dependencies, a foreign action or any intervening write refuses.
No worker-supplied root, receipt, operation or deadline grants authority.

Using whichever predecessor proof independent review accepts, freshly acquire
actual current Identity, Consent and Collection authority. Recheck the exact
current root and manifest, generation exactly predecessor plus one, and exact
operation/receipt in its authenticated ledger; the advancing floor anchor must
also agree where the admitted capture requires it. Preserve the original
observations, digests and cache as historical facts. Journal a separate bounded,
owner-derived transition/admission bound to the original preflight, exact
successful action and fresh root; Saved must reconstruct it chronologically,
not rerun or accept serialized worker authority. An old empty-index or nil-get
result describes the earlier root; it must never be represented as an assertion
about the new root. The model-facing projection must preserve provider/tool-call
integrity and clearly identify historical root metadata while retaining the
original transcript. It must refuse where an occurrence cannot be safely
projected. Existing `ManagedReference.withdraw` refuses some tool-call and
provider-data shapes, so a claim that its existing projection already covers the
actual fixture needs proof. Retaining the source result does not make the old
Collection result current.

The preflight is not the final send admission. Existing `ObservedRead.read`
closes its Collection view before returning, and `ManagedUse.with_dependencies`
retains Identity/Consent but does not itself retain that view through its
callback. The implementation must prove current root/ledger exclusion at the
actual owned final send admission, using a retained Collection callback or an
equivalent demonstrated lock invariant. After admission, already-admitted
in-flight bytes and uncertainty follow the existing reviewed contract; this is
not a physical instantaneous cancellation promise. Preserve all original source
proofs and the normal current-use/result checks.

## Qualification needed

Focused controls must show a genuine successful model-selected capture followed
by a completed final turn and actual worker-result delivery; inspect its durable
journal, exact root/operation/settlement and Saved reconstruction independently.
Include an intervening publication, same-generation identity ambiguity if
possible, unrelated/foreign/unknown operation, wrong predecessor, changed
project/pin/epoch, missing/false cache, mixed old roots, record-bearing input,
tampered/reordered transition, later policy/source changes, and owner loss at
admission. A stale empty index must be presented only as historical, and no
historical note content may be made current by this path. Keep the two original
settled-but-refused stores untouched and do not replay either operation.

Inspected shared source SHA-256 values: `ManagedReference`
`916ef4e4423c92222b5d8561d121df9abc76e970fd156643195a4b13ea57fead`,
`ManagedUse` `5a81882447bcc6ac2061b4392b07edecad927ea615eb3a5835eec09b8949762b`,
`ManagedLineage` `f7dcce1055deab1a30292c34148553d05a2cc6df9ace966c8fe1ea4a34e75c95`,
`ManagedCollectionCall` `d8fd728e2beecbaba51cf2a3e7cf6f8a7fb6f3758b8acb0a03577c9801e4bb5b`,
and `Collection` `8115f10d5c251261bf2aaa2e2aa4e6202934724c113850d1f41803e6fd622a56`.
These identify inspected source only, not a new compiled or tested cohort.
