> Historical first repair record, superseded by the
> [second audit repair](../2026-10-26-p30-p31-plan-review2/index.md) on **2026-10-26**.
> Its developer answers remain authoritative; some design judgments and limits
> were replaced. Use the [current design](../../knowledge-design.md) and
> [current plan](../../plan.md). The original body below is unchanged.

# P30/P31 plan audit and remediation

Dated **2026-10-26**. A developer-supplied read-only audit reviewed `eccf7c7` and
identified five high, eleven medium and six lower-priority planning issues. Its
private scratchpad report was read, not copied into the repository. This record
preserves the findings' disposition and the subsequent developer answers.
The [former plan](prior-plan.md) and [first design](../2026-10-26-p30-p31-plan/index.md)
retain the original claims. Use the [current plan](../../plan.md) for active
status/dependencies and the [revised design](design.md) for detailed contracts.
All repairs below concern the plan; no runtime feature is claimed implemented.

## Decisions after the audit

| Question | Developer answer, recorded verbatim |
| --- | --- |
| Did “Zev” mean TypeSafe's Jev? | Yes—TypeSafe Jev |
| Activation during a conversation? | Next session, with a clear message |
| Saved knowledge permission in `ipse run`? | Reuse saved knowledge permission automatically, without --yes |
| Qualified completion if graph/PDF quality misses? | Yes, with the limitation clearly recorded |
| Narrow Rust PDF-parser exception if Elixir/Erlang is unsuitable? | Yes, allow that specific exception |

The earlier choices remain: automatic useful facts/decisions with visible changes;
persistent project consent; retrieve before asking material questions; route among
enabled sources but ask before changing providers/paid services; include PDF/Word.
The Rust answer permits a specific architectural exception, not a selected library
or unreviewed native dependency. The headless answer authorizes a future narrow
admission change, not a claim that today's runtime already supports it. These
distinctions are reflected in [AGENTS.md](../../../AGENTS.md).

Design judgments made during remediation, rather than falsely attributed user
answers: main-model tool capture by default; optional separate extraction; a small
notes preview before scalable storage; repository/worktree sharing offered in setup;
concrete retention targets; line-oriented enhancement editing; and an interim notes
release checkpoint. Each remains subject to its stated implementation/quality gate.
No publication or paid inference is authorized by this planning work.

## Findings and dispositions

“Addressed” means an implementer now has a specified choice, dependency or testable
contract. It is not runtime verification. The ledger and design link by package ID;
the lifecycle specification is not repeated in both documents.

| Finding | Disposition in the revised plan |
| --- | --- |
| H1: extraction unavailable for most providers | Main-model source-bound tool capture is the default, all main tool protocols covered. Separate extraction is optional. Ollama alone has native schema-bound auxiliary output today; strict validated text extraction also already exists for other routes. No promise of zero continuation cost. |
| H2: default retrieval inherits rejected lexical strategy | Small preview uses bounded complete note inclusion and model read/search tools; larger baseline is explicit bounded search/fusion plus query reformulation. New independent quality bars and a concrete retrieval-remediation increment are mandatory. No hidden embedding account. |
| H3: activation/handoff loses history | Developer chose next **new** session. Existing conversation/resume stays pinned; no automatic handoff or restart. Forget explains already transmitted history separately. |
| H4: headless consent requires broad `--yes` | Developer chose saved knowledge-only authority in `run` without a flag/`--yes`. New admission code must preserve explicit denies and reject workspace/shell/MCP/delegation outside their own grants. |
| H5: P30 appears first but depends on P31 | P31A is the named active entry point, P30A/B parallel. P30C–E use P31B/E; notes consumers satisfy P30 without waiting for graph/PDF. |
| M1: Jev/Zev and local adapter | Confirmed Jev; remove `zev-rs` selection. Keep hosted System One and explicit loopback-compatible endpoint support distinct; no self-hostable Jev claim. |
| M2: poisoning and chat/tool secrets | Default direct user assertions/accepted decisions and typed verified host outcomes only; external/assistant material is separately selected reference evidence. All-path exclusions and source-authenticity/poisoning tests required. |
| M3: separate-process limits and exit queue | Protected per-project ledger with retained OS locks, transaction ordering, worker-slot locks and bounded parked references. Exit stops workers; explicit continuation handles only known unstarted work. |
| M4: planning MCP and decisions | Operator-owned exact per-tool planning-read declaration, never server annotation alone. Undeclared MCP denied. Accepted planning choices remain deferred; explicit later save with revalidation, no auto-flush. |
| M5: editable enhance and billing | Concrete show/replace/accept/cancel flow works with line input; optional editor has a defined handshake. Current main route by default, bounded draft-only request and explicit separate helper selection. |
| M6: clarification before retrieval | Terminal/intent construction may parallelize; integrated notes/document clarification acceptance depends on E/F respectively. Earlier workspace-only prototypes are qualified as such. |
| M7: graph/PDF hard gate and Rust rule | Developer permits qualified completion with quality failures experimental/off, exact limits and follow-up. Safety/resource/provenance gates remain hard. Narrow Rust parser exception recorded; DOCX independently qualifies. |
| M8: heavy first slice and no interim release | C0 uses bounded existing State; C1 scales later. D0 packages notes first, E is an interim release checkpoint before graph/PDF/full store. |
| M9: capture retention | Selective excerpts, not one source per turn; proposed 90-day automatic TTL, explicit pins, 30-day superseded history, seven-day parked candidates, cap warnings/visible pause and turnover tests. |
| M10: unavailable human macOS tester | Recruit at A; automated checks on both OSes and independent fresh-user journeys; explicitly missing human-platform evidence gets a release-time qualification decision, never an invented pass. |
| M11: separate empty worktree memory | Setup recommends repository-wide notes keyed to verified common-dir identity, with folder isolation available. File evidence/workspace authority remains worktree-specific; no merge by remote URL. |
| L1: undefined simple router | Complete-note preview; larger deterministic query-all eligible stores, capped RRF k=60 and stable ties. P30 must compare against that baseline. |
| L2: no capture overhead/cost limits | One bounded ordinary batch/turn, local p95 target, measured token/continuation/end-to-end overhead, optional extractor deadline/save-lag target and explicit finite paid-helper cap. |
| L3: duplicated scope drifts | Short active status/dependency/gate ledger; one replacement detailed design; original prose retained historically. |
| L4: missing commands/naming trial | Proposed `/knowledge` and `/enhance` vocabulary and concrete naming/discoverability trial in A; all syntax labeled proposed. |
| L5: Decisions pricing/residency absent from consent | Dated operation-specific price facts and endpoint/region/cache/account-control display requirements; no inferred ZDR/account eligibility. |
| L6: forget implies lossless conversation erasure | Continue with explicit history limit or start fresh with reviewed bounded note; the latter loses full native history and never happens automatically. |

## Evidence and verification scope

Source review confirmed tool protocols, auxiliary structured-output limits, existing
Memory/State capacity, retained cross-process locks, blanket headless approval,
MCP mutation classification, line-oriented input and handoff contents. Relevant
owners include [provider registry](../../../lib/ipse/provider/registry.ex),
[extension inference](../../../lib/ipse/extension/inference.ex),
[State](../../../lib/ipse/extension/state.ex),
[BudgetStore](../../../lib/ipse/usage/budget_store.ex),
[actions](../../../lib/ipse/extension/actions.ex),
[terminal](../../../lib/ipse/cli/terminal.ex),
[Memory](../../../extensions/bundled/memory.ex) and
[recovery manual](../../operator/recovery.md#continue-in-a-fresh-session).

The [P27 retained comparison](../2026-10-23-p27-heldout-comparison/index.md) supports
the lexical qualification caveat: its supported-answer metric passed while cited
support missed the reference threshold. That frozen workload cannot qualify the
new notes or document paths. Primary TypeSafe/OpenAI references are linked beside
the dated claims in the [design](design.md#p30-interfaces-and-useful-consumers).

Read-only internal reviews independently checked capture/retrieval, lifecycle and
decision interfaces, then checked the rewritten plan. Repairs include bounding
index framing, precise confirmation/proposal binding, preview versus full-store
endurance, regional-processing wording and planning-only authorization.

Actual checks: `elixir dev/check-docs.exs` passes for **435 Markdown files and
4,091 local links**, with zero errors. The prior-plan body matches `eccf7c7`
with only declared relative-link rebasing; the first design body is unchanged
apart from a new supersession notice before it. Whitespace checks pass. No runtime,
live-provider, parser, performance, release or human test was run for this change.
