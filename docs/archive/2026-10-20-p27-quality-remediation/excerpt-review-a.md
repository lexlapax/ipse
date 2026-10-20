Historical independent review, 2026-10-20. Original report retained below unchanged.
It covers the nine-file whole-chunk-first excerpt repair against `08ecc55`,
with the stated limits. Current procedures: [knowledge training](../../developer/knowledge-extensions.md).
Replacement and acceptance status: [remediation record](index.md) and [P27 plan](../../plan.md#p27-optional-research-graph-and-rag).

# Independent whole-chunk-first review A

Verdict: no actionable correctness, security or structural finding in the current complete diff. This review supersedes my earlier verdict for the old compact policy. The first report remains unchanged. This is a deterministic implementation review, not model-quality acceptance or P27 completion.

## Reviewed snapshot

Base HEAD is `08ecc5531530dd9e55f8cc1ec1da7572e3cfbac5`.

- SHA256 of `git diff 08ecc55`: `7d967bca2aabc24ab018ded1e574d4f79c99f970f795e9ff5284df4135766d01`.
- SHA256 of the Evidence diff: `bcc07f6242a93521818055527fb429b37b28ef6ba7d5d249dc11993a847fa5e9`.
- Nine changed files, 487 insertions and 78 deletions.
- Evidence is now 1086 lines, compared with 931 in the base.

I read the new standalone brief and evaluated its whole-chunk-first contract as authoritative. I inspected the entire current nine-file diff against the base, rather than limiting review to the latest selector patch. The surrounding source/citation validation, lexical/dense/remote callers, Research path, ordering/fusion/graph identity, adapter mapping, Answer packing, SDK builder and complete-result proof remain in scope. I had read all three whole affected manual chapters in the first review; I rechecked the revised explanations against those complete documents and searched them for old policy claims. I did not read the exposed omission diagnostic or any private workload content.

## Findings and structural judgment

No required change identified.

### The revised selection contract is implemented

`extensions/knowledge/src/evidence.ex:757-787` validates the query before its whole-chunk shortcut. A valid original chunk of at most 1024 bytes yields its complete local range, then passes through the same authoritative `citation/4` constructor. The shortcut therefore preserves both query validation and independent source/span validation. It applies to absent and punctuation-only queries as well as matching queries. It also covers exactly 1024 bytes.

Only oversized chunks build matching original-token groups. `token_offsets/1` at lines 973-980 retains the original exclusive end while emitting the same normalized terms used for scoring. The two coverage passes at lines 790-849 select maximum distinct normalized-term coverage, then the shortest and earliest original-byte core. Oversized original tokens are excluded from whole-token coverage without altering BM25 token counts. Each retained group fits alone, which makes the trim queue nonempty whenever its head is inspected. Once shortest-window removal empties the queue, its positive coverage target fails before another peek. I found no reachable empty-queue fault.

For a legal hull, lines 883-907 find the first preceding unit whose start can fit with the original hull. Earlier starts are in byte order, so that is the earliest legal preceding boundary. The final following-unit scan uses the selected start and monotonically increasing ends, preserving preceding-context priority while retaining every following complete unit that fits. It does not jump across a rejected unit or manufacture disjoint text. This differs materially from the former one-neighbor rule and matches the revised intent.

Long hulls use the single 1024-byte centered fallback at lines 910-925. Clamping transfers unused edge space; clipping then moves inward to valid codepoint boundaries. The already valid core endpoints prevent this adjustment from clipping a selected whole token. No-core chunks use complete-unit prefixes up to 1024 bytes, or a UTF-8-safe prefix if the first unit alone is too long. No compact 512 target survives in the selector.

### Callers and retained contracts

The complete runtime diff still has one policy owner. Corpus supplies the original query to `rank_remote/5` and `dense_candidates/4`. Dense candidates still require a compatible current vector before requesting their citation. Research inherits the lexical operation. Searches found no old four-argument remote definition or caller.

The score calculations, score/span/scope ordering, RRF formula and scoped chunk fusion key are unchanged. Changed excerpt bounds can legitimately affect span IDs and span-sensitive ties. RRF still reinforces one chunk regardless of a graph citation's different exact span. The domain regression retains `3/61`, both opposing graph bases and the eligible seed while accepting a whole-chunk lexical representative.

Rerank references are computed from the final saved candidates; short-ID response mapping returns those same candidates. Its 128-byte shown prefix remains a separate limitation, explicitly demonstrated by the query-after-byte-128 test. Answer retains complete-citation longest-prefix admission under its existing encoded 4096-byte cap. The source-backed six-480/three-900/escaping cases still exercise actual preparation and omitted-tail behavior. Larger excerpts can admit fewer sources; that is a consequence of the new contract, not evidence of improved answer quality.

The complete-result fixture's full 1024-byte quote, escaped citation and independent Graph bases remain compatible with the new policy. The SDK builder still compiles the shared Evidence module into each independently selected artifact. I did not execute an artifact build or package proof.

### The file-size exception remains justified for this bounded change

The 931-to-1086 growth crosses the review threshold and requires a specific reason. The operation consolidates three retriever excerpt policies next to the authoritative original-byte tokenizer and citation constructor, while deleting Corpus's separate grapheme-prefix policy and byte arithmetic. Its entire selection logic is contiguous. Graph, persistence and lifecycle paths gain no excerpt-specific branches. There is no new configuration, persistent policy state, runtime module, dependency or compatibility arity.

The revised requirement also deletes two policy concepts: the 512-byte preference and per-side neighbor count. The remaining special case is the foundational whole-chunk rule, expressed once before indexing or segmentation. It is not scattered caller-specific branching.

I waive the line-count blocker here. A separate forwarding module would preserve all selection machinery and add indirection. A substantial tokenizer/span-selector module could be a real future ownership boundary, but I found no change-local simplification sufficient to justify splitting scoring normalization from the current exact-byte owner. Replacing two forward scans with a combined winner-state algorithm would preserve the queue/count machinery while making maximum-coverage and shortest-window state more coupled. A first-hit prefix or brute-force span search would respectively change the required behavior or add unnecessary work. No behavior-preserving large deletion or earned deeper decomposition emerged from this review.

This exception is limited to this cohesive operation; Evidence's existing graph and validation breadth does not authorize unrelated additions.

### Manuals describe the revised policy

The developer citation section now states whole-chunk-first behavior, oversized-only query cropping, earliest preceding context, all fitting following units, the sole 1024 limit and final citation authority. Corpus gives the runnable actor/condition example and preserves the byte/chunk/semantic limits. Research points to that canonical operator explanation and no longer mentions a neighbor-count allowance. The old dense 200-grapheme rule is removed. Searches across all three complete chapters found no surviving compact-512 or at-most-one-neighbor claim. Their commands and examples still refer to the same selected extension APIs and profiles. Final CLI execution remains pending outside this review.

## Verification actually run

From `/Users/spuri/projects/lexlapax/ipse`:

```sh
mix test test/knowledge_evidence_test.exs test/knowledge_packages_test.exs test/knowledge_domain_regressions_test.exs
elixir scripts/check-docs.exs
git diff --check
```

- Focused tests: 31 outer tests passed in 28.4 seconds, seed 237128. The two VM wrappers also execute the embedded package and domain suites and propagate nonzero failure status. This outer count is not the total internal case count.
- Docs: 290 Markdown files, 2991 local links and manual/archive rules, zero errors.
- Diff check: exit zero, no output.

I also executed these independent pure probes against actual `Evidence.excerpt/3`:

1. 100 deterministic oversized 24-unit chunks. The reference used the known generated unit ranges to choose the earliest preceding boundary fitting with the hull and the greatest fitting following end. All exact offsets and source-span validations matched.
2. 24 whole-chunk cases across sizes 1, 511, 512, 513, 1023 and 1024, with empty, punctuation, absent and matching queries. Every quote equaled the full original bytes. Nil and 1025-byte queries refused for every case.
3. 80 deterministic long Unicode inputs, with original `İstanbul` groups and four-byte context. The independent reference enumerated all legal original-group windows, selected the maximum-coverage/shortest/earliest result, and clipped using prefix validity rather than the production boundary helper. All exact offsets and authoritative span checks matched under a 1024-byte centered target.

The exact probe commands follow.

```sh
elixir -r extensions/knowledge/src/evidence.ex -e '
alias IpseKnowledge.Evidence, as: E
make_source = fn text ->
  {:ok,s}=E.source(%{"source_id"=>"probe","partition"=>"notes","generation"=>1,"title"=>"Probe","text"=>text,"uri"=>"local:probe","observed_at_ms"=>1,"event_at_ms"=>nil,"expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"notes","partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}}); s
end
for seed <- 1..100 do
  :rand.seed(:exsss,{seed,seed+5,seed+10})
  chosen=:rand.uniform(20)+2
  parts=for n<-1..24 do
    size=44+:rand.uniform(26)
    if n==chosen, do: "needle "<>String.duplicate("x",size-9)<>". ", else: String.duplicate("x",size-2)<>". "
  end
  {units,_}=Enum.map_reduce(parts,0,fn part,a -> {{a,a+byte_size(part)},a+byte_size(part)} end)
  {core_start,core_end}=Enum.at(units,chosen-1)
  first=units |> Enum.filter(fn {a,_}->a<=core_start and core_end-a<=1024 end) |> hd() |> elem(0)
  last=units |> Enum.filter(fn {_,b}->b>=core_end and b-first<=1024 end) |> List.last() |> elem(1)
  text=Enum.join(parts); true=byte_size(text)>1024 and byte_size(text)<=2048
  s=make_source.(text); {:ok,[chunk]}=E.chunks(s); {:ok,c}=E.excerpt(s,chunk,"needle")
  true={c["start_byte"],c["end_byte"]}=={first,last}; true=E.valid_span?(s,c)
end
for size<-[1,511,512,513,1023,1024], query<-["", "?!", "absent", "x"] do
  text=String.duplicate("x",size); s=make_source.(text); {:ok,[chunk]}=E.chunks(s)
  {:ok,c}=E.excerpt(s,chunk,query); true=c["quote"]==text
  {:error,:invalid_query}=E.excerpt(s,chunk,nil)
  {:error,:invalid_query}=E.excerpt(s,chunk,String.duplicate("q",1025))
end
IO.puts("100 earliest-preceding/maximal-following probes and 24 whole-chunk/query-boundary probes passed")
'
```

```sh
elixir -r extensions/knowledge/src/evidence.ex -e '
alias IpseKnowledge.Evidence, as: E
for seed <- 1..80 do
  :rand.seed(:exsss, {seed, seed+8, seed+16})
  words = for _ <- 1..16, do: Enum.at(["İstanbul", "alpha", "beta", "unrelated"], :rand.uniform(4)-1) <> String.duplicate(" ", :rand.uniform(24))
  text = String.duplicate("😀", 140) <> " " <> Enum.join(words) <> String.duplicate("😀", 140)
  terms = MapSet.new(~w(i stanbul alpha beta))
  groups = Regex.scan(~r/[\p{L}\p{N}]+/u, text, return: :index) |> Enum.flat_map(fn [{a,n}] ->
    set = Regex.scan(~r/[\p{L}\p{N}]+/u, String.downcase(binary_part(text,a,n))) |> List.flatten() |> MapSet.new() |> MapSet.intersection(terms)
    if n <= 1024 and MapSet.size(set)>0, do: [{a,a+n,set}], else: []
  end)
  trials = for {a,_,_} <- groups, {_,b,_} <- groups, b>a, b-a<=1024 do
    covered = groups |> Enum.filter(fn {x,y,_} -> x>=a and y<=b end) |> Enum.reduce(MapSet.new(), fn {_,_,s},acc -> MapSet.union(acc,s) end) |> MapSet.size()
    {-covered,b-a,a,b}
  end
  {_,size,a,_b} = Enum.min(trials)
  lo = max(0,a-div(1024-size,2)); hi=min(byte_size(text),lo+1024); lo=max(0,hi-1024)
  lo=Enum.find(lo..(lo+3), fn n -> String.valid?(binary_part(text,0,n)) end)
  hi=Enum.find(hi..(hi-3)//-1, fn n -> String.valid?(binary_part(text,0,n)) end)
  {:ok,s}=E.source(%{"source_id"=>"probe","partition"=>"notes","generation"=>1,"title"=>"Probe","text"=>text,"uri"=>"local:probe","observed_at_ms"=>1,"event_at_ms"=>nil,"expires_at_ms"=>nil,"origin"=>%{"kind"=>"provided","store_profile"=>"notes","partition_or_scope"=>"notes","receipt"=>nil,"historical"=>false}})
  {:ok,[c]}=E.chunks(s); {:ok,quote}=E.excerpt(s,c,"i stanbul alpha beta")
  true = {quote["start_byte"],quote["end_byte"]} == {lo,hi}
  true = E.valid_span?(s,quote)
end
IO.puts("80 revised exhaustive Unicode/core/window probes passed")
'
```

Inspection used `git diff --stat 08ecc55`, complete path-specific `git diff 08ecc55 -- ...` reads for all nine files, `nl -ba extensions/knowledge/src/evidence.ex`, `wc -l extensions/knowledge/src/evidence.ex`, the diff SHA256 commands above, and targeted `rg` searches over the three manuals and affected source paths. In particular:

```sh
rg -n '512|200.grapheme|at most one|neighboring.unit|compact|first.match|rank_remote/4|dense_candidates/3' docs/developer/knowledge-extensions.md docs/operator/corpus.md docs/operator/research-extensions.md extensions/knowledge/src/evidence.ex extensions/knowledge/src/corpus.ex
```

Remaining 512 matches belong to URI and host-read bounds, not excerpt policy.

## Verification limits

No private workload, semantic annotation/rationale, external service, inference, SSH, measurement replay, package launch, artifact build, Git mutation or child delegation occurred. Only the new report was written. The original two platform proofs were stopped according to the brief; I did not count their partial runs as passes. I did not rerun the full suite, public worker CLI/proof, extracted-runtime checks, Arch checks or final platform checks. The 73/73 exposed-span diagnostic was not used as a test oracle. Nothing here establishes semantic completeness, better real-model answers, latency, charged RAM, or milestone acceptance.
