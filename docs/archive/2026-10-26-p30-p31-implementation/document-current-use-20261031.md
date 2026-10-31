# Acquired workspace documents checked before query return

2026-10-31, increment based on `e86b1b8`. This historical engineering record
does not complete P31F or the full goal. The [plan](../../plan.md) owns acceptance;
current procedures belong to the [Corpus manual](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
and [Knowledge training chapter](../../developer/knowledge-extensions.md#follow-acquired-document-bytes-into-cited-storage).

## Implemented boundary

Corpus collects workspace acquisition references from returned evidence and the
complete citation bases of returned claims. It retains the original acquisition
receipt and checks the original relative path, whole-file SHA-256 and byte count
through the existing native binary read. The host hashes the bounded original;
only one byte and its metadata are returned. Packed v3 and compact v4 receipts
retain their original provenance. Supplied-byte documents trigger no path or URI fetch.

A failed check withholds all evidence/claims. State/MCP source-token revalidation
or a Collection native-generation check follows the file reads, with source
eligibility checked again. Changed storage conflicts even if the file still
matches. Coverage separates original acquisition, fresh read operation IDs,
store revalidation and actual invocation action counts. Added reads share the
existing 16-effect/512-read allowance. Corpus reuses the Collection classifier
only for Collection operations; the host independently enforces its own limits.

The same guard precedes legacy embedding input, rerank input and vector commit.
A model-only preset lacks workspace-tool authority and refuses acquired-file use;
no capabilities are added. Shared Collection producer embedding batches retain
their separate stored-source guards and are outside this file-check claim.
No core, public SDK, native protocol, dependency or approval boundary changed.

These are bounded on-use checks. There is no filesystem watcher, automatic
rename discovery, refresh, reindex, deletion, atomic multi-file snapshot or
file lock held through later consumption. Old stored generations, journals
and saved results remain historical. Complete later-use authority, producer
freshness, installed qualification and real Word/retrieval quality remain open.

## Exercised behavior and preserved failures

Fresh public artifacts run in actual native Sessions with synthetic Word bytes
and no model service. Both State and Collection paths query an unchanged file,
then replace, rename, delete and redirect it. Replacement/rename/deletion refuse
without evidence/claims. The host refuses a symlink at tool-context admission
before a read intent; the enclosing invocation remains conservatively unknown.
Tests inspect that absence, restore the original path explicitly, and issue a
new query. Closing/resuming after deletion does not replay acquisition or queries.
An interposed State revision change during the native file check conflicts;
a subsequent explicit query can succeed against the new coherent revision.

Initial controls incorrectly expected a one-call Collection publication rather
than its explicit draft continuation. A later expectation incorrectly required
a worker-level JSON result for the earlier host symlink refusal. The corrected
tests preserve both gates and the unknown/no-replay boundary. Two broader Word
staging tests also assumed changed original files remained queryable. They now
verify refusal while changed, restore the original to prove its stored generation
survives, and restore the replacement before continuing its draft.

The first accounting implementation called a Collection classifier from
State-only isolated VMs. Three regressions exposed that accidental dependency.
The classifier now runs only on Collection requests; isolated domain, graph
population and minimal-public-SDK controls passed three tests in24.9seconds.
Four final freshness/race controls passed in22.5seconds. The minimal artifact
also checks acquired-file capability refusal before vector commit and rerank.
The selected semantic cohort passed four controls in50.6seconds; that run
preceded the final classifier short-circuit repair. These selected results do
not replace the whole-suite baseline.

Local logs use `/tmp/ipse-document-current-use-*-20261031.log`; original failed
logs remain. The [source/test inventory](document-current-use-20261031.json)
was frozen before the final regression run and includes the actual native helper.
No real model, daemon or metadata-service request was made and no live allowance
was consumed. Operator Corpus, developer Knowledge extensions and the package
README were reviewed as whole documents, with current-file recovery integrated
into acquisition and citation guidance.

## Final source checks

The frozen final cohort passed **32 tests with one optional fixture skipped**
in134.5seconds (`frozen-regressions` log). It includes document acquisition,
ingestion, indexing abort, isolated domain/graph population, package and minimal
artifact controls. The four source/test hashes and native helper were unchanged
after the run. Standard build passed180modules and three inert bundles;
warnings-as-errors compilation, format, CI policy and credential-free demo passed.
Documentation validation checked980Markdown files and8156local links with0errors.
These checks do not constitute a new complete default-suite result. That separate
run is still evaluating the clean earlier committed `e86b1b8` source.
