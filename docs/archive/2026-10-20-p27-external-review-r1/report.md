# Independent P27 review at `b9370fb`

- Target: `b9370fb61cff9131463baca201584e5d9470bc47` (`lexlapax/ipse`)
- Date: 2026-10-20
- Scope: read-only review. No repository history was modified or pushed. No saved real comparison was operated, no private predictions or references were opened, and no model work was replayed.

This is an independent review, not an acceptance record. **P27 remains open.**

## Method

- **Checkout:** a clean disposable clone in a session scratch directory, checked out at the exact target SHA. Companion `bbbaf6b` descends from the target and changes only `docs/`, so product code was reviewed at the target.
- **Review areas:** after reading `AGENTS.md`, the P27 plan section and the audience indexes, the work was split into five independent areas:
  1. the store layer;
  2. Corpus/Graph/Research domain logic;
  3. the generic host additions;
  4. evaluation and native measurement;
  5. the manuals.
- **Order of reading:** each reviewer formed findings before reading `docs/archive/2026-10-20-p27-whole-source-review/index.md`.
- **Checking:** the main session re-checked each finding below against source at the cited lines.
- **Probes:** these ran in separate copies, never in the review checkout. Each finding is labelled **OBSERVED** (reproduced by a probe) or **SOURCE INFERENCE**.
- **Prior dispositions:** none of the findings below appears among the internal review's dispositions.

## 1. Findings, most severe first

### F1. Medium-High: RRF fusion keys on the exact citation span, so the same chunk found by two retrievers is never fused (OBSERVED)

- **Where:**
  - `extensions/knowledge/src/evidence.ex:360-372` deduplicates and accumulates on `candidate_key/1`.
  - `evidence.ex:716-719` defines `span_key` to include `start_byte` and `end_byte`.
  - Callers: `corpus.ex:449-451` and `corpus.ex:476`.
- **Why the spans differ:**
  - Lexical windows start at the first matching token (`evidence.ex:690-706`).
  - Dense candidates start at the chunk start and are capped at 200 characters (`corpus.ex:576-582`).
  - Graph candidates carry the fact's own citation spans.
- **Trigger:** one chunk that both BM25 and cosine rank first.
- **Observed:** the pure-module probe returned the same chunk twice, at spans 0–84 and 40–84. Each scored `1/61` instead of one candidate at `2/61`. The other source scored `1/62`.
- **Consequence:**
  - Hybrid and lexical+graph fusion lose RRF's reinforcement.
  - Duplicates take up `top_k` slots and are sent to the reranker twice.
  - Any P27B hybrid-versus-lexical/dense comparison would measure a defective fuser.
  - No test covers overlapping candidates from different components.
- **Invariant broken:** correct fusion over chunk identity, and score identity for the comparison gates.
- **Minimal repair:**
  - Fuse on `{source_key, generation, content_sha256, chunk_id}`.
  - Keep the best-ranked component's span, or every contributing span.
  - Add an overlap regression test.
  - Make this fix before any held-out comparison.

### F2. Medium: Store can push an MCP partition past the 88-record snapshot ceiling, which then strands drafts and blocks forget, abort and inspect (OBSERVED)

- **Where:**
  - `store.ex:1905-1911`: `capacity/3` admits up to 256 records for every backend.
  - `store/mcp_cas.ex:244`: a full snapshot refuses once `ceil(rows/8) + 1 > 12`, which means more than 88 records.
  - Each paged `open` / `append` / `publish` re-snapshots and adds only 1–3 records, so the 256 check never stops it.
- **Trigger (v2 MCP fixture probe):**
  1. 15 puts bring the store to 75 records.
  2. `open` a 40 KiB source, then append.
  3. The append taking the store from 88 to 90 records is admitted, because 88 + 2 ≤ 256.
  4. The next `append`, `inspect`, and `forget` (with the correct revision) all return `remote_snapshot_limit`.
- **Consequence:**
  - The open draft is stranded. Its root stays busy and `abort` needs a full snapshot.
  - Suppression and forget become impossible through Ipse, which breaks the deletion-propagation acceptance.
  - The manuals describe the ceiling as an inherited condition for already-large stores, not one Store creates itself. The prior record covers only stores that start at 89 or more records.
- **Invariant broken:** explicit recovery and suppression remain available; Store does not create states it cannot read back.
- **Minimal repair:**
  - For `mcp_cas` profiles, refuse when `records + added > 88`.
  - Forget and abort add no records, so they stay possible at 88.
  - Add a regression: an append at 87–88 records is refused, then forget and abort succeed.

### F3. Medium: scoring trusts literal-integrity verdicts taken from the reviewer-supplied file (SOURCE INFERENCE, consistent with existing fixtures)

- **Where:**
  - `examples/knowledge/evaluation_runner.exs` `dispatch(:score)` (around lines 791–826) passes `reviews.json` to `EvaluationScore.score/4`.
  - `evaluation_score.exs:544-553` (`integrity_receipt`) accepts any row that has `independent: true` and a verdict other than `unmeasured`. It forces `invalid` only for a foreign project.
  - `metrics.exs:284` counts a citation as supported when integrity is `valid` and the semantic verdict is `supported`.
  - `source-bytes-v1` rows are computed only at review-packet time (`evaluation_review.exs:91-101`). They are not recomputed or hash-bound at score time.
- **Trigger:** a reviewer, or anyone who edits `reviews.json`, changes a `source-bytes-v1` row from `invalid` to `valid` for a quote that is not in the corpus, and marks the citation supported.
- **Existing fixture:** `test/knowledge_evaluation_score_test.exs` (around lines 133–150 and 389–398) already passes gates using integrity rows from a caller-named checker with no corpus.
- **Consequence:**
  - The byte-level integrity check, documented as independent of semantic judgment, can be overridden by the semantic review channel.
  - Citation precision and span credit can be inflated toward the 0.95 gate.
  - An incomplete `reference_integrity_complete` is reported but not enforced.
- **Invariant broken:** literal integrity must stay separate from, and independent of, semantic verdicts.
- **Minimal repair:**
  - At score time, after the prediction-hash and review-binding checks, load the verified corpus. The corpus is not a label, so hash-before-label ordering is preserved.
  - Recompute `source-bytes-v1` and require the supplied rows to equal it exactly, or replace them.
  - Optionally, report gates as unmeasured when reference integrity is incomplete.

### F4. Medium: graph extraction advertises up to 32 facts, but Store admits only 2 (State) or 1 (MCP) (OBSERVED)

- **Where the bound is advertised:**
  - `graph.ex:87` and `graph.ex:336`;
  - the model prompt's `max_facts` (`adapters.ex:399-409`);
  - `docs/operator/graph.md` ("at most 32 facts").
- **Why it can't be reached:** `store.ex:931` reserves `div(max_items*12000+2047, 2048) + 1` pages. Each page is a write, and `effect_plan` (`store.ex:1918`) caps writes at 16.
- **Observed** (`projection_open`, facts projection):

  | Store | `max_items` | Result |
  | --- | --- | --- |
  | State | 1 | ok, 10 effects |
  | State | 2 | ok, 16 effects |
  | State | 3 and 8 | `effect_limit` |
  | State | 32 | `store_byte_limit` |
  | MCP | 1 | ok |
  | MCP | 2 and above | `effect_limit` |

- **Consequence:** the documented bound can never be reached. Model extraction commits at most 1–2 facts, and callers get a fail-closed but misleading refusal.
- **Minimal repair (either):**
  - Reserve from the actual encoded size for explicit facts, which are known before open, and keep the worst case only for model extraction.
  - Or narrow the schema, validation, prompt and docs to the bound Store can admit.

### F5. Medium: some valid stored sources cannot be exported, and `limit` is ignored (OBSERVED, State and MCP)

- **Where:**
  - `store.ex:1683` slices 4096 *raw* bytes.
  - `store.ex:1689` repeats the full text in the single-part form.
  - `store.ex:1698` requires the JSON encoding to be at most 12,000 bytes.
  - `export_source` never reads `args["limit"]`, although argument validation requires it in 1..4.
  - Page writing uses the encoded-size-aware `fitting_prefix`, so these sources store successfully.
- **Trigger:** each of these stores fine, then export returns `export_bounds`:
  - a 3,990-byte JSONL source;
  - 4,096 bytes of `"a\n"`;
  - 3,000 quote characters;
  - 6,000 control bytes (about 6× JSON escaping).
- **Consequence:** the documented export/migration path fails permanently for valid sources, with no smaller-page fallback.
- **Invariant broken:** a bounded export can page every stored source.
- **Minimal repair:**
  - Size each part by encoded length, as `fitting_prefix` does.
  - Emit the duplicated single-part form only when it fits.
  - Honour `limit` or remove it from the accepted arguments.

### F6. Low-Medium: the Corpus graph/hybrid seed can come from ineligible facts and matches substrings (SOURCE INFERENCE)

- **Where:** `corpus.ex:639-645`. `graph_seed` takes the alphabetically first subject that is a case-insensitive substring of the query.
- **Candidate pool:** `all_facts(snapshot)` includes facts from expired, future-observed and historical sources, and facts outside their validity interval. This is because `selected()` loads projections for every active root (`store.ex:1393-1397`).
- **Substring match:** "lease" matches "Release".
- **Consequence:**
  - An ineligible or partial entity can become the seed.
  - Traversal then reports a complete, empty graph component, silently leaving out current graph evidence.
  - The seed is not reported in coverage.
- **Invariant broken:** temporal eligibility applied before selection, and honest completeness.
- **Minimal repair:**
  - Seed only from `validate_facts` output at `as_of_ms`.
  - Use the longest token-boundary match.
  - Record the seed in coverage.

### F7. Low: a paid embedding can be dispatched although its receipt cannot fit `journal.max_record_bytes`; the journal then seals (OBSERVED)

- **Where:**
  - The embedding begin path in `lib/ipse/session.ex` (around 1411–1451) checks provider, approval and budget, but not record capacity.
  - Completion appends the vector-bearing `extension_effect_result` through `account/2` (around 4195).
  - `Journal.Writer.append_record` (`writer.ex:196-199`) seals when the record exceeds the limit.
  - By contrast, SDK-2 publication reserves capacity before work (`session.ex:969-974`).
- **Trigger:** `journal.max_record_bytes = 65536`, then an approved `embedding.create` of 4×4096 dimensions.
- **Observed:** one HTTP request was made. The journal tail ends `request_usage_observed, journal_limit_reached`, with no completion record. Resume returns `{:error, :journal_limit_reached}`.
- **What is preserved:**
  - Sealing is documented and nothing is replayed.
  - Usage is observed and the budget is settled.
- **Consequence:** a billed effect is admitted although its receipt size is known in advance (inputs × dimensions) and cannot be recorded.
- **Minimal repair (either):**
  - Refuse before approval or egress when the maximum source and completion records exceed `max_record_bytes`.
  - Or reserve capacity as publication does.
- MCP `mcp.text` sources near a 64 KiB limit follow the same path; this part is source inference.

### F8. Low: the owned-listener check misses an IPv6 wildcard listener on the same port (OBSERVED)

- **Where:** `native/ipse-listener.rs:85-98` reads only `/proc/self/net/tcp`. `native/README.md` (around 626–628) says wildcard bindings refuse.
- **Trigger:** the direct child binds `127.0.0.1:P` and also `[::]:P` with `IPV6_V6ONLY`.
- **Observed:** the probe, built around the unchanged source, printed `ADMITTED`. `ss` showed both listeners.
- **Consequence:** a service described as loopback-only is admitted while reachable on every IPv6 interface. IPv4 ownership proof is unaffected.
- **Minimal repair:** also parse `/proc/self/net/tcp6` with the same bounds and refuse any listening row on port P. Or narrow the documentation to IPv4.

### F9. Low: profile validation accepts unused MCP authority that the docs say it rejects (OBSERVED for validation; the grant is SOURCE INFERENCE)

- **Accepted by `Profiles.validate`:**
  - `graph/mcp-explicit` with an `mcp_query` retrieval profile. Graph never reads retrieval profiles.
  - `research/mcp` with an `mcp_query` retrieval profile. Research refuses anything except bm25 (`research.ex:62`).
- **Effect:** `spec.exs:117-161` then requires and writes that binding alias into trust `mcp_bindings`.
- **Docs that claim otherwise:** `extensions/knowledge/README.md:70`, `graph.md` and `research-extensions.md` say "rejects unused authority".
- **Severity:** the authority is inert, because package code is fixed, but the documented property is false.
- **Repair:** restrict retrieval kinds per package (Graph none, Research bm25 only).

### F10. Low: smaller domain issues (observed where stated)

- **(a) Negative fact gives a complete abstain (observed).** A current negative assertion about the queried entity yields a complete `abstain` with no evidence (`evidence.ex:637-643`, `564-576`). This matches the documented traversal rule but invites a reader to conclude nothing is asserted. Expose such negatives as context claims, or count them in coverage.
- **(b) Lexical window can miss the matched term (observed).** The window can fail to contain the term when downcasing changes token boundaries, for example `İ` (`evidence.ex:690-698` against `749`). The citation falls back to bytes 0–1024. Compute offsets from the scoring tokenization.
- **(c) Hybrid failures mislabelled (source inference).** In hybrid, a lexical or graph failure is reported as `missing_embedding` (`corpus.ex:492-495`).
- **(d) Self-comparing hash check (source inference).** `adapters.ex:136-138` compares hashes computed from the same input, so it always passes. Binding vectors to inputs relies on host checks. Remove the check or make it meaningful.
- **(e) Wrong error at the time boundary (source inference).** Research computes `remaining_ms` twice (`research.ex:297/310`, `333/341`). At the 1000 ms boundary this can produce `invalid_adapter_input` instead of `time_limit`.

### F11. Low: definite State quota refusals are reported as `unknown` (SOURCE INFERENCE, pre-existing)

- **Where:** `lib/ipse/extensions/state.ex:190-194,317` returns `:extension_state_quota`, which `lib/ipse/extensions/host.ex:334` maps to `unknown`.
- **Effect:** Store stops with an unknown effect. This is safe, since nothing is replayed, but imprecise. It is reachable near 1 MiB because Store's estimate (Elixir `JSON`) and the host's size check (`Jason`) can differ.
- **Repair:** map pre-write refusals to `failed` with a code.

### F12. Informational: Session live admission is looser than restore while a saved-output drain is open (SOURCE INFERENCE, not currently reachable)

- **Where:**
  - These handlers match `extension_action: nil` but not `extension_output: nil`: `extension_action_begin`, `extension_mcp_prepare` / `_bound`, and `extension_tool_context_commit` (`session.ex` around 1102–1201).
  - `ResultSource.restore_event` rejects an action intent while a producer is open (`result_source.ex:609-617`).
- **Why it is unreachable today:** Worker and Bootstrap already refuse all stages while a producer is open.
- **Repair:** match `extension_output: nil` in those heads, so live admission and restore agree.

### Documentation findings

- **D1 (Medium): the P27 status in `docs/plan.md` is stale and internally inconsistent.**
  - `plan.md:73-75` and the table row at `:81` still say P27 is "resuming from its preserved continuation". The detailed section names Linux confirmation, external review and quality/resource acceptance as next steps.
  - `plan.md:548-549` calls the resource-join and review-binding corrections "pending", but they are committed as `62aac9c`, the target's parent. `docs/archive/2026-10-20-p27-native-fixture-identity/index.md:49` still calls them "uncommitted".
  - `plan.md:557-559` reports "the corrected working increment" passing 1,324 tests without naming a SHA.
  - The `25f1d8e` / `21d710c` / `75b7077` hosted-run paragraph comes after later events, out of chronological order.
  - Repair: name commits and their verification, update the status row, and put the narrative in order.
- **D2 (Medium): the implemented `mcp_query` / `query-v1` remote retrieval route is undocumented.**
  - It is implemented in `profiles.ex:161-164`, `corpus.ex:95-109` and `adapters.ex:267-283,554`, and exercised by `mcp-proof.exs`.
  - `operator/corpus.md:401-402` and `developer/knowledge-extensions.md:582` mention a "selected remote query" without giving its profile, the partition rule or the wire contract.
  - Repair: add an options example and a closed `query-v1` contract.
- **D3 (Low): the remote CAS server contract is only partly specified.**
  - The developer manual omits:
    - the `snapshot`, `get_many`, `put_immutable_many` and `collect` arguments;
    - the closed reply envelope;
    - the directory limits (256 rows, 1 MiB, kinds);
    - the 60,000-byte text limit (`mcp_cas.ex:66`).
  - `corpus.md` links to no specification.
  - Repair: add an action/envelope table, or name `test/support/knowledge_mcp_fixture.exs` as the reference.
- **D4 (Low): the operator manual doesn't say snapshots consume effects.**
  - A full snapshot uses `1 + ceil(records/8)` of the 16 effects, so a large partition hits `effect_limit` before `remote_snapshot_limit`.
  - The developer manual says so; `corpus.md:405-414` does not.
- **D5 (Low): smaller documentation gaps.**
  - `corpus.md:239-241` omits that MCP indexing takes exactly one chunk (`corpus.ex:647-648`).
  - `dependencies.md:79` omits `native/ipse-environment.rs`; this predates P27.
  - `operator/mcp.md:258-260` points research retrieval only at the native `research.md`.
  - `native/README.md:95` has the typo "exits with1".

## 2. Architecture assessment

### Ownership and the extension/core boundary

The boundary holds:
- A grep found no Corpus, Graph, rerank or BM25 logic in `lib/`.
- The host additions are generic, closed-schema, and validated in several layers (Worker, Host task, Session, pure restore):
  - result source/view/document/publication;
  - mixed read/effect grants;
  - MCP action binding;
  - typed embeddings;
  - conditional State put.
- Domain modules remain absent from the host VM in the source and installed proofs.

### Store

The design is sound:
- **Content-addressed pages:** page keys bind partition, source, generation, draft, kind, ordinal and body hash.
- **Publication:** claim, then immutable staging, then a final CAS.
- **Suppression:** permanent. Import generation ordering and root tombstones prevent resurrection.
- **Collect:** protects pages reachable from roots and live drafts, and rechecks roots before deleting.
- **Unknown outcomes:** always stop and never retry.
- **v1/v2 cutover:** behaves as documented. v1 refuses missing-root creation with `atomic_admission_unavailable` before dispatch, while reads and updates keep envelope version 1.

The main structural weakness is that capacity is spread over independent per-backend constants (256 records, 88 snapshot records, 16 effects, 12,000-byte views, 1 MiB). F2, F4 and F5 all come from these bounds disagreeing. A single per-profile capacity model checked at admission would remove the whole class.

### Domain core

- **What is strong:** `Evidence` is a pure core behind closed adapters, with rigorous identity, attribution and fail-closed bounds:
  - BM25 with k1 = 1.2 and b = 0.75;
  - float32 canonicalization and finiteness checks;
  - rerank permutation binding;
  - time-qualified facts;
  - compatible positive facts not treated as conflicts;
  - the separation of exclusion and failure.
- **Where the weaknesses are:** they are algorithmic, not safety problems:
  - fusion at the wrong granularity (F1);
  - eligibility ignored when choosing the seed (F6);
  - the reservation that overrides the extraction bound (F4).
- **Why it matters now:** F1 and F6 bear directly on the open P27B quality and engine-selection gates.

### Host lifecycle

- **SDK-2 publication:**
  - Re-verified chunk by chunk, with exact journal reservations.
  - `output_id` is bound to the intent digest, byte count and SHA-256.
  - The seal is re-derived from the Session's own state.
- **MCP actions:** journal intent before dispatch, deny children twice, re-check descriptor digests and turn post-dispatch loss into `unknown`.
- **Embeddings:** bind execution and destination to the approved selection and record admission before egress.
- **Gaps:** the only admission inconsistencies found are F7 and F12.

### Evaluation and native measurement

No defect was found in:
- frozen source, runtime, data and model identity (`verify_v2`);
- one-shot exclusivity (`mkdir`, `create_new`, native root, stage claims);
- the three memory subjects (fresh `clone3` with `CLONE_INTO_CGROUP` per stage; parent interval via a per-descriptor `memory.peak` reset);
- the strict 2,000 ms natural tail, which agrees between Rust and Elixir;
- authority re-checks after completion;
- late-output handling (EOF only after the population is empty);
- descriptor hygiene;
- file-copy identity checks;
- hash-before-label ordering;
- the six-stream audit re-join.

The Linux memcg backend is used only by the measured entry point. Ordinary operation does not need it. F3 is the one evaluation-architecture defect. Engine-selection logic does not exist yet, so it could not be reviewed.

### Compatibility

- Existing storage formats and v1 reads/updates are preserved.
- Legacy grants keep their original limits; the mixed allowance (512/16/528) applies only to `host.actions.mixed`.
- Resume refuses a changed `embedding_profiles` snapshot, which protects older sessions.

## 3. Acceptance assessment

| Acceptance item | Status | Basis |
| --- | --- | --- |
| P27H1–H4 generic host contracts | **Satisfied for protocol scope** | Code review, focused tests, full suite here, hosted run `39440053471` green on Ubuntu and macOS for the exact SHA. Caveats: F7, F12 |
| Named pluggable search/fetch/store/retrieval/embedding/rerank profiles | **Mostly satisfied** | `profiles.ex`. Unused-authority rejection is overstated (F9); `mcp_query` is undocumented (D2) |
| Source/chunk/version/citation identity | **Satisfied** | Content-addressed pages, chunk IDs, span re-validation |
| Bounded ingestion/traversal/retrieval | **Satisfied as fail-closed**, with **inconsistent bounds** | F2, F4, F5 |
| Lexical operation without mandatory embeddings | **Satisfied** | `state-lexical`, credential-free demo and proofs |
| Deletion propagation and stale-index policy | **Partially open** | Sound by design; F2 can make forget unreachable on MCP stores |
| Contradictory/stale/weak evidence | **Mostly satisfied** | Polarity and exclusion handling; F6, F10a, F10b weaken completeness and evidence quality |
| Partial failures, cancellation, budgets, no automatic replay | **Satisfied** | Unknown outcomes stop; budget admission; owned cancellation |
| Hybrid/graph/rerank matched comparisons and engine selection | **Open** | Not run for this target. F1 must be fixed first. Selection logic is absent |
| Frozen held-out quality evaluation | **Open** | The 350-row comparison is on older source `914bc0a`, its semantic review is still in progress, and it does not cover this target. Reused inputs are not an untouched held-out workload |
| Exact workload-charged memory/resource comparison | **Open** | Collector architecture reviewed with no defect found. No real measured run on this target. Collectors were not run under real cgroups here |
| Independent semantic judgment and scoring | **Open; architecture defect F3** | Review binding and ordering sound; integrity is not recomputed at score time |
| Linux confirmation of the target | **Satisfied by this review** | Full source suite passed on Arch Linux (below). Native sandbox, package and installed proofs were not rerun here; hosted Ubuntu covers them |
| Coherent manuals | **Mostly satisfied** | Operator and developer chapters are task- and training-oriented; examples validated. D1–D5 remain |
| Independent external review | **Supplied by this report** | Findings above must be dispositioned before completion |

**Unsupported claims:**
- None of the evidence establishes semantic quality, model quality or exact memory peaks for `b9370fb`.
- The fixture counts and the 350-row record must not be read as completion evidence.

## 4. Commands, platform and outcomes

**Platform:** Arch Linux x86_64, kernel 7.2.9-arch1-1; Elixir 1.20.4 on Erlang/OTP 29; cargo/rustc 1.99.0. Isolated `MIX_HOME`/`HEX_HOME` copies; demo ran with a temporary `HOME`.

The main baseline ran in the review checkout at `b9370fb`:

```sh
./scripts/build.sh                  # rc=0
mix format --check-formatted        # rc=0
mix compile --warnings-as-errors    # rc=0
mix test                            # rc=0 — 1346 passed, 36 excluded, 0 failures, 0 skipped (764.3 s)
HOME=$(mktemp -d) ./bin/ipse demo   # rc=0, "Demo finished"
elixir scripts/check-docs.exs       # rc=0 — 271 files, 2875 links, 0 errors
```

The test log contains expected crash/exit traces, for example under `extensions_invocation_test.exs:1508`. None is a failure.

**Separate copies:**
- **Host tests:** result document/publication/source/view, journal reservations and effect-result tests: 74 passed.
- **Host probe:** the F7 embedding-record test.
- **Store probes:** snapshot ceiling (F2) and export (F5), using the in-repo MCP CAS fixture.
- **Domain probes:** pure-module probes for F1, F4, F9, F10a and F10b.
- **Native:** rustc unit tests for `ipse-listener`, `ipse-file-copy`, `ipse-sequence` and `ipse-bound` (pass), plus the IPv6 listener probe (F8).
- **Docs:** built the `corpus mcp-lexical` (v2), `research mcp-model` and `corpus state-semantic` artifacts from the manual examples. Generate, import and `ipse config` all exited 0.

**Remote:**
- `gh run view 39440053471`: `headSha = b9370fb…`, conclusion `success`, both `test (ubuntu-latest)` and `test (macos-14)` succeeded.
- `bbbaf6b` was confirmed to be a docs-only descendant of the target.

**Not run (limits):**
- `./scripts/package.sh` and the extracted-package proofs.
- Native-sandbox-enabled suite tags, among the 36 excluded tests.
- `ipse-measure` / `ipse-sequence` collectors under real cgroups, which would need `systemd-run --user` or cgroup changes.
- Real MCP stdio/HTTP servers beyond the in-repo fixtures.
- Live Ollama or paid inference.
- Interactive `/ext` chat walkthroughs.
- macOS.
- Real comparison artifacts, predictions and references (out of scope by instruction).

**Residual uncertainty:**
- Store export/import and collect were reviewed only in the store pass, not cross-checked by the domain pass.
- MCP server-process cleanup after `MCPCall.bounded` brutal-kills its task was not traced end to end.
- The severities of F9 and F10a depend on design intent the docs only partly state.
