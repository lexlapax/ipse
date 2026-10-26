# Second P30/P31 plan audit and repair

Dated **2026-10-26**, source baseline `7f4857b`. The developer supplied a second
read-only audit identifying two high, five medium and three low planning issues,
then requested repair followed by our own adversarial audit and further repair.
The private scratchpad report was read, not copied into the repository. This
record concerns planning only: no runtime behavior, live model quality or storage
performance is claimed verified.

Use the [current plan](../../plan.md) for status/dependencies and the
[current design](../../knowledge-design.md) for detailed proposed contracts.
The [previous plan](prior-plan.md), [previous design](../2026-10-26-p30-p31-plan-review/design.md)
and [first audit record](../2026-10-26-p30-p31-plan-review/index.md) preserve provenance.
The first audit's verbatim developer answers are unchanged. The repairs below are
design judgments within those choices, not additional answers attributed to the
developer. No runtime implementation, provider spending, dependency selection or
publication is authorized by this repair.

## Supplied findings and dispositions

“Addressed” means a concrete dependency, contract and acceptance requirement is
specified. It does not mean its future implementation or benchmark has passed.

| Finding | Repair |
| --- | --- |
| N1 high: preview fills permanently in ordinary use | State-only C0 becomes an internal prototype. C1a sustainable notes storage is required before E's interim release; C1b adds document/graph scale later. Require 30/90-day workloads and annual turnover, useful capacity, safe suppression reclamation and old-import floors. No future migration dependency for ordinary continued use. |
| N2 high: P30 has little useful work and no completion rule | Finite frozen experiments, zero-call bypass for fitting notes and no alternatives, large-set selection plus shadow candidate assessment. Measured negative results close an experiment; missing evidence remains unverified. Hard operation gates remain required; P30 may finish with no qualified default strategy. Later multi-source routing is separate. |
| N3 medium: generated headless prompts treated as human assertions | Host input-origin classes distinguish `run_input` from interactive attestation. Default prose candidates await bounded review; selected reference intake remains attributed. Saved permission still automatically admits eligible host-verified outcomes without `--yes`. Test useful automatic saving as well as injection rejection. |
| N4 medium: yes has no identified proposal | Reuse native question identity or a bounded host-generated pending proposal with exact text/version/hash and visible focus. Only an unambiguous interactive answer to the displayed version accepts it. Stale, unseen, multiple and headless affirmatives cannot. Direct facts require no added approval. |
| N5 medium: retention surprises and broken temporal history | Explicit remember pins unless duration supplied; directly stated enduring preferences persist. Ordinary facts retain 90-day TTL without renewal by model reads. Current temporal assertions retain support until change/forget; history retains at least 365 days after supersession. 30-day cleanup applies only to obsolete display/index revisions. Preserve imported TTLs unless a migration policy is selected. |
| N6 medium: enhance absent on default subscription route | Baseline is an ordinary main-Session draft turn with native history and the selected provider/billing, not extension auxiliary inference. A freezes contract; I implements default-route checks. Enforce effect ceilings across callbacks, explicit acceptance as a new turn, and no unsupported ChatGPT output cap. |
| N7 medium: forged worktree joins another memory | Protected admitted root/common-directory mapping plus reciprocal registered admin/backlink checks before any recall. Workspace metadata alone cannot confer membership. Replaced, moved, spoofed and unsupported layouts need explicit admission with no inherited knowledge. |
| N8 low: history growth omitted | Include call/results, later input replay, native-history/journal growth, compaction frequency/cost and near-limit cases in matched 100/500-turn overhead checks. Keep compact receipts; preserve native pairs and unknown-effect evidence. |
| N9 low: model byte offsets unreliable | Supply exact quotes and host occurrence/version/chunk IDs. The host requires a unique match and derives UTF-8 offsets. Repeated/missing/normalized/changed quotes fail visibly. |
| N10 low: first journey uses enable too late | Proposed standalone setup precedes first chat. Existing-chat enable and unchanged resume have separate next-new-session acceptance. |

## Own adversarial review

Three parallel source-informed reviews cover storage/retrieval, decision/draft
semantics and evidence/lifecycle. A second pass reviews the actual edited design
and ledger for contradictions and missing implementation contracts. It found seven
additional ambiguities; all were repaired, then the affected reviewers checked the
actual repaired text again:

| Finding in our edited draft | Further repair |
| --- | --- |
| A1: a blanket zero-call rule also prohibited unqualified evaluation and candidate assessment when notes fit | Scope production bypass per consumer. Explicit bounded experiment permission/budget can admit unqualified shadow calls without publication; ordinary knowledge consent cannot. |
| A2: notes retrieval remediation was assigned to later F | E owns notes search/selection/citation remediation, supported by C1a; F owns document remediation. Neither release can defer its failed quality gate to the other. |
| A3: enhancement acceptance could imply exiting planning/read-only | Accept exits only draft mode and submits a new turn under the enclosing mode/current authority. Add acceptance-while-planning/read-only coverage. |
| A4: “up to 2,000 notes” could qualify using mostly tiny collections | Require a separate 2,000-active-note, over-context test stratum with independent thresholds and targets absent from initial context/index pages. |
| A5: a current temporal assertion could expire before its first supersession | Retain current temporal support until correction/supersession/forget, show staleness, then apply historical retention. Test first change after day 90. Freeze the workload's combined persistent mix, historical changes and payload counts so capacity claims are finite and meaningful. |
| A6: the model had no specified way to obtain required source IDs | Add a bounded host-issued per-turn source index and evidence read contract, scoped to authorized occurrences, preserving native authors/history and explicitly reporting unavailable evidence. Count its overhead. |
| A7: prior-support validation could reject a genuinely new recommendation | Pending recommendations may contain unverified assistant claim text. Validate shape/exclusions/optional references; the rendered proposal plus actual user acceptance proves the selected decision, not its premises' objective truth. |

The follow-up checks found no remaining material contradiction in their bounded
storage/retrieval, decision/draft and lifecycle/authority scopes. This is plan
review, not proof that the future implementation is correct. The 24/64-MiB notes
envelope remains provisional and must be measured against the frozen workload.

## Evidence and checks

Read the relevant whole documents and source owners, including
[State](../../../lib/ipse/extension/state.ex),
[CLI input](../../../lib/ipse/cli.ex),
[Session Turn](../../../lib/ipse/session/turn.ex),
[Provider](../../../lib/ipse/provider.ex),
[OpenAI adapter](../../../lib/ipse/provider/openai.ex),
[extension inference](../../../lib/ipse/extension/inference.ex),
[workspace discovery](../../../lib/ipse/workspace.ex),
[saved question validation](../../../lib/ipse/session/saved.ex) and
[extraction adapters](../../../extensions/knowledge/src/adapters.ex).
The new plan relies on these inspected limits without presenting new commands as
existing behavior. Whole-document review of the operator Memory chapter, developer
knowledge chapter and both audience indexes confirmed their current-behavior
guidance remains distinct from the proposal. Current manuals remain authoritative
for the released product; this change alters no runnable examples or runtime source.

Actual checks: `ERL_CRASH_DUMP=/dev/null elixir dev/check-docs.exs` passes for
**438 Markdown files and 4,130 local links**, with zero errors. Whitespace checks
pass. The prior-plan body matches `7f4857b` with declared relative-link rebasing and
trailing section-separator whitespace normalized;
both earlier archive bodies are unchanged after their new supersession notices.
No runtime test, benchmark, parser trial, provider request or human journey ran for
this documentation-only change. No numerical target above is a measured result.
