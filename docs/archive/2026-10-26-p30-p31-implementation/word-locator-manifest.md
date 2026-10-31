# Paged typed Word locator manifests

Dated **2026-10-28**. This implementation-section record extends the
[staged workspace acquisition](word-staged-acquisition.md) with paged extraction
metadata. It supersedes that section's 2,048-byte raw locator-manifest ceiling;
the [plan](../../plan.md) remains authoritative for delivery status. Full C1b,
installed Word intake, continuous file-change tracking, real Word fidelity and
production kernel admission are not qualified here.

## Versioned data and bounded storage

The extension accepts at most **16,384 canonical metadata bytes**, 32 typed
segments and 32 warnings. The source still has at most 65,536 extracted bytes
and 32 chunks. Acquisition remains at most 32,768 original bytes through exact
4,096-byte native pages. Store limits remain 256 namespace records and 1 MiB;
complete old-plus-staged data still consumes that capacity. No SDK object,
string, depth, host-result or journal ceiling was widened; no dependency was
added. The unchanged extraction recipe remains `ipse-documents-v11` because
storage paging does not alter parser text or locator selection.

Metadata bodies of at most 2,048 bytes retain the existing packed document
receipt version 3. Larger bodies use compact **receipt version 4**, containing
original hash/size, format, extraction recipe, coverage status, acquisition
summary when applicable, canonical manifest hash/byte count, exact segment and
warning counts, and one immutable manifest-head reference. That reference is
null only while building a draft or an in-memory complete source; a selected
stored root requires a real reference. Existing root format 1 remains readable.

Larger manifests reuse the immutable text/progress machinery:

- `document_content` holds one nonempty, UTF-8-safe canonical-JSON slice of at
  most 1,024 bytes.
- `document` links the previous progress record, exact metadata byte offsets
  and that content page's key/digest. At most 16 slices/32 metadata records fit
  the declared envelope. Inputs requiring more pages refuse intact.
- Every page is content-addressed and bound to partition, source key, generation,
  draft ID, typed page kind and ordinal. Hydration rejects missing/tombstoned or
  revised immutable records, bad hashes, wrong kinds, cycles, changed draft IDs,
  gaps, repeated/reordered byte offsets and content ordinals.

Workspace `read_document` opens a draft when either text exceeds 8 KiB or the
typed manifest needs pages. `continue_document` stages one metadata slice before
text; each command still reacquires and re-extracts the hash-pinned original,
performs the final acquisition check, and uses existing source-write approvals.
Metadata-bearing ready continuations add exact `metadata_offset` alongside the
existing text `offset`, draft ID and expected revision. Both offsets must match
the current draft before writes. Small legacy continuations remain compatible.
An existing selected source remains selected during metadata-only staging.

Final publication first reassembles the complete metadata chain privately,
checks canonical JSON bytes, complete byte count and digest, validates the
compact summary against all warnings and ordered segments, and validates every
segment's exact UTF-8 text/hash/locator against complete staged source text. It
then publishes the manifest head with content/chunk references in the existing
atomic root CAS. There is no partial-manifest promotion.

Stored-source hydration repeats that complete validation. A privately hydrated
**Source version 2** carries the complete `document` body plus compact origin;
Source version 1 remains unchanged. Namespace State/MCP replies carry bounded
individual immutable records, never the 16-KiB metadata JSON as one SDK string or
a full hydrated source in one State wrapper. Selected MCP retrieval follows the
manifest closure before producing evidence. Citations remain version 2 with
only the selected segment-local locator/span and compact origin descriptor;
query coverage retains the full verified partial-extraction warnings. A compact
descriptor alone cannot become a readable document source.

The original acquisition operation remains snapshot provenance. Later stage
checks are separately journaled and must reproduce the original body/path/hash;
they do not extend the snapshot's authority. Interrupted text or metadata writes
remain unknown, and Session resume performs no automatic stage or acquisition.
The existing single-envelope import path explicitly refuses Source version 2
instead of dropping its paged typed manifest. Complete paged migration remains
open.

## Focused controls and environment boundary

Checks used the isolated copied diagnostic SDK graph
`/tmp/word-staged-host-46765`; current Tools/ToolAction were compiled there with
no warnings. Fresh artifacts were built by actual Session setup. The primary
graph was not compiled or modified. No model, service, credentials, downloads,
production profile admission or aggregate suite was exercised.

- First actual Session locator control **46774** reached the expected missing
  page refusal, then exposed a test-fixture mistake: deleting/restoring an
  immutable State page through CAS increments its revision, so it must remain
  unreadable. Fault cases now restore the original isolated fixture bytes
  between controls; this is test setup, not product rollback behavior.
- Repaired locator control **46775** passed one selected case in 7.6 seconds,
  seven excluded. It imports an actual DOCX with 24 paragraph/table locations
  and metadata over 2 KiB, proves old-source selection during a metadata-only
  stage, then obtains an exact table-cell citation and verified partial warning.
  Missing, forged and rehashed/reordered manifest pages, plus a compact header
  attempting to hide warnings, all refuse through actual Session/State transport.
- Selected MCP locator control **46776** passed one case in 3.8 seconds, four
  excluded. It stages the complete manifest, hydrates the selected page closure,
  and verifies exact paragraph-24 citation and refusal of missing/reordered
  hydrated metadata.
- [46777 scoped run](word-locator-manifest/section-46777.log) encountered real
  `/tmp` write quota exhaustion: nine native fixture writes failed with EDQUOT
  and eight Session cases were invalidated during artifact setup. All five
  supplied-source/CAS cases passed, including the new selected manifest control
  and explicit refusal of incomplete Source-v2 import. The outer exec sandbox
  also failed to create its synthetic mount target; these are recorded
  environment failures rather than passing checks or runtime regressions.
- [46778 affected cases](word-locator-manifest/native-session-46778.log) used an
  owned private repository temporary directory, with the same diagnostic helper
  and unchanged product policy. All **19 native/actual Session cases passed**
  in 17.5 seconds. The final locator control also checks exact metadata/text
  offset refusal, rehashed content-order corruption, and SDK validation of every
  successful actual host outcome. Owner loss after an actual metadata write or
  text write, before its durable result, leaves retained files and journal bytes
  unchanged on resume.
- [46779 existing plain staging](word-locator-manifest/plain-stage-46779.log)
  passed the selected 64-KiB UTF-8 open/append/publish control in 3.1 seconds,
  40 excluded, covering the shared stream loader's stricter draft/ordinal checks.

Independent review of the prior staged section also identified a narrow binary
result-validator grammar mismatch: a complete result could structurally validate
against arguments that native execution refuses (`file_max_bytes` without an
offset, or mixed line/binary arguments). The validator now applies the same
encoding/range/line-option checks as execution. Four negative argument controls
are included in the passing native selection. This was not an observed native
read corruption and did not require a result-limit increase.

Source/log byte counts and SHA-256 values are retained in the
[manifest](word-locator-manifest/manifest.json). This remains an intermediate
bounded document section: more than 32 segments/chunks, larger originals/text,
the accepted 1,000-source/20-MiB-evidence profile, migration, installed operation,
continuous source changes and independent Word fidelity/quality gates remain.
