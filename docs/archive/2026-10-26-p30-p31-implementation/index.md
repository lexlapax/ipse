# P30/P31 implementation record

Dated **2026-10-26**. Implementation was authorized against clean source
`fbb207d` on branch `codex/p30-p31`. This is a dated engineering record, not a
current-behavior manual. The [plan](../../plan.md) owns package status;
the [operator manual](../../operator/index.md) owns shipped procedures.

The [complete amended proposal](baseline.md) is frozen from
`docs/knowledge-design.md` at `fbb207d`. Its body is unchanged except relative-link
rebasing; a historical notice was prepended. The [provenance manifest](manual-provenance.json)
records source and snapshot hashes. The former live design is now a pointer with
preserved section targets. Later decisions below amend this baseline explicitly.

## Authorization and external evidence

The implementation task covers both milestones, full tests, an adversarial
post-implementation audit and a review handoff. It does not authorize publication.
The developer selected these finite qualification limits in this conversation:

- Up to **300** calls on Ipse's configured ChatGPT subscription route.
- Up to **1,000** local Ollama calls.
- Up to **12 GiB** of model downloads for the primary Qwen embedding/4B answer pair.
- Prepare human journeys; actual independent human and macOS use remain pending.

The configured main route is ChatGPT, requested model `gpt-6.1-sol`. Only Ipse's
own documented authentication is used. No Codex credentials or private transcripts
are imported. Paid API/hosted P30 engines have no selected account/spending cap;
leave their live qualification open. The allowance is a ceiling, not a target.
Do not repeat failed requests automatically. Track consumed calls in this record.

Ollama **0.40.5** is already installed. Resident tags include `qwen3.5:9b` and
`llama3.2:3b`; neither silently substitutes for the primary embedding/answer pair.
Mutable tags and abbreviated list IDs are discovery data, not immutable model proof.
No model download or local inference had run at the initial inventory checkpoint.
Later, the explicitly selected primary pair was pulled to
`http://127.0.0.1:11434`. The [provisioning receipt](ollama-provisioning.json)
records full reported digests, sizes, metadata and runtime. Summed artifact size
is **3,963,324,792 bytes**, below the 12-GiB allowance; this is an upper bound on
new artifact payload before shared-blob reuse, not measured network transfer.
No local inference has run. Download success establishes neither quality nor
resource/offline qualification. No daemon configuration or existing model was changed.

## P31A contracts and evidence

- [Host-owned contracts and package mapping](contracts.md).
- [Storage/parser evaluation and selected implementation direction](selection.md).
- [Qualification protocol and provisional workloads](qualification.md).
- [Independent fresh-user journeys](journeys.md), prepared but not executed by a person.
- [Independent frozen qualification inputs and private-answer provenance](independent-data.md).
- [Incremental adversarial foundation audit and repairs](foundation-audit.md).
- [Internal protected control ledger audit and repairs](control-audit.md).
- [Control compaction, maintenance headroom and boundary repair](control-compaction.md).
- [Actual-owner transactions and protected project identity](transaction-identity-component.md).
- [Native operator-channel incremental audit and fixture repairs](operator-channel-audit.md).
- [Session input witness audit and source-boundary repairs](session-input-audit.md).
- [Versioned reference projection audit and replay repairs](reference-audit.md).
- [Sustainable collection storage component and measurement provenance](storage-component.md).
- [Declarative collection publication constraints](collection-policy-component.md).
- [Protected collection SDK, source proofs and replay bindings](collection-sdk-component.md).
- [Native read ownership and staging-frame ordering](native-read-component.md).
- [Admitted decision operation, incremental review and controls](decision-operation-audit.md).
- [Optional document parser, bounded staging and package evidence](document-parsers.md).
- [Fixed-revision source and platform verification receipts](verification.md).
- [Nonpublishing interaction model](../../../dev/knowledge/interaction.exs) and
  [boundary tests](../../../test/dev/knowledge/interaction_test.exs).
- [Finite main-route pilot](../../../dev/knowledge/pilot.exs),
  [explicit runner](../../../dev/pilot-knowledge.exs) and
  [dispatch/cap tests](../../../test/dev/knowledge/pilot_test.exs).

The interaction model exercises next-session activation, explicit displayed
acceptance, stale/cross-client/expired/disabled refusal, original-source provenance,
multiple pending cards, draft replacement, one-use consumption and cancellation.
Its terminal-origin proof is explicitly **simulated**. Passing it establishes a
contract observation, not real terminal attestation or model adherence. It performs
no filesystem publication, model call or task effect.

The pilot uses three 20-turn exposed synthetic sessions on the configured main
route. It declares only the fake capture tool, validates source quotes, returns
nonpublishing receipts, and allows at most one continuation per turn (120 requests
total). It refuses configured shared budgets because direct provider calls cannot
enforce them. It neither selects an alternate route nor caps the unsupported
subscription output-token field. Input/response bytes and provider deadline remain
bounded. Request failures stop the pilot. Missing visible text has null TTFT.

Initial focused verification: `mix test test/dev/knowledge` passed **11 tests**;
the subsequent baseline-preservation test brought that directory to **12 tests**.
After protocol and audit repairs, the combined decision/probe suite passes **35
tests**. The credential-free demo, formatting, strict compilation and documentation
checker passed. The full pre-repair suite passed 1,794 tests with 36 exclusions;
full post-repair verification remains separately recorded.
Mix required loopback permission in this execution environment; TLS/tests were not
weakened. Full source, native, package, model-quality and human checks are separate
gates and have not been inferred from these tests.

### First actual main-route pilot

The [sanitized measured receipt](chatgpt-pilot.json) retains exact probe/data hashes,
per-request numerical metrics and first outcomes, without model text, attribution
IDs, credentials or transcript dumps. The run completed **60 turns, 102 requests,
42 capture continuations and 42 proposed items**, all with uniquely matching source
quotes. It published **zero** records. This consumes **102/300** authorized
subscription calls; **198 remain**. Local calls/download consumption remains zero.

The exposed pilot flagged concrete concerns: all items were assigned persistent
(30) or temporal (12), with **no automatic category**; all three uncertain-statement
cases proposed an item, and repeated facts proposed duplicates. Do not call that
semantic success. The receipt contains counts/size/category rather than generated
claim text, so independent entailment/usefulness assessment is unavailable for this
run. Before integrated qualification, add a private, explicitly retained synthetic
candidate audit record and independent labels; never infer 42 useful unique facts
from 42 exact quotes. No workload ratification follows from this pilot alone.

Request duration p50/p95 was **4.12/6.28 seconds**; first-visible-text p50/p95 was
**2.47/4.36 seconds** over 60 requests. The other 42 requests were tool-only with
null TTFT. These are request-level observations, not user-to-answer timing,
paired knowledge-on/off overhead or cache-isolation evidence. No invoice cost is
inferred for subscription calls. The 20-item/day useful-intake floor and capacity
mix remain provisional pending independently assessed integrated sessions.

## Open readiness items

Pilot usefulness labels are development-authored, not independent held-out labels.
The 2,000-note/20-items-per-day floor remains provisional until useful intake and
class mix are independently assessed. P31B/C0 may proceed from frozen structural
contracts, but C1a/E cannot claim final workload or semantic acceptance from this
prototype. Real verified terminal input, host context projection, consent,
sustainable storage and capture are not implemented by the development model.

Recruitment is an explicit open item: the developer requested prepared journeys,
not a claim that a tester exists. Mac automated/human evidence and P30 live-engine
access remain distinct open items. Record every later qualification at its actual
source revision rather than updating historical success claims.
