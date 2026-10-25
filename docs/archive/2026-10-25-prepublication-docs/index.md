# Prepublication semantic documentation review

Dated 2026-10-25 UTC (work began 2026-10-24 Pacific and continued on October 25).
The developer required a complete
repository documentation audit and remediation before publishing v0.1.0, then
clarified that this means semantic editorial work, not just links or superficial
changes. Starting source is `16176571780ec43e526549c41be6a660373da2e4`, the accepted
qualified candidate and already pushed stable tag. Publication remains on hold.

## Review the reader's task and the product contract

The [coverage ledger](coverage.json) inventories 429 starting narrative/legal
documents: 15 operator chapters, 22 contributor chapters, 24 entry/reference
documents and 368 historical documents. The initial Markdown/plaintext inventory
contained 426 files; three extensionless license files are explicitly included
in this complete ledger. It records each current document's reader task,
editorial disposition and byte identity. Current documents were reviewed as whole
documents for prerequisites, sequence, concepts, complete examples, expected
results, failure recovery, authority, terminology and implementation limits.
A correct link or passing JSON parser is insufficient for that review.

The user journey is installation/build → credential-free demo → explicit route
and credential setup → offline diagnosis → first real task and approval → result
inspection → saved-session recovery. Optional tools, extensions, retained sources,
accounting and diagnostics branch from that working baseline. The contributor
journey starts with a complete synthetic Session, traces its owners and invariants,
then chooses a feature owner and a meaningful source/installed proof. Existing
chapters that already teach those tasks coherently are retained, rather than
rewritten simply to enlarge the diff.

Historical material is reviewed as historical material: provenance, supersession,
current-versus-retained navigation, original verdict and preservation. Old source
commands, failed experiments, withdrawn verdicts and then-open gates are not
silently rewritten to describe today's implementation. This does not claim a fresh
line-by-line revalidation or rerun of every historical experiment. Original report
bodies and frozen evaluation evidence are unchanged. Archive-index corrections
identify current guidance without expanding old acceptance. The coverage ledger
makes that review boundary explicit instead of calling a hash check semantic review.

## Findings and remediation

| Finding | Reader consequence and repair |
| --- | --- |
| Existing installation could be overwritten after a failed `mkdir` | The original exact shell block continued and exited zero while replacing a sentinel executable. The revised grouped first-install commands stop on failure and refuse existing directories, dangling links and occupied launcher paths before extraction. |
| Upgrade/removal instructions depended on implicit state | Add a complete separate next-version extraction procedure, guard launcher switching, explain partial extraction and rollback, and make uninstall choose an explicit version and matching link. Retain sign-in revocation before deleting the last executable. |
| First-use entry points disagreed about account selection | Align README, installation, user index and release notes around demo before account setup; then teach setup, doctor, the first real task and resume. |
| Multi-command extension examples concealed asynchronous sequencing | State explicitly that each `/ext` operation must finish, including approvals, before the next. Corpus, Graph, Memory and reporting examples otherwise invite a multi-line paste whose later commands are refused as busy rather than queued. |
| Money-policy procedure required readers to assemble fragments | Explain accounting, admission policy and estimated reporting separately. Replace assembly instructions with complete synthetic operator JSON, offline inspection, expected output, real-route substitution and uncertainty/recovery. A report's rate card does not install a spending policy. |
| Artifact compilation was described as inert | Correct the example guide: compilation of trusted source can execute compile-time code. Distinguish inspection/import, trusted compiler preparation, worker startup and subsequent precompiled verification. |
| Current plan mixed today's gates with long historical narratives | Rewrite its opening around selected scope and next results, link bounded decisions, and keep publication, live-account eligibility and human qualifications distinct. Old text-only accounting scope does not prohibit later embedding support. Gemini's implemented route is not Vertex/OAuth. |
| Decision-engine research claims exceeded verified sources | Refresh the proposed scope against primary OpenAI Decisions and SystemOne documentation. Decisions is generally available and typed scores/probabilities need not be categorical choices. Qualify the unverified Zev repository/license/protocol selection instead of asserting one. The milestone remains proposed and unimplemented. |
| Contributor references obscured the actual contract | Name `Ipse.JSON` explicitly, use the supported selected-provider contract rather than an old subset, clarify storage units and write the native CPU allowance as `ceil(timeout_ms / 1000) + 1` seconds. Preserve narrower domain bounds. |
| Archive navigation called superseded material current | Route embedding, Memory, Research, feed, diagnostic, question and evaluation learning tasks to their current owners. Name earlier review handoffs historical and distinguish retained closure evidence from today's verification procedure. Preserve original bodies and claims. |
| Extracted manuals linked to files absent from the package | An actual retained Linux archive had 123 unresolved local prose targets, including 89 in current documents. Bundle current manuals; pin omitted source/example/history references to the recorded build commit and label a version-tag fallback. Preserve fenced examples and third-party notices. Admit the actual tar's required manuals and local targets after creation. |

The substantial original installation, resource-control and plan documents are
preserved under `before/`. [Provenance](manual-provenance.json) binds original
revision, source hash, archived hash and the historical-banner/prose-link
adjustment. Legal text and historical report bodies are not editorially rewritten.

Primary research refreshed on 2026-10-25 UTC uses
[OpenAI Decisions](https://developers.openai.com/api/docs/guides/decisions),
[SystemOne](https://docs.typesafe.ai/api/system-one),
[xAI's security FAQ](https://docs.x.ai/developers/faq/security) and
[its Hermes announcement](https://x.ai/news/grok-hermes).
These sources establish documented interfaces or precedent, not an Ipse live
account check or approved xAI client registration.

## Verification and its boundaries

The [verification receipt](verification.json) records commands and observations.
The initial inventory and per-document hashes are in [coverage](coverage.json).
Current CLI configuration examples are admitted through the actual bundled CLI
with isolated application homes; reviewed-artifact templates are explicitly not
called runnable without their required artifact. Selected pure contributor
examples and the documented Session/lab exercise use built source and synthetic
providers. No paid inference, sign-in or provider eligibility check is added.

Exact installation shell blocks are exercised with synthetic archives and private
home substitution. The old overwrite is retained as a causal negative control;
first install, occupied paths, symlink switching, failed extraction and guarded
uninstall are observed directly. This is automated procedure verification, not
a human upgrade walkthrough or a new macOS installation claim.

Packaging has behavior tests for local/manual versus source/history references,
exact revision and labelled fallback, fenced examples, actual-tar admission,
missing manuals/targets, root escape and malformed provenance. A separate scanner
checks the resulting archive's local prose targets. The full installed-package
proof exercises real bundled CLI/runtime paths, setup/doctor/demo, helpers/locks,
extension-free versus selected-extension upgrade behavior, Unicode and the
synthetic Memory workload. Runtime/host inventories must remain unchanged.

A preparation attempt used an older scratch checkout without a newly linked
acceptance record and correctly failed source-target validation. Complete public
documentation was then supplied; the guard was retained. Sandboxed Mix attempts
were refused for loopback/filesystem-lock `eperm`; permitted runs retain TLS and
test assertions. An invocation missing the package verifier's required `--input`
was rejected by its closed grammar and was corrected. None is relabelled as a
completed proof or a product defect.

The [real-terminal sequencing exercise](extension-command-sequencing.json)
uses the exact Corpus build/import and first source/query commands. Pasting both
commands before the first approval reproduced the busy refusal. Five fresh
individual State-write approvals completed the stored source; a new explicit
query then returned complete coverage and the exact 74-byte quotation. The
synthetic journal retained two completed invocations and no model request.
This is an author exercise, not a new human walkthrough.

The first committed remediation at `6d7aa47` passed hosted compilation and format
but failed documentation checking on both platforms in
[run 40170977432](https://github.com/lexlapax/ipse/actions/runs/40170977432).
Two new snapshot-banner links accidentally named the author's absolute checkout;
the local checker accepted them because that checkout existed. The
[failed metadata](initial-hosted.json) remains retained. The correction uses
portable relative links and retains prior snapshot hashes. The checker now
refuses absolute filesystem links and repository escapes. A separate
[five-case portability proof](documentation-portability.json) observes the old
false pass, both refusals and valid relative/HTTPS links in an independent tiny
repository. No source-test or package success is claimed for that failed run.

The corrected `050fe76` was built in a clean clone with the exact matching
Elixir/OTP notices retained from the previously verified local distribution.
The [clean archive inspection](clean-local-archive.json) verifies its checksum,
compiled source identity, 46 documentation pages, 205 pinned source/history
references and all 24 modern-toolchain notice files against SHA256 and Git blob
identities. The [independent scan](clean-local-links.json) finds zero unresolved
local targets. All twelve installed-package checks pass with unchanged inventories,
private state and no system development toolchain on the runtime path. This is
local Linux/Elixir 1.20.4/OTP 29 evidence; floor and macOS evidence remain separate.

The corrected implementation's [hosted matrix](implementation-hosted.json) at
`050fe76`, [run 40171323951](https://github.com/lexlapax/ipse/actions/runs/40171323951),
has Linux success and macOS cancellation. Linux reports 1,806 tests, zero failures
and 36 exclusions and completes every installed proof. macOS reports 1,771 tests,
zero failures, 36 exclusions and one skip; its native suite reports 36 tests,
zero failures and six exclusions. It builds/admit-checks the archive and completes
the earlier installed proofs, then hits the explicit 45-minute outer job deadline
during the final Knowledge proof. The later experimental sandbox gate did not run.
The [timing and correction](ci-job-budget.json) retain GitHub's timeout annotation.
Both workflows now allow a finite 60-minute matrix budget for the complete
sequence. Product, provider, worker, per-test and proof deadlines and assertions
are unchanged. This does not establish why that host was slower, and the canceled
matrix is not called a passing result.

## Final verification and editorial disposition

The [complete matrix at 5daf5d0](final-hosted.json),
[run 40174384724](https://github.com/lexlapax/ipse/actions/runs/40174384724),
passes both platforms with the 60-minute outer allowance. Ubuntu reports 1,806
tests, zero failures and 36 exclusions. macOS reports 1,771 tests, zero failures,
36 exclusions and one skip, plus 36 native tests with zero failures and six
exclusions. Every executed workflow step succeeds, including archive admission,
all independent source/installed proofs and experimental macOS sandbox enforcement.
The [full job/step metadata](final-hosted-workflow.json) preserves those scopes.

The earlier [0aad07c matrix](verification-baseline-hosted.json),
[run 40171775193](https://github.com/lexlapax/ipse/actions/runs/40171775193),
also completes successfully on both platforms under the former allowance.
That later success does not erase the separate `050fe76` cancellation or establish
its slowdown's cause. Runtime, native implementation, packaging/rendering,
documentation-checker and release-test source are identical between `0aad07c`
and `5daf5d0`; the latter adds the outer-budget correction and prose/record work.

The [final clean local archive](final-local-archive.json) binds `5daf5d0`,
46 documentation pages, zero unresolved local prose targets and 24 modern-runtime
notice files. Its 205 pinned references resolve to
[120 actual Git targets](final-git-targets.json) with the expected blob/tree type.
The [Graph and Research terminal exercises](knowledge-manual-examples.json)
add the generated source-bound assertion, attributed traversal and provided-text
investigation, with exact quotes, complete coverage and zero canonical request
admissions. Their explicit synthetic/approval qualifications remain in the receipt.

The semantic editorial audit and remediation are complete within the review
boundary above. The final follow-up updates this evidence and the plan's release
status; it changes no runtime, verifier, test or workflow implementation. Existing
human/live qualifications remain unchanged. The remaining work is release
reconciliation and publication authorization, not another documentation rewrite.

## Reconcile the release candidate before publication

The stable-tag [workflow at 1617657](https://github.com/lexlapax/ipse/actions/runs/40169083307)
belongs to the pre-audit candidate. Documentation and packaging repairs change
shipped bytes; green checks on that older candidate cannot verify these repairs.
That run succeeded on both platforms and created an unpublished draft. The
[re-download inspection](original-draft-inspection.json) admits its exact four
assets, GitHub digests and checksums, offline compiled `1617657` identities and
13 floor-toolchain notice files per archive. The
[workflow metadata](original-draft-workflow.json) is retained. Its Linux archive
still reproduces 123 missing prose targets, including 89 in current documents;
successful packaging did not resolve the documentation defect.
Keep its artifacts/evidence distinct and unpublished. Moving an already pushed
tag or deleting/replacing a remote draft requires an explicit decision after the
repaired candidate is concrete and verified. No tag has been silently moved.

The prior qualified acceptance remains bounded: assisted fresh-account Linux
walkthrough, no human macOS/upgrade walkthrough, unverified Grok live inference
and approved-client OAuth, and unverified Gemini foreign-history live acceptance.
This documentation review neither closes those limits nor creates a fresh
independent runtime verdict. Publication remains a separate authorization after
candidate reconciliation, complete platform verification and draft inspection.
