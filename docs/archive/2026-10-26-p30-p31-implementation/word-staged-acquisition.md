# Bounded staged Word acquisition

Dated **2026-10-28**. This implementation-section record supersedes the
4,096-original-byte/8,192-extracted-byte acquisition restriction described in
[the earlier workspace bridge](word-workspace-acquisition.md). It does not
qualify the complete P31C1b document profile, installed Word journey, real Word
fidelity, continuous file-change tracking or production kernel support. Current
delivery status remains in [the plan](../../plan.md).

## Transport and source contract

The existing native `read` tool keeps its complete base64 version-1 result.
Explicit `encoding: "base64"` plus `byte_offset` selects a version-2 page;
`file_max_bytes` defaults to 32,768 and cannot exceed it. `max_bytes` remains
at most 4,096 bytes per reply. Nonzero offsets require a complete-file
`expected_sha256`. Binary-only options without binary encoding, line options
with binary encoding and `file_max_bytes` without a byte offset refuse.

Every page reads the complete bounded file twice, requires byte-identical reads,
and rechecks descriptor/path identity, protection, size/times, workspace admission
and the owned resource scope before returning. It hashes the complete original
bytes, then returns only the selected page. The closed version-2 envelope has
`version`, `encoding`, `path`, total `byte_count`, complete-file `sha256`,
`offset`, base64 `data`, `page_sha256` and exact next byte offset or null. It has
no misleading `complete: true` field. The host validates the typed envelope and
page digest without changing ToolAction's existing 8-KiB explicit-binary result
ceiling or its ordinary 4-KiB text ceiling. Generic SDK object, string, depth,
worker and journal limits are unchanged.

Corpus `read_document` assembles at most eight pages in its bounded private
continuation. The first page selects an exact original hash; every subsequent
page is hash-pinned. The extension checks offsets, complete byte count, each
page digest and the reconstructed complete-file digest. It extracts the actual
DOCX, validates the complete typed locator manifest and issues a final pinned
page-zero read before proposing any source write. That last read again hashes
the complete original file. Hashes for initial generation 1/revision 0 may be
omitted by the caller; refreshes and stage continuations require a concrete hash.
An ordinary native page-zero `read` returns it, without a shell hashing step.

Sources with at most 8,192 extracted bytes retain the existing immediate put.
Larger text opens the existing immutable-page/CAS source draft. The result's
`continuation` is a ready-to-invoke object:

```json
{
  "id": "source",
  "arguments": {
    "store": "notes",
    "action": "continue_document",
    "args": {
      "source_id": "workspace:source",
      "draft_id": "<returned draft ID>",
      "expected_revision": 1,
      "offset": 0,
      "path": "source.docx",
      "expected_sha256": "<complete original hash>"
    }
  }
}
```

Each explicit continuation reacquires, reassembles and re-extracts the pinned
original, then performs the final acquisition recheck. It appends one UTF-8-safe
piece of at most 4,096 bytes, or publishes when the exact complete text has been
staged. The Store independently binds complete text/hash/byte count, original
hash, recipe, typed locators, warnings and workspace path to the immutable draft
target. The original acquisition operation in that target remains its snapshot
provenance; later checks have separately journaled host operation receipts.
Ordinary public `append`/`publish` cannot substitute text into a document draft.
CAS generation, draft ID, offset and expected revision still fence each stage.
An existing selected source remains readable until the final root switch.

Native reads retain ordinary workspace read authority; source page/root writes
retain existing approval and journaling. The two document presets remain opt-in;
old presets gain no tools. Native acquisition calls count against the existing
16-effect budget, alongside Store writes, rather than becoming uncharged reads.
No host Actions, consent, workspace, shell or provider authority was widened.
An interrupted effect remains unknown and resume starts no acquisition or stage.

## Focused verification

Checks used an isolated copy of the available-host diagnostic SDK graph at
`/tmp/word-staged-host-46765`, with current Tools/ToolAction compiled there.
The primary graph was neither compiled nor modified. Fresh document artifacts
were built by the actual Session fixture. No live model, credentials, download,
service, production native admission or aggregate suite was exercised.

- [46769 section](word-staged-acquisition/section-46769.log): 21/22 passed in
  22.9 seconds. The passing cases include native Tools 10, ToolAction 1, actual
  Session 7 and the existing supplied-document source 3. Session tests exercise
  an actual DOCX larger than one host reply and Unicode text over 8 KiB, staged
  replacement retaining old selection, exact typed cited query, source changes
  between pages and between stages, stale continuation refusal, and owner loss
  after an actual append write but before its durable result. Resume leaves
  retained files and journal bytes unchanged. No model request is needed.
- The new staged CAS fixture first compared all request bookkeeping after a
  refusal, although reads legitimately add request entries. After comparing
  persisted records/generation, [46770](word-staged-acquisition/ingestion-46770.log)
  passed its existing three controls and exposed a second test mistake: requesting
  a full 2-KiB chunk violated the unchanged 1,024-byte citation span limit.
- [46771 staged CAS](word-staged-acquisition/cas-46771.log): the repaired selected
  control passed in 3.6 seconds, three excluded. It checks complete staged
  source publication, exact final text/hash/typed citation and refusal of an
  ordinary append substitution without changing persisted records/generation.
- [46772 existing plain staging](word-staged-acquisition/plain-stage-46772.log):
  the unchanged 64-KiB UTF-8 open/append/publish control passed in 2.8 seconds,
  40 excluded, covering the shared Store open-path change.
- [46773 compilation](word-staged-acquisition/compile-46773.log) reported no
  compile or runtime warnings. After final tool-description edits,
  [46773 native controls](word-staged-acquisition/native-46773.log) passed all 11
  Tools/ToolAction cases in 0.02 seconds.
- Focused formatting and whitespace checks passed. Source/log byte counts and
  SHA-256 values are retained in the [manifest](word-staged-acquisition/manifest.json).

## Remaining boundaries

This section retains the existing 65,536 extracted-byte source envelope,
32 chunks, at most 32 typed segments and 2,048-byte raw locator metadata limit.
The immutable root/value and complete old-plus-staged capacity checks can refuse
before those nominal maxima; no metadata is truncated to fit. Acquisition over
32,768 original bytes still refuses. Long locator manifests need separately
paged storage, and the 1,000-source/20-MiB-evidence/10,000-chunk profile remains
open. The larger-file path is a bounded intermediate implementation section.

Partial extraction warnings remain visible in storage and query coverage.
Imported bytes are an acquired snapshot, not proof the current workspace file
still exists or remains unchanged. Rename/deletion/change tracking, guided
installed intake/recall, full migration/capacity qualification and frozen real
Word fidelity/retrieval measurements remain required. No dependency was added.
