# Guarded shared producer through an actual Session — 2026-10-29

This synthetic local-loopback qualification uses the private artifact whose manifest
SHA-256 is `8de1ae2e139b416b8cdf7c8015f6b2c990e9003bc3f445bd4b2bd7b3a517b229`.
Its copied Corpus changes only the production page refusal to the existing
`Producer.start`/`advance` delegation. The public production page remains closed
at this freeze. This is actual native/SDK/Session execution, without a live model
account, inference service outside localhost, Word input, or supplied-vector claim
of model provenance. The extension author also wrote these fixtures; independent
Host/cohort review is separate.

## Exact controls

Both cases use four ordinary public Source3 puts, each 7,480 UTF-8 bytes and two
chunks, a public compact generation-job begin, explicit operator collection binding
v2 with `source_use: shared_producer_v1`, a registered loopback embedding route,
and normal full-argument approvals. Claim publication is a real same-invocation
native commit. The fixture endpoint returns 1,024-dimensional vectors and an
explicit reported `fixture-model`. The main conversation provider is forbidden.

| Control | Actual result |
| --- | --- |
| 47213 nil-TTL positive | One case passed in 33.6 s; four guarded batches and four observed HTTP bodies; eight producer storage approvals; ready claim revision 35; complete shared-vector page 45,064 B. |
| 47214 whole-claim source expiry | One case passed in 45.0 s; Source4 alone had a finite expiry. First embedding approval arrived before expiry and was held until after it. One approval, zero observed HTTP bodies, pending claim revision 29. |
| 47216 read-only retained-store inspection | Both original journals equal saved bytes; real claim operation/revision matches same-parent prepare/commit; positive native page has eight exact fixture vectors and matching input hashes; expiry remains pending. No effects or model replay. |

The positive used nil expiries. The negative proves a captured claim source expired
during approval, without asserting that Source4 supplied the first batch's text.
The old selected domain root was exact absence in both fixtures and remained so;
this does not qualify replacement of a populated selected generation. Both cases
validate Saved reconstruction before and after confirmed close. No worker stage is
adopted by another Session and no failed/unknown intent is retried.

Positive journal: 3,057,740 B, 963 events, SHA-256
`876535ce2ca3adb89c20f736125b04f07b0f72daf52f01150ad3b54daf2aaa81`.
Expiry journal: 2,457,817 B, 767 events, SHA-256
`85655310a32c26c2b98ecba75f2767795617e8e57a75bb996a346bedaaafc5c9`.
The positive initial claim committed as `cc3450a3bd75f24a287314464414a183`,
revision 29; its final ready record committed as
`1ad1382b9171d775f860cd38e76f1d29`, revision 35. Expiry's claim committed as
`1facf73990d16e5a729c1aa026b2de79`, revision 29. Ready page SHA-256 is
`c8dad1feefacf0adbe529fc60de1cd8720238dd02c3ebe674d8555fa48936c40`.

## Failures, repair and retained boundaries

The logs retain the first failures rather than replacing them: 47199 configuration
schema lacked binding v2; 47201 fixture expected an immediate source result rather
than following its known draft; 47202 omitted the explicit service registration;
47205 reached admitted inference but its gate refused before HTTP. Early teardown
removed those failed native homes; their journals remain, and no native read of
those removed stores is claimed. A journal-only reconstruction initially failed
on the developer model's generation-1000 seed assumption (47208); its explicitly
diagnostic adapter then validated the recorded relation/cache (47209).

One fresh bounded diagnostic graph preserved all decisions and logged only named
gate stages (47211). Authentication, Session admission and batch spending passed,
then the reader rejected its callback's bare `:ok`. The
[caller-return repair](document-source-admission-return.md) returns an exact opaque
success marker through native reader, Identity and Resources cleanup; only the
matching returned marker authorizes egress. This ordinary repaired graph, without
diagnostic instrumentation, produced 47213/47214. Read-only native inspection of
the retained diagnostic store also passed (47212). The first final-readback script
assumed a nonexistent header session-id field (47215); corrected 47216 derives the
actual Session binding from recorded guarded actions. No failed intent was replayed.

## Frozen provenance and remaining work

[Manifest](shared-producer-guard-session/manifest.json), SHA-256
`c191be053710bcc6c291b62edb8f600837477e9ee7c9642d489dfd36d6fe904b`, pins 34
source snapshots, 12 scripts, 20 logs, 18 synthetic evidence files, three exact
701-file runtime inventories and 26 artifact files. It includes the independently
reviewed [worker wire](shared-producer-guarded-wire.md) and exact initial/return
Host ancestors. [Verifier](shared-producer-guard-session/verify.exs) and its
[log](shared-producer-guard-session/verify.log) perform hash checks only. Compiled
files stay under `_build`; no binary or native private key is archived. Original
later fixture homes remain on admitted `/tmp` tmpfs, with hashed path locators.
The helper is `40fa075e85348990407c4baf16617c91a7649a4cfa48fb7fa816f0dfba5f8b02`.
Complete 216-module application inventories bind the new Host owners.

This qualifies the first shared-vector page and its guarded source admission in
the stated cases. Finite-TTL positive execution, canonical public-route adoption,
later pages/facts/header/group completion, complete producer accounting, populated
capacity/rebuild, GC/migration and representative Word quality remain separate.
Validated executed receipts do not establish independently authenticated historical
model provenance; the existing provenance flag remains false. Admission uses the
reviewed short final locked decision; bytes admitted before a later source change
remain an in-flight liability.
