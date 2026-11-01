# Refuse unsupported private Worker inputs before transfer

Dated **2026-11-01**, based on `b47022c` and the fixed-source inventory below.
This is bounded host-invariant work; full C0 and P30/P31 acceptance remain open
in the [plan](../../plan.md). Current reader contracts belong to
[extension authoring](../../developer/extensions.md),
[events](../../developer/extension-events.md),
[text ownership](../../developer/lifecycle-events.md) and
[operator selection](../../operator/extensions.md).

## Reassess the input routes

The export adapter requires an actual committed invocation parent and pending
frame. A transform, notification or text callback cannot acquire that contract
by inventing a parent. The audit instead traced every direct Worker call family.
Exports and action/page continuations use the retained input fence. Nested managed
services already refuse. Initialization carries selected operator options.
Observability uses only the existing metadata projection. The remaining private
purposes need explicit refusals until their own transport is qualified.

A selected shipped formatter provided the first counterexample: a registered
model read the protected root and its final managed answer reached the actual
presentation callback. Its committed result retained that input. The baseline
passed the ordinary control but failed the managed refusal: **one of two passed,
147 excluded, in 10.1 seconds**. The first repair passed both in 10.4 seconds.

Independently compiled sink artifacts then exercised private answer notifications,
private tool-result feeds and visible text, with actual acknowledgments. Ordinary
and managed metadata positives remained requirements. The first fixture attempt
failed all eight cases during compilation because its SDK-only path did not
load Jason; it now uses OTP's existing `:json` encoder. Its executable description
also declares the actual subscriptions. The second run passed three of eight:
feed artifacts lacked their required `lifecycle.record` capability, while the
notification and text expectations exposed the old allowed routes. After that
declaration repair, **five of eight passed, three failed, 149 excluded, in
22.3 seconds**. The log prints actual private feed and notification callback
payloads. The text case completed where the new unsupported-purpose contract
requires refusal. These synthetic root-metadata controls establish no new
record-content or accepted-decision sink qualification.

## Refuse at each existing owner

Session now refuses a managed presentation before transform intent or Worker
startup. A private notification retains its ordinary intent but passes no
payload to Host, producing the existing known `not_started` result. Optional
notifications continue and required notifications fail settlement. A matching
private tool feed checks known-empty lineage before private projection, intent
or queue admission; refusal records the actual gap and closes `view_unavailable`.
Metadata notifications/feeds keep their existing path. Jobs retain protected
export input. Unknown lineage grants no private entry.

For selected Worker text consumers, the dependent model request refuses before
admission when its complete dependency snapshot is managed. This applies to
optional and required consumers, with explicit fresh-session recovery after
disabling the consumer. It avoids placing managed bytes in an asynchronous
Worker queue. Compaction has no text-consumer output and retains its own path.
The three initial sink repairs passed all eight cases in 22.0 seconds.

These refusals preserve known effects and the original recorded answer. They
mint no source permit, renew no deadline and add no native protocol or dependency.
Their scope is selected private Workers; existing embedded-client and native
transcript contracts retain their separately scoped evidence.

## Keep required delivery and recovery exact

Adding required-consumer and idle controls first passed ten of twelve cases in
27.6 seconds. One failed fixture assumption expected only a release-owner record
on feed resume; `lifecycle.record` also starts its existing metadata epoch. The
test now requires exactly the owner and valid resumed epoch, linked to the actual
closed predecessor, plus strict Saved reconstruction and unchanged callback
traces. It permits no resumed consumer, feed or model work.

The other failure exposed an existing producer-identity bug. Required text
readiness was checked inside the registered provider child, but the broker admits
only its original producer. The check now runs in that producer before inference
admission and again through its registered dispatch-gate callback. The provider
child receives no broker authority. Buffered text already returns to the original
producer, and required frame acknowledgments still precede answer acceptance.
A new ordinary registered-model positive requires actual required text delivery,
preventing this unrelated failure from passing as a managed-data refusal.

All thirteen sink cases then passed in 27.9 seconds. They include ordinary
optional/required callbacks, acknowledged managed metadata, exact one-versus-three
HTTP request counts, known native writes before notification/feed refusal, no
private callback or feed intent, known unstarted notifications and strict
close/idle recovery. Final controls additionally observe actual durable
acknowledgments before closing successful notification/feed leases. Observation
watchdogs change no production deadline or accepted outcome.

## Fixed-source qualification

The serial fixed-source qualification passed:

- Build: 183 host modules and three inert bundles; formatting and strict compile.
- Existing transform/subscription/feed/text/job/lineage/registered-dispatch
  compatibility: **106 passed in 76.4 seconds**.
- Combined private-sink, presentation, nested-result and Worker-input controls:
  **23 passed, 139 excluded, in 42.5 seconds**.
- Genuine native approvals: **11 passed, 12 excluded, in 174.7 seconds**.
- Single/two accepted-decision input journey: **one passed, seven excluded,
  in 42.7 seconds**.
- Broker/producer and runtime/tool lifecycle invariants: **38 passed in
  30.9 seconds**.
- CI policy, isolated-home credential-free demo and documentation checker:
  **1003 Markdown files, 8343 local links, zero errors**. Private permission-denied
  directories remain untouched.

The source, event, lifecycle, testing and operator manuals were reviewed as reader
documents and reconciled around admission, delivery, required policy and recovery.
The native helper has the same hash as the preceding qualified candidate; no
Rust source, native ABI or dependency changed. No new package was built for this
focused increment; installed qualification belongs to a later exact candidate. No older
package qualifies this runtime change. The original whole-suite failures remain
unchanged as an aggregate. Complete inherited-source boundary, capacity,
installed/platform, human, quality and adversarial qualification remain open.


| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `lib/ipse/session.ex` | 271839 | `1ad553b18926f1b3d7eac0b90871a49faac464ed45ecabeaf6afb319ca80a8ef` |
| `lib/ipse/session/turn.ex` | 74187 | `9be5b672fc237ab1e623b20bf8cfe98d4636e9b99a1230e6ecf49ebf516effc7` |
| `lib/ipse/extension/host.ex` | 33077 | `a7f5d876fcaaf719e93cedf17a2c53d13edef147977e9074067b97bfeef33e40` |
| `lib/ipse/extension/feeds.ex` | 26006 | `34281b5cdee7d0c1c380248c269bb046475af23933fbbcb51c693eb590476640` |
| `test/ipse/extension/managed_collection_call_session_test.exs` | 298525 | `b3a3c4678509ff60b5d7d42e45ef5ebb4283e6fb8a27ee5a3adeccec9e9d8276` |
| `test/support/managed_delivery_sink.exs` | 5843 | `5586c30a0640c6ac7a8f6e929c4bab29d1d4eb9d0ca2b6f887326822e8824bc2` |
| `priv/ipse-runner` | 969344 | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |
| `/tmp/ipse-presentation-input-baseline-20261101.log` | 5524 | `b1c48775eebade81f9e3e9d8ee34bd684a9ae38e0a47ad8e85c8c387da224b84` |
| `/tmp/ipse-presentation-input-first-20261101.log` | 402 | `736c668f5ea007a58cc00d31c4482f2de3a0c1d4c9b1367a682caf98bf468ef4` |
| `/tmp/ipse-presentation-input-compile-first-20261101.log` | 83 | `9b0acda94a385256915bb774078aa93c8fe13b915ea274a5072e4aa7ac277be5` |
| `/tmp/ipse-private-sinks-baseline-20261101.log` | 9884 | `c008fcaa7df0d18ece15d0496c88f7551267f66110103b91430f9331f23bd30a` |
| `/tmp/ipse-private-sinks-baseline-second-20261101.log` | 4806 | `0595c05f45645def9ac7f7c6cc13b577393b811526351a5bffeadea707ba1ef9` |
| `/tmp/ipse-private-sinks-baseline-third-20261101.log` | 6994 | `54499adadc601d1d7501c3323b82edbf0a07da055afc5cb781c0d926f094489a` |
| `/tmp/ipse-private-sinks-first-20261101.log` | 400 | `1c23430e5546d3198338a8b620696d37ef383527d86dd1015bf6c4f7c949f672` |
| `/tmp/ipse-private-sinks-required-first-20261101.log` | 2624 | `a5a2029933ba17d626bb29cddd30a88fd4b0ad64ceed9115579453c05772a322` |
| `/tmp/ipse-private-sinks-required-second-20261101.log` | 348 | `e5dda47ca3318c229965213b1e67bf8588248a42c79d0fdbdbbf7f493e32d828` |
| `/tmp/ipse-private-sinks-build-final-20261101.log` | 845 | `d4b7a8efde7a1a7267e3882d7906552a8d4921b02b4973d153b165574d166615` |
| `/tmp/ipse-private-sinks-format-final-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-private-sinks-compile-final-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-private-sinks-compatibility-final-20261101.log` | 357 | `bc50afb3f124f02a1775c5f61bed2c861143e50e2b2af1242072add871867ae9` |
| `/tmp/ipse-private-sinks-boundaries-final-20261101.log` | 410 | `5d3336ec63a5c3fa2d5d0337298f6cb731b3e0ab333571ac870d572167a03dd0` |
| `/tmp/ipse-private-sinks-approval-final-20261101.log` | 327 | `6da470dedc0100c490cfc4db730be976864a3992147064551b35ba6a45a8130c` |
| `/tmp/ipse-private-sinks-accepted-final-20261101.log` | 287 | `c7f6063ed98aa11822bbe6455ef051a100c7a7c43ad11c849c90e6eaaa92bb1d` |
| `/tmp/ipse-private-sinks-ci-final-20261101.log` | 32 | `e856938f2d4ee3eb319a90056aca83ff6b7347ea57ff71bac975f84df18ae633` |
| `/tmp/ipse-private-sinks-demo-final-20261101.log` | 2720 | `a54af3f35340ee4a247ac74373e5ab33660c1a8f69ea2362232ce4324b8039f0` |
| `/tmp/ipse-private-sinks-broker-final-20261101.log` | 289 | `6ac38dac2d059548847e8dd398af69980bf3ce5023c70ffdd656b1506502b0e5` |
| `/tmp/ipse-private-sinks-docs-final-20261101.log` | 757 | `860afd2d57732432c05852b07539a6b325d13a4f7b77ede027d4a7c4bb9d3b9e` |
