# Independent whole-P27 review A

Reviewed working tree based on `beb9009cd0ba286aa45931a0082270f4e5eb0506`, including the uncommitted R1 runtime changes and the three named untracked implementation/test files. The prior external runtime baseline is `b9370fb`. This is a read-only review, not acceptance. P27 remains incomplete.

I found one additional actionable correctness defect. No critical defect was established. I did not confer with the other independent reviewer.

## P2 / medium: unrelated stored facts eventually disable every graph query

**Locations**

- `extensions/knowledge/src/evidence.ex:425-427`: `validate_facts/3` refuses a list longer than 256 before checking relevance or eligibility.
- `extensions/knowledge/src/store.ex:1616-1627` and `:1651-1655`: Store concatenates projections and permits up to 256 facts in each individual projection chain. There is no equivalent 256-fact partition-wide admission condition.
- `extensions/knowledge/src/graph.ex:187-203`: Graph flattens every selected source's facts into one list and passes that entire list to `Evidence.traverse/5`.
- `extensions/knowledge/src/graph.ex:216-217`: the failed validation becomes `refused / invalid_evidence`.
- `extensions/knowledge/src/corpus.ex:642-646`: Corpus graph/hybrid seed selection uses the same flattened list and validator, so those strategies also inherit the failure. That consequence is source inference; the direct Graph failure was reproduced.

**Execution path**

Ordinary successful `source put` and `extract` invocations can publish more than 256 facts across sources while remaining well inside the storage, source-count, per-invocation fact, SDK input and effect bounds. A subsequent query for an entity whose own component is small fails because facts about unrelated entities count against the validator's global 256 ceiling.

This is a persistent availability failure after supported writes. The stored bytes remain valid. Increasing the query's traversal allowance cannot repair it because the failure occurs before traversal. Expired and otherwise excluded facts also count before eligibility filtering, so those can contribute to the same condition.

**Observed fixture evidence**

The self-contained probe is `/tmp/ipse-p27-independent-a-probe/graph_total.exs`. Its successful log is `/tmp/ipse-p27-independent-a-probe/graph_total.log`.

It loads the current domain source in a separate Elixir VM and uses the repository's existing synthetic State host fixture. Every operation enters Graph through `handle("invoke.command", ...)`; every command argument object passes `Ipse.Extension.validate/1`. The probe handles both inline values and complete result-publication values. It does not call a model, socket or external service.

1. Publish nine one-byte sources, with distinct IDs and entities.
2. For each source, publish 29 distinct attributed facts in four explicit batches of at most eight facts. Each batch fits the ordinary 16 KiB SDK input bound. Every source write and extraction succeeds.
3. After each source, query `entity1` with depth one and `top_k: 1`. Its own component always contains only 29 facts.
4. The first eight queries succeed. After the ninth source, the query refuses.
5. Explicitly suppress source nine and repeat the same query. It succeeds again without changing or collecting the retained record slots.

Observed final rows:

```text
%{status: "ok", records: 128, sources: 8, facts: 232, gaps: []}
%{status: "refused", records: 144, sources: 9, facts: 261,
  gaps: [%{"code" => "invalid_evidence"}]}
%{records: 144, after_forget: "ok", query_status: "ok"}
```

The probe is domain/adapter evidence, not a fresh real Session/native State integration run. Its successful public callback path establishes the domain count mismatch; the repository's existing State owner has capacity for these 144 records.

**Minimal bounded repair**

Keep full structural, attribution and temporal validation for the stored population. Separate that validation from the query's selected graph/context bounds. Validate the bounded Store population in source/projection batches, then build a validated adjacency/index representation for traversal and seed selection. Apply explicit limits to the reached edges and the complete supporting/counterassertion context for the query. Return a named query-context refusal if that relevant context exceeds its bound.

The important property is that unrelated published facts do not poison a small entity query. Do not fix this by dropping contradictory bases, silently truncating the fact population, narrowing the 32-fact extraction interface or allowing unvalidated facts to choose a seed. Keep the bounded population policy explicit and shared between Graph and Corpus graph/hybrid callers.

Regression coverage should retain the successful nine-source scenario above, an expired unrelated population, and a relevant component whose full counterassertion context exceeds the chosen query bound. Check the direct Graph path and Corpus graph/hybrid path.

## Architecture and repair assessment

The domain/host boundary remains appropriate. Retrieval, graph semantics and retained-source lifecycle stay in the independently built extension. The host owns generic effects, approvals, canonical accounting and result publication. Profile validation restricts Graph to store/extraction families and Research to BM25 retrieval; operator-bound services remain configurable.

I traced the R1 repairs in context, rather than treating their handoff reports as proof:

- Fusion now accumulates by chunk/namespace identity while retaining an exact representative span. Claim bases stay separate from the representative citation.
- Eligible graph seeding, negative context and original Unicode token offsets have concrete owners in Evidence. Research samples the remaining duration once before fetch/rerank dispatch.
- Store's v3 selection, atomic remote capacity requirement, actual packed-batch effect accounting, explicit-fact preparation and encoded export fitting address the reported admission disagreements. The qualified remote service must enforce the atomic contract itself, as the manuals now state.
- EffectCapacity sizes complete canonical records, including repeated action bindings. Session checks before action approval and again before embedding inference admission. This is a per-record preflight. It does not reserve aggregate journal events/bytes, and the manuals retain that limitation.
- Scoring recomputes literal integrity from corpus bytes after verifying predictions and the review binding. Runner reloads the declared corpus member and verifies its member hash; the scorer validates document hashes. Reviewer-provided integrity flags cannot override the recomputed rows. Invalid reference spans refuse scoring.
- The owned-listener repair reads both IPv6 and IPv4 tables and refuses a same-port IPv6 listener. This review did not execute its Linux path.

The remaining count mismatch is another instance of capacity policy living at incompatible aggregation levels. The useful simplification is a validated bounded graph population with one clear query-context selection owner. Adding a second global count check to Graph and Corpus would duplicate policy and preserve the availability defect.

## F12 assessment

I found no reachable extension-public path that starts an action while output publication is open. Worker permits only `result.output` while `producer` is set (`lib/ipse/extensions/worker.ex:146-150`). Session's caller/job checks also bind admission to its active task. The looser live Session heads remain defense-in-depth work unless a caller can bypass that protocol owner. I do not classify F12 as a demonstrated runtime defect.

## Documentation and acceptance

I inspected the stable operator Corpus, Graph and Research chapters and developer knowledge-extension/evaluation guidance, concentrating on current ownership, explicit bounds, v3 cutover, source migration, complete results and corpus-backed scoring. These now explain the repaired behavior and distinguish fixture checks from semantic quality. They do not describe the aggregate fact-query limit that produces the finding above. No documentation-only mismatch is promoted to a second defect here.

The known missing corrected-source quality, matched resource evidence, final platform/installed checks and engine selection remain open acceptance work. The historical 350-row run remains negative diagnostic evidence. I did not treat those known gaps as new code defects or operate any saved real comparison.

## Verification and coverage limits

Actually run:

- Git status/diff inspection and targeted source reads of the domain packages, Store/adapters, effect lifecycle, State quota response, listener repair and evaluator identity/review/resource paths.
- The bounded direct Elixir fixture probe above, including the suppression recovery control. The first scratch version lacked handling for complete ResultPublication output; I corrected the scratch driver and reran. That initial driver exception is not a product failure.

Not run:

- Broad Mix build/test jobs, package builds, demo, installed-runtime proof, Linux cgroup/native listener execution, actual remote CAS services, live Ollama, paid inference or real held-out scoring.
- A complete line-by-line re-audit of every unchanged native measurement/model-service helper or every manual command. I traced the relevant identity/admission/audit ownership and repaired paths; that does not establish a fresh platform/security acceptance verdict.

The referenced `interrogate/references/code-quality.md` does not exist. I applied the adjacent actual `code-quality-review.md` with the full rubric. Author implementation reports were read as claims. No repository source, tests, documentation, Git state, saved run or receipts were modified. Only the scratch probe and this report were written under `/tmp`.
