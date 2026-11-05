# Scoped independent review

Historical review for the five-file private source/test delta
`4fff1b5e7be1d949aa9354d2067a7d0006a4ef660d78285f048826b4c68a7bbf`.
Both the integration owner and an independent source reviewer accepted that exact
delta before artifact and Session execution. The independent review read the
existing State CAS/get-many and Evidence fact/span contracts, not only the patch.

The accepted boundary is explicit ordinary-State selection: current supporting
source joins, State row and namespace CAS before write, existing write-before
expiry, strict tags/tombstone refusal, latest-only undo, flattened comparisons
that preserve original facts/citations, and exact final row/generation query
revalidation. Public entity IDs remain 256 bytes; expanded lowercase forms are
internal data. The empty-selection path keeps the original fact validation.

Artifact closure and actual State approvals/Saved/idle behavior were separate
gates. The later three-artifact build and single fresh Session journey passed
their independent source/runtime/State/Saved/process/Input checks. This review
does not turn pure expiry or unknown-result simulations into actual expiry or
interrupted identity-write qualification. It does not establish semantic entity
identity, managed-Graph authority, mixed old/new runtime coexistence, installed
use, full graph capacity or P31G completion.
