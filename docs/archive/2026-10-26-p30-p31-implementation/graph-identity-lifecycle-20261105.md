# Ordinary State Graph alias, merge and undo

Dated **2026-11-05**, US/Pacific. Historical source and verification record,
not a current procedure or P31G completion claim. The
[Graph manual](../../operator/graph.md#select-and-undo-an-entity-alias-or-merge)
and [knowledge training](../../developer/knowledge-extensions.md#follow-an-explicit-entity-choice-through-state-cas)
own current guidance; the [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance)
owns remaining acceptance. This follows the earlier
[main-tool capture checkpoint](graph-main-capture-20261104.md).

## Bounded selection over immutable facts

The command-only `identity` export adds explicit ordinary-State alias, merge,
inspection and latest-step undo. One closed format-1 `graph_identity` row stores
at most eight active steps and 6,000 encoded bytes. Each choice carries its
original labels, base State revision and complete attributed source citation.
An alias cannot shadow an entity already present in current facts; a merge
selects a representative for two distinct current entities. Neither asserts
semantic identity or grants managed-note authority.

The existing State snapshot, row/namespace CAS and ordinary approval APIs are
sufficient; no core, dependency, native protocol or model API changed. Source
and fact expiry narrow the existing `write_before_ms` decision fence. Queries
revalidate SourceTokens and then the exact selection row and generation before
return, reserving its extra read within the unchanged 512-read/16-effect bound.
Traversal comparison changes, while original facts, IDs, labels and citations
remain intact. Undo removes only the named latest step at its exact revision.
Denied or unknown mutations stop without replay, rollback or settlement.

The new row kind deliberately refuses older shared Store readers. Graph,
Corpus and Research packages sharing that partition need the matching reader
upgrade and old pinned Sessions must close. The row remains after all active
steps are undone. Per-source export/import does not carry this partition
selection; migration must not silently promote historical choices.

## Source, build and actual checks

The exact [five-file source/test delta](graph-identity-lifecycle-20261105/source-and-tests.patch)
has SHA-256 `4fff1b5e7be1d949aa9354d2067a7d0006a4ef660d78285f048826b4c68a7bbf`.
The [scoped independent review](graph-identity-lifecycle-20261105/independent-review.md)
accepted its current-source, CAS, immutable-fact, strict-tag, latest-undo and
final-row fences. Seven complete State-path helper modules compiled with zero
diagnostics. **26 protocol tests passed**, including ten earlier capture
controls; these are not an additional 26 new cases.

Controls cover alias→merge→undo, current source/citation changes and expiry,
competing State revisions, denied/unknown callbacks and already-applied unknown
inspection, tombstones, malformed/float tags, bounded requests, preserved
collection metadata and unsupported MCP refusal. An exact preimage Store reader
refuses the real new row while accepting the old empty partition. That is a
private compatibility control, not a mixed old/new runtime qualification.

One inert build reused the complete read-only 241-module/16-app private SDK.
It built explicit Graph/state-explicit, Corpus/state-lexical and
Research/state-fetched artifacts; each has 26 modules and 27 declared payloads.
All **25 common helper BEAMs are byte-identical**. Schema, complete payload,
license, import and original SDK path/hash/raw-link checks passed. The
[artifact identities](graph-identity-lifecycle-20261105/artifact-identities.json)
identify the reviewed dirty `800235a5` host plus its five earlier root-chain/queue
paths; this is not a new clean committed host. Artifacts were not imported or
activated by that build.

**One fresh disposable Session journey passed** through the real Graph artifact
and ordinary State approval API. It stored a synthetic source and two supplied
facts, denied an alias write without changing State bytes, approved an alias
and merge, refused a stale revision, then undid the latest merge and alias.
Queries preserved the original claims and exact citation bases. Complete result
values were compared; the fixture uses the public materializer for saved-result
deliveries rather than assuming every result is inline.

Confirmed close, strict Saved reconstruction and same-ID idle reopen passed.
An independent no-App post verifier restored both the full journal and its
pre-idle prefix, matched all invocation/action intent-result IDs, checked the
unchanged pre-idle intent digest and final State hashes, and found zero inference
events. Source/runtime/artifact checks and separate actual-host process/Input
cleanup passed; all three actor/post/operator statuses are zero. The
[safe result](graph-identity-lifecycle-20261105/result.json) and
[receipt pins](graph-identity-lifecycle-20261105/receipt-pins.json) bind that scope.
The journey used direct programmatic ordinary approvals, with no model, MCP,
Input/TTY read, native consent or original retained-cohort access. It is not
independent human use.

## Preserved failures and remaining gates

A boundary test first produced **25/26 passed**: a legal 256-byte Unicode entity
expanded to 384 bytes on downcasing, so its accepted alias then refused a query.
The correction bounds only the internal normalized representation; public and
stored original labels remain 256 bytes. The genuine source/capture/alias/query
case and all 26 tests pass after that change. An empty-selection counter control
also preserves the original single fact-validation pass for ordinary queries.

The first sandbox build invocation failed during Input-holder inspection because
`fuser` could not open its socket, before claim, staging or compiler execution.
The unchanged host build guards then passed. A demonstrably unused guard module
attribute was removed before its final zero-diagnostic definition check.
All [first dispositions](graph-identity-lifecycle-20261105/preserved-outcomes.json)
remain separate; the one actual Graph actor had no retry and its fresh root is
retained. No old unknown operation was resumed or reconciled.

Actual CAS-at-expiry and interrupted unknown **identity-write** controls remain
open; earlier capture controls do not substitute for them. Mixed-package live
coexistence, installed use, original-source/managed-note graph admission,
automatic identity inference, semantic quality and full Graph capacity also
remain open. No populated-day, annual or complete P31G result is claimed.

Both complete current manual chapters were reviewed and integrated, with a
canonical private check of 1,208 Markdown files and 9,969 local links, zero errors.
The [current-main integration](graph-identity-lifecycle-20261105/main-focused.json)
passes all three outer capture/population tests in 24.9 seconds; the nested 26
protocol cases are not added to that total. A separate canonical-reader control
accepts the new row with current helpers and confirms the exact older reader
refuses it while accepting an empty partition. Canonical formatting changes
only one extra blank line at each of the five files' ends. These checks preserve
the distinct private actor provenance above. The public
[manifest](graph-identity-lifecycle-20261105/manifest.sha256)
contains only source, scoped review and sanitized counts/hashes. Private journal,
State, transcript, configuration, capability and absolute fixture paths are
excluded.
