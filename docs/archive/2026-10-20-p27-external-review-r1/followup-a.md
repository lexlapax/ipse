# Independent P27 R1 follow-up review A

No additional actionable finding was established in this follow-up. Both accepted internal defects are repaired in the reviewed source. This does not complete P27 acceptance or establish model quality, resource comparisons or engine selection.

This review follows `/tmp/ipse-p27-r1-independent-a.md`. I read the updated brief, graph-capacity design and implementation reports, then independently checked their claims against the current source, Store ownership rules, callers, maintained controls and my original probe. No source or Git mutation was made and I did not confer with the other independent reviewer.

## Reviewed identity

I decoded `/tmp/ipse-p27-r1-final-source-before.json` and recomputed SHA-256 for all 460 listed files. All matched. The check ran during this follow-up and reported zero mismatches. This binds the reviewed runtime/test sources to that inventory; it is not a platform or release receipt.

## Graph population and context repair

### The original failure is gone

I reran the unchanged original independent probe, including its suppression recovery control:

```sh
elixir /tmp/ipse-p27-independent-a-probe/graph_total.exs
```

The new output is `/tmp/ipse-p27-followup-a/original-probe.log`. I preserved the original negative log.

The ninth source now returns:

```text
%{status: "ok", records: 144, sources: 9, facts: 261, gaps: []}
%{records: 144, after_forget: "ok", query_status: "ok"}
```

The same query formerly refused at 261 facts despite its entity having only 29 facts. No narrower extraction, changed fixture input, extra grant or storage allowance was needed.

### The population ceiling has a sound Store-derived bound

`Evidence` now distinguishes `@max_query_fact_rows = 256 * 32` from `@max_claim_context = 256`.

I checked the ownership assumptions behind the multiplication:

- Store admits at most 256 retained records for a State snapshot. MCP's full-snapshot limit is smaller. Roots, body pages, vector records, tombstones and orphan pages consume that same physical allowance.
- Each selected fact manifest's decoded record has at most 32 facts, enforced by `Store.load_projection_items/5`.
- `Store.load_page/6` verifies partition, source key, source generation, page kind, immutable record identity and its reference hash. A manifest cannot be used as a valid projection for another source/generation.
- `Store.load_projections/2` derives each valid head key from the manifest's fixed kind/profile. The projection map cannot contain two valid heads with that same key.
- `Store.load_projection/5` requires every predecessor's profile to equal the head's profile and rejects repeated manifest keys. Two different valid profile heads cannot count one fixed-profile manifest twice; a repeated manifest within one chain fails its cycle check.
- Thus each distinct selected manifest contributes at most 32 rows once. The 8192 ceiling is conservative and follows from existing persisted bounds. It is not an assertion that 8192 distinct facts fit a physical store.

The per-head 256-fact check, eight-head/root bound, 32-source bound, encoded snapshot limit, ordinary SDK request bounds and physical record limits remain in place. A fixed-profile chain's fact deduplication can only reduce the row count. Shared fact body pages do not invalidate the argument because every distinct manifest still consumes a retained record.

### All attribution is checked before selecting relevant context

`Evidence.validate_facts/3` still validates every input fact's closed shape and identity, then checks source generation/hash, literal span and temporal eligibility. The larger population guard does not introduce a subject-first filtering path. Its prepend/reverse accumulation preserves fact/gap order while avoiding the prior repeated list append.

`graph_seed/4` receives the complete validated population. `traverse/5` independently validates before walking. The duplication remains bounded and is unchanged in ownership; it does not let an invalid unrelated assertion choose a seed or escape canonical validation.

The selected path remains bounded by depth/nodes/edges. `claim_context/3` then gathers every selected assertion plus eligible negative assertions on reached subjects and counterassertions conflicting with selected facts. It checks the complete context before evidence construction and classification. Context 257 returns `{:error, :graph_context_limit}`. It does not retain the first 256, strip a contradiction basis or pattern-match a classifier failure.

Graph and Corpus graph preserve that named refusal. Corpus hybrid propagates it from `hybrid_graph/1` through `rank_semantic/1`; its missing-embedding policy does not turn a graph-context failure into a lexical success. Refused results contain no successful claims/evidence. Complete result publication remains subject to its original 4 MiB aggregate limit, so a legal 256-fact context is not a promise that every combination of maximum-sized bases can be published.

## Completed Research capture repair

`Research.next_fetch/1` now sends an empty remaining queue directly to ranking. The remaining-time check still gates a queued next fetch. Ranking still gates a selected rerank before proposing that model action.

Consequences checked against the complete paths:

- An empty complete search with no rerank can return complete abstention even when less than 1000 ms remains. It does not fabricate a fetch or claim unfinished source work.
- A valid final captured source retains its checked body hash, exact citation and source-count/byte coverage without requiring time for a nonexistent next fetch.
- A queue with another hit still returns `time_limit` below 1000 ms.
- A selected rerank still needs its remaining allowance. Completing capture does not authorize an extra model call after the guard fails.
- Unknown, denied, invalid JSON/hash and invalid-source paths retain their existing refusal behavior. The change only removes the irrelevant next-fetch gate after capture is complete.

The amended tests distinguish the generated clock-controlled module used for exact 999/1000/1001 decisions from the unmodified Research module used for the completed-capture controls. They do not present generated-clock tests as production-clock execution.

## Independent checks actually run

Ran only these bounded checks, in separate VMs while root retained the broad platform jobs:

1. Recomputed all 460 final-inventory source hashes, zero mismatches.
2. Reran the original independent Graph probe, which now succeeds with 261 facts at 144 retained records.
3. Ran:

   ```sh
   elixir -pa '_build/test/lib/*/ebin' \
     -r test/test_helper.exs \
     -r test/knowledge_graph_population_test.exs \
     -r test/knowledge_domain_regressions_test.exs -e ''
   ```

   Passed both outer isolated suites in 10.4 seconds. Output is `/tmp/ipse-p27-followup-a/focused.log`.

The isolated suites cover all three query routes, 261 facts, exact 29-claim bases, expiry, a cross-source counterassertion and both conflict labels, invalid manifest sharing, relevant context 256/257, negative context beyond a one-edge path, invalid unrelated spans despite expiry, and the finite 8192/8193 input guard. The Research suite covers completed empty search, complete final capture, queued-fetch refusal and the exact clock decisions. I read the assertions rather than treating test success alone as proof of the intended semantics.

## Wider effects and documentation

The repair stays in domain query behavior. It adds no host operation, service, inference route, effect/read allowance, storage format or replay path. Root revalidation still precedes a successful Graph/Corpus response; early graph-context refusal publishes no positive result. Suppression remains permanent and affects subsequent queries; it does not rewrite historical results.

I rechecked the current operator Graph/Corpus and Research limit paragraphs and developer population/ownership explanation against the implementation. They distinguish stored population from relevant context, specify `graph_context_limit`, preserve full bases and explain completed capture without a next-fetch allowance. I found no new mismatch in those changed explanations.

The listener causal-reversion change and v3 fixture correction affect verification, not runtime semantics. My earlier F12 assessment remains unchanged: Worker blocks new action production while output is open; no reachable public bypass was established. The host/evaluator findings and limitations in the first report remain the context for this follow-up, rather than being represented as freshly rerun platform acceptance.

## Coverage limits

No broad Mix build/test job, packaging, installed-runtime proof, native Linux/cgroup/listener run, live CAS service, live Ollama, paid inference or private benchmark/scoring artifact was used. The public domain callback tests use the maintained synthetic host fixture; their embedding responses are fixtures and establish no semantic quality. The 8192 boundary test uses repeated valid fact rows to exercise the finite validator guard, not a claim of an attainable 8192-fact physical corpus.

This follow-up verifies the accepted repairs and their immediate whole-P27 ownership consequences. It does not replace a fresh audit of every unchanged native/model-service helper or a complete manual command walkthrough. The historical 350-row negative result, corrected-source held-out quality, matched charged-memory evidence, final platform checks and engine selection retain their existing open status.
