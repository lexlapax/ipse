# Complete held document values — independent review

Scoped read-only review, 2026-10-29, of the
[logical-value helper](document-held-value.md), against the accepted
[held reader](document-held-reader-independent-review.md) and existing
[packed layout](document-packed-layout-independent-review.md).
The [plan](../../plan.md) owns completion.

Disposition: accepted as transport decoding under a trusted held reader. No
blocking defect was found. It does not authenticate a source-use policy, create
inference permission or expose a worker endpoint.

Verified manifest SHA-256
`86342fa9c06e719ef8c062d65cbfce419c575515033c90306d613f990f35679a`,
the two source/test snapshots, five retained compiler/test/freezer files, ancestor
manifest and both complete runtime/private-asset inventories. Each has exactly
697 physical regular files and two recorded symlinks; only DocumentStage BEAM
differs. The candidate source matches its snapshot. The native helper and the
accepted Collection held-reader implementation are unchanged. The
[verifier](document-held-value-review/verify.exs) and
[result](document-held-value-review/verify.log) retain these checks.

Source comparison finds only the new `read_value/2` entry. It calls the supplied
trusted closure once for the selected key, preserves nil absence, validates the
existing closed packed wrapper, concatenates every original part and checks full
body length/hash. Existing bounds remain ten parts of at most 6,144 bytes and a
60-KiB logical body, within the document record's separate 64-KiB physical limit.
`ResultDocument.decode` then applies the existing complete-object, duplicate-key
and structural checks. No reserialization substitutes for the original logical
body hash. Escaped/corrupt reads, malformed wrappers and decode failures refuse.

The returned revision and operation ID come from the actual native record. Its
hash/byte count come from the validated logical body, deliberately differing from
the Collection manifest's physical packed-record hash/size. Source-admission
callers must retain that distinction when comparing heads, logical bundle hashes
and native revisions. A shaped fake callback can manufacture a shaped return;
this helper grants no authority independent of the actual same-owner held
Collection closure. Native-loss classification remains the enclosing held
reader's responsibility; decoder refusal must not be used to erase that outer
unknown outcome.

Retained 47164 requires empty compiler diagnostics. Retained 47165 passes two
native tests: actual inline document publication/read with exact operation ID,
revision, logical body hash/size and distinct physical hash; escaped closure
refusal; full roughly 40-KiB reconstruction; and actual stored bad-hash,
duplicate-JSON and extra-wrapper-field refusals. These are trusted synthetic
storage controls. The earlier eleven reader tests were not repeated, and neither
were these two controls during this review.

The graph inherits the separately recorded complete-host checkpoint and reader
overlay, predating public Management/current-bundle integration. It is not a fresh
all-current package build. No packing/schema, SDK envelope, quota, source policy,
dispatch, native helper or public gate changes follow from this acceptance.
No model call, runtime edit, effect or aggregate test was performed here.
