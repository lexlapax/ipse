# Maximum-label metadata geometry — 2026-10-29

This pure protocol measurement follows [native/public finalization](shared-finalization-native.md).
It identifies limits of the current version-one directory representation without
changing capacity targets, SDK/native ceilings, stored recipes or runtime code.
The [manifest](shared-metadata-geometry/manifest.json) binds exact client/fixture
source snapshots, compiled cohorts and every chronological log. No native
operation or model request ran.

The fixture constructs 5,000 distinct legal 256-byte fact identifiers, each
mostly backslashes, across 125 group memberships. It verifies a representative
identifier with the actual fact constructor. It renders the current 64-row
entity-page format, then feeds exact complete client `object_read` envelopes
using the host's existing longest-prefix rule: at most 6,144 original bytes and
8,192 JSON-encoded string bytes per read reply. All page hashes and bytes are
authenticated. This is metadata geometry, not a populated source/vector/fact
store or a claim that the host accepted these values for publication.

Final control47063 passed one focused test in5.6seconds:

| Measurement | Result |
| --- | --- |
| Current entity pages | 79 |
| Complete object-read replies, before snapshot/stat overhead | 704 |
| Existing Job behavior | Refuses exactly at512reads, before any proposed effect |
| Largest current page body | 37,503bytes |
| Its actual-format native packed wrapper | 70,064bytes; exceeds65,536 and would refuse sealing |
| Client write transport for that body | Exact bytes in7parts/6proposed frames; largest13,128bytes |
| Separate48,011-byte canonical escaped value | SDK transport completes in8parts; largest frame12,668bytes; this does not assert native packed-value acceptance |
| Proposed32-row page, every row with all125memberships | 31,181body bytes;47,547native packed-wrapper bytes |

The 704 figure is therefore an exact reply-envelope/read-budget counterexample,
while the same maximum-label version-one pages already encounter an earlier
native packed-wrapper refusal. Both limits must be addressed. The proposed
32-row geometry is a conservative sizing exercise, not an implemented format.

## Rejected transport proposal

An initial diagnostic incorrectly applied an8KiB *encoded*-string limit to
write packets. The SDK actually limits strings to8KiB *decoded* bytes and the
complete encoded host-call envelope to16KiB. The host read-slice rule has its
own encoded-string limit. Those are distinct contracts.

The proposed writer splitter would have unnecessarily refused existing legal
48KiB client payloads. It was rejected and its source is retained under `_build`.
The current Collection client is byte-identical to the reviewed prerequisite
and native-finalization cohorts. Its existing6,144-byte UTF8 split plus actual
complete-frame validation remains unchanged. Since UTF8 boundary adjustment
removes at most three bytes, a fresh48KiB client value needs at most nine parts,
below the native ten-part bound. Actual resumed stage part counts are not
exposed by `stage.inspect`; an exact remaining-slot admission there would need
a separately reviewed receipt/API change, rather than inference from offset.

47059 retained a fixture syntax failure.47060 retained a missing modeled
`value.stat` handler.47061 passed only against the rejected encoded-string-quota
diagnostic and is not runtime qualification.47062 passed against the unchanged
writer and established704reads plus exact legal write transport.47063 adds the
native packed-wrapper measurement and proposed32-row sizing. The native
frame/parser/result validators are the copied document-decision cohort pinned
by the preceding native-finalization manifest; no helper or Core overlay ran.

The next [versioned design](shared-directory-v2-design.md) must provide bounded
durable semantic verification and explicit page commitments, preserve exact
version-one readers/canonical roots and respect the native wrapper. Full
capacity, operation/key/peak accounting, GC/migration and Word/model quality
remain separate required work.
