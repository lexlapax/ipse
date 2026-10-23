# P27 maintenance and fingerprint compatibility, 2026-10-23

Historical implementation and verification record following the
[independent review](../2026-10-23-p27-independent-review/index.md) and
[first repairs at 4171fb4](../2026-10-23-p27-review-remediation/index.md).
The initial maintenance implementation is
`dd0a130a398eafef078d048c09a24095c4081c80`. The compatibility follow-up below
has its own source identities and checks in the receipt. Current procedures
belong to the [operator MCP manual](../../operator/mcp.md),
[architecture training](../../developer/architecture.md) and
[developer source map](../../developer/index.md).

## N7 disposition

This closes the reported maintenance work through focused changes inside existing
owners. It adds no source file, module, process or dependency.

| Responsibility | Change |
| --- | --- |
| Conversation and feature policy | Context owns system/reference rendering and context manifests. Questions owns availability, Delegation owns child admission, and Turn privately assembles the request tool catalog. Unused Context arguments and overload wrappers are removed. |
| Authoritative effects | Session retains journal writes, accounting, approvals, resource registration and conversation state. Its callbacks from synchronous Turn/Invocation remain intentional authority boundaries, not separate actors. |
| Repeated representations | Host SHA256 production/admission and JSON-safe unsigned admission use existing `Ipse.JSON` ownership. Independently compiled Knowledge shares equivalent predicates through Evidence. Host-dependent evaluator/verification helpers reuse host primitives without changing their digest inputs. |
| HTTP lifetime | Removed the unused httpc APIs/backend and `:inets` startup. Finch retains private clients, borrower/lease monitoring, resource tickets, name retention until teardown, socket closure and cancellation. Concurrent and active-cancellation controls now exercise real Finch requests. |
| Persistent MCP identity | New sessions use version-two, domain-tagged canonical JSON endpoint and descriptor hashes. Loader and saved-binding validation share Config's endpoint implementation. Legacy sessions keep their exact version-one encoding and future bindings. |
| File and module ownership | Cohesive multi-module files remain together, including registry/configuration and model/embedding inference. Session.Invocation and Extension.Invocation have distinct active-owner and generic-contract responsibilities. Splitting each module into a wrapper file would conflict with the approved consolidation. The developer map now explains these choices. |

Standalone tooling, pure host-free modules and trust-bootstrap hashes retain their
small independent implementations. Raw binary/base64 digests, nullable contracts
and domain-specific bounds are distinct contracts. These are not equivalent
helpers left accidentally behind. Legacy MCP term encoding is retained only for
the saved version-one contract, including its existing cross-major-OTP limitation.

The owner explicitly chose: "Version new sessions; preserve old journal validation."
No migration command, automatic journal rewrite or bypass of configuration drift
was added. Unknown versions, mixed binding/header versions and attempted downgrade
refuse. Version refusal precedes tail repair and effect dispatch.

## Review and causal controls

Independent internal source reviews checked the fingerprint change and the
primitives/HTTP changes from separate ownership perspectives. They found no
production defect. One review caught old test metadata fixtures that omitted the
new version; these fixtures were corrected without weakening production admission.

The first full runs on both platforms exposed another test dependency: the
isolated MCPCAS contract harness loaded Profiles and MCPCAS without Evidence.
Package builds already include Evidence. The shared-helper change requires the
isolated harness to declare it too. This is a test-loader correction; the first
full runs retain their failed status and later contract verification is separate.
The first isolated macOS correction then exposed a second harness assumption:
plain-VM application lookup can mistake a checkout named `ipse` for its application
directory. Its repeated `-pa` arguments reversed the parent's code-path order and
promoted the inherited `.` entry ahead of the actual SDK. A private-directory-only
trial also failed because its `ipse-*` basename had the same application-name
ambiguity. The final harness filters implicit relative paths, preserves the
original prepend order and runs in a private directory with absolute load paths.
A separate control confirms correct SDK selection from both the checkout and a
temporary directory. The failed trials remain preserved; the runtime verifier's
path-admission check was not weakened.

The new controls pin historical and canonical endpoint bytes, public-field
sensitivity and object-order independence. Ordinary and extension Sessions resume
legacy journals, dispatch through their original scheme and remain inert on idle
resume. Extension controls cover both stdio and HTTP. Unknown, noninteger,
downgraded and absent versions against version-two metadata preserve the refused
journal bytes, including a partial tail, with no further fixture call.

Additional controls cover exact SHA256 and unsigned-integer boundaries, delegation
admission order/routes/budgets, question availability, separation of trusted
system text from untrusted references, concurrent Finch isolation and active
request cancellation. The focused cohorts passed 130 and 43 tests respectively;
the later full runs include the final downgrade controls.

## Preserved evaluation

The [held-out comparison](../2026-10-23-p27-heldout-comparison/index.md) remains
versioned evidence from 817ab84. Its archive still hashes to
`bb1d87e7115af9dbbcbd7c323e83243461f08390531f8c70f0558ff1420bf7f0`.
No predictions, judgments, source data, resources or published scores were changed.

An offline check reran the current scorer against the saved 350 predictions,
original corpus/references and `reviews/final-reviews.json`. The entire decoded
result equals `comparison/scores-final.json`, including every strategy, citation,
metric and gate. This tests the helper substitutions without new inference or
judgment. It does not establish fresh quality on the now-exposed workload.

The first probe selected pre-owner-resolution reviews and decoded published nulls
as OTP `:null` rather than the scorer's `nil`, so that probe failed comparison.
Its output is preserved separately. The corrected input/decoder check passes;
this was a verification setup correction, not a product fix or changed judgment.

## Final verification

The accompanying [verification receipt](verification.json) binds changed source/test/tooling files,
platform toolchains, actual command results and preserved log identities. It
distinguishes current checks from earlier receipts. These checks do not replay
the consumed real-model comparison or establish new charged-memory figures.

| Check | Result |
| --- | --- |
| Build, formatting, strict compile and CI-policy check | Passed on macOS and Linux |
| Initial complete macOS default suite | 1477/1478 passed, one skipped, 36 excluded; one isolated contract-harness failure, 1152.6 seconds. This run remains failed. |
| Initial complete Linux native-inclusive suite | 1530/1531 passed, 19 excluded; the same isolated harness failure, 1015.2 seconds. This run remains failed. |
| Final isolated contract correction | One outer test passed on each platform, including the embedded contract controls. Runtime/tooling files stayed unchanged after the full runs began; only this test harness changed. |
| Credential-free demo | Passed on both platforms |
| Package and release closure | Built on both platforms; each generated release excludes `inets` from its application closure |
| Exact installed-package verification | Passed on both platforms with isolated homes and runtime paths |
| Source and exact installed MCP verification | All twelve checks passed in each mode on each platform; both transports, unchanged inventories and zero live-model calls |
| Offline scoring | Entire decoded report equals the published final report for all 350 saved outcomes |
| Whole-document editorial review and docs checker | Affected manuals reconciled with source and runnable proofs; 394 Markdown files, 3615 local links, zero errors |

All jobs used an isolated Git checkout on Linux; its primary checkout remained at
`a912db1` and existing services were untouched. Full-run and corrected-case results
are composed coverage, not a claim of a second clean full run. Hosted CI for the
initial maintenance commit is a separate status. No fresh macOS sandbox-specific
check, toolchain-floor runtime check or live-model measurement is claimed.

## Formatter and standalone bootstrap follow-up

Hosted run 40012980389 for dd0a130 failed formatting on Ubuntu and macOS before
tests ran. Elixir 1.18 and 1.20 formatted one long Knowledge guard differently.
Splitting its two sequential Boolean conditions preserves validation order and
failure behavior and passes both formatters. Local Elixir 1.18.5 verification
uses OTP 29; it is not an OTP 27 runtime claim. The earlier repair's hosted run
40006711554 passed and is separate evidence.

A focused standalone index-abort control then exposed application-directory
guessing in the shared fixture bootstrap, beyond the previously corrected contract
harness. The loader now locates the actual loaded SDK BEAM, requires a regular
`.beam` file and applies the existing exact SDK-directory admission. No source
inventory or trust boundary is broadened. A fresh-VM regression deliberately puts
an application-like directory ahead of the SDK and verifies successful loading.

The receipt preserves the initial platform runs and package identities unchanged,
and separately records the three follow-up source/test/tooling files. The
Knowledge validation cohort passed five tests on macOS. The new shadow-directory
control and the existing precompiled-fixture and copied-source-removal controls
passed three tests. The combined cohort passed eight tests on Linux. Strict
compilation and the current platform formatter passed on both systems. The current
development controller passed all twelve source and installed MCP checks on each
platform against the existing artifacts and exactly identified initial packages;
inventories stayed unchanged and there were no live-model calls. The docs checker
again passed 394 files and 3615 links. These bounded checks do not constitute a
new complete suite or a new measured comparison.
