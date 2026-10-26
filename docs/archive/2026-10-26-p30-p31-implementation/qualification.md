# Finite qualification protocol

Historical contract record, **2026-10-26**, source `fbb207d`; use the
[implementation record](index.md), [frozen baseline](baseline.md#qualification-and-release-gates)
and [current plan](../../plan.md). Targets below are declared before implementation
evaluation. None is an observed pass merely because it appears in this document.

## Separate populations and evidence

| Main route | Required protocol evidence | Live scope at declaration |
| --- | --- | --- |
| ChatGPT subscription | Native Responses call/result replay, stable additional-tools declaration, draft without unsupported output cap | Configured `gpt-6.1-sol` pilot within 300-call allowance; later integrated quality/cache/latency still open |
| OpenAI API | Responses capture calls, refusal/continuation/native pairing | No paid route/cap selected |
| Ollama | Native tool arguments/results, truncation refusal, typed capture, explicit local identity/context | 1,000-call primary-pair allowance; resident 9B is a separate comparator |
| Anthropic | Native tool_use/tool_result and role folding; tail remains outside system prompt | Fixtures required; live unverified |
| Gemini | Function call/response, signed/native history and role folding | Fixtures required; live unverified |
| OpenRouter | Pinned upstream tool protocol and no hidden route fallback | No paid route/cap selected |
| Grok API/subscription | Provider-bound native Responses; billing/auth kept separate | Account eligibility/live acceptance remains separately unverified |
| Explicit loopback compatible | Selected chat/Responses subset with exact target identity | No silent substitute for native Ollama; fixture qualification required |

Run the existing captured-wire conformance suite plus the owning package's new
capture/context fixtures for every row. Protocol success never supplies live
semantic quality or paid-account eligibility. The demo remains deterministic.

The exposed [pilot cases](../../../dev/knowledge/pilot.exs) consist of three
20-turn sessions across project decisions, preferences, corrections, temporal
changes, explicit pins/durations, duplicates, uncertain statements, quoted hostile
text and no-memory turns. They are development-authored and repeated in a declared
pilot; they are not 60 independently authored held-out cases. Fake storage receipts
measure tool propensity/overhead, not integrated publication/recall quality.

Before C1a/E semantic qualification, obtain independently authored, frozen labelled
collections disjoint from development/pilot inputs. Do not relabel author-written
fixtures or repeated tasks as independent. Preserve exact content/model/recipe
hashes, first outcomes, exclusions, assistance and adjudication. Semantic support
and citation support require independent assessment; source-byte matching alone
cannot judge usefulness, entailment or model carryover.

| Population | Minimum and strata | Qualification |
| --- | --- | --- |
| Capture | 200 fresh cases; direct facts, persistent/task-local preferences, accepted/unaccepted cards, native answers, verified outcomes, run input, references, secrets/poisoning, corrections | No false attestation/effect authority; useful fact/decision capture measured with independent labels; all-path exclusion tests |
| Small notes recall | 100 prompts over independent <=32-note collections, fitting the actual allocation | 100% eligible byte coverage; >=90% supported answers, >=95% supported citation pairs, >=95% critical-decision recall |
| Capacity recall | 100 prompts over independently authored collections at frozen active capacity, at least 2,000 notes; answer absent from first page; constrained/zero inline recall | Same semantic bars separately; bounded candidate discovery/read coverage, no whole-index prompt injection |
| Documents | 100 prompts; synonym-only, missing sources, changed versions, conflicting evidence, PDF/Word tables/columns/Unicode/revisions | Same answer/citation bars; Word independently qualifies; PDF quality may be experimental/off only with exact failure record |
| Relationships | 100 entity/relation cases including aliases, namesakes, polarity, temporal changes and unsupported statements | Extraction scored independently of traversal; false merge/unsupported relation cases remain explicit |
| Enhancement | Main-route ordinary/draft/cancel/replace/accept, existing grants, planning, resume, compaction and late callbacks | No prohibited dispatch; cancelled canary requirement absent from later unrelated prose/tool args; native history preserved |

## Storage and performance

Until pilot-derived useful intake is assessed, preserve the initial workload floors:
2,000 active notes, 200 persistent records (100 pins/50 preferences/50 current
temporal assertions), 6-KiB max note plus evidence, 24-MiB records/evidence/history,
64-MiB total notes store. Freeze derived intake as max(20, ceil(40 × highest
observed session-average useful-unique items/turn)) across qualified routes, with
measured category/payload mix and a 2× one-day burst margin. Higher measured intake
increases required workload/capacity; it cannot lower useful capture silently.

Run 30 then 90 simulated workdays at 40 turns/day, frozen ordinary intake,
four corrections/two forgets per day, offline week/restarts/imports, two overlapping
OS processes and representative plus maximum payloads. Continue through day 365,
10,000 update/correct/forget cycles and at least four temporal supersessions/day.
Current temporal support survives its first update after day 90; prior support
lasts >=365 days after supersession unless explicitly reduced. Reads never renew TTL.
Normal workload has zero capture pauses. Separately exercise 320 proposals/day:
report dedup/refusal/pause/capacity, warn at 80%, never evict persistent evidence.

Local admission/publication target p95 <250 ms; local retrieval p95 <500 ms warm/
2 s cold on declared four-core/8-GiB/local-SSD reference hardware. Record actual
host CPU/RAM/storage/runtime, sample count and disk/RAM peak; another host is not
implicitly qualified. Measure 100/500-turn capture overhead, native/journal growth,
compaction count/cost, <=one capture-only continuation/turn and median <=10% extra
measured tokens. No candidate means zero mandatory extractor calls.

Cache-isolation trial: 20 paired cold and 20 paired warm requests per qualified
route/model, identical eligible prefix and matched changing suffix byte budgets;
warmup excluded from pairs but counted in calls. Keep cache TTL/settings and delay
fixed per route; intentional epoch resets are a separate stratum. Targets:
<=5 percentage-point cache-read-ratio regression and <=10% non-read input increase.
Product overhead trial: 20 paired knowledge-off/on 100-turn replays, then the
500-turn stratum, p50/p95 TTFT regression <=20%. These large integrated trials
need a subsequent finite call allowance if they exceed the current 300-call cap;
the cap is never silently expanded to fit the design. Initial allowance supports
the pilot and bounded layout/latency probes, not every required live gate.

Record dispatch-to-first-visible-text and input-to-first-visible-text separately.
Tool-only output has null TTFT plus first-tool/completion timing. Cache counters
are nullable; non-read includes cache writes; uncached subtracts writes only when
all counts are known/consistent. Unknown is not zero. Layout fixtures do not prove
provider cache hits. Ratify live tolerances before held-out measurement; failures
remain failures, and missing metrics remain explicitly unverified.

## Optional local route

Use the primary Qwen pair under the selected finite local allowance. Compare
exposed tuning first; one optional 9B resident comparison only when its identity,
hardware and remaining allowance are verified. Freeze actual templates, chunking,
native dimensions, normalization and complete immutable model identity before
held-out queries. Compare lexical/main-model reformulation/hybrid using matched
source/model/context/steps. Measure candidate recall, supported answers/citations,
abstention, poison resistance, capture/tool behavior, cold/warm TTFT, RAM/VRAM and
old+staged index peak disk. Verify offline operation with the knowledge route's
egress blocked after provisioning; loopback alone proves no offline property.

Acquisition ceiling is the developer's 12-GiB model allowance, at most two primary
model acquisitions, 30-minute overall acquisition deadline and visible progress.
Cancellation records unknown daemon completion and performs no automatic retry.
Models are unbundled. D1/F must add protected cross-project inference slots and
ownership/unknown-work recovery before claiming ordinary installed support.

## P30 finite experiment declaration

Exactly two consumers: notes selection beyond the context allocation, and candidate
assessment on actual validated main-tool inputs in replay/shadow mode. Fitting
note sets and absent candidates require zero decision calls. Freeze two development
tuning attempts per engine/consumer, then one held-out run; do not keep trying
new datasets until something wins. Compare the engine-free complete-note/search
baseline at identical source/step/token envelopes. Never publish shadow results.

Useful selection requires no critical-decision/citation regression, >=5 percentage
points supported-answer improvement **or** >=20% total inference cost reduction
with all baseline quality bars retained, and <=20% p95 end-to-end latency regression.
Assessment requires >=20% relative reduction of false-durable candidates without
reducing useful/critical capture by >2 percentage points, <=20% p95 latency
regression, and a declared finite per-project cost cap. Report abstention separately.
Where total cost cannot be known, that cost benefit is unverified; quality benefit
can qualify only with explicit finite calls/resources and no hidden zero-price claim.

Native results retain uncertainty/distributions; advice cannot create provenance,
truth or permission. Protocol/refusal/count/type/range/sum/rubric corruption,
zero-egress denial, reservation/journal ordering and actual-work cancellation are
hard gates. Outcome is useful/qualified, evaluated/rejected, or unverified. Missing
paid-engine access is not a negative evaluation and cannot close P30E without a
separate explicit scope qualification.
