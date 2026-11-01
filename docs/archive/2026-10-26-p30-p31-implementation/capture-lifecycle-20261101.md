# Registered V3 lifecycle and queue controls

Dated **2026-11-01**. Author fixture repair on top of `e569c4f`, after the
[same-owner domain-selection repair](domain-selection-20261101.md). This is a
historical verification record, not a runtime change, independent audit or
milestone acceptance. Current procedures belong to
[testing](../../developer/testing.md#require-positive-controls-and-inspect-uncertainty)
and [native knowledge](../../operator/knowledge-permissions.md); the
[plan](../../plan.md) owns remaining scope.

## Preserve the failures and distinguish their causes

Seed 791669 selected three unchanged required integration cases against current
source: V3 first-publication/activation/recovery, V3 full-pending-queue admission,
and legacy metadata-v2 receipt/accounting. All three failed: zero of three
passed, 164 excluded, 56.0 seconds, exit 2. The log is
`/tmp/ipse-capture-journey-baseline-20261101.log`.

Both V3 cases actually published their first record, then failed at the next
model continuation. Their direct demo `provider_module` lacked the registered
native send/completion ownership required by managed history. The legacy case
instead refused at its metadata-v2 publication gate before publishing. It remains
an open compatibility/integration requirement; this change neither promotes its
request to v3 nor changes its positive expectation into a refusal pass.

## Use the existing registered adapter fixture

The two V3 cases now explicitly select the existing registered Ollama wire
fixture, the capture export and enough complete response pairs for their two
or three actual Sessions. The ordinary provider adapter, inference service,
completion witnesses and managed dependencies are unchanged. No successful
transport/Review witness is manufactured. No runtime, native helper, dependency,
policy limit or deadline changed.

The activation case still requires the actual first operation/root witness in
Identity, exact v3 effect/normalization bindings, measured settlement and a
second successful publication at generation two. It now also checks strict
Saved reconstruction, both completed adapter requests for each Session, four
actual HTTP requests overall, confirmed closes and the exact idle-resume
ownership suffix without Worker replay. Later publication must leave the active
Identity catalog unchanged. Existing binding tamper checks remain.

The queue case still proves successful admission below capacity, fills the
retained pending population to 64, and requires the next action to be failed
with `collection_unavailable`, unchanged snapshot/root witness and a settled
reservation. It now requires strict Saved reconstruction, two completed adapter
requests for the refused attempt, six actual requests overall and idle recovery
without another callback. A known failed capture can be returned to its model
and the turn can finish normally; an unrelated unregistered-route failure is
not the capacity assertion.

The first registered run retained the old turn-error expectation, seed 791670:
one of two passed, 165 excluded, 32.5 seconds, exit 2. The queue case observed
`done: ok` after its known refusal. Its negative storage/accounting assertions
were preserved while correcting that turn expectation. The repaired cases then
passed, seed 791671: two passed, 165 excluded, 18.6 seconds, exit 0. Logs are
`/tmp/ipse-capture-journey-registered-{first,fixed}-20261101.log`.

The `registered_capture_lifecycle` tag selects these cases. The testing chapter
integrates them into the existing registered capture exercise rather than
introducing another authority path. The entire chapter and the current operator
knowledge/recovery procedures were reviewed for consistent prerequisites,
completed-turn versus failed-effect distinctions and no-replay guidance.

The final combined selection, seed 791672, passed **eight tests**, 159 excluded,
83.7 seconds, exit 0. It ran lifecycle, repeated sequence, competing publication
and registered result/revocation/ambiguous-mapping cases together. Its log is
`/tmp/ipse-capture-journey-combined-20261101.log`; retained synthetic roots are
`/tmp/ipse-collection-sdk-b838357e05baeab7645098cf0724c2b1`,
`/tmp/ipse-collection-sdk-f6450f4dccf2e76e74deebc55c02514c` and
`/tmp/ipse-collection-sdk-8dbb6884599d1749b63a8237ae298ddf`.
The [selected-input receipt](capture-lifecycle-20261101.json) hashes the final
test input and all four logs after execution. It is not a prelaunch freeze or
complete loaded-runtime inventory.

Final whole-checkout formatting and documentation checks exited 0. Logs are
`/tmp/ipse-capture-journey-format-20261101.log` and
`/tmp/ipse-capture-journey-docs-20261101.log`. The prior runtime build and strict
compile remain applicable because this increment changes only tests and prose;
no full suite or package was rerun for it.

## Qualification limits

These are actual native/Session/HTTP controls with synthetic model responses
on the qualified Linux `7.2.11-arch1-1` tmpfs profile. They establish no live-model
quality, elapsed retention endurance, installed package, macOS, newer-kernel
Btrfs or independent human result. Source implementation and bundled artifacts
are unchanged from the previously built `e569c4f` candidate. No new real model
request, download or external review was made.

The [complete frozen baseline](full-suite-20261101.md) remains 3,653 passed and
54 failed at `f44b63c`. No focused pass is subtracted from that aggregate.
Legacy publication, subscriber-based approval replacements, source/loss
integration and full P30/P31 acceptance still require their own evidence.
