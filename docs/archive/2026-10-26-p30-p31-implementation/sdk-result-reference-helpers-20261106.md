# SDK helpers for exact result references

Engineering record dated 2026-11-06. [Invocation authoring](../../developer/extension-invocations.md#return-inline-data-or-prepare-complete-output)
owns the current API procedure; the [plan](../../plan.md) owns acceptance.

A selected-result consumer needs a durable output descriptor even when its
complete object is small. Automatic publication correctly keeps a small reply
inline, so it cannot supply that reference reliably. The SDK now exposes
`ResultPublication.prepare_paged/1`, using the existing private Output and terminal
transport. It changes neither the object nor any capability, stage or size bound.
The existing `prepare/1` keeps its automatic inline/paged choice.

The SDK also exposes `canonical_object_digest/1`. It validates one complete
object under the existing ResultDocument aggregate limits and hashes that object
with the host's existing canonical JSON encoder. This differs from
`canonical_digest/1`, whose ordered input list is part of the encoded digest.
Native document input commitments require the object form. Neither helper grants
data access, authenticity or effect authority.

The complete focused publication file passed thirteen tests in 5.2 seconds,
including an actual SDK-2 worker's small paged result, exact Unicode/numeric
content, terminal-only output, and SDK-1/service refusal. The file also retains
its ordinary large-output, malformed-frame and inline compatibility controls.
Object digests match the existing native canonical encoder for aggregate values;
private runtime terms and oversized strings refuse. Selected test inputs and the
private compiled runtime inventory remained unchanged. An earlier combined run
passed eighteen publication/restore-binding tests; it predates the additional
actual-small-worker case and is retained separately, not added to the thirteen.

The host compiled strictly in a separate build, with 201 files, zero warnings and
unchanged source checks. The first private build attempt used an incorrect Mix
build-path level and could not find copied dependencies; it is preserved. The
corrected private builds passed without changing the live full-regression copy.
No model or original notebook was used.

The developer invocation and authoring chapters and operator extension manual
were reviewed as whole documents. Worked examples and aggregate limits were
integrated into the invocation chapter; ordinary operator use and eligibility
remain unchanged. This completes these small SDK primitives, not the separate
document restore journey, full-source, installed or P30/P31 acceptance.
