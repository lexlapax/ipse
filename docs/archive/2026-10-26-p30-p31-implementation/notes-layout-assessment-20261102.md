# Notes layout assessment — 2026-11-02

**Historical correction:** The calendar used here renewed corrected replacements
incorrectly. Its projected record count and ordinary-sized data-overflow claim
are withdrawn; see the [corrected assessment](native-calendar-correction-deadline-20261102.md).
The original calculations remain below as historical evidence.

This author-run, pure assessment uses the working calendar at `da2cedb` and
closed synthetic native seed checkpoints 1–188. The [plan](../../plan.md) owns
current acceptance and the [storage chapter](../../developer/knowledge-storage.md)
owns current behavior. The [analysis source](notes-layout-assessment-20261102.exs)
and [receipt](notes-layout-assessment-20261102.json) retain the calculation and
hashes. No native publication, model request or storage-budget change occurred.

The working calendar's 29,939 managed operations and 8,478 optimistic record
descriptors encode to 8,189,404 bytes. The current decoder refuses that
8,478-record state because its limit is 8,192; a separate 8,192-record state
roundtrips exactly. At 10,000 descriptors the encoded state reaches 8,656,659
bytes, 268,051 above the existing 8-MiB ceiling. These are synthetic metadata
shapes and do not establish a valid published state or actual workload fit.

At the calendar's final 7,991 public notes, projecting the observed 1,024-byte
native statement shapes gives 24,950,261 bytes of public values. Every live
metadata row contains two 32-byte hashes: their base64 text alone adds at least
681,899 bytes. The resulting 25,632,160-byte lower bound exceeds 24 MiB by
466,336 bytes before anchors, clocks, dictionaries, wrappers or format. This is
a same-shape projection, not an executed annual population or a ratified mix.

For 1,348 closed seed values, OTP zlib compressed 4,217,092 canonical bytes to
1,547,250 bytes and restored every original byte. This is a physical-compression
observation for these synthetic values. Current logical accounting sums the
uncompressed canonical record sizes, so compression alone cannot satisfy that
logical limit. It proves no maximum-payload, latency, native allocation or
whole-workload result. The first analysis output was retained, but its source
was subsequently extended; the archived source identifies the final run.

The existing [adapter evaluation](selection.md#sustainable-local-notes) remains
relevant. Any storage change needs the native publication/ownership boundary,
source and history preservation, bounded migration and recovery, and full
workload/resource tests. The proposed larger-profile decision remains with the
developer; until decided, the current limits and acceptance contract apply.
Original Session and management journals remain separately measured harness
state and must also appear in the broader resource assessment.
