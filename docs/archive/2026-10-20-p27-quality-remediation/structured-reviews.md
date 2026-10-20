# Structured model-call review records

Historical scoped records, 2026-10-20. Provenance is the six original bounded review reports, hashed in [the verification receipt](structured-model.json). Current guidance: [model calls](../../developer/extension-model-calls.md) and [knowledge training](../../developer/knowledge-extensions.md). Acceptance and remaining work: [plan](../../plan.md#p27-optional-research-graph-and-rag). Original prose is retained; headings are nested two levels for this combined record. Reports describe their own snapshots, not later corrections.

## review-a-original

### Independent review A

#### Findings

No findings.

#### Scope exercised

Reviewed the frozen change against base `7e4c638` and read the selected design as rationale. Traced the implementation beyond the patch through `Ipse.Extensions.Actions`, `Operation`, `Inference`, Session action approval/admission/completion, `Ipse.Usage` journal reconstruction, `Ipse.JSON`, the existing MCP schema validator, credential resolution, budget dispatch, Ollama response construction, knowledge profile/build validation, Graph projection setup, Store profile identity, and knowledge extraction/reranking continuation checks.

Checked these specific boundaries:

- v1 retains its exact request fields and raw-text result envelope; v2 requires an object-root response schema and shares the original whole-request and SDK bounds.
- The schema remains part of the complete request hash and displayed approval. Provider compatibility is checked before admission and again during saved-source reconstruction.
- Prepared inference strips inherited owner settings and selects native Ollama `format` explicitly. The provider guard prevents unsupported providers or summary policy from silently ignoring/replacing it.
- Live derivation and saved successful outcomes both reject malformed JSON, duplicate decoded keys, schema mismatches, non-object roots, and independently excessive SDK objects. The original accepted raw string is returned unchanged.
- Session records completion and usage before deriving the extension outcome. Schema-invalid completed content therefore stays accounted, with the existing response receipt and inert recovery path.
- Knowledge schemas use actual short IDs and task cardinality; the existing exact quote, attribution, polarity, and permutation checks still determine domain validity. The empty rerank case avoids an unsupported empty enum.
- The opt-in profile field passes the existing BuildSpec options admission and participates in projection profile identity. It requires no capability or schema bypass.

Ran the complete `test/extensions_model_call_test.exs` file in a standalone Elixir VM, loading dependencies from existing `_build/test/lib/*/ebin` and compiling only the frozen changed modules in memory. Result: **9 passed**. The probe is `/tmp/ipse-p27-review-a-probe.exs`. This did not invoke Mix compilation or write repository artifacts.

#### Limits

Did not run the full suite, package/release checks, live Ollama/model inference, or another platform. Reviewed the new session/HTTP/knowledge tests and their surrounding execution paths but did not independently rerun those integration files. No private evaluation material, credentials, or operator journals were accessed. Runtime, tests, and repository tooling were left unchanged.


## review-b-original

#### Findings

##### 1. [critical] Structured extraction can emit a request the host must reject
**Location**: `extensions/knowledge/src/adapters.ex:389-452`, `lib/ipse/extensions/model_call.ex:70`

**Finding**: The adapter accepts an extraction task when its inner JSON `input` is at most 4096 bytes, then adds a response schema and returns the call without checking the encoded 8192-byte limit on the *whole* `model.complete` request. Because `input` is a JSON string inside another JSON request, quotes and backslashes in a valid source are escaped twice. The schema pushes some calls that worked with the legacy contract over the host limit. The host rejects them before approval or admission, so selecting `output_contract: "json_schema_v2"` makes those existing source chunks impossible to extract.

**Evidence**: An isolated Elixir probe (`/tmp/ipse-p27-review-b-check.exs`) constructed a valid public `Evidence.source` containing 1700 quotation marks, obtained its canonical 1700-byte chunk through `Evidence.chunks/1`, and passed it to `Adapters.start/3` with `max_edges: 1`. The adapter emitted a v2 call with a 3448-byte `input`. `Jason.encode!` gives 8460 bytes for that request, and `ModelCall.validate/1` returns `{:error, :invalid_extension_model_call}`. Removing only the new schema and restoring version 1 gives 7848 bytes and `:ok` from the same validator. The check used the current source files and existing dependency beams without modifying the repository or invoking inference. The corresponding test covers long plain `x` input, which does not exercise double escaping.

**Suggestion**: Apply the host's full encoded-request bound when building the knowledge call and define how the adapter handles a selected chunk that does not fit. A focused regression case should use escape-heavy valid source text and compare both output modes. If structured mode is meant to accept every legacy-admitted input, the representation or chunk sizing must leave room for the schema rather than merely reporting a clearer failure.

#### Exercised scope and limits

Read the frozen runtime diff and surrounding `ModelCall`, `Provider`, Ollama stream, MCP schema, JSON parser, Session admission/finish, inference coordinator, usage restore, action validation, knowledge profiles/adapters/evidence, proof examples, and focused tests. Traced request hashing, provider selection, completed usage, raw response retention, schema matching, restore validation, quote attribution, and rerank permutation checks. No other concrete issue found in those paths. I did not run the full suite, package build, or a native model. `mix run --no-compile` was blocked by the sandbox's TCP filesystem lock, so the reproducer used standalone `elixir` with `ERL_LIBS`; its output is recorded above. The existing 256 KiB native receipt cap can leave an oversized receipt unretained, which is an explicit preexisting limit and not a finding against this patch.


## review-a-corrective

### Independent review A, corrective pass

#### Runtime verdict

No new runtime findings in the corrected frozen patch. The 12 KiB v2 ceiling resolves the quote-heavy input regression without changing v1's 8 KiB ceiling, field limits, SDK object limits or response contract. The adapter now checks the complete encoded request before returning a host call. Its two local size branches match the host's version-specific limits and do not introduce an SDK dependency or another module.

Read the appended bound correction in the selected design and the corrective patch, including the exact-size Session approval/wire/restore regression. Rechecked how that request travels through the existing SDK envelope, action hashing, approval, accounting and reconstruction boundaries. The earlier review report remains unchanged.

#### Documentation findings at the reviewed snapshot

##### 1. Warning: remove the minimum-context size guarantee

Location: `docs/developer/extension-model-calls.md:111`.

The sentence “Independently bounded input fits below minimum configured context” is no longer true. A v2 request with an input consisting of 2048 emoji passes `ModelCall.validate/1`. That input is 8192 UTF-8 bytes and its actual `Context.helper_messages/2` representation encodes to 8621 bytes. The minimum configurable `context_bytes` remains 8192. `ModelCall.prepare/2` deliberately builds independent helper configuration and does not carry that main-context policy.

Replace the size guarantee with the actual independent request/helper limits. Do not imply that request validation establishes a backend model context-window or token fit.

##### 2. Warning: the example procedure omits the new proof modes

Location: `examples/model-calls/README.md:11-36`.

The complete README still instructs the reader to run “both selections” and provides only the default and `none` source and installed commands. The developer chapter now describes four combinations and links to this README for installed verification. Following that link never exercises native structured output.

Integrate source `json` and `json none`, installed `json` and `json-none`, and the expected exact `format` check into the existing proof procedure. Explain output contract and reasoning selection as independent choices. Keep the distinction between scripted HTTP behavior and actual model inference.

##### 3. Warning: teach the domain opt-in alongside the existing adapter explanation

Location: `docs/developer/knowledge-extensions.md:450-595`, “Plan projections before inference”, and its lifecycle exercise later in the same document.

The whole chapter explains extraction fields, byte quotations, rerank IDs, permutations and provider lifecycle proofs, but never names `output_contract` or `json_schema_v2`. A contributor cannot discover how the new profile setting changes request version, who constructs the schema, or why domain validation remains necessary. The modified Graph lifecycle proof explicitly selects the new mode and checks native `format`, which the training exercise also leaves unexplained.

Integrate one concrete extraction/rerank profile example into the existing projection/adapter discussion. Follow `Adapters.model/5` and `response_schema/2`, show that omitted selection keeps v1, and link to the generic model-call contract for native Ollama support and 8/12 KiB complete-request bounds. Explain the adapter's independent 4096-byte encoded task-input bound and complete-request preflight, plus the unchanged quote/attribution and exact-permutation checks. Amend the existing Graph lifecycle exercise to identify its structured-format assertion. Avoid adding a detached milestone summary.

#### Checks actually run

- Repeated the standalone frozen-source `extensions_model_call_test.exs` run. All 9 tests passed, including exact 12288-byte v2 admission and one byte above it.
- Independently reconstructed the 1700-quote extraction request in both modes. Inner input is 3448 bytes; v1 is 7848 bytes and v2 is 8460 bytes. Both validate and retain the supplied text exactly. Both refuse 2048 quotes at the unchanged inner-input bound.
- Constructed a v1 request of exactly 8192 bytes and a request of 8193 bytes with identical field lengths. The first validates and the second refuses.
- Compared domain `JSON.encode!/1` and host `Jason.encode!/1` on 13 escaping/Unicode cases used by the complete-request preflight. Encodings agreed.
- Reproduced the accepted wide-input/helper-context sizes in finding 1.
- Read all of `docs/developer/extension-model-calls.md`, `docs/developer/knowledge-extensions.md` and `examples/model-calls/README.md`, including source ownership, worked examples, limitations, recovery and verification instructions. Checked their 25 local links and heading anchors and parsed all 8 fenced JSON examples. No link or JSON failures.

Standalone probes are `/tmp/ipse-p27-review-a-probe.exs`, `/tmp/ipse-p27-review-a-r2-probe.exs` and `/tmp/ipse-p27-review-a-r2-doc-probe.exs`. They load existing dependency BEAMs and compile changed modules only in their own VM, without Mix compilation or repository artifacts.

#### Limits

Did not independently run the corrected full suite, installed proofs, live Ollama inference, another platform, or the exact-size Session integration test. Its new path was reviewed against the surrounding implementation. Root's future checks are not counted here. Manual findings describe the files read before the planned integration of their remaining structured-contract explanation. No private evaluation material, credentials or operator journals were accessed. No repository files were changed.


## review-b-corrective

#### Code verdict

No blocking finding in the corrected runtime delta. The original valid-source failure is repaired: the isolated current-source probe in `/tmp/ipse-p27-review-b-check.exs` produces a canonical 1700-quote chunk, an inner `input` of 3448 bytes, and a whole v2 request of 8460 bytes that `ModelCall.validate/1` now accepts. The unchanged v1 request is 7848 bytes and still validates. A second isolated probe (`/tmp/ipse-p27-review-b-preflight.exs`) shows a valid 1800-quote source with inner input 3648 bytes: the v1 adapter now refuses it as `invalid_adapter_input` before proposing a host call, while v2 emits a valid 8860-byte request. Thus the new adapter preflight covers the old 8 KiB limit and the new 12 KiB limit without shortening source text.

The larger v2 request fits the adjacent envelopes I traced: `Ipse.MCP.Schema.validate_object/1` bounds the SDK object at 16 KiB; `Ipse.Extensions.Worker` accepts a 32 KiB logical message assembled from at most 8 KiB physical frames; `Ipse.Extensions.Actions` bounds journal intent/result events at 64 KiB. The 12 KiB Session test exercises the real approval, HTTP wire body, and saved restore path. `JSON.encode!` (adapter preflight) and `Jason.encode!` (host limit) produced the same encoded byte count for ASCII controls, escapes, and sampled Unicode; the source files use the same map values, so I found no practical preflight discrepancy.

##### Verification consideration

The added `2048`-quotation extraction test reaches the preexisting *inner* 4096-byte input check before the new whole-request preflight. The new v1 preflight is reachable at `1800` quotations, where the inner input is 3648 bytes and the whole v1 request would be 8248 bytes. Add that case if the branch needs a direct regression assertion for the new preflight; the isolated probe above already demonstrates its behavior. This is a test-coverage suggestion, not a runtime blocker.

#### Operator manual integration

I read `docs/operator/graph.md`, `docs/operator/corpus.md`, and `docs/operator/research-extensions.md` as whole manuals. At this review snapshot, their runnable model profile selections still omit `output_contract`, so they exercise legacy version 1 even though the new structured route is available. Integrate `"output_contract": "json_schema_v2"` into each relevant model example only where the example explicitly selects native Ollama. Nearby task explanation should identify the generated extraction `facts` or rerank `order` schema, host validation before returning text, independent quote/span or permutation checks, model-egress approval, and refusal without automatic retry or provider switch. Graph's present statement that the model “must return only the closed fact schema” is instruction/domain-decoder guidance for its current v1 example; clarify when the host additionally enforces a declared schema. The existing input/output-byte guidance remains correct but should mention that the complete v2 request is bounded at 12 KiB, v1 at 8 KiB, and escaped source text can make either whole request refuse before model egress. Corpus and Research rerank procedures already explain short IDs and permutation refusal; avoid appending separate feature-status blocks rather than integrating the new option into those procedures.

No stale contradiction found in the remaining operator material I read. These are documentation integration items for the active authoring pass, not claims that the code is broken.

#### Scope and limits

Compared the corrected source against the earlier frozen patch and reviewed `ModelCall`, knowledge adapters/profiles/evidence, SDK and worker envelopes, action/result validation, Session approval, CLI approval rendering, and the focused new tests. Re-ran two public synthetic probes with standalone Elixir and existing dependency beams. I did not edit repository files or run Mix, the full suite, packaging, native inference, or private evaluation material. Root's reported focused Session test was read as source and trusted only as its stated run result; I did not independently rerun it. The original review remains in `/tmp/ipse-p27-structured-review-b.md` for provenance.


## review-a-manuals

### Developer documentation recheck

- Finding 1 resolved. The minimum-context fit guarantee is removed; helper request bounds and the service's context window now have distinct ownership.
- Finding 2 resolved. README source commands select default, `none`, `json`, and `json none`; installed commands select default, `none`, `json`, and `json-none`. These exactly match their respective parsers. The four-mode explanation preserves independent reasoning/output choices and synthetic-proof limitations.
- Finding 3 substantially resolved. The knowledge chapter integrates the profile opt-in, recipe/request version distinction, schema construction, full-request preflight, 8/12 KiB limits, native Ollama restriction and existing domain validation. The lifecycle exercise correctly describes the Graph `format` object, required `facts`, `maxItems: 1`, successful quota control and separate Corpus embedding route.

One small documentation remainder: beside the complete-request 8/12 KiB paragraph, state that Adapters independently limits its encoded task-input JSON to 4096 bytes before constructing the host request. The chapter currently omits this domain-specific byte limit, while its generic model-call link describes a 4096-character field limit. This was part of finding 3 and matters for the quote-heavy input correction.

Rechecked the changed passages in their previously reviewed whole-document context and reran the scoped link/example probe. All 26 local links/anchors and 9 JSON examples passed. No runtime tests, model calls, private evaluation access or repository edits in this recheck.


## review-b-manuals

#### Disposed

The three operator procedures now select `output_contract: "json_schema_v2"` in their runnable native Ollama model examples. Graph explains the generated `facts` schema, completed-usage retention, independent quotation/span checks, 12 KiB complete-request ceiling, refusal before an oversized call, and no repair or fallback. Corpus and Research explain the `order` schema, independent complete-permutation check, refusal, completed usage, and how omitting the option selects the legacy text contract for another provider. These changes are integrated beside the commands they qualify; my earlier substantive manual-integration findings are resolved.

I read the three manuals as whole documents in the previous pass and checked the current edits against their surrounding procedures and remaining cross-references. The root's `/tmp/ipse-p27-structured-manuals-c1/result.json` reports literal JSON extraction plus build/configure/import/real CLI selection passed for Graph, Corpus, and Research, with zero model or MCP calls. I did not rerun those commands.

#### Minor unresolved wording

- `docs/operator/graph.md` still describes the example as requiring a “local tool-capable model.” `ModelCall.execute/2` calls the provider with an empty tool list; tool capability is not a requirement for this extraction route. Remove “tool-capable” to avoid overstating setup needs.
- The Graph example correctly puts `"version": 1` beside `"output_contract": "json_schema_v2"`, while the prose refers to `model.complete` version 2. One sentence should explain that profile version 1 is Graph's domain-profile version and the output contract selects host request version 2. Otherwise a reader may change the profile's `version` to 2 and get a configuration refusal.

These are editorial polish items, not blockers for the structured-output behavior. The earlier 1800-quote v1 preflight test-coverage suggestion remains noted in `/tmp/ipse-p27-structured-review-b-r2.md`; the independent probe exercised that branch. No repository files, runtime, tests, or private evaluation data were touched in this pass.


## Lead dispositions

Act on the reproduced quote-heavy request failure. Version 1 retains 8 KiB; the new version-2 request allows 12 KiB within unchanged SDK bounds, and the adapter preflights complete encoded requests. The original 1700-quote case passes unchanged in both modes. The 1800-quote probe independently covers the v1 preflight branch. The latter is noted as a permanent-test coverage suggestion; the current frozen tests cover large ordinary input, the original escaping regression, inner-input refusal and exact 12 KiB live approval/wire/restore.

Act on the manual findings: remove the context-size guarantee, document all four proof modes, integrate domain opt-in and lifecycle/schema ownership, update operator examples, state the independent 4096-byte domain input bound, remove the tool-capable-model requirement, and distinguish Graph profile version 1 from host request version 2. Root inspected the resulting prose and verified the literal operator configurations through actual builders, generators, import and CLI config selection. Both corrective runtime reviews report no blocking finding.

No inference quality, exact memory comparison, engine selection or whole-P27 verdict follows from these scoped reviews.
