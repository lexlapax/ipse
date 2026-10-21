# P27 structural implementation records

Historical implementation record, 2026-10-20. The
[selected whole-codebase design](../2026-10-20-p27-structure-design/index.md)
follows a whole-tree survey, competing proposals and independent design review.
This directory records individual implementation increments. It does not establish
completion of the entire redesign or P27. Current guidance belongs to the
[architecture training](../../developer/architecture.md) and
[contributor learning path](../../developer/index.md); acceptance belongs to the
[plan](../../plan.md#p27-optional-research-graph-and-rag).

The [supported-toolchain compatibility investigation](floor-compatibility.md)
records the later Elixir-1.18 warning and raw-launch Unicode repairs, including
their completed focused checks and the limits of earlier platform receipts.

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

## Give evaluation declarations a pure owner

This increment starts at `2c72b69fa0cd380d62186b2e7666c6d0dc423c81`.
`dev/evaluation/contract.exs` now owns recipe construction, complete declaration
admission, Freeze's distinct plan-shape recognition, selected commands and model
origins. The old Plan module/file and Runner validation API are deleted. All
callers move directly, including generated installed launches and tests; there
is no forwarding compatibility module. The formatter includes the final `dev/`
location, and measured launch admission pins this source owner explicitly.

Declaration construction no longer requires Runner, model-service code or the
CAS fixture. A fresh-VM test builds a plan with absent data/artifact paths and
checks that those execution implementations remain unloaded. Runtime callers
receive tagged selection/origin results through Runner's existing error boundary.
Preflight derives command keys only after complete declaration admission. Freeze
keeps portable projection, local resolution, identity IO and its generic version-one
map seals. Shape recognition does not become executable policy validation.

The before/after oracle retains 8,738 public-specification and synthetic mutation
outcomes, including exact successful maps and error atoms. Every outcome matches
on macOS and Linux. Both [bounded reviews](contract-reviews.md) report no finding.
One source-only AST probe also compares eleven moved Plan clauses and thirteen
moved Runner clauses under the documented ownership substitutions. Both reviewers
read the complete developer evaluation chapter. Its literal declaration example
runs successfully with absent dataset and artifact paths.

The [verification receipt](contract-verification.json) binds the same
[462-file implementation inventory](contract-source.json) to 89 focused tests on
each platform. macOS additionally passes the normal build, formatting, strict
compilation and demo. Linux passes build, formatting, strict compilation, package
and installed-package checks. Its complete source and installed synthetic subjects
each retain 350 first predictions, complete execution/resource audits, unchanged
read-only inspection and refused reentry/tampering. Synthetic answers remain
absent through prediction and measured audit; post-audit review/scoring controls
retain ten authority/input refusals and three review-binding refusals. The
unreviewed score deliberately refuses quality acceptance. No model weights or
private evaluation inputs are used.

The first focused attempts exposed remaining preflight and test-alias callers,
plus a deprecated API in the new purity test. Those corrections precede the
frozen successful checks; the earlier failed attempts are not passing evidence.
Full product/native/macOS-specific suites and hosted CI were not repeated for this
developer-tooling increment. Installed measured helpers retain their existing
trusted source loading; stronger common installed isolation remains open.

This unit preserves historical declaration, request and aggregate-score behavior.
The separately selected new evaluator generation and individual qualification
policy are subsequent work. These protocol fixtures establish no held-out quality,
matched real-model resource result, engine choice or whole-P27 acceptance.

## Consolidate trusted example artifact builders

Historical S04 implementation record, 2026-10-20, over `c9c4999`. Current
construction instructions belong to the
[artifact training chapter](../../developer/extension-artifacts.md#build-and-inspect-a-package).
One finite `scripts/build-artifact.exs` command replaces five example builders.
Its 214 implementation lines replace 311 lines, while preserving eleven
artifacts across the five recipes, both Memory versions, SDK-1/2 declarations,
catalogs, options, runtime constraints and ordered file paths. The independent
knowledge-package builder remains separate. Every active static, dynamic and
generated caller, CI command and affected manual now uses the shared command.

The compiler uses a private staging working directory, rejects diagnostics and
publishes only a fully checked descriptor and file inventory. Stable original
source filenames prevent temporary stage names from changing rebuilt bytes.
Duplicate flags, invalid MCP omission fixtures, existing outputs, dangling output
links and shared lab declaration drift refuse. The saved-result load marker stays
in private staging and is absent from the final files. All owned stage
initialization is covered by cleanup.

Two [integration reviews](builder-reviews.md) covered the implementation and
whole affected manuals. The lab invariant test's incomplete fixture could mask a
missing guard; it now establishes a successful seven-artifact control first.
Deleting the guard makes the corrected test fail. Both stale manual instructions
were repaired, and the literal scratch-manifest exercise passes on both platforms
without loading the worker. Eight focused regressions pass.

The [verification receipt](builder-verification.json) binds the identical
[459-file implementation inventory](builder-source.json) before and after both
platform runs. macOS passes 1,401 tests with one skip and 36 exclusions, plus
30 dedicated native checks. Linux passes 1,440 tests with native sandbox tests
included and 19 exclusions. Both pass build, formatting, strict compilation,
demo, package and installed-package checks. These local runs use OTP 29 with
Elixir 1.20.3 on macOS and 1.20.4 on Linux. A new hosted OTP-27/Elixir-1.18 run is
not part of this receipt.

The subsequent [hosted run for `240e416`](https://github.com/lexlapax/ipse/actions/runs/39521623611)
failed formatting on both platforms after successful builds. Elixir 1.18 requests
different wrapping in `dev/evaluation/contract.exs` and
`examples/knowledge/evaluation_review.exs`; later steps were skipped. The follow-up
uses an explicit `if` block and a local query-order value to keep both formatter
versions stable. The complete Elixir 1.20.3 and isolated Elixir 1.18.5 formatting
checks pass, as do all sixteen focused plan/review tests. These local checks do
not turn the failed hosted run into a passing receipt. No command, declaration,
query-order condition or evaluation policy changes.

The repair is committed as `bad4f26b2227cd67705ed14ebc295226c7e97b10`.
Its [complete hosted workflow](https://github.com/lexlapax/ipse/actions/runs/39522389967)
passes on both Ubuntu and macOS, including package and installed checks. This
replaces the failed hosted gate for structural readiness; it does not establish
completion of S05, the entire consolidation or P27's quality and comparison gates.

Each platform runs all five artifact proofs through source and installed hosts:
all four model selections retain nine assertions each, embedding and MCP retain
twelve each, saved results retain exactly 4 MiB and 1,024 fragments with exact
historical reads and inert resume, and the lab retains its actual installed CLI
selection. Its final deliberate service crash still reports expected unconfirmed
cleanup. Previously compiled SDK-1/2 artifacts also pass source and installed
invocation with unchanged inventories. Catalog comparisons do not substitute for
these actual runtime checks or weaken artifact identity.

Linux additionally completes the migrated generated builder call through both
source and installed structured, sealed-answer synthetic comparisons. Each has
350 distinct first predictions, sixteen measured stages, complete resource and
execution audits, confirmed whole-lifetime cleanup, read-only re-audit, refused
reentry/tampering, and the review/scoring binding controls. Synthetic answers stay
absent through prediction and audit. Unmeasured semantic judgments correctly
prevent quality acceptance. These fixtures establish no actual model quality or
matched real-model resource comparison.

The historical [check controller](builder-checks.exs),
[literal exercise runner](builder-manual-exercise.exs),
[source inventory helper](builder-source-inventory.exs), and
[bounded receipt collector](builder-receipt-collector.exs) retain the original
verification code and temporary-path conventions. Previously compiled SDK
artifacts are retained locally and identified by receipt inventories; generated
artifacts and raw journals are not committed. Use current manuals for supported
procedures. Stronger common precompiled installed isolation remains S05.

## Remaining work

Shared verification, development-tooling ownership,
the remaining evaluation layout, costs, bundled behavior, configuration and Session state
remain separate implementation units. The complete operator/developer manual
consolidation and whole-codebase review remain open. The separately recorded
[exposed diagnostic](../2026-10-20-p27-quality-remediation/index.md#retain-the-complete-excerpt-diagnostic)
retains its pinned `bfe8ca5` source and first outcomes; these structural increments
do not change its source or replay its attempts. Fresh private evaluation inputs remain
withheld until the final code/configuration freeze. No quality improvement,
resource comparison, engine selection or P27 acceptance is claimed here.

## Consolidate evaluation and platform ownership

S06/S08 implementation record, 2026-10-21, over `f10334f`. Substantive evaluation
code now lives in `dev/evaluation/` under `Ipse.Development.Evaluation`. Shared OS
probes live in `dev/platform/`, and the scripted model-service probe lives in
`dev/fixtures/`. Small examples and explicit public commands retain their tasks.
Input projection and literal integrity share the pure Dataset owner. Review and
Score retain hash-before-label authority, and Score and Metrics remain separate.
Generated launches, exact BEAM sets, tests, CI and current manuals move together.
The evaluator, measured knowledge and authority closures contain exactly 21, 25
and 26 unique modules, each with one Dataset. Historical captures retain their
original source requirements; no compatibility fallback was added.

Two source-only reviews found one broken test caller: an evaluation Session alias
was shadowed by the host Session. The existing test reproduces the failure before
the explicit alias repair; all three completeness cases then pass. Focused input,
score, review, declaration and execution checks pass. The first declaration-copy
failure remains recorded separately from its unchanged successful rerun after new
source files were registered for the fixture's Git inventory.

The [combined receipt](evaluation-platform-verification.json) retains distinct
437-file identities for the structural checks and the later compiler repair.
Linux passes 1,475 tests with native sandbox checks enabled and 19 exclusions,
all relocated memory/listener probes, a fresh package, both model-service modes
and complete source/installed synthetic comparisons of 350 first outcomes each.
Both comparisons complete their execution and resource audits. These results
belong to the original structural identity.

macOS passes 1,432 of 1,433 tests, with one skip and 36 exclusions. Its sole
failure exposes nondeterministic Elixir checker-metadata encoding in the existing
artifact builder. Independent retained builds differ only in ExCk bytes and
decode to identical terms. The repaired builder adds deterministic compilation
at the trusted recipe boundary while preserving source locations, diagnostics
and staging. Eight prototype builds have identical whole BEAMs and unchanged
code/checker semantics. A source-only review finds no blocking repair issue.
All eight builder tests pass on each platform; all five recipes and their eleven
artifacts build. The repaired macOS source/package runs pass 27 affected commands,
and the separate repaired Linux source/package follow-up passes 13. Previously
failed runs are retained; no full-suite rerun on the repaired identity is claimed.

This unit removes one implementation file. The broader code/test line count
increases by 30 through formatting and the compiler repair/check. It establishes
ownership and exercised compatibility, not held-out quality or engine selection.
Current procedures belong to [evaluation training](../../developer/knowledge-evaluation.md),
[verification training](../../developer/testing.md) and
[artifact construction](../../developer/extension-artifacts.md). Remaining core
consolidation, whole-manual work and final integrated P27 gates remain open.

## Separate usage arithmetic from bundled behavior

S09/S10 implementation record, 2026-10-21, over `423c3e3`. Pure fixed-point
cost arithmetic and aggregation now belong to `Ipse.Usage.Costs` and
`Ipse.Usage.CostSummary`. Bundled memory, reporting, trace and transform behavior
belongs to `Ipse.Builtins`. Ten files and eleven modules move with every active
caller, Registry closure, fixture and manual reference. Old implementations and
compatibility aliases are absent. Public `Ipse.Extension`, generic host
`Ipse.Extensions` and independently built `extensions/knowledge` retain distinct
roles. The [architecture chapter](../../developer/architecture.md#find-extension-code-by-its-role)
teaches how to find each owner.

All eight inert builtin descriptors are identical before and after on both
platforms, including IDs, contracts and options. The exact 97-member host identity
set is unchanged. Both source-only reviews find one stale current-manual cost
owner and no runtime defect; the reference is corrected. The affected chapters
were read as whole documents, including their examples and source ownership.
This scoped editorial check does not complete the remaining all-manual rewrite.

The [verification receipt](usage-builtins-verification.json) binds the same
437-file implementation inventory on macOS and Linux. Each platform passes
110 focused tests, strict compilation, formatting and a fresh package. Previously
compiled SDK-1/2 model-call, saved-result and laboratory artifacts pass three
source and four installed checks on each platform without rebuilding those
artifacts. The checks preserve approval, accounting, memory and hook behavior.
Documentation links pass. No full suite was repeated for this ownership move;
final integrated native/platform/package gates remain open. No private inputs
or actual model calls were used, and P27 remains incomplete.

## Assemble runtime policy in Config

S11 implementation record, 2026-10-21, over `f51d80b`. `Config.resolve/4`
retains data-only discovery, precedence, validation and fingerprinting.
`Config.runtime/2` owns session policy assembly from those effective values and
the client's explicit paths, MCP/endpoint selections and interaction policy.
The CLI's second provider/default table, duplicate settings guards and
`runtime_settings/1` conversion are removed with their callers. Config's closed
provider table owns both supported atoms and default models, avoiding reliance
on another module having created those atoms first.

Endpoint checking and Registry, MCP and sandbox admission retain their order.
The CLI still checks credentials afterward; the key is discarded there and
resolved freshly by the owned provider request. Profile runtime facts retain
the final merge, and embedded Session fixtures are unchanged. No persisted
configuration field, endpoint, credential reference or billing choice changes.
The [configuration training chapter](../../developer/configuration.md) explains
the resolution/admission boundary and its worked precedence exercise.

A synthetic before/after comparison captures 204 exact CLI configuration
outcomes: all supported providers and an unknown provider, valid/invalid bounds,
approval modes, direct endpoints, missing MCP input and selected profile routes.
Every returned map or error matches. Both source-only adversarial reviews report
no finding and include the complete affected chapter. macOS passes 90 focused
configuration, CLI, profile, subscription, embedding and budget tests, build,
formatting, strict compilation, the credential-free demo and documentation links.
The first sandboxed test launch could not acquire Mix's loopback filesystem
lock; tests pass with the required local socket access. No model calls or private
evaluation inputs were used. This scoped record does not claim a full suite,
Linux rerun or installed-package proof; final integrated gates remain open.

## Give pure saved reconstruction one owner

S12 implementation record, 2026-10-21, over `a5186e6`. `Session.Saved` owns
pure context and resume-fact reconstruction from loaded events. The public
`Session.restore_context/1` keeps its narrow message-list result. Session retains
locked source validation, permitted tail repair and reload, page-dependent
question recovery, workspace/skill discovery, and writer startup. The new helper
is included in Registry's host identity. `Questions.tool_result/3` supplies one
shared frame for live question results and saved-answer validation.

An AST comparison confirms all fifteen moved reconstruction clauses, plus the
shared question-result body, after explicit ownership/name/visibility changes
and replacing two tool-phase predicates with the equivalent admitted descriptor
stage test. The first strict compile catches a guarded message-restoration
clause missed by the move script. That clause moves before the successful
strict compilation, AST audit and 161 focused recovery/invocation tests.
Both source-only adversarial reviews find no defect and read the full affected
[persistence chapter](../../developer/persistence.md). Its literal synthetic
reconstruction exercise and the real CLI demo pass on macOS; documentation links
pass. A final private fact-field name correction is checked by strict compile,
the exercise and demo after the focused run. No full-suite, Linux or package
rerun is claimed for this scoped extraction. Those integrated gates, the remaining
invocation model, whole manuals and P27 evaluation remain open.

## Consolidate current invocation facts

S13 implementation record, 2026-10-21, over `cdebac7`. Seven independent Session
fields become one `Session.Invocation` value for the current parent/request,
action, step, bound sources, results and interrupted flag. Recovered questions
construct the same facts. The owner keeps its actual lifecycle phase, pending
approval caller/reference/return phase, worker fences, timers, output indexes
and writer reservations. Registry pins the added helper. The existing durable
`Extensions.Invocation` contract remains separate, with an explicit distinct
alias for the current value.

The lifecycle mapping in [invocation training](../../developer/extension-invocations.md#follow-current-facts-through-the-owner)
covers admission, action begin, approval/denial/expiry, source and result commit,
questions, publication, cancellation and deadlines. A competing lifecycle enum
was deliberately avoided: publication resources and action facts are separate
dimensions. Append ordering and host gates remain owner-held. Idle reset clears
all current facts, including the prior private step counter; the public
cumulative invocation count and journal format are unchanged.

macOS strict compilation and 187 focused invocation, event, publication, model,
embedding, MCP, memory, cost, service and question tests pass. Both source-only
adversarial reviews find no defect; their whole-chapter checks cover architecture
and invocation training. Formatting and documentation links pass. No full-suite,
Linux or installed proof is claimed by this scoped record. The next integrated
checks cover the coherent core changes; whole-manual consolidation and P27's
held-out quality/resource/selection gates remain open.
