# Knowledge and prompt assistance: product readiness assessment

Research and proposal dated **2026-10-26**. This is a historical assessment of
`3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c`, after v0.1.0 publication. It does not
change implemented behavior, authorize implementation, or amend milestone scope.
The [plan](../../plan.md) owns current acceptance; the
[operator manual](../../operator/index.md) and
[contributor manual](../../developer/index.md) own current procedures.

## Assessment

The user's concern is justified. Ipse has implemented knowledge storage,
retrieval, provenance and extension machinery, but has not delivered the simple
knowledge assistant described in the request. Turning on an instance does not
make conversations populate a graph, ingest a document folder, or recall relevant
knowledge before each answer. Those are missing product behaviors, not missing
instructions for an already available switch.

This expectation was present in the earlier design: the
[2026-10-16 proposal](../2026-10-17-before-self-hosting-review/knowledge-extensions.md)
described optional automatic recall, approved capture and prompt-driven graph
work. P26 later explicitly accepted the explicit-note baseline, with automation
separately scoped; P27 accepted independently configurable packages and a measured
retrieval reference. Meeting those narrower gates did not deliver the original
end-to-end knowledge experience. That distinction belongs in future acceptance,
not just in a footnote explaining how to configure extensions.

v0.1.0 still has a useful purpose: it is a local, resumable general-purpose agent
harness with multiple explicitly selected providers, workspace tools, skills,
approvals, sessions and optional extension hosting. Its prototype and examples
are substantially oriented toward coding. A user can perform real tasks with it.
The knowledge family is at a different level of readiness: explicit note use is
available after technical configuration, while Corpus and Graph are primarily
integration and evaluation workflows. Calling the entire release useless would
miss the working agent; presenting its knowledge packages as effortless personal
memory would overstate what shipped.

I recommend a dedicated **knowledge and prompt-assistance usability milestone**,
with working user journeys as acceptance. Keep automatic relationship capture
inside that scope as an opt-in deliverable. First make activation, evidence,
permissions and inspection usable; then deliver notes, document retrieval and
graph capture through those shared facilities. Prompt enhancement and selective
clarification can proceed in parallel. They do not require a decision-engine
service or voice support first.

The other report gets the central usability diagnosis right. I disagree with its
blanket near-term deferral of automatic graphs, its claim that approval is the
only capture gap, and several interpretations of external research. Those
differences affect the proposed work, not the validity of the existing release
receipts.

## Evidence and limits

This assessment combines source and test inspection, whole relevant operator and
developer chapters, the published P26/P27 scope and evaluation record, inspection
of the retained v0.1.0 Linux archive, and primary web sources accessed on
2026-10-26. Independent passes examined knowledge implementation, prompt/event
contracts, and external research claims. The result below reconciles those passes
with direct inspection; it is not a new runtime or model-quality certification.

The supplied report was read in full: `ipse-knowledge-and-prompt-shaping-analysis.md`
from the user-provided scratchpad path, SHA256
`b8931fc40576da547e79359fecc1258099df292390152e163a775cd556577794`.
It is treated as an analysis to check, not as implementation evidence. No private
transcripts or credentials are reproduced here. No paid inference, external
product trial, or benchmark rerun was performed. Product documentation establishes
documented workflows; papers establish their authors' reported experiments.
Recommendations below are design judgments, explicitly separated from those facts.

## What a user gets today

| Capability | Implemented and usable mechanism | What is missing from the expected experience |
| --- | --- | --- |
| Conversation continuity | Durable Session history, explicit resume and bounded context/compaction | Automatic search of arbitrary earlier sessions as a knowledge collection |
| Project instructions | Workspace instructions and explicitly loaded skills | Automatic extraction of stable preferences or decisions into those instructions |
| Working/persistent Memory | Bundled, default-off explicit notes; session/project/operator scopes; lexical recall, TTL, suppression, exports | Guided activation, automatic recall/capture, friendly note management and scoped reusable write consent |
| Corpus / document RAG | Independently built artifact; explicit source storage and indexing; lexical/dense/hybrid query with citations | Shipped ready-to-use artifact, file/folder ingestion, progress/recovery UI and automatic context integration |
| Graph | Independently built artifact; explicit or model-assisted extraction over stored sources; attributed facts and bounded traversal | Conversation capture, convenient fact entry, entity management, automatic recall and a simple local setup |
| Research | Native research skill and evidence ledger; separate extension for provided or configured search/fetch sources | A default search service, automatic Corpus/Graph persistence, or a general autonomous knowledge pipeline |
| Clarification | Native `ask_operator`, up to three structured questions per call, with answers returned to the main model | A calibrated missing-information policy, editable prompt enhancement, or guaranteed read-only planning mode |
| Extension activation | Select a reviewed configured instance at startup with `--extension INSTANCE`; direct `/ext` commands afterward | A general `/enable graph` installer/configurator or idle hot activation of unconfigured capabilities |

These distinctions are documented in the current
[Memory](../../operator/memory.md), [Corpus](../../operator/corpus.md),
[Graph](../../operator/graph.md), [Research](../../operator/research.md),
[extensions](../../operator/extensions.md), and
[usage](../../operator/usage.md) chapters. A complete manual for a low-level
interface does not make that interface an ordinary-user workflow.

### A realistic current workflow

For a repeated project instruction, a user can maintain the workspace's
`AGENTS.md` and start a normal session. This is the simplest current route for
instructions that should consistently accompany work. It is not a fact database
or an automatic learning mechanism.

For persistent notes, follow the Memory manual to save an operator configuration
with a logical project store and the bundled artifact. Start chat with that
configuration and `--extension project-notes`. The manual's direct command
example writes a note with a source ID, generation and expected revision; the
operator approves the state write. A subsequent `/ext ... recall` prints evidence
to the terminal. It does **not** by itself insert that evidence into the assistant's
conversation. A model-initiated recall tool does return its result to the model.
It still needs the outer extension-tool approval in default ask mode, even when
the underlying lookup is read-only.
Model-driven note creation also has an outer extension-tool approval and an inner
state-write approval in default ask mode. There is no honest one-step equivalent
of this setup in v0.1.0.

For a local graph, follow the explicit State preset in the Graph manual: build or
obtain a compatible artifact, import and inspect it, generate/review configuration,
store a source, construct its attributed fact, extract, then query. **MCP is not
required** for this path. The explicit fact example currently uses an Elixir
helper to calculate source/chunk identities and citation spans. That is appropriate
as a contributor proof, but excessive as the primary product interaction.

Corpus and Graph expose **query** as a model tool. Their source, index and extract
operations are operator commands. Therefore merely asking today's main model to
save new graph relationships does not give it an existing Graph capture tool.
Extraction is also not universally Ollama-only: the optional `json_schema_v2`
contract requires the documented native Ollama route; the v1 text contract can
use other admitted model profiles. None of this establishes live extraction
quality for those profiles.

## Why adding a flag alone would not solve it

### Distribution and activation

Working and persistent Memory are bundled. The inspected Linux release archive
contains their modules but no `IpseKnowledge` modules or independently built
Corpus/Graph/Research artifact. Installed users can import a compatible prebuilt
artifact, but the documented path currently starts with a source build. Shipping
verified prebuilt artifacts can preserve independent builds and SDK boundaries;
independence is not a reason to require every user to become a package developer.

The selected-extension catalog is bounded to 32 entries and 16 KiB. The documented
combination of Memory plus all three knowledge packages exceeds the byte limit.
A descriptor-only probe with instances `notes`, `corpus`, `graph`, `research`
measured 23 entries and 18,672 encoded bytes: the combined catalog is refused,
while each individual catalog passes. Names affect encoded size; this is the
measured composition, not a constant for every configuration. The
[probe](catalog-probe.exs) and [result](catalog-result.json) retain the source hashes.
A promise that one switch enables the entire family would currently fail
admission. Fix the intended composition deliberately: reduce redundant exposed
schemas, distinguish operator management from model-facing tools, or review a
bounded catalog change. Raising every limit without measuring prompt cost is not
a product design.

### Acquisition and integration

Source commands accept structured text and identity fields. There is no ordinary
folder importer that handles supported file types, excludes secrets, reports
changes and makes source IDs/revisions invisible to the user. There is also no
production job mapping conversation evidence to retained notes or graph facts.

Memory, Corpus and Graph export no public value services today. Existing service
routes are pure, inline values and cannot perform nested State/MCP/model effects;
`tool.call`, under `host.tools`, cannot recursively invoke extension tools. A generic orchestration
extension cannot simply call all three current packages as if they were internal
functions. Put initial recall/capture jobs inside the owning package, share pure
implementation helpers where appropriate, or design a specific reviewed
composition contract. A new general workflow framework is unnecessary.

In particular, a friendly capture tool inside Graph can reuse its existing
tool/command dispatcher and derive citation identities from a unique supporting
quotation. Exposing that operation to the main model is package work; it does not
require a new nested-service API. Event-driven capture can likewise live inside
a reviewed Graph preset. Broader cross-package composition, reduced approval
friction and nonblocking maintenance are distinct changes.

### Recall and capture policy

There is no production `before_request` recall or `after_turn` capture subscription
in these packages. Current read-only State/context host actions need no per-effect
approval, so an in-package recall adapter is feasible on existing primitives.
This is a plausible implementation route, not an already shipped integration.
`before_request` runs once per accepted operator turn, not before each continuation
in the model's tool loop. Published context has eight items per instance, at most
2,048 bytes each, within a shared 16-KiB rendered budget. Failed replacement keeps
the previous set. An optional recall failure therefore needs explicit stale-context
handling; it must not quietly reuse irrelevant prior-turn facts.

Capture must additionally decide which text is eligible, distinguish speakers and
evidence status, extract/deduplicate, handle conflicts, preserve provenance,
publish atomically enough for recovery, and obtain appropriate authority. Simply
removing approvals would leave these questions unanswered. Existing `after_turn`
jobs keep the Session busy; they are not an independent background service.
Private event delivery contains one selected view of one occurrence, and workers
are fresh per job: prompt/answer joining is deliberate work. Answers over 8 KiB
have an unavailable text view with identity metadata, not a complete transcript
available for extraction. Capturing long answers or relevant tool results needs
an explicit evidence path. `host.history` is a
bounded view of the current Session, not a cross-session search API.

### Permission and capacity

Today's native edit and exact-shell session grants do not authorize extension
State writes, model calls or MCP effects. A source operation may produce several
approved State writes for immutable pages and publication. Repeating that after
normal turns would reproduce the approval fatigue already reported by the user.
Broad `--yes` is not a satisfactory everyday knowledge setting.

State namespaces are bounded to 256 records and 1 MiB encoded data. A knowledge
partition admits up to 32 source roots, but roots, source pages, projections,
progress records, old generations and suppression consume the same namespace
budget. Extra partitions within the same binding do not raise that ceiling.
Useful capacity is not “32 ordinary documents” or a fixed number of conversations.
Measure it with the intended data and expose remaining capacity before ingestion.
Collection can free old body bytes while retaining tombstone record slots;
repeated updates can exhaust records despite little active text.
Evaluate larger local storage behind the adapter before promising an enduring
personal archive; retain the small State backend as a bounded option.
Evaluate suitable maintained Elixir/Rust storage facilities before inventing an
engine; no new dependency or external database is selected by this report.

## Prompt assistance: available seams and genuine gaps

Prompt assistance comprises several different operations:

| Operation | v0.1.0 foundation | Product/contract work still needed |
| --- | --- | --- |
| Find information already available | Workspace reads, skills, selected retrieval tools; bounded context publication | Choose relevant sources before asking the user; show what was retrieved |
| Ask about missing intent | Native `ask_operator` and extension `host.question` | Calibrated policy, context-aware questions, follow-through and headless behavior |
| Suggest a better prompt | Append-only prompt transforms; model calls and display mechanisms | Editable proposal, accept/edit/cancel, original and accepted intent preserved |
| Add retrieved background | `before_request` jobs plus State reads and `context.publish` | In-package recall, attribution, budgets, duplicate/stale-result control |
| Plan before acting | Existing skills can request analysis and planning | Host-enforced effect restrictions if advertised as a safe read-only mode; explicit transition to execution |
| Apply a mid-task correction | `/cancel` interrupts; ordinary busy input queues | Live steering semantics if promised; today's queued input is not immediate redirection |

The SDK's prompt transform can append attributed reference text, not silently
replace the operator's request. An extension question's answer resumes that
extension; it is not automatically a user message in the main model transcript.
The extension must explicitly communicate the answer onward. In particular,
direct receipt-backed context provenance currently accepts successful `ok`
receipts, whereas a question receipt has status `answered`. This is a seam to
review for accepted clarification provenance, not proof that every possible
question-and-context prototype is impossible; assertion context is available.
This is a source-derived restriction, not a newly reproduced runtime refusal.
Native `ask_operator` already
returns answers into the main model loop and is the straightforward first path.
Its three-question bound is per call, not per task. Headless and child sessions
cannot obtain interactive answers; they stop when the question is attempted
rather than inventing a response. Detecting every missing input is not guaranteed.

Use a skill/policy and native questions to prototype selective clarification
before adding core machinery. Keep domain prompt analysis and planning in an
extension or skill. Put preservation of accepted operator intent, enforced effect
restrictions, cancellation and authorization in the host/client where required.
Do not turn a model-generated rewrite or a retrieved note into a higher-priority
instruction merely by inserting it into context.

An effective initial policy is: inspect available context first; ask when the
missing choice materially changes the outcome or authority; otherwise state a
reasonable assumption and proceed. A factual gap calls for retrieval; an intent
gap may require the user. A clarification answer is not blanket permission for
external effects. A plan is not execution approval. These distinctions should be
visible in the interaction and preserved in the journal.

## What external products and research actually support

### Useful product patterns

These are documented patterns, not claims that the products share an architecture
or that their quality has been independently verified here.

| Primary source | Observed pattern | Implication for Ipse |
| --- | --- | --- |
| [Claude Code memory](https://code.claude.com/docs/en/memory) | Human-authored instructions and automatic notes are separate; local auto memory has a toggle, a bounded startup index and on-demand detail | Make memory visible and scoped; keep retrieved facts distinct from instructions; do not load an entire archive on every turn |
| [Copilot Memory](https://docs.github.com/en/copilot/concepts/prompting-and-context/copilot-memory) | Repository facts carry citations checked against the current branch; user preferences have a separate scope; unused entries expire after 28 days | Freshness and scope are product behaviors, not merely storage metadata; a citation is useful only if its current validity is considered |
| [Open WebUI Knowledge](https://docs.openwebui.com/features/workspace/knowledge/) | Create/upload/attach a collection; native models retrieve using tools; full-context and retrieval modes differ | A user chooses documents and asks a question, rather than supplying chunk hashes; model-directed search and automatic injection must be described distinctly |
| [Open WebUI Memory](https://docs.openwebui.com/features/chat-conversations/memory/) | Reviewable memory tools, separate injection controls and optional periodic review | Capture, recall and maintenance deserve separate controls; periodic extraction need not run on every turn |
| [Mem0 Platform Graph Memory](https://docs.mem0.ai/platform/features/graph-memory) | Built-in entity extraction and co-occurrence links with no external graph database to configure | Simple graph-backed UX is real. This particular product explicitly does **not** create typed relations such as `manages`; it is not equivalent to Ipse's attributed subject/predicate/object facts |
| [Graphiti](https://github.com/getzep/graphiti) | Episode-based temporal graph construction with source provenance; open framework requires model/database integration | An application can hide deployment complexity, but must own entity resolution, temporal updates and source lifecycle |
| [Augment prompt enhancer](https://docs.augmentcode.com/cli/interactive/prompt-enhancer) | User invokes enhancement, reviews/edits the resulting input, or cancels and restores the original | Offer prompt improvement as an explicit authoring interaction, preserving the user's final choice |
| [Claude Code permission modes](https://code.claude.com/docs/en/permission-modes) | Planning is a distinct permission mode with documented action rules | A planning label should have enforcement semantics; do not claim that a prompt alone creates a read-only boundary |

The framework literature also distinguishes memory written on the request path
from asynchronous maintenance, with different latency and consistency tradeoffs.
That is a useful design distinction, not a recommendation to add its framework
or language runtime. [LangGraph memory overview](https://docs.langchain.com/oss/python/concepts/memory).

There is no basis here for universal claims that all successful products use
plain files, none uses graphs, or the market is abandoning retrieval. For example,
Continue describes its deprecated `@Codebase` interface as replaced by more
integrated codebase awareness. A deprecated interface is not a rejected capability.
[Continue's migration explanation](https://docs.continue.dev/reference/deprecated-codebase).

### Corrections to the supplied report's benchmark reasoning

| Claim or implication | What the primary evidence supports |
| --- | --- |
| Mem0g helps only temporal questions and otherwise makes memory worse | In the authors' experiment, graph improves both temporal and open-domain categories, while single/multi-hop scores fall. Overall LLM-as-a-judge scores are 68.44% versus 66.88%. Retrieved-token and stored-representation sizes are different metrics, not a universal 2× inference-cost law. [Mem0 paper](https://arxiv.org/html/2504.19413v1) |
| Letta's 74% versus Mem0g's approximately 68.5% proves files beat graphs | The vendor compares its file-search agent with another study's published result. This motivates an agentic file-search baseline; it does not isolate representation under a matched pipeline. [Letta experiment](https://www.letta.com/blog/benchmarking-ai-agent-memory/) |
| Roughly 39% versus 89% demonstrates general GraphRAG answer failure | Those HotpotQA figures are answer-string retrieval coverage for triplet-only retrieval versus RAG. The paper also finds benefits for other graph variants and combinations. Preserve original text and evaluate the actual use case. [RAG versus GraphRAG, v3](https://arxiv.org/html/2502.11371v3) |
| Asking when uncertain produces questions on 496/500 tasks | That figure is for a baseline explicitly required to ask before execution. For Claude Sonnet 4.5, the selective multi-agent treatment asks on 344 tasks, with 69.40% resolution versus the baseline's 70.40%, using a simulated user. It supports measuring useful and unnecessary questions separately. [Ask or Assume, v3](https://arxiv.org/html/2603.26233v3) |
| Clarification research establishes general prompt rewriting quality | ClarifyGPT reports 70.96%→80.80% Pass@1 on MBPP-sanitized with ten human participants; Ambig-SWE's maximum 74% gain is relative, model-dependent and uses simulated users. These are task-specific interventions, not an arbitrary-prompt guarantee. [ClarifyGPT](https://arxiv.org/abs/2310.10996), [Ambig-SWE](https://arxiv.org/html/2502.13069v3) |

CLAMBER additionally motivates measuring ambiguity detection and question quality;
its 2024-model results are not measurements of today's Ipse models.
[CLAMBER](https://arxiv.org/abs/2405.12063v2).
LightRAG's model-size guidance is a maintainer recommendation, not a universal
minimum for every extractor. Its separate extraction/query roles and small-scale
default-store caveats are more useful design lessons.
[LightRAG repository](https://github.com/HKUDS/LightRAG).

### What Ipse's own P27 comparison establishes

The frozen comparison covered 50 questions, two synthetic projects and 22 source
documents. Hybrid was the only strategy to meet both registered answer/citation
targets: 46/50 supported answers and 79/83 supported citations. Lexical had 48/50
supported answers but missed the citation target. Both explicit and model graph
had 45/50 supported answers and missed citation support. Six failed first outcomes
remain in the denominators; one rerank judgment used a disclosed owner resolution.
[Full P27 evidence and qualifications](../2026-10-23-p27-heldout-comparison/index.md).

This justifies the selected reference configuration **for that workload**. It
does not measure normal-user setup, raw conversation capture, durable preference
learning, temporal entity changes across everyday sessions, or correction fatigue.
The explicit-fact strategy bypasses extraction; the model-graph strategy exercises
extraction from supplied documents, not the proposed ambient conversation pipeline.
Neither a passing SDK fixture nor the selected retrieval winner completes those
missing product gates. Automatic graphs should be evaluated on their promised
relationship tasks, not required to beat every other retriever at every task.

## Proposed user experience

All command names in this section are **illustrative future interface sketches**,
not runnable v0.1.0 commands. Final naming should follow a small usability trial.

The first setup should offer a few understandable choices: remember project
notes, use selected documents, and track relationships. Selecting one explains
where data stays, what can be captured, which already-configured model/profile is
used, whether any text leaves the machine, and the budget. Save those settings.
For the first increment, obtain one bounded session grant when capture starts;
covered operations then run without repeated approvals. A new or resumed session
needs its own grant. Later enable/disable controls select the saved settings, not
a secretly renewed permission. A persistent automation grant can follow as an
explicit separate choice with its own versioning and revocation lifecycle.
An unset extraction/embedding profile should lead to a clear setup choice, never
a silently selected cloud service or reuse of unrelated credentials.

For example, the intended workflow could be:

```text
ipse knowledge setup
/knowledge on notes
/knowledge add ./specs
/knowledge on graph
/knowledge status
/knowledge inspect <item>
/knowledge forget <item>
/knowledge off graph
/enhance <draft request>
```

Do not require the operator to understand State partitions, artifact digests,
schema grants, byte offsets or MCP for the local baseline. Keep advanced
inspection available. If safe hot activation is not part of the first increment,
setup should save the configuration and clearly offer a new session; do not fake
immediate activation in an existing pinned session.

### Separate four decisions behind the simple controls

1. **Acquisition:** explicit notes, selected files, user turns, assistant outputs,
   or selected tool results. Choosing document RAG does not authorize personal
   conversation capture. Cross-project sharing is a separate choice.
2. **Representation:** notes, original source chunks, attributed graph assertions
   or a combination. Keep original evidence so extraction loss is recoverable.
3. **Recall:** a small deterministic context contribution, model-requested search,
   or both under one budget. Retrieval does not imply permission to rewrite
   instructions or act on remembered commands.
4. **Write policy:** explicit request, proposed batch for review, or bounded
   automatic capture. Disabling capture, disabling recall, forgetting an item,
   and deleting retained evidence are different operations and must say so.

### Treat automatic output capture as evidence, not self-confirmation

“Capture prompts and outputs” should mean recording their provenance and selected
meaning, not promoting every assistant sentence into an established fact. A user
statement, an assistant proposal, a verified tool outcome and a quotation from an
external source need distinct labels. For example, “we could migrate to Postgres”
is a proposal; “we decided to migrate” is a reported decision; a successful
migration receipt is evidence of an executed change. They are not interchangeable.

Graph extraction needs alias resolution, negation, uncertainty, time and source
conflict handling. Preserve an attributed assertion before deciding whether it is
eligible for ordinary factual recall. Conflicting sources should remain visible;
an arbitrary confidence score must not settle them. Prevent feedback loops in
which a previous speculative answer is recalled, repeated and counted as a second
independent source. Assistant summaries must retain their original dependencies.

Forgetting must suppress future use and dependent derived records in the declared
scope. Reindexing, fresh aliases or an old backup must not silently resurrect the
same forgotten content under a new ID. Current same-store explicit dependency
suppression is a useful foundation, but a cross-store capture pipeline needs a
deliberate dependency/invalidation design. Journals, backups and external services
have separate retention; the UI must not promise their erasure from a memory
forget operation.
Define this guarantee over managed source lineage and known aliases; do not
promise semantic erasure of every independently rephrased statement.

### Reduce approval fatigue with bounded consent

Add a host-reviewed extension policy tied to an instance/artifact, namespace,
operation set, source scope, byte/write limits and, where applicable, a named
model profile and call/spend budget. Show a short summary of authorized work and
resulting changes. Batch the user's review of a logical ingestion/capture operation;
do not expose each internal page write as a new decision when the approved policy
already covers it. Keep every actual effect journaled and recoverable.

A grant must cover the intended outer extension invocation as well as its allowed
inner effects; otherwise even ordinary model-driven reads still interrupt work.
A session grant should be visible, revocable, and not silently inherited by
children or renewed on resume. If persistent automation is offered later, give it
an explicit saved-policy lifecycle, version-change review and disable controls.
Local read access, durable writes and model/network egress are separate authority.
Changed scope/profile, exhausted budget, conflicts and destructive collection must
have explicit outcomes. Classification scores may suggest a capture; they never
grant permission. Implementing this policy is a host change, not a workaround
inside trusted extension code.

## Scenarios to build and test

| Scenario | Expected ordinary-user result | Today's gap and acceptance focus |
| --- | --- | --- |
| “Remember that this project uses pnpm.” Start a new session. | One scoped note, visible confirmation, automatic relevant recall; a later correction replaces the applicable fact | Existing notes require technical setup and model-directed recall. Test next-session reuse, worktree/root semantics and no cross-project leakage |
| “Use the documents in ./specs to answer my questions.” | Preview included files, ingest with progress, ask naturally, inspect citations; changed/deleted files update results | No folder importer or auto-recall. Start with documented text formats; unsupported PDF/OCR must be explicit, not silently skipped |
| “Track our clients and who owns each account.” | After explicit enablement, extract entities and typed relations from eligible turns, show a concise change log | No conversation capture adapter. Test aliases, role attribution, ambiguous names and duplicate evidence |
| “Alice took over Acme from Bob last week. Who owned it when the contract changed?” | Preserve both time-qualified assertions; retrieve graph paths with original evidence and abstain if dates are insufficient | Current `as_of_ms` filters retained current generations; it cannot reconstruct replaced versions. Design historical retention explicitly and test extraction separately from as-of answers |
| “That was hypothetical; forget the Acme ownership claim.” | Show affected records and derived facts; stop using them; explain retained journals/backups | Test re-ingestion, aliases, backup restore and in-flight capture against suppression |
| “Research an issue and save the useful sources for later.” | Bounded explicitly selected retrieval; review a save batch; Corpus and optional graph gain source-linked records | Research/native ledger and knowledge stores are currently separate. Compose through reviewed contracts, not hidden recursive calls |
| “Add login.” | Inspect existing app; ask only material missing choices, such as identity provider and account model; present an editable task brief if requested | Native questions exist; automatic policy and accepted rewrite UI do not. Clarification must not ask for information already in the repository |
| “Make this request clearer.” | Show original and proposed text; accept/edit/cancel; run only the accepted request | Append-only transforms are not prompt editors. Test invented requirements, cancellation and journal identity |
| “Plan the deployment.” | Read-only investigation under stated policy; separate execution decision | A skill can advise today. A guaranteed plan mode needs host enforcement across native, extension and MCP effects |
| “Stop, use the staging database instead.” | Interrupt stops further owned dispatch, reports any in-flight effect uncertainty, and records subsequent intent before a new attempt | Ordinary text currently queues. Do not advertise live steering until interrupt/acknowledgment semantics are implemented |

The client/contact and document scenarios matter: Ipse is a general-purpose
harness. Passing a coding-only trial would not establish these non-coding uses.

## Roadmap fit and recommended order

The current numbers do not name this work. **P20 is completed self-development;
P30 is proposed advisory decision engines; P31 is deferred voice/realtime media.**
If “p20” meant “p30”, the conclusion is still the same: easier knowledge and prompt
assistance should not be hidden inside the decision-provider adapter milestone.
Preserve completed milestone history. Add a named follow-up to P26/P27 and the
operator-usability work, assigning its number only when the roadmap is accepted.

| Increment | Deliverable | Ownership and dependency |
| --- | --- | --- |
| K1: usable activation and authority | Verified compatible artifacts, setup/status/disable, supported catalog combinations, scoped reusable consent | Packaging/client plus generic admission and approval work; no retrieval algorithm rewrite |
| K2: notes that carry forward | Explicit natural-language remember/correct/forget, bounded automatic recall, optional capture proposals | Memory package jobs and management UI; first complete cross-session user journey |
| K3: usable document retrieval | Text file/folder ingestion, stable identity/change tracking, citations, progress, recovery and realistic capacity | Corpus package and reviewed ingestion/storage contracts; lexical local baseline, optional explicit embedding/hybrid profile |
| K4: automatic relationship capture | Eligible turn/source capture, entity resolution, typed/time-qualified assertions, inspect/correct/forget, automatic relevant graph recall | Graph package plus required shared evidence/invalidation contracts; opt-in profile and budget, not deferred indefinitely |
| K5: prompt assistance | User-controlled enhancement, selective clarification, accepted task brief; separately enforceable plan mode if included | Prototype policy with native questions first; extension owns domain logic, client/host owns accepted intent and effects |
| K6: whole-product acceptance | Archive-based normal-user journeys, matched quality/latency/cost checks and adversarial recovery | A release gate for the integrated product, not another SDK-only demonstration |

K5 can run alongside K2–K4 after the contract decisions. K4 depends on acquisition,
consent and evidence identity; it need not wait for a claim that graphs universally
outperform hybrid retrieval. K1 must not turn into a large framework project:
deliver the smallest supported composition that makes K2 usable, then extend it.

P30 can later supply a measured advisory choice such as “is this a durable capture
candidate?” or “does this task need clarification?”. Begin with explicit user
requests, deterministic policies and the configured conversational model where
appropriate. Adopt a separate classifier only if matched evaluation shows value;
its score cannot authorize a write or select a paid provider. P31 can later consume
the same accepted text-intent and clarification contracts for transcripts. Neither
is a prerequisite for this work, and this report does not verify their proposed
external service APIs.

## Acceptance that would close the actual gap

These are proposed gates, to be agreed before implementation and measured on a
fresh candidate. They are not claims about current results.

- **Installed usability:** a fresh user starts with a release archive, enables
  local notes/document knowledge and optional graph capture without a source
  checkout, Elixir helper, hand-written JSON, hashes or MCP. Record setup time,
  decisions, interruptions and any assistance. Verify status/disable/inspect and
  correction/forget without developer interpretation.
- **Permission ergonomics:** after a bounded policy is accepted, routine covered
  captures do not prompt per State page. Out-of-scope source access, egress,
  profile changes and budget exhaustion stop or ask as designed. Record both
  useful confirmations and avoidable prompts; do not improve the count by using
  unrestricted `--yes`.
- **Knowledge quality:** independently label raw turns/documents, expected facts,
  relations, temporal updates, negations, hypotheticals and retractions. Measure
  false admissions and missed facts separately from retrieval and final-answer
  support. Test an ordinary lexical/file-search baseline, notes, hybrid and graph
  plus original passages under matched models/context/cost. Predeclare thresholds
  for the intended tasks; do not reuse exposed P27 questions as fresh acceptance.
- **Clarification quality:** include fully specified tasks, context-resolvable
  gaps, material intent gaps and tasks with safe defaults. Measure unnecessary
  questions, missed important ambiguity, invented requirements, completion,
  latency and model spend. Include human users; simulated users alone do not
  measure annoyance or usability.
- **Lifecycle and privacy:** disabled features create no workers/stores/calls;
  cancellation/owner death stops owned work; already-dispatched remote effects
  may have happened and retain unknown outcomes; interrupted effects are not replayed;
  indexing resumes explicitly; concurrent writes conflict correctly; capacity
  failure is actionable; no cross-project disclosure or deletion resurrection.
  Test the full selected package combination, not just each package alone.
- **Evidence and visibility:** answers identify retrieved sources; missing/stale
  evidence leads to a visible limitation. Status distinguishes saved, proposed,
  skipped, pending, failed and disabled work. Disabling recall removes future
  contributions but does not promise to erase existing provider/journal history.
  On optional recall/publication failure, clear obsolete contributions or stop
  inference according to the declared policy; never silently reuse prior-turn data.
- **Documentation:** write the normal-user journey first, with prerequisites,
  expected results and recovery. Move artifact-building/hash exercises to
  contributor training. Retain advanced configuration and honest limits. Validate
  the installed walkthrough itself; passing a documentation link checker is
  insufficient.

LongMemEval's separation of information extraction, cross-session reasoning, knowledge updates,
temporal reasoning and abstention offers useful test dimensions, without adopting
its scores as Ipse acceptance. Its separate indexing/retrieval/reading analysis
helps localize failure; neither taxonomy substitutes for scoring raw graph fact
admission. [LongMemEval](https://arxiv.org/abs/2410.10813v2).

## Decision recommended

Accept the diagnosis and authorize a bounded design brief next, with K1–K6 as
candidate increments. Keep the four user outcomes explicit: remember useful
information, answer from selected documents, track relationships automatically
when enabled, and help refine incomplete requests. Preserve P26/P27's existing
correctness foundations while making those outcomes independently demonstrable.
The next implementation should be judged by a new user's completed task, not by
the existence of another export, adapter or configuration example.

## Source audit map

These links pin the inspected source revision. Line numbers locate the contract
or inspected assertion; existing tests are evidence of intended behavior, not a
claim that the full suite was rerun for this report.

| Finding | Source at the inspected revision |
| --- | --- |
| Current Memory tools and command exports | [memory.ex:51](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/extensions/bundled/memory.ex#L51) |
| Corpus/Graph expose only query as a model tool | [corpus.ex:18](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/extensions/knowledge/src/corpus.ex#L18), [graph.ex:18](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/extensions/knowledge/src/graph.ex#L18) |
| Shared Graph tool/command dispatch and quote-derived fact evidence | [graph.ex:42](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/extensions/knowledge/src/graph.ex#L42), [packages_test.exs:59](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/test/extensions/knowledge/packages_test.exs#L59) |
| Outer extension-tool approval and inner write approval | [turn.ex:649](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/session/turn.ex#L649), [memory_session_test.exs:318](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/test/extensions/bundled/memory_session_test.exs#L318), [actions.ex:726](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/actions.ex#L726) |
| Native session grants' scope | [permissions.ex:13](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/session/permissions.ex#L13) |
| Catalog bounds and actual package composition | [catalog.ex:92](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/catalog.ex#L92), [knowledge-extensions.md:43](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/docs/developer/knowledge-extensions.md#L43) |
| Namespace identity/capacity and package page overhead | [state.ex:6](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/state.ex#L6), [knowledge-storage.md:26](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/docs/developer/knowledge-storage.md#L26) |
| No nested effectful services or recursive extension tool calls | [host.ex:437](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/host.ex#L437), [external_calls.ex:397](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/external_calls.ex#L397) |
| Before-request event delivery once per accepted turn | [turn.ex:197](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/session/turn.ex#L197) |
| Existing cross-session recall-to-context fixture | [event_job_test.exs:529](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/test/ipse/extension/event_job_test.exs#L529) |
| Context limits, replacement and receipt status admission | [context.ex:5](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/context.ex#L5), [context.ex:166](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/context.ex#L166) |
| After-turn ownership and bounded private answer views | [turn.ex:896](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/session/turn.ex#L896), [lifecycle.ex:435](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/session/lifecycle.ex#L435) |
| Current-session-only history | [history.ex:1](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/history.ex#L1) |
| Native clarification updates the main model's messages | [turn.ex:164](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/session/turn.ex#L164), [questions.ex:17](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/tools/questions.ex#L17) |
| Extension answers resume the extension callback | [invocation.ex:726](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/session/invocation.ex#L726) |
| Append-only transforms and queued busy input | [projection.ex:282](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/extension/projection.ex#L282), [terminal.ex:442](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/lib/ipse/cli/terminal.ex#L442) |
| Shipped runtime/docs packaging and separate artifact import path | [package.sh:14](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/dev/package.sh#L14), [knowledge README:185](https://github.com/lexlapax/ipse/blob/3a5d6c5c50717510c8aab89933f17a7a9ddb5e9c/extensions/knowledge/README.md#L185) |

The Linux archive inspected was
`dist/documentation-audit/341e458-rebuilt/assets/ipse-0.1.0-linux-x86_64-glibc-2.39.tar.gz`.
It is a locally retained asset from the published release; its existing
[release verification record](../2026-10-25-prepublication-docs/index.md) owns
download identity and package verification. This research inspected its member
list; it did not re-certify the archive or execute a new installed walkthrough.

The descriptor probe ran with Elixir 1.20.4 / OTP 29 and no application startup:

```sh
ERL_CRASH_DUMP=/dev/null elixir \
  -pa _build/dev/lib/ipse/ebin -pa _build/dev/lib/jason/ebin \
  docs/archive/2026-10-26-knowledge-productization/catalog-probe.exs
```

It reloads the measured descriptors, Catalog and JSON helpers from source. Other
built modules/dependencies must already be available; it does not build a release.
Loading only declaration owners produces warnings about unneeded runtime callees
not loaded by the probe. Those paths are not invoked. This is a catalog measurement
with individual-admission controls, not a warnings-as-errors compile or Session test.

## Review and verification of this report

Three adversarial passes checked implementation/packaging, prompt/host contracts,
and external evidence. Corrections incorporated into this report include the
outer read-tool approval, tombstone capacity, historical-version limitation,
once-per-turn event timing, separate private views, question-receipt provenance,
consistent consent lifetime and the benchmark metric/model qualifications.
These passes checked the report's claims; they are not a new external product audit.

The source-reloaded catalog probe and its four individual-catalog controls passed
as a measurement: the requested combined catalog is rejected as recorded.
Documentation validation checked 430 Markdown files and 4,031 local links with
zero errors; whitespace validation passed. Runtime/provider code, dependencies
and the accepted roadmap were not changed. No full runtime suite or new live
inference was run for this documentation-only work.
