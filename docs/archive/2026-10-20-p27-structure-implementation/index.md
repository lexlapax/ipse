# P27 structural implementation records

Historical implementation record, 2026-10-20. The
[selected whole-codebase design](../2026-10-20-p27-structure-design/index.md)
follows a whole-tree survey, competing proposals and independent design review.
This directory records individual implementation increments. It does not establish
completion of the entire redesign or P27. Current guidance belongs to the
[architecture training](../../developer/architecture.md) and
[contributor learning path](../../developer/index.md); acceptance belongs to the
[plan](../../plan.md#p27-optional-research-graph-and-rag).

## Give shared JSON operations one owner

The increment starts from `bfe8ca5d62b4a270ec26a72e60622d8c08c9847d`.
General host inputs previously depended on `Extensions.Manifest.decode_json`,
unrelated callers used Manifest's raw SHA-256 helper, and configuration, accounting
and extension records depended on Compaction's canonical list digest. These
operations now belong to the existing `Ipse.JSON` module. Manifest retains artifact
validation and compatibility; Compaction retains checkpoint projections.

The migration removes the former helper APIs and their unused aliases in the same
change. It updates direct calls, captures, pipelines, generated child-VM expressions
and the packaged demonstration. Builtin `JSON` encoding remains a distinct module.
No dependency, runtime module, persisted format, inference request, permission or
retry was added. Host and builtin BEAM identities legitimately change; identity
validation is retained.

The decoder still defaults to 32 KiB, admits explicit limits through 1 MiB,
rejects duplicate decoded keys and retains its depth and parser errors. Raw SHA-256
still accepts iodata. Canonical digests still require a list, recursively sort
stringified object keys and preserve the existing scalar encoding, including
negative zero. This move is not a new canonicalization specification.

A before-change capture contains 602 synthetic decoder, raw-hash and canonical-hash
outcomes. The comparison reports no difference. Function-clause comparisons retain
the refusal class rather than the old defining module, and two invalid-value
exceptions normalize their fresh reference/function identities. Other returned
values and error fields are compared directly. Five permanent tests pin encoded
limits, escaped/nested duplicates, depth, iodata hashing and persisted digest
bytes. The broader 65-test focused check precedes two additional boundary
assertions; these counts overlap the full suites.

Both bounded adversarial reviews, [A](json-review-a.md) and
[B](json-review-b.md), report no finding. One independently reran all
602 outcomes and compared normalized syntax trees across 119 caller files.
Their scope includes standalone loading, generated code, Registry closures,
public SDK dependencies and the three integrated developer chapters. These
reviews do not establish full platform or package execution by themselves.

The same [462-file runtime/test/tooling inventory](json-source.json) passes on
both platforms. macOS has 1,374 passing tests, one skip and 36 exclusions. Linux
has 1,413 passing tests and 19 exclusions with native sandbox tests included.
Both pass build, formatting, strict compilation, demo, all fifteen knowledge
presets, four source/installed knowledge proof pairs and generic package checks.
The [verification receipt](json-verification.json) binds the source, package,
original/archived reviews and logs. Later editorial records differ from the
reviewed patch; the runtime/test/tooling inventory is identical before and after
both platform runs.

Previously compiled SDK-1 model-call and SDK-2 result-publication artifacts also
pass source and installed invocation on both platforms without rebuilding. Their
inventories remain byte-identical. SDK-1 retains all nine assertions; SDK-2 retains
the exact 4-MiB result, 1,024 fragments, historical reads, inert resume and confirmed
cleanup. The SDK-1 installed harness still uses its existing trusted-source loader;
SDK-2 precompiles its harness. Consolidating stronger installed isolation remains
open. These checks use fixtures, with no actual model inference. The macOS
native-specific suite and separate measured 350-row proofs were not repeated for
this increment.

The three affected developer chapters were reviewed as whole documents, and
operator extension/recovery chapters retain accurate identity and frozen-runner
guidance. The agent source map names the shared JSON owner. Documentation links
and archive rules pass. No operator command or configuration format changes.

## Remaining work

Shared artifact construction and verification, development-tooling ownership,
evaluation loading, costs, bundled behavior, configuration and Session state
remain separate implementation units. The complete operator/developer manual
consolidation and whole-codebase review remain open. A running exposed-data
diagnostic uses its own pinned `bfe8ca5` checkout; this implementation does not
change its source or replay its attempts. Fresh private evaluation inputs remain
withheld until the final code/configuration freeze. No quality improvement,
resource comparison, engine selection or P27 acceptance is claimed here.
