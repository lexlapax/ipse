# Internal final P27 audit — reviewer A

Target: `89151b6e049e1f7c8b2d396ea42f7c788e155955`, main, initially and finally clean. Read-only repository review; no source, build, refs, services, model state or frozen evidence changed. Reviewed the supplied brief, repository instructions, interrogate rubric and code-quality lens. This report distinguishes source tracing, isolated causal probes, and inspected historical verification.

## Verdict

Two warning findings remain, both narrow MCP boundary cases. Neither changes the frozen hybrid qualification or establishes a resurrection, replay, or approval bypass. The ordinary-result privacy case should be repaired at the shared MCP result boundary. The legacy binding case is fail-closed and requires an explicit compatibility decision; do not weaken saved-binding validation to accommodate it. No critical finding or justified structural rewrite was found.

## Findings

### A1 — warning: ordinary MCP results can recreate a configured private value during redaction

- Location: `lib/ipse/mcp.ex:349-354`; sink: `lib/ipse/session/turn.ex:1247-1268`.
- Trigger: admitted synthetic environment values `FIRST_TOKEN=q[redacted]` and `SECOND_TOKEN=zz`; tool returns text `qzz`, either success or `isError: true`.
- Cause: the single longest-first redaction pass checks the longer secret before replacing `zz`. The replacement creates `q[redacted]`, exactly the other configured secret. `result_text/2` checks UTF-8 and length, but does not recheck private values. Ordinary `tool_completed` persists the text and exposes it to the conversation. The extension path now rechecks both successful text and tool errors, so its C3 regression does not cover this ordinary path.
- Observed probe: in an isolated Elixir VM, compiled exact current Config source and current MCP source with only `result_text` changed from private to public for direct invocation. For the above content, observed `{{:tool_error, "q[redacted]"}, true}` and `{{:ok, "q[redacted]"}, true}`, where the Boolean is `Config.contains_private?` on returned text. No network, worker or model launched. The Session sink is source-traced; root was asked for an ordinary Session causal probe.
- Consequence: a known private value can enter ordinary journal/model output despite selected-value redaction. This is a collision edge, not a general-purpose credential extraction demonstrated here.
- Smallest repair: refuse as unknown if post-redaction ordinary text still contains a configured private value, at shared MCP result acceptance. Cover both success/error and ordinary Session journal/no-replay. Audit resource/prompt result acceptance for the same property. Do not repeatedly redact indefinitely or merely conceal it in the UI.

### A2 — warning: legacy own-server hashing and cross-server public manifests produce invalid extension bindings

- Location: `lib/ipse/mcp/config.ex:87-91`, `lib/ipse/extension/external_calls.ex:310`; rejecting caller: `lib/ipse/session/invocation.ex:299-309`.
- Trigger: the same legal overlapping-secret shape in `test/ipse/mcp/config_test.exs:94`: first server has args `--k=xabc`, own secret `abc`, other server secret `xabc`; a legacy journal selects fingerprint version one and subsequently invokes an extension MCP binding.
- Cause: v1 fingerprint hashes own-secret-redacted args `--k=x[redacted]`, but the returned server retains global redactions. `MCPCall.binding` serializes args `--k=[redacted]`. Pure saved public validation recomputes the hash from that different public manifest and rejects it. Session `bind_mcp` invokes that validator before dispatch.
- Observed probe: compiled exact Config and ExternalCalls source in memory (existing read-only test ebin supplies dependencies), synthesized the above server and a closed empty-object tool schema, called `fingerprint_version`, `binding`, and `valid_binding?`. V1 returned `{1, ["--k=[redacted]"], false, false}` for manifest hash equality/binding validation; otherwise identical v2 returned `{2, ["--k=[redacted]"], true, true}`. No file/build/network mutation. Current config unit control expressly asserts the different legacy manifest args, and the ordinary inert legacy-resume control cannot detect extension-call refusal.
- Consequence: C1 restores ordinary inert resume but does not establish the stated legacy extension-binding compatibility for overlapping argument secrets. Calls fail closed; no unauthorized effect or secret leakage was observed. Manuals already advise against secrets in arguments, which limits practical impact but does not make this accepted config impossible.
- Smallest justified repair: define a canonical legacy binding public representation that agrees with its historical hash while retaining global output redaction and no private manifest bytes. If that cannot safely be supported for this legacy shape, explicitly document and test its refusal and recovery choice. Preserve old saved records and strict public hash validation. Add a binding/invocation control, not only inert resume.

## Acceptance / coverage matrix

PASS below means inspected source plus named evidence supports the scoped requirement; it does not mean this reviewer reran a platform suite.

| Plan criterion / boundary | Status | Evidence and limit |
| --- | --- | --- |
| Attributable bounded source/chunk/generation/version/hash/citation identities | PASS | Evidence source/citation reconstruction, 2048-byte chunks/1024-byte citations; Store content/projection and query revalidation paths inspected; matching domain tests/receipts inspected. No fresh exhaustive domain execution. |
| Suppression, stale projection refusal, delayed work/import recovery | PASS | Permanent suppressed root, exact draft revision/generation/hash checks, import historical origin, State and MCP adapter response checks, query root revalidation. No automatic replay found. |
| Historical/as-of semantics | accepted-limit | Current retained generations only; Corpus, Graph and developer manuals explicitly explain replaced-generation absence and complete eligible-retained abstention. |
| Contradictory, negative-only, stale, weak evidence | PASS | Evidence provenance checks, query scope exclusions versus failures, graph context limits and documented unassessed semantic support; measured wrong answers remain published. No universal semantic guarantee. |
| Approval, exact selected profiles, budgets, cancellation, partial failure, inert recovery | PASS with A1/A2 warnings | Durable host-effect contracts and descriptor revalidation remain; deadline-edge completion repair and C3 extension checks inspected. A1 is a remaining private-result boundary; A2 is a narrow legacy fail-closed incompatibility. |
| Zero applicable authority/isolation/replay/resurrection failures in corrected controls | PASS for inspected receipts; UNPROVED as new execution | Final macOS/Linux/source/installed logs hash-match receipt; no suites rerun by reviewer. No stronger sandbox claim. |
| Generic host contracts, unchanged legacy grants and SDK bounds | PASS with A2 | Domain modules remain independent; SDK result envelopes and explicit capabilities retained. A2 qualifies legacy MCP compatibility. |
| Independent package/preset selection | PASS for inert capability scope | New 12 tests instrument Worker/State/MCP/embedding/model entrypoints, require instrumentation, create disabled/enabled Sessions and resume, close them and destroy tracing; setup removes artifact root. Together with original three presets covers all 15. These are inert capability tests, not domain-operation/live-service tests for every preset. |
| Seven strategies × 50 held-out questions × two projects; all first outcomes | PASS | Independently extracted immutable bundle: 185 members hash/size match, 350 rows all attempt one, seven variants each 50, two projects each 175, 344 ok/six failed, 635 citations. |
| Freeze/audit before reference release | PASS as recorded custody; accepted-limit | Frozen manifests/release narrative inspected. Ordering/backend/host truth is not independently attested by a present-day file inspection. No seal replay or new reference release. |
| Independent semantic judgments / literal integrity | PASS within owner-approved method extension | Raw final review and report inspected; independent final resolution is 349/350 plus owner case, owner `independent: true` is disclosed as scorer compatibility/global completeness dependency. No new rejudging; no backend-model attestation. Literal-integrity execution rests on frozen scorer and prior independently recomputed evidence. |
| Individual 90% answer / 95% citation strategy qualification | PASS | Recomputed counts directly from raw final semantic reviews joined to predictions: hybrid 46/50 and 79/83; other variants match publication and fail at least one threshold. Aggregate gates fail and are not selection gates. |
| Resource comparison and justified engine selection | PASS for recorded comparison; accepted-limit | Matched resources and narrative report requests, latency, storage and charged memcg peaks, not RSS/VRAM; one fixed-order mixed CPU/GPU run, 8-GiB partial residency, unknown tokens/unpriced local inference remain limits. No fresh kernel/GPU attestation. |
| Minimal measured reference authority | PASS | Corpus and developer example specify state-dense, empty rerank registry, hybrid RRF60/top_k10/no graph/reranker; state-semantic optional authority is separate. Setup/build/config/import receipt inspected, not reexecuted. |
| Consolidation, manuals, architecture and implementation review | PASS with warnings | Cohesive Session owner with synchronous Turn/Invocation; authority callbacks intentional. No new layers justified. Domain Store remains large but its root/page state machine is cohesive; no demonstrated dramatic deletion preserving contracts identified. Relevant manuals and dated correction notes examined; report does not substitute for exhaustive all-chapter editorial certification. |
| Exact-target hosted CI | UNPROVED here | Did not fetch hosted run 40032500880. No green claim for target is made. Root must inspect its fresh status separately. |

## Checks personally performed

- Verified exact HEAD and clean status; `git diff --check` passed.
- Read current P27 criteria, last repair diff and broader changed-file inventory; traced MCP configuration/call/result/binding boundaries, ordinary result sink, extension effect-source envelopes, inference lifetime/deadline repair, State/MCP adapters, Store publication/suppression/import/capacity/revalidation, Evidence identity and Corpus final revalidation.
- Read original independent review/remediation/maintenance dispositions, final review/receipt, comparison and acceptance audit; inspected relevant operator/developer Knowledge and MCP manuals and new preset controls. No claim to have read every source or every one of the 36 manual chapters exhaustively.
- Hash-verified all 14 source-file rows in final verification receipt against exact target. All 20 final macOS/Linux log files were available locally and hash-matched their receipt rows (build, format, strict compile, full suites, demo, package, installed package, artifact, source MCP, installed MCP).
- Extracted evidence only into `/tmp/ipse-p27-audit-astra-evidence`; all 185 manifest member hashes and byte counts matched. Independently counted grid/outcomes/citations and recomputed raw final semantic counts for all seven strategies.
- Ran two isolated pure causal probes described above. Existing compiled dependency paths were read; changed source modules were compiled in VM memory only. No Mix suite, dependency fetching, source editing, service action, live inference, remote action, seal replay or judging performed.

## Inspected verification rather than personally executed

Final receipt reports macOS 1497 passed, one skipped, 36 excluded, and Linux 1550 passed/19 excluded; all final source/installed MCP checks and package proofs passed. Its source rows and local log hashes matched. Earlier failures remain failures in remediation/maintenance records. Elixir 1.18.5 formatter on OTP29 is not OTP27 runtime evidence. Fresh Linux native, macOS sandbox-specific, package execution and physical kernel/GPU claims were not independently rerun here.

No broader reference-choice reversal is warranted by either finding. Fix or explicitly adjudicate these narrow host compatibility/privacy boundaries before describing the latest review corners as entirely closed.

## Follow-up on proposed repair

The lead proposed moving the private-output check into shared MCP acceptance and making v1 public argument rendering agree with own-server fingerprinting. Both are appropriately small boundary repairs. For the manifest fix, check rendered args against the original live server/global redactions, not the own-only temporary rendering server; fixed-message refusal is appropriate if public rendering would contain a private value.

A1 also applies to ordinary resource/prompt results at `lib/ipse/mcp.ex:734-745` (`render_untrusted/3`). It independently redacts the full wrapper/body and then checks only UTF-8/length. A third isolated exact-source probe (exposing only this private helper in memory) returned `{:ok, text}` with `contains_private?(text, server) == true` for both resource and prompt using the same synthetic qzz collision. A result_text-only fix is incomplete: add the same final private check at catalog rendering, or centralize safe final text acceptance without expanding machinery. This follow-up was sent to the lead before implementation.

## Post-fix assessment — integrated uncommitted patch

Reviewed the subsequent uncommitted runtime and test diffs after the original exact-89151b6 audit. Original findings above remain historical findings against that commit. No concrete remaining issue was found in the integrated repair.

- Shared `MCP.result_text/2` now checks post-redaction text before either successful or server-error acceptance. `render_untrusted/3` applies the equivalent check after constructing and redacting the complete resource/prompt wrapper. Both return the existing unknown result, preserving ordinary batch-stop and no-replay semantics. Removing the extension's diagnostic-only recheck is appropriate: that result arrives exclusively through the shared checked path; successful source persistence retains its existing defense.
- `Config.manifest/1` selects own-server argument redaction for absent/v1 and global argument redaction for v2, then checks public args against the original live server/global private set. The hash and saved binding now agree. Already valid v1 saved public manifests keep their original self-consistent bytes; this changes no validator or saved event. V2 hash inputs remain unchanged for admissible output. Collision output refuses with fixed exception text, rescued into generic invalid configuration on the normal loader path.
- The new three-server configuration regression catches a collision introduced only by global replacement (`qzabc` → `q[redacted]`), which pre-global manifest checking alone missed.
- The legacy integration control starts from real saved initial workspace/extension state, removes only the version header and substitutes legacy fingerprints, resumes, reaches real approval, asserts no dispatch before approval and self-consistent public hash, approves exactly one dispatch, validates Actions.restore, closes, resumes idle, and asserts unchanged journal bytes, discovery and call counts. It tests the previously missing binding/approval/recovery path rather than merely opening a legacy session.
- Ordinary success/error controls perform a fixture-side write, assert unknown plus not_started for the next batch item, no secret journal bytes/no further model request, and inert resume. Catalog control exercises dispatch for both resource and prompt; existing cleanup belongs to its linked fixture and Session helper teardown.

Personally reran only isolated in-memory source probes after the fix. Both ordinary tool success/error returned unknown; resource/prompt returned unknown; legacy and v2 MCPCall.valid_binding? both returned true, with respectively `--k=x[redacted]` and `--k=[redacted]`. No Mix suite/build or repository mutation was performed by this reviewer. Full focused/integrated test execution remains the lead's verification responsibility.
