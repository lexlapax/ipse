# Explicit Word payload to stored cited evidence

Dated **2026-10-28**, branch `codex/p30-p31`, based on pushed `704bd1d` and the
existing dirty DOCX v11 extraction work. This is scoped synthetic implementation
evidence. It does not declare P31F or Word qualification complete. The
[plan](../../plan.md) owns milestone status; the
[Corpus manual](../../operator/corpus.md) owns operator procedures.

The later [bounded workspace acquisition record](word-workspace-acquisition.md)
adds explicit opt-in native reads and repairs receipt transport through actual
Session State admission. Its canonical storage envelope supersedes the initial
direct receipt representation below; this earlier source/artifact evidence is
preserved with its original hashes and scope.

## Implemented path

The existing Corpus `source` command now accepts the explicit `put_document`
action. Its closed arguments are:

```text
source_id, generation, expected_revision, title, filename, bytes_base64,
uri, observed_at_ms, event_at_ms, expires_at_ms
```

No path, origin, extraction receipt or authority field is accepted. The worker
decodes the supplied bounded bytes, runs the actual DOCX extractor, and projects
the extracted segments into the existing Store `:put` CAS workflow. It opens no
workspace file, follows no relationship or URL, starts no model service and adds
no authority. Ordinary `put` still rejects a caller-supplied internal document
receipt before a host action.

The provided source's typed `document_extraction` receipt binds its original
binary SHA-256/byte count, format, extraction recipe, complete/partial status,
warnings and exact UTF-8 segment spans, text hashes and paragraph/table/annotation
locators. Store root and draft validation check metadata separately from full
hydrated source validation; metadata-only selection cannot manufacture evidence.
Existing immutable pages, source revisions, CAS conflicts, selected read tokens,
final revalidation, replacement and suppression continue to apply.

Document chunks stop at extraction-segment boundaries. A quotation cannot span
the synthetic separator inserted between paragraphs/table cells. Document
citations use version 2 and retain the existing citation fields plus a `document`
object containing original SHA-256, extraction recipe/status, typed locator and
segment-relative UTF-8 quote offsets. Citation validation recomputes that object
from the current retained source; changing a locator, original binary hash,
recipe or source revision cannot preserve the citation. Version-1 text sources
and citations keep their original contracts.

Partial extraction warnings survive storage and appear as `partial_document`
query gaps. Returned quotations remain available, but query coverage cannot
claim completeness. No original file is modified or implicitly re-extracted.

This explicit-payload increment retains the existing command/Store ceilings:
base64 input at most 8,192 bytes, extracted source text at most 8,192 UTF-8 bytes,
at most 32 segments/chunks, and at most 2,048 encoded JSON bytes of typed
document metadata. Complete inputs outside those bounds refuse; text, warnings
and locators are never trimmed to obtain admission. Approved workspace
acquisition and larger-document staging/storage are separate unfinished work.

## Verification actually performed

The new `test/extensions/knowledge/document_ingestion_test.exs` exercises the real
Corpus continuation, extraction, Store and Evidence modules against the
synthetic local State/CAS fixture. It verifies paragraph/table citations,
Unicode offsets, original hash/recipe binding, revision replacement and old
citation refusal, forgetting, partial warnings, input/receipt rejection,
selected CAS source reads and final revision-token validation. This is not an
actual external MCP server or host Session approval journey.

- An initial 46721 run failed both new cases with `root_bounds`: draft-target
  metadata validation incorrectly asked a document source with empty placeholder
  text to validate as a complete source. The metadata/content checks were
  separated. The two cases passed at 46722.
- The first two cases plus the existing Evidence file passed **32 tests** at
  seed 46723, max-cases 1, in 26.8 seconds. This predates the additional selected
  CAS case and final document-only ceiling/recipe hardening.
- The final [source selection](word-source-bridge/source-46725.log) passed all
  **3 tests**, seed 46725, max-cases 1, in 10.2 seconds, exit 0. Log SHA-256:
  `addf992a0a8860c80db697395cb1e163702dfc74f6667a6c8dc6c305665943fb`.
- A fresh `corpus/state-lexical` artifact built without diagnostics at
  `/tmp/ipse-word-bridge-artifact-46725`. Manifest SHA-256:
  `7ffffbee61a753d508a790bc50eaa186ee96ab66a01f243e5bd190d505456c66`.
- The [built-artifact selection](word-source-bridge/artifact-46726.log) passed
  all **3 tests**, seed 46726, max-cases 1, in 2.1 seconds, exit 0. It requires
  Corpus, Documents, Evidence and Store to load from that artifact's `ebin`, and
  checks the actual command argument schema. Log SHA-256:
  `4af45aca6dedfbfece953b83335316ff68a3644e85c975fb133ca0ef86f9033d`.
- Changed Elixir files were formatted; their focused `git diff --check` passed.
  No aggregate suite, installed release, human Word corpus, live inference or
  production native profile qualification ran for this increment.

The artifact run uses the same test file with
`IPSE_DOCUMENT_TEST_ARTIFACT=/tmp/ipse-word-bridge-artifact-46725`; without that
variable it compiles the current extension source in an isolated VM. Existing
host SDK beams came from `_build/operator-assertion-sol/_build/test/lib/ipse/ebin`.
No native helper or storage profile was changed or admitted by these checks.

## Source inventory and remaining work

Modified: `extensions/knowledge/src/documents.ex`, `corpus.ex`, `store.ex` and
`evidence.ex`. Added: the focused ingestion test and this record/log pair. The
pre-existing DOCX extractor, document/fidelity tests, Session, native storage,
shared manuals, plan and indexes were not edited by this work package.

Final implementation SHA-256 values:

| File | SHA-256 |
| --- | --- |
| documents.ex | `2a647ecd4f1ec26ff3e537b6c7aa337a1dcc20b1045409bc9dc0e37f947df4c5` |
| corpus.ex | `f52f3fe4551223ccf15d8f6c48b9727c4382d81ddb0a57ba4f4baf22a736c205` |
| store.ex | `91bc29c5698a8f32893ad6f22f9a45e413f6387c6b511d8fe1342243f359513c` |
| evidence.ex | `711a824da1fcb9f1e19cc6413e2e018256967781af61a4f775c8c26d7af9f0d2` |
| ingestion test | `84b6efd566a29710786ca619dd70905c4816367c42b6ed22209dc23a5ac30264` |

Still required: approved file acquisition/change tracking, larger-document
staging and capacity, host Session/installed approval journeys, real Word fidelity
and retrieval quality, cross-store lineage/current-use integration, migration
and final manual/audit acceptance. In particular, this does not implement
`/knowledge add PATH` or qualify automatic Word retrieval. The parent work package
must integrate the new action/limits into the complete operator and developer
chapters, reconcile their previous extraction-only wording and run its docs
check before declaring this sub-goal complete. Changes remain uncommitted for
that integrated review; no release was published.
