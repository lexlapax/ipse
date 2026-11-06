# Document verifier v18 — 2026-11-06

Historical synthetic verification. The [plan](../../plan.md) owns current status;
the [Corpus manual](../../operator/corpus.md) and [developer testing guide](../../developer/testing.md)
describe current use and checks.

Linux CI run `42265010030` passed the repaired saved-result proofs but failed
the source document proof: its independent verifier still required extraction
version 16 while the artifact returned version 18. The failed run remains failed.
The verifier now expects v18 and retains both ordinary and separator-prefixed
footnote/endnote cases, with linked and unlinked annotations and original paragraph
ordinals checked. Comments retain their ordinary case. Other extraction, warning,
citation, PDF and independent-artifact checks remain in place.

Plain-VM controls passed on the current v18 parser, refused the older v17 parser
at the version check, and refused that older parser even when a test wrapper
relabeled its output as v18. A separate reviewer also checked the endnote-only
relabelled case. These are parser controls, not the complete proof.

Fresh synthetic source and installed proofs each passed all nine checks with a
PDF-enabled SDK and archive built from `fff77fbe`, using the separately pinned
verifier overlay. The archive SHA-256 was
`a0da585ebe5b9070e04ccaf8dae8f05e4b38e519f4c04762989d520a7eae140b`;
the verifier source was
`5d978c04a7b22e67fe59adec235c3eb706430d0b4603f49e66dc576d01b5e613`.
Source, artifact, archive, overlay, runtime and symlink inventories remained
unchanged; process groups, shared input and test listener were clear afterward.
No model service or existing notebook was used.

These proofs apply to the recorded `fff77fbe` runtime, before the later planning
change. They do not establish current final-package qualification, broad Word
fidelity, P31 quality or a complete full-source baseline.
