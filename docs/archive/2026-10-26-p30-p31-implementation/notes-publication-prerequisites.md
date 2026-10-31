# Authentic root-only reads before new capture

Scoped implementation, 2026-10-29, after the
[failed first genuine capture](remember-publication-first-control.md) and
[independent prerequisite review](remember-publication-prerequisite-independent-review.md).
The [plan](../../plan.md) owns acceptance. This repairs a pure prerequisite check;
the final native CAS still establishes disk currentness.

`ManagedReads.root_prerequisite?/4` matches each v3 root-only dependency against
its own successful current-parent `collection.call` snapshot or explicit nil-get.
It reuses the actual CollectionCall outcome/binding validators and existing full
read-dependency binding, including project, namespace, pin/policy and complete
request/result digests. A missing record field is not nil absence. Nonempty gets,
scans/indexes, foreign actions and mismatched pin/namespace/generation refuse.

`ManagedToolUse.publication_prerequisites?/3` requires no inherited input and an
identical complete root observation across the whole dependency union. Each
dependency must match its own authentic action; it need not borrow one snapshot's
request/result hashes. No dependency is removed and no note-key naming convention
becomes authority. Existing empty-dependency handling and other source/output gates
are unchanged.

The [manifest](notes-publication-prerequisites/manifest.json), SHA-256
`ae6c379a3e297ee63ea6dda1e50ea82ec2bd22d6b962ba90ae4e66cf834edf5b`,
retains both production owners, the exact focused test source, five
launcher/log/freezer files and complete parent/candidate runtime inventories.
Only ManagedReads and ManagedToolUse are overlaid on the
[notes-admission graph](notes-publication-admission.md). `47171` strictly compiled
both without diagnostics. `47172` passed three focused tests (ten excluded):
authentic snapshots; distinct explicit nil-gets without a snapshot; and missing,
foreign, nonnil, inherited, mixed-root, mismatched-policy and valid-empty-scan
refusals. The previous minimal snapshot fixture was corrected to carry the actual
v3 summary, project/namespace and pin-bound action fields.

The later [genuine native Session-channel capture](remember-publication-absence-integration.md)
published one literal and settled its matching operation without a model call.
It used these exact two runtime overlays. The first failed store remains untouched;
no operation was replayed. Neither this prerequisite cohort nor the positive fixture
qualifies all capture sources, terminal CLI behavior, races or later-use sinks.
Independent implementation review is pending; no aggregate test or paid inference
ran for this repair.
