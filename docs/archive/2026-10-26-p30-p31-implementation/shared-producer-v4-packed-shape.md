# Escaped fact pages and packed storage — 2026-10-29

Historical development evidence following [batched citation validation](shared-producer-v4-batched-spans.md).
The [plan](../../plan.md) owns acceptance. This candidate precedes the later
[split-append change](shared-producer-v4-split-append.md).

A synthetic 256-chunk group with 256 wide, heavily escaped fact fields first
refused its read reservation before effects. Fixed-generation catalog and
source-reference reads reduced that cost, but the next model run reached a
fact page whose logical JSON fit 48 KiB while its native packed wrapper exceeded
the physical value limit. The model stopped after prior synthetic writes; no
actual native effect or replay was involved.

Group packing now checks the complete native representation while splitting
pages, and checks the group header and summary before staging. A focused
256-fact control verifies that escaped pages split, every resulting value fits,
and unpacking reconstructs the supplied data. The fixed-generation catalog
reference and retained source-bundle selection use the previously checked
catalog hash and revision; a final catalog stat still verifies that anchor.
The append reservation also counts additional escaped read pages in catalog,
root and Job anchors; model controls compare the count to the actual reader.

Splitting added three fact pages. On this candidate the full escaped group then
refused before any stage: 410 reads plus 106 reserved reads exceeded 512. The
following split-append work addresses that specific cost, not the wider quality,
physical peak or Session handoff gates. A fresh two-page synthetic native Session
passed with an empty old root on artifact
`65fe163851b5c8f1c843a6b621296f3a800a8a07a752ed630b76c536e02b70ea`.
It did not execute the private wide append.

The [manifest](shared-producer-v4-packed-shape/manifest.json), SHA-256
`1f401bebdbf172d9afa419a7c3f0d812f4b50ef6a7ae582974efc30572b5def5`,
pins 95 source, artifact, test, diagnostic and synthetic evidence files. The
failed runs and their reasons remain intact. Independent review, native
large-group publication and full reservation proof remain open.
