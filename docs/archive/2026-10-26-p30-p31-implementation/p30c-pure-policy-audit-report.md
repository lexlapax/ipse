# Independent P30C pure-policy audit

One actionable reporting discrepancy was found and accepted by Root: the component receipt and runtime JSON claim12 new policy tests, while the exact committed policy test source declares and executes11. No production correctness defect was found in the reviewed pure policy, SDK delegates or independent artifact closure. Independent owned baseline11/11, fresh adversarial12/12, corrected supplemental2/2 and a fresh minimal-SDK/actual-artifact child all pass.

This is an incremental audit of committed pure checkpoint `3b5a64391b1bc4f5bed39c5f2faf79dcee0c7f2b`. It establishes no qualified strategy, inference quality, model access, protected decision-v2 operation, actual managed reader, shipping automatic consumer, Session admission or milestone acceptance. The auditor did not author or change production code. No native helper, external/model/network call, qualification gold, credential or private transcript was exercised.

## Accepted finding: P3 correct the new-policy test count

Before repair, `docs/archive/2026-10-26-p30-p31-implementation/p30c-pure-policy.md` says “12 cases” in the new-policy-cases row; `p30c-pure-policy-runtime.json` has `checks.new_policy_tests:12`. The exact test source SHA `e616ce0d1069312cfb33660363730ab2f459ad787a2fc7ab6305397465105480` has11 actual `test` declarations, independently counted through its parsed Elixir AST, and the unchanged suite executes11/11. `independent-owned-test-count.log` lists every declaration and line. `independent-baseline-11.log` retains the actual run. The initial raw log filename `independent-baseline-12.log` was based on the supplied receipt and is retained byte-identically; its actual output also says11 passed.

The discrepancy overstates the new policy case count by one. Correct that count in the owning record/runtime JSON. It does not establish a missing behavior or production defect. The original author55 total is separate and remains unaffected unless another observation disproves it; this auditor did not rerun all55 or change their count.

Root accepted this reporting finding before any repair and will correct the owning record after this frozen report. No repair or after-repair closure is claimed here. Exact before receipt SHA is `1e5fe7969a871f4a11d0e87dae8b479d5481c8d286e5d990ff30f4939f3a578c`; before runtime JSON SHA is `cfacdbbd91f8556025a41148690c4cfe50fac6beb17d361febd0b687140f0ae5`. Both bytes are retained as `owner-component-receipt.md` and `owner-runtime-receipt.json`.

## Frozen scope and provenance

Origin: `/tmp/ipse-p30c-policy-20261026-01`. Independent working graph: `/tmp/ipse-independent-p30c-pure-policy-20261027`. Original source/runtime before/after manifests contain695 source and688 runtime inputs,1,383 rows, with SHA `ed7b5142e7cc92516972155801fd8cce162e5da2fd24dd2ba81105e9c2d40797`. Every declared original and copied byte matched before testing, after tests and at preservation. No repository/index/shared build/helper or original graph was edited.

| Input | SHA256 |
| --- | --- |
| Policy source | `474ebedf74cb8aa229b09b417179043d680b24f7f21bba8d7807146007d1ea9f` |
| Owned policy test | `e616ce0d1069312cfb33660363730ab2f459ad787a2fc7ab6305397465105480` |
| Public SDK source | `3de1485431047f08b5837feb23773fb6a3ab363f6d7d354063bdb4402985328b` |
| Actual Knowledge builder source | `d323397fb4c2bab6d65a124fa9b43a3710de57d8c2675a0f389335a6bbaeb322` |
| Copied host SDK BEAM | `da60868d42fa85cdb5658f20c65004ea559c86fc2d75324517947437ae00d3a9` |
| Retained author's actual1.18 artifact policy BEAM | `b9a3e765f2e595933b54176bce46a47ed3024a1d50e2ad0cf54a82ecc7ea303e` |
| Fresh independent actual artifact manifest | `6a40cc93b0513fa8894bfdd848fee9d305e543b59033f734fd2e53eeb3512327` |
| Fresh independent actual artifact policy BEAM | `0e23b5ae675cd5ec04b7282f867b0e3c7d8b17c2210d323e4ba5dcf564e2ea4b` |
| Private/shared old helper, inventory only | `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29` |
| Entire developer decision chapter reviewed | `5974ae49713e7c21acac707a1c60a366821f065f9def25073b40c326273c7ee0` |
| Fresh primary driver | `cc45c838f24a84187a8b157deac5a2ecef5d56597089c90fc00d09eec777c62e` |

The original graph's dependency-source symlink was inherited on copy. All executed dependency BEAMs were private from initial freeze. No dependency source was compiled/evaluated through that link by the independent tests: SDK source compilation uses only the three copied public files and private dependency ebin paths. Before supplemental probes and durable preservation, all271 sealed dependency-source rows were materialized into private regular files and reverified against the same manifest. The treatment and original link target are retained in `DEPENDENCY-SOURCE-LINK-TREATMENT.txt` and `materialize-sealed-dependencies.exs`. This changes no sealed regular byte. Runtime priv is materialized for preservation; unused telemetry source is explicitly omitted. Ancillary original history is not a claim of a new whole-current-tree build.

## Actual independent checks

| Check | Result | Evidence |
| --- | --- | --- |
| All declared original/copy inputs |1,383 unchanged throughout | `verify-independent.exs`, `independent-freeze.log`, `independent-integrity-final.log` |
| Exact owned policy suite |11/11; seed618204;1.6s; compile diagnostics empty | `run-baseline.exs`, `independent-baseline-11.log` |
| Fresh primary adversarial controls |12/12 on first run; seed508319;0.02s | `run-independent.exs`, `independent-adversarial-first.log` |
| Supplemental first run |1/2; one overly broad pure-Plan tamper assumption | `run-supplemental.exs`, `independent-supplemental-first.log` |
| Corrected supplemental controls |2/2; seed407961;0.02s | `run-supplemental-corrected.exs`, `independent-supplemental-corrected.log`, `supplemental-correction.diff` |
| Fresh minimal SDK compile, actual builder and isolated child |Pass; all3 delegates exercised; Session/Artifact/DecisionCall unavailable | `build-independent-minimal.exs`, `independent-minimal-build.log`, `independent-minimal/{compile.log,builder.log,replay.log}` |
| AST count of exact owned test source |11 declarations | `count-owned-tests.exs`, `independent-owned-test-count.log` |

The primary fresh driver emitted one unused private default-argument warning; its12 assertions/groups pass unchanged and that warning is retained. Production compile diagnostics were unaffected. The supplemental first failure expected an unused `qualification_sha256` change in development to invalidate pure Plan data. Such data can reconstruct coherently without changing request, action permission or production qualification. The corrected control changes the request-bearing profile instead; that mismatch refuses. This is a documented harness assumption correction, not a new production finding. The original supplemental driver/log and one-line assertion diff remain retained. An initial correction-generator tokenization error was fixed before it produced any corrected driver; the generator's original and corrected source are retained.

The new minimal SDK is compiled from exact `lib/ipse/json.ex`, `lib/ipse/decision.ex` and `lib/ipse/extension.ex`, with private existing Jason/JSONSchex/JSON Pointer BEAMs. The unmodified Knowledge builder produces a new retained `knowledge/native` artifact. Every manifest-listed output length/hash is verified in a separate child. The child has neither Session, Artifact nor DecisionCall, exercises neutral request/result validation and `select_decision/5`, runs assessment mapping with an independent refusal, and verifies production remains zero-call despite a qualification digest. It confirms `host.decision` is absent and the only tool export remains `capture`. This demonstrates the actual public SDK closure and packaging; it does not dispatch advice or import/trust/enable an artifact.

Root's author receipts report strict128-source compilation, final55 total tests in6.0s seed752530, actual Elixir1.18 format/minimal compile/artifact evidence and source/runtime seals. Their retained logs remain author evidence. This auditor reran the owned11 suite and authored14 fresh groups plus a separate artifact child; it did not repeat the whole55, actual1.18 compiler, full application suite or packaging. The original overwritten sandbox compile-failure log remains absent exactly as the author receipt discloses.

## Fresh adversarial coverage

- Production on both consumers stays zero-call for strategy none/decision, optional fake qualification digests and profile data. Unsolicited advice on a bypass refuses; receipts retain `source_facts:untrusted`, nil request/result digests and no permission.
- Closed policies/facts reject unknown fields, floats/private terms, invalid UTF8, integer overflow, duplicate members, malformed qualifications and profiles. Exact64-byte operator profiles pass;65 bytes and nonmatching grammar refuse.
- Pack member permutations collapse to one canonical set and deterministic alias representative. A removed alias cannot reappear through advice. Duplicate sets cannot manufacture additional request alternatives.
- Actual UTF8 byte widths and supplied separators/framing control pack fit. Exact allocation boundaries admit only fitting member sets; filtering an over-budget baseline produces the remaining valid fallback.
- A complete fitting set retains all16 records with strategy none or decision, beyond the4-record decision-pack cardinality. Missing fitting coverage, partial/unknown coverage and absent rows return labelled zero-call gaps, not a fabricated empty-set decision.
- Exact16 candidates/eight alternatives/four members pass;17/nine/five refuse. Assessment accepts exactly eight and rejects nine without hiding a question.
- Bounded selection excerpts preserve valid UTF8, truthful shown/original byte counts, original content hash and explicit partial coverage. Assessment input is never truncated.
- Probability0.8 is inclusive; a value just below it remains low-probability even with confidence1. Raw confidence cannot supply threshold eligibility. Malformed distributions refuse. The separately frozen0.2 margin remains explicit, though mathematically redundant at normalized selected probability>=0.8.
- Assessment independently preserves a valid per-question refusal while keeping another allowed defer. Reordered/duplicated/missing/extra-field answers, cross-question corruption or an unpermitted action make the whole result fall back. Advice cannot change origin, TTL, category, evidence, acceptance, capability or publication.
- Private Plan request/fact/profile mismatches refuse. A Plan is reconstructible pure data, not a capability; fully coherent harmless metadata is not treated as an authentication boundary.
- Exact8,192 encoded input bytes fit;8,193 uses request-limit fallback with original facts retained. Exact16,384-byte aggregate facts remain bounded without truncation;16,385 refuses. SDK request/result and private Plan bounds remain independent.
- Receipt canonical digests bind exact facts/policy/request/result data while explicitly retaining untrusted status. Unknown/unavailable candidates, budgets, zero/one alternatives and absent rows produce no extra request.

## Static review and explicit limits

Reviewed complete policy, test, SDK delegates, unchanged neutral validator, actual builder, before runtime receipt and complete developer decisions chapter. The policy has no IO/inference/admission path. Production qualification cannot be manufactured from JSON. The helpers delegate to one existing neutral validator; complete result validation precedes per-question mapping. Boundaries are byte-based on actual supplied rendered strings, and complete fitting sets bypass decision-pack cardinality. Canonical set identity, same-plan reconstruction and known safe baseline results are consistent with the pure contract.

The supplied facts still prove neither complete rendering/framing nor current eligibility, allocation, genuine empty coverage, profile resolution or actual producer identity. A future trusted host adapter must derive those grants, bind result to exact admitted request/producer, validate actual rendered projection and recheck current resources/evidence before any effect. A neutral response with matching question IDs is structure, not proof of its engine/request origin. Pure receipts and development request data cannot supply protected admission, suppression or publication authority. These integration obligations are documented limits, not newly discovered missing features.

No native helper v2, managed reader, automatic capture/recall consumer, quality inference, finite experiment, held-out comparison, model download, account, platform or milestone acceptance was tested or inferred. No engine-quality conclusion follows from these synthetic controls. The accepted count correction is reporting-only; production functional code remains unchanged.

## Durable reproduction

Evidence is preserved at `/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-p30c-pure-policy`. All directories0700 and regular single-link data files0600; all source/destination bytes, declared inputs and final manifests are checked, with Elixir file/directory fsync. Full source/runtime/floor artifact/private independent SDK-artifact outputs, before receipts, drivers and first/corrected logs are retained. `files.sha256`, `diagnostics.sha256` and `PRESERVATION-RECEIPT.txt` bind the completed evidence.

Never execute or modify evidence in place. Copy into a new private working directory and run `elixir <copy>/run-independent.exs`, `elixir <copy>/run-supplemental-corrected.exs` or `elixir <copy>/run-baseline.exs`; they use copied code paths/project CWD. Pure runs require no executable native helper. To rebuild the retained minimal closure, use a fresh work copy with no generated `independent-minimal` directory, then run `elixir <copy>/build-independent-minimal.exs`. Verification recipes retain original origin paths for provenance; preserve the declared relative-input manifest and adapt only verification roots if the old origin is unavailable.
