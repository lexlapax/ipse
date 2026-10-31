# Independent review of signed choice commitment repair

Read-only review dated 2026-10-28, following the
[choice-compaction finding](compaction-independent-audit.md) and the
[repair evidence](index.md#signed-choice-commitment-repair). No production code
was edited and no runtime test was rerun during this review.

The repair addresses the reported loss of the signed choice commitment. The
normalizer first authenticates the old anchor and exact history metadata, then
derives a versioned commitment from the complete capsule. `compact_choice/2`
validates the closed capsule and its lineage before hashing its canonical JSON;
the new anchor page containing that digest is authenticated under the existing
project-domain MAC. The successor key/hash edge and admission clocks remain
separate. A compact value does not itself grant historical-use authority.

The retained native 87288 control establishes actual removal of the old page,
opens the new anchor through DomainAuth, and compares the signed commitment to
the original capsule. Its separate altered intent copy recomputes the unkeyed
facts digest but fails the capsule/commitment comparison. The same focused case
refuses same-lineage recapture and a stale-floor import; 87289 checks that pinned
history refuses expiry. This is evidence of the tested paths, not a comprehensive
tamper, backup, interruption, or annual-workload qualification.

The previous frozen decoder accepted a legacy page and refused a page carrying
the new choice tag; the new decoder accepted those new wire bytes. The format
descriptor still identifies version 3 and `IMB2`: the distinguishable version is
the new choice tag and versioned commitment. These controls establish refusal
when an old decoder encounters that page, **not** a namespace-wide startup or
installed old-runtime refusal.

`knowledge operation` inspects journal and control status but does not compare
the retained capsule to the authenticated commitment. Its status is therefore
not independent capsule authentication; the native test made that comparison
inside a trusted callback after opening the actual signed page. The developer
guide and implementation evidence state this limit. End-to-end historical-use
authority, final current-source integration and the full milestone audit remain
open.

The reviewed current source hashes are in
[current-sources.sha256](evidence/compaction-repair-independent-review/current-sources.sha256).
The seven current files named there match the corresponding frozen repair source
snapshot hashes. All 14 entries in the repair source manifest passed the
[snapshot check](evidence/compaction-repair-independent-review/source-manifest-check.log),
and every item in its compatibility/log artifact manifest passed the
[artifact check](evidence/compaction-repair-independent-review/artifact-manifest-check.log).
No further concrete defect was found in this limited review.
