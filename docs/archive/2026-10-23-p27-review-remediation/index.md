# P27 independent-review remediation, 2026-10-23

Historical repair record. This follows the
[independent review of a7f4982](../2026-10-23-p27-independent-review/index.md),
published at `a912db1`. The enclosing repair commit identifies the implementation.
Current procedures belong to the [operator manual](../../operator/index.md) and
[developer training](../../developer/index.md).

The independent review confirms P27 acceptance within its optional-package scope.
These repairs change neither the selected retrieval implementation nor the
measured comparison. Frozen predictions, raw judgments, scores and the evidence
archive remain unchanged. No live-model run or consumed benchmark seal was replayed.

## Findings and dispositions

| Finding | Disposition |
| --- | --- |
| N1, dispatched MCP tool error labelled refused | Fixed. `MCP.call/4` separates a server-declared `tool_error` from a pre-dispatch error. Extensions retain `failed/mcp_tool_error`, redacted text up to 2048 UTF-8 bytes and an explicit truncation flag. Ordinary turns record an error and warn that effects may have happened. Neither path infers rollback or replays on idle resume. |
| N2, FIFO skill file blocks the owner | Fixed for the reported path. Discovery and selected loading require bounded regular files and share the existing bounded reader. Explicit prompt expansion runs in an owned task; cancellation and worker failure settle the pending caller. The existing documented concurrent-replacement limitation remains. |
| N3, undisclosed adjudication sensitivity | Disclosed in the comparison and acceptance audit. Independently recomputed both primary reviews from the unchanged bundle: hybrid qualifies under both, while lexical and rerank also qualify under B alone. Only final adjudicated scores make hybrid the sole qualifying strategy. |
| N4, deadline-edge inference admission left open | Fixed. Expiry while syncing admission closes it with a failed completion before refusing dispatch. The worker receives the matching model/embedding request-failure outcome, rather than a limit outcome that would contradict the admitted request on recovery. |
| N5, as-of completeness overstated | Operator and developer manuals now say that `as_of_ms` filters currently retained generations. Replaced generations are not reconstructed; complete abstention does not certify historical completeness. |
| N6, owner resolution described as independent | The record now labels it an owner resolution extending the pre-registered method. It changes one rerank answer/citation judgment and review completeness, but no strategy's qualification or hybrid score. Six prior verdict-label corrections changed no numeric score. Raw reviews and uncertainty remain intact. |
| N7, maintainability | Removed unused `Journal.validate_complete/1` and `Provider.Stream.feed_lines/2`. Remaining Session coupling, duplicated predicates/digests, test-only HTTP compatibility machinery and file/module naming are retained maintenance work. MCP fingerprint portability is now explicit; a format change needs versioned recovery compatibility, not an incidental hash replacement. |
| N8, PlugCrypto advisory | Official Hex metadata and the upstream changelog confirm the newly released 2.2.1 fix for CVE-2026-105963. Updated only that lock entry and the dependency inventory. Current Ipse callers do not use Plug cryptography, but new builds no longer bundle the affected version. |

The original N1 report incorrectly says no `isError` fixture/test exists. The
low-level client already tested it as a generic error; extension classification
and retained diagnostics were missing. The new Session regressions cover both
stdio and HTTP after a real fixture-side partial effect.

## Causal verification

Before the fixes, focused tests reproduced four failures: FIFO discovery did not
return, the client returned a generic error, and both extension transports saved
`mcp_refused` after dispatch. The FIFO test releases a blocked reader through a
separate shell writer so failure does not leave the test run hung.

The deadline regression pauses the real journal writer during admission, crosses
the producer deadline, then releases it. The original implementation returned an
active admission without completion. The repaired return has no active inference,
contains a failed completion, makes zero connections to the inert listener, and
restores its usage journal successfully. This is a controlled journal delay, not
a real-model timing claim.

Additional controls check escaped diagnostic bounds and UTF-8 boundaries, saved
error recovery without replay, off-owner skill reads, cancellation, worker failure,
and oversized/changed skill refusal without conversation mutation.

## Final checks and their boundaries

The [verification receipt](verification.json) records final source/test/lock
hashes, toolchains, actual log hashes and the exact macOS archive. All 19 changed
code, lock and test files match between the final local tree and Serenity's
isolated verification tree.

| Check | Result |
| --- | --- |
| macOS build, formatting and strict compile | Passed with OTP 29 / ERTS 17.0.5 and Elixir 1.20.3 |
| macOS full default suite | 1469 passed, one skipped, 36 excluded; 1151.8 seconds. Final runtime code; later test-only fixture changes have separate controls below. |
| Final Rust FIFO/skill/file-effect and ordinary MCP-error controls | 32 passed on macOS, 32 passed on Linux; unrelated MCP tests excluded by the selected location filter. Uses the existing Rust fixture, no new external utility dependency. |
| Linux native-inclusive baseline | 1519 passed, two setup failures, 19 excluded; 979.9 seconds. The source archive lacked Git metadata required by two evaluator declaration tests. This run remains failed. |
| Corrected Linux checkout and final runtime | Restored Git metadata from a912db1 without replacing source; strict compile, 139 focused tests including both failed evaluator cases, and demo passed. Final test-only FIFO fixture changes then passed the separate 32 controls. |
| Credential-free demo | Passed on macOS and in the corrected Linux tree |
| Documented MCP source CLI proof | Passed all twelve checks, both transports, unchanged inventories and zero live-model calls |
| macOS package and exact installed-package proof | Passed with a utility-only runtime PATH and private homes |
| Exact installed MCP proof | Passed all twelve checks with the independent artifact, unchanged inventories and zero live-model calls |
| Whole affected manuals and documentation checker | Operator/developer chapters reconciled with implementation; 393 Markdown files, 3599 local links, zero errors |

Linux logs and the preserved initial failure remain under
`serenity:/var/tmp/ipse-p27-review-repair-a9OCy4cT/`. Its original native run closed
before final code/test overlays and corrected checks began. No source files were
changed during that run. All verification jobs exited; the primary checkout and
existing services were untouched. These checks do not rerun real-model quality,
charged-RAM comparisons, installed Linux packaging or macOS sandbox proofs.
Hosted CI for the new repair commit is not used as a completed gate here.

The preserved evidence archive still hashes to
`bb1d87e7115af9dbbcbd7c323e83243461f08390531f8c70f0558ff1420bf7f0`.
