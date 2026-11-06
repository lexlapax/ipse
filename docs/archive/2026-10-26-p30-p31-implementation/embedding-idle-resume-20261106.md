# Embedding verifier idle-resume correction, 2026-11-06

This record covers a verifier-only correction and a bounded synthetic source
proof. It does not change Session ownership, embedding permissions, providers,
budgets or transport limits. Follow the current
[verification procedure](../../developer/testing.md#reopen-the-same-mode-and-inspect-permitted-suffixes)
and [embedding operator procedure](../../operator/extensions.md#generate-vectors-explicitly)
for their separate contracts.

## Original failure and correction

The hosted Linux platform job `127857612887` for the `24b9` candidate completed
its MCP source and installed proofs, then failed at the embedding verifier's
idle-resume whole-journal byte-equality assertion, previously line 229 of
`dev/verification/embedding.exs`. The failed hosted run remains failed; this local
check does not relabel it or establish a hosted rerun.

Same-mode reopening retains the exact original journal prefix. A current journal
with the release-receipt layout then appends exactly one well-formed
`session_release_owner_started` record for that same Session. A legacy journal
without that layout stays byte-identical. Embedding now applies the same narrow
suffix validation as the independently precompiled MCP proof, followed by strict
Saved reconstruction. Changed prefixes, other events, malformed/foreign owner
records and extra lines still refuse. Its idle-state, budget-file and complete
transport equality checks remain intact. Confirmed close remains a separate
release operation, outside the reopening-only suffix assertion.

The helper stays local to the Embedding verifier because its independent proof
compiles only that declared source/module closure; it does not acquire a runtime
dependency on the MCP verifier. No Core behavior or deadline was changed.

## Actual local checks

The focused test in `test/dev/verification_test.exs` passed **one selected case**,
with 38 excluded, in 1.5 seconds. It exercises two valid suffixes and eleven
refusals, including duplicate JSON keys, a changed prefix, a foreign Session,
extra/duplicate events and missing/extra newlines. Those assertions are one test,
not thirteen independent integration journeys. The source/runtime checks passed
and its scoped process checks were empty. The enclosing sandbox command could
not create its initially selected outer scratch directory; it continued and the
existing `Runtime.with_runtime` constructed its own private runtime successfully.
No claim is made that the refused outer HOME/TMP directory existed. The later
source-proof launcher fails closed on setup and used an actual private scratch.

A fresh embedding artifact was built through the canonical inert builder, with
no application, Session or inference service. The subsequent actual-host source
proof passed **all twelve declared checks**, using exactly two synthetic loopback
provider requests and zero live model calls. It retained:

- exact approval inputs/profile/destination, denial with zero dispatch and budget
  exhaustion without another request;
- actual Ollama/OpenAI adapter request shapes and coordinate reconstruction for
  768 and 4096 dimensions, including eight vectors across 48 result pages;
- operation-aware usage, shared request/input accounting and zero embedding
  output-token liability;
- strict Saved reconstruction, same-mode idle reopening without worker/provider
  replay, unchanged budget/transport and no worker module loaded in the Host.

The source launcher was bounded at 180 seconds plus ten-second termination
allowance. Before starting it, a fresh private filesystem location passed a
32-MiB allocation, file fsync and allocated-block check. All source, artifact and
immutable 16-application runtime inventory postchecks passed. The owned process
group and scoped BEAM/helper checks were empty; an independent actual-host
observation confirmed that scoped neutrality. These observations make no global
Input-channel or unrelated-listener claim.

The actor used ordinary disposable Session approvals and synthetic data. It
borrowed no real provider credentials and accessed no retained notebook. This is
source protocol evidence, not live embedding quality, an installed proof, hosted
CI completion or whole-suite acceptance.

## Provenance

The tested verifier source SHA-256 is
`4417f8c553e6ae2c76a43762bae01683fd8e4e8412617f6937857f41c860d58c`;
the focused test-file digest is
`2ab1600889092b1671ea1ad6c27d0cd758b3fa1dd68eb39a4262a5e991a22841`.
The immutable runtime inventory digest is
`211b2bdb9ac11702d679c089516699d2e7b9a9cefe58f28b48a654afecfc34e2`,
and the three-file input artifact inventory digest is
`d4946a01eec66cfd424cdab13d8c3531270bb5b847c225bca9323a2bcf46582d`.
The activated launcher differed from its retained OFF source by removal of only
the two disabling lines. Its digest is
`181bd973dfdde92003d8aac5ec1e6d41b0d8e7d1ef276ddfa7632f07ed862454`.

The source report, terminal status and independent neutral-observation digests
are respectively
`3a1b1c239f193fa22880fe49a32dbff3e9aaac3814f579aa0831131709fab1b6`,
`2ca688f434b2b6890c7207bedde746f35c7421f42fa8dee2ed3781b02820d560`
and `dc26f8adaaa89508baba36feeed50731cf83204be9833494a6023fc4c2ce79c8`.
Private logs, synthetic journals and runtime copies remain outside this public
record.

The complete Testing chapter and the overlapping operator Extensions, Usage and
Recovery manuals were reviewed. Their existing source/installed distinction,
exact same-mode suffix guidance, explicit embedding approvals and no-replay
rules remain accurate; no operator procedure changed for this verifier repair.
