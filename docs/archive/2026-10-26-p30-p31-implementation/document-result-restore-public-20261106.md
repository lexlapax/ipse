# Bounded public document Collection restore, 2026-11-06

This record describes one synthetic public Session journey against a private
copy of the source runtime. It is not an installed-release, full-capacity,
cross-project or changed-target restoration qualification. Current operator
steps are in the [Corpus manual](../../operator/corpus.md#back-up-a-small-document-collection);
the implementation and validation boundaries are in
[storage training](../../developer/knowledge-storage.md#restore-completed-document-collection-data).

The fixture used ordinary public Corpus commands and a synthetic supplied text
source. It built the lexical index, retained native-backed pages and plans as
`saved.result` references, and validated pages through separate closed producer
Sessions. The successful final plan covered **11 records in three pages**. The
restore Session used the same admitted project and collection. It confirmed a
denied open without a changed observed descriptor, then completed a same-floor
open, page sequence, commit and rollback. It also completed an abort and a later
same-floor commit and checkpoint drop. Reuse of the dropped checkpoint refused;
a new open and abort succeeded afterward. A selected lexical query remained
available after these operations.

The first plan was captured before an ordinary public source update. Its recorded
floor was 6; the updated collection's observed floor was 19. An attempt to open
the old plan refused, with the observed target status unchanged. The public error
is not by itself a proof of the precise refusal cause. The separate native floor
rule prevents an older lineage from lowering the destination floor; this run does
not establish that restoring changed target content is generally possible.

All **72 first command outcomes** were recorded as confirmed. The fixture started
24 Sessions; each had confirmed close, strict Saved reconstruction, and a
same-ID idle reopen with no new effect intents. The process used a NoModel
provider and a zero-request budget. Its scoped source, runtime and artifact
postchecks passed, and the owned process group was empty after exit. These
observations are limited to the retained fixture and do not attest a global Input
channel or unrelated processes.

The retained local receipt at
`_build/verification/document-backup-controller-20261106-01/public-outer-01/receipts/summary.json`
has SHA-256 `7099f37e7fb3e88c584dfaf076d9f42cca4e8ed5dd71a6d5a4a1ad9399371964`;
the outer status has SHA-256
`1dc8042b0e7eccb1cd1ef2ebdb25e031cb3384be41657915ac4fc5cbd8ada194`.
The reviewed launcher was bound to source inventory
`d3c186e27a318846cbfbc3170cff949b0613db9c93279f06b111c04924e06336`,
private-runtime inventory
`f61d44c2e5c23dd0754a6360b825b89550e4de679130550c6fb46cfee57f183d`,
artifact inventory
`95b07e6e359e94114a91a232920b1aefd697d2afe772b63145b924950402cacc`, and
artifact manifest
`ad521895391db16333277ae623d530ca3e62309e565e4e7f25625cf5fc7bbe47`.
Those local inventories and the per-step and closure receipts are retained with
the private run; no private journal or source text is reproduced here.

Before that journey, ten focused Host origin/restore controls passed and a
separate no-App controller/classifier run passed 24 child cases. Those controls
cover origin and epoch tampering and bounded completed-domain classification;
they are synthetic tests, not additional public Sessions. After the journey, the
current whole native migration test file passed **8 of 8** cases in 23.5 seconds
against the private runtime, with source/runtime posts and scoped cleanup checks
passing. The three counts are separate; they are not additional public Sessions.
The native run's retained `status.txt` SHA-256 is
`f276b197387cb4acd6078575f5feec513f51610e2d2226a250d889eea2da9f99`;
its test log SHA-256 is
`96b5aad1be2ca9dfdb17fdbc3b4cf1081b2df6ecdb6c6d1c70681a0eb72359d9`.

The first-slice controller accepts at most 32 recognized completed records in
four pages, at most eight records per page, and at most 128 operation and lineage
entries. Those are ceilings, not a successful full-capacity test. Stored-result
provenance, the current artifact's validator and native epoch/floor fences remain
required. Cross-session adoption of an unfinished restore, changed-target recovery,
larger or segmented sets, live-job import and general Collection migration remain
open. The native regression is a separate synthetic-fixture check; it does not
expand the scope of the public same-floor Session result.
