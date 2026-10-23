# Reviewer B final P27 audit

Target: `89151b6e049e1f7c8b2d396ea42f7c788e155955`. Initial status was clean. Read-only repository audit; no source, builds, services, refs, model state or evidence were changed. No child agents, full Mix suite, model inference or external messages were used. Applied the supplied interrogate rubric/code-quality lens and unslop writing rules.

## Findings

### B1, warning: ordinary MCP results still disclose post-redaction private values

Location: `lib/ipse/mcp.ex:349`, result classification at lines 351-354. Persistence path: `lib/ipse/session/turn.ex:1247`, `:1266`, `:776-817`.

Reachable trigger: configure two valid private environment values `q[redacted]` and `zz`. An ordinary configured MCP tool returns text `qzz`, either with `isError: true` or as success. Config.redact sorts longer secrets first, sees no first secret, then replaces `zz` with `[redacted]`, producing the first configured private value `q[redacted]`. This is the exact same collision already covered for extension diagnostics by `test/ipse/extension/mcp_call_session_test.exs:252`.

Observed: an isolated Elixir VM loaded Config and compiled the unchanged `result_text/2` and `unknown/0` AST clauses under a private probe module, making only their visibility public. Synthetic success returned `{:ok, "q[redacted]"}` and synthetic error returned `{:tool_error, "q[redacted]"}`. `Config.contains_private?` returned true for each output. No service or project build was used. The VM emitted unresolved-call warnings for unused Config functions because dependencies were deliberately not loaded.

Source-traced consequence: ordinary Turn.tool_completed adds its diagnostic prefix without rechecking private values. Both success and error flow through tool_result to append_tool_message and notification, making the private value durable and available to the next conversation-model request. Extension MCPCall.execute now checks both success and diagnostic paths, but ordinary MCP does not use those checks. The current ordinary error regression asserts redaction and partial-effect/inert recovery, but does not exercise the collision.

Smallest repair: after redaction in the shared MCP result boundary, check `Config.contains_private?(text, server)` and return unknown before success/error classification. Add ordinary Session regressions for both success/error collisions, preserving real partial-effect and inert-resume assertions. This also reduces policy duplication rather than adding a new layer. The root was asked to run a bounded ordinary Session regression for confirmation; no full Session reproduction was personally run.

Severity rationale: configured-private-value disclosure violates the explicit privacy invariant and the intent of C3. The crafted collision is unusual, so this is a warning rather than an unqualified broad exploit claim.

No other high-confidence actionable defect emerged from the portions traced. This does not constitute exhaustive line coverage of all P27 code.

## Acceptance and coverage matrix

PASS below means the inspected source/evidence supports the scoped claim. It does not mean I personally reran the archived suite.

| Plan criterion | Verdict | Coverage and limit |
| --- | --- | --- |
| Attributable source/chunk/generation/version/hash/citation identity | PASS, sampled | Inspected Store/State contracts, domain ownership manuals, selected-query and projection descriptions and caller boundaries. Existing suites remain receipt evidence; did not retrace every Evidence function. |
| Suppression, delayed work, import/as-of eligibility | PASS, sampled; accepted-limit | Store suppressions/root capacity/collection/import paths and manuals agree that as-of filters retained generations rather than reconstructing history. Historical results remain historical receipts. Did not execute live races. |
| Contradictory, stale, negative/weak evidence | UNPROVED personally | Inspected training contracts and recorded tests/quality findings. Did not rerun or independently semantically rejudge graph outcomes. No new contrary defect established. |
| Approvals, accounting, budgets, cancellation, owner loss, partial failure, inert recovery | FAIL for private transport; otherwise sampled PASS | B1 survives in ordinary MCP. Extension unknown-on-collision is implemented. Late inference admission explicitly calls measure_request on post-journal expiry. Ordinary/extension effects have distinct durable classifications. Cancellation and owner-loss coverage relies on inspected receipts and existing controls. |
| Zero applicable authority/isolation/replay/resurrection failures | FAIL pending B1 adjudication | New privacy counterexample is outside passing suite coverage. I observed no new replay or resurrection defect. No untested sandbox guarantee is inferred. |
| Generic contracts, independent optional packages, unchanged legacy grants/SDK bounds | PASS, sampled | Shared MCP version parser accepts absent-v1 and explicit integer-v2 only. Legacy fingerprint calculation strips cross-server redactions for hashing while runtime redaction retains them. Public saved bindings require matching metadata version. All 15 preset declarations have idle capability tests, with caveat below. |
| Seven strategies, 50 questions/two projects, every 350 first outcome | PASS, archived evidence | In-memory OTP archive extraction personally counted 350 prediction lines. Full archive SHA256 matched the immutable receipt. Seven-strategy publication includes six failed outcomes. Authorship/custody relies on original recorded declarations. |
| Freeze/audit before reference release and literal checks | PASS, receipt-backed | Read acceptance/index disclosures and immutable score gates. No rerun of seal/audit/release, no replay or new reference access procedure. |
| Independent semantic review of applicable outcomes | accepted-limit | Documents accurately disclose 349/350 independent final resolutions and 634/635 pairs, owner `independent:true` compatibility field, and global completeness dependence. Approved method extension is not independent review. No rejudging. |
| Individually >=90% answer and >=95% citation, reject weaker | PASS, archive-backed | Original saved final score has complete grid/review/quality flags true. Published hybrid 46/50 and 79/83; sensitivity and narrow margin disclosed. Did not independently recompute all numeric scores. |
| Matched latency/usage/storage/exact RAM and engine choice | PASS, archived; accepted-limit | Read full resource/selection disclosure. Kernel charged RAM includes cache/kernel, is not RSS/VRAM. Mixed partial 8-GiB GPU residency, single fixed-order run, unknown tokens and unpriced local inference are explicit. No fresh hardware measurement. |
| Consolidation, manuals, platform/installed checks and independent review | PASS, receipt-backed, incomplete personal editorial scope | Read review dispositions, current Knowledge training/scoring/storage, operator Research and substantial Corpus/Graph. Some large combined reads truncated; I do not claim whole-document review for every operator/developer chapter. Verified all final receipt source hashes and both platforms' listed local log hashes. Hosted exact target status was not fetched and is UNPROVED by this reviewer. |

## Specific corner assessments

- C1: source satisfies the required distinction. Config.fingerprint_version/2 deletes `:redactions` only in the manifest/hash input for legacy v1; the returned runtime server retains the complete redaction set. Manifest hashing and cross-server output redaction are separate.
- C2: Config.journal_fingerprint_version/1 admits only an absent field or integer 2. Session.open selects that scheme before configuration restoration. MCPCall.public_server? admits a version field only for exact 2; metadata comparison shares the header parser. No downgrade path found in these inspected paths.
- C3: extension success/error result checks close the reported extension cause; B1 remains in the ordinary route.
- Preset inert tests: all twelve added presets build actual declared artifacts, import and resolve trust, start disabled/enabled Sessions, close/resume them, and assert zero worker/State/MCP/embedding/model execution. Tracing is destroyed in `after` and parent fixture root removal covers artifacts. They intentionally use base options rather than each semantic/MCP profile's operational configuration. Therefore they prove inert capability grants, not every preset's operation, service configuration or cancellation. The archive states this boundary accurately. A failed assertion before Session.close_confirmed lacks test-local `after` cleanup, but I did not establish an externally surviving process or justify a separate defect.
- Reference instructions: current examples use state-dense, empty rerank, top_k10; state-semantic is a separate authority expansion. The published reference is consistent with those descriptions.
- Structural lens: moving the private-value guard into shared result parsing is preferable to another ordinary/extension wrapper. No preference-only file splitting or new abstractions recommended.

## Checks personally run

1. `git status --short`, `git rev-parse HEAD`: clean exact target.
2. `git diff --check`: passed.
3. Read-only source/manual/receipt inspection, including recent diff inventories and supplied review rubrics.
4. Isolated AST result parser probe described in B1. First trial accidentally omitted the guarded result_text clause and selected only fallback unknown; corrected clause selection unwrapped `when` and produced both disclosures. The first trial is not passing product evidence.
5. Standalone Elixir hash check of all 14 `source_files`, ten macOS logs and ten copied Linux logs in final-review/verification.json. Every listed byte count and SHA256 matched.
6. Immutable evidence.tar.gz SHA256 matched `bb1d87e7115af9dbbcbd7c323e83243461f08390531f8c70f0558ff1420bf7f0`.
7. OTP in-memory archive extraction counted 350 prediction rows and decoded saved final complete_first_grid/complete_review/quality_gates_passed as true. No archive files were extracted to the repository.

## Receipts inspected, not rerun

Final-review receipt reports macOS 1497 passed, 1 skipped, 36 excluded; Linux native-inclusive 1550 passed, 19 excluded. Both package/installed proofs and twelve-check source/installed MCP proofs have matching log identities. Formatter-floor receipt says Elixir 1.18.5 on OTP29 and explicitly makes no local OTP27 runtime claim. Prior failed verification attempts are retained separately. The exact hosted run 40032500880 was not queried, and I make no green claim for it.

No full suite, source mutation, dependency installation, service operation, live account or model test was performed.

## Post-fix assessment, integrated uncommitted changes

This section reviews the subsequent working-tree fix over 89151b6. It preserves the original finding and verdict above as the exact-target assessment.

No concrete remaining issue found in the integrated diff. B1's causal condition is closed at the shared `MCP.result_text/2` publication boundary. I repeated the same isolated AST probe against the edited source. Both synthetic success and tool-error collisions now return unknown with the fixed generic text. No Mix, file build, service or model call was run.

The resource/prompt renderer also checks the entire rendered text after redaction. That includes its generated prefix and prompt role markers. New catalog controls exercise both resource and prompt collisions. Ordinary Session tests exercise success and error collisions after a real effect, stop a two-call batch with unknown/not_started, assert no second model request or private journal value, then idle-resume without replay. Removing the extension error-only guard is justified by the shared parser guarantee. Its retained success-source check still protects source admission.

Version-one public manifest arguments now use own-server redaction, matching the legacy writer and the hash inputs. Runtime output redaction still uses all configured secrets. The full-set postcheck on those public arguments refuses a private output with a fixed error rather than publishing it. Version-two manifest/hash behavior uses the same global redaction contract. Saved validation recomputes the fingerprint from the actual retained public manifest; the change restores that equality for the overlapping-secret legacy case and does not change a binding schema or journal version.

The new legacy extension regression constructs an absent-version journal using an actual initial workspace/event snapshot, opens it under current configuration, waits for exact approval, checks public args and recomputed fingerprint, confirms no preapproval call, approves one effect, validates Actions.restore, then compares journal bytes and discovery/call counts across idle resume. This goes beyond a pure hash fixture and directly covers approval, saved binding and inert restoration. The configuration collision fixture covers global-secret creation by argument redaction.

I traced remaining MCP publication families: ordinary definitions have a full catalog private-value check; extension discovery checks its whole public binding; tool results now check after redaction; resource/prompt content now checks after full rendering. I did not identify another reachable private-content publication gap in these callers. Arbitrary equality with constant host messages was not treated as disclosure of externally supplied bytes.

Post-fix matrix adjustment: B1 is repaired by source inspection and the repeated isolated probe; full Session and catalog verification is pending the root's focused test results. Thus the original FAIL is no longer a source defect in the reviewed working tree, but this reviewer does not independently claim passing Session-suite verification or exact-commit hosted verification. No new full-manual or all-P27 acceptance claim is added.
