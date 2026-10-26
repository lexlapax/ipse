# Prior P30–P32 plan at eccf7c7

Historical snapshot dated 2026-10-26. Source: `eccf7c7:docs/plan.md`,
P30 through P32. The original bodies are retained with relative archive links
rebased. Use the [current plan](../../plan.md) and [revised design](design.md)
for the replacement; the [audit disposition](index.md) explains the changes.

## P30: advisory decision engines

**Planned; unimplemented.** Deliver a separate typed decision operation plus
usable knowledge consumers. A classifier can assess supplied candidates and choose
among allowed alternatives; it cannot generate missing evidence, establish truth
or authorize an effect. The [delivery design](../2026-10-26-p30-p31-plan/index.md#p30-as-a-usable-decision-capability)
records the verified interfaces and their differences.

Candidate adapters are [OpenAI Decisions](https://developers.openai.com/api/docs/guides/decisions)
at `POST /v1/decisions` and [TypeSafe System One](https://docs.typesafe.ai/api/system-one)
for Jev, using explicit engine/profile/endpoint/credential/billing choices.
An operator-run loopback engine is optional. The identified
[Zev candidate](https://github.com/bhubbard/zev-rs) is experimental: similar endpoint
names do not establish wire, model or quality equivalence. Pin and qualify its
actual subset before selection. No engine, SDK, dependency or live account access
is established by this plan. Reverify external contracts before implementation.

### Contract and actual consumers

Expose a versioned `host.decision` effect beside the existing model/embedding
operations. Requests contain bounded evidence, named questions, string choice IDs,
ordered score levels or predicates. Preserve finite probabilities, fractional
scores, distributions and separately identified provider confidence. Validate
identities, types, ranges, distribution coverage/sums and score consistency;
never coerce uncertain probabilities into permissions. Structural corruption
invalidates the result. Valid per-question
refusals can coexist with independent answers; dependent actions need every
prerequisite answer. Retain uncertainty, insufficient evidence, refusal, malformed
output, timeout and budget denial as distinct outcomes.

| Consumer | Useful behavior | Boundary |
| --- | --- | --- |
| Knowledge routing | Select local notes, document search, graph or a combination for a query | Only enabled, eligible sources and approved services within current limits |
| Capture assessment | Assess durability, support, ambiguity or conflict of extracted candidates | Cannot invent a candidate/source, certify truth or grant write permission |
| Clarification assessment | Help identify a material unresolved choice after retrieval | Optional measured strategy; no mandatory extra call for every prompt |
| Provider/profile routing | Assess a finite set of explicit routes | Suggest a change; ask before changing model providers or paid services |

Decision dispatch itself requires permission, a reserved budget and a journaled
intent before any egress. Every consumer maps typed results through deterministic policy, then ordinary
permission, version and budget checks before a journaled effect. Filter prohibited
alternatives before classification. A decision can choose within prior consent;
it cannot expand that consent or silently change a provider/billing destination.
This makes automatic knowledge routing useful without repeating approval prompts.

The host owns cancellation, bounded transport, intent/outcome records, usage and
atomic reservations. Record engine/resolved model, rubric, input-source versions,
policy revision, selected action and override reason without diagnostic source
text dumps. Do not infer zero cost from missing prices or double-count cache tokens.
P31's project budgets constrain decision calls alongside extraction/embedding.
No fallback to another engine or chat model. A configured failure policy may defer,
stop or use a disclosed fixed local strategy; unavailable/uncertain is never a
successful decision. P31 also has an explicitly engine-free baseline.

### Delivery and acceptance

| Package | Deliverable |
| --- | --- |
| P30A | Neutral typed contract, supported adapter subsets, consumer inputs and pinned protocol fixtures |
| P30B | Engine profiles/adapters, owned host effect, validation, accounting, admission and cancellation |
| P30C | Per-consumer policy mappings, finite allowed alternatives and visible uncertainty/failure; integrate P31B consent |
| P30D | Real retrieval-routing and capture-assessment consumers after P30C and P31E/F; graph after P31G; optional separately qualified clarification strategy |
| P30E | Independent per-consumer evaluation, installed integration, manuals and separately recorded opt-in live eligibility |

P30A/B can progress alongside P31's host contracts. P30 completion requires real
consumers, not an unused wrapper or a profile-suggestion demo. Compare each consumer
against deterministic or existing-model behavior on independently labeled inputs,
including asymmetric error costs, abstention, quality, latency and spend. Freeze
thresholds before evaluation; preserve failures and engine/model/rubric versions.
One passing consumer does not qualify every use. An unqualified strategy stays
experimental/off even when its adapter passes protocol tests.

Required checks cover valid/invalid/mixed-refusal output, independent versus
dependent questions, oversized/slow/disconnected services, owner death, cancellation
during an actual request, zero dispatch on denial, accounting and no substitution.
Installed P31 fixtures must prove the decision changes an eligible route or capture
outcome without widening authority. Separately qualify live access and each enabled
automatic strategy; fixtures do not prove model quality or account eligibility.

## P31: usable knowledge and prompt assistance

**New planned milestone; unimplemented.** The developer selected this scope after
the [post-release assessment](../2026-10-26-knowledge-productization/index.md).
P26's explicit notes and P27's technical packages remain completed within their
original scopes. P31 makes their capabilities usable through the installed product.
Voice/media moves to P32; P20 remains completed self-development.

### Product behavior and settled choices

An ordinary user enables project notes, documents or relationships through guided
setup, works normally, sees useful facts/decisions saved, and receives relevant
cited recall in later sessions. They can inspect, correct, forget, pause, disable
and export knowledge without building packages, preparing hashes, writing JSON
or arranging MCP for local use. Features remain independently selectable and off
until enabled; basic local retrieval needs no embedding or decision service.

The developer chose **automatic useful-fact/decision capture with visible changes**,
**permission that persists across project sessions**, and **checking available
information before asking about material missing choices**. Do not reduce this
to proposal-only capture or repeated per-session approval. Guided setup makes
source scope, destinations, retention and finite limits concrete before enabling.
Automatic extraction may use an explicitly selected model under that policy;
local storage does not imply local inference or authorize sending all source text.

The developer also chose **automatic routing among enabled knowledge sources,
with a new choice before changing model providers or paid services**, and **PDF
and Word ingestion within P31**. The initial proposed format boundary is text,
Markdown/code, text-bearing PDF and Word `.docx`; scanned/OCR, legacy `.doc` and
unsupported/encrypted inputs need explicit support decisions and honest per-file
results. They cannot be silently presented as indexed. PDF/Word work is required
for P31 completion even when plain text is the first development slice.
The [delivery design](../2026-10-26-p30-p31-plan/index.md) owns the detailed
journeys, proposed contracts, staged dependencies and qualification cases.

### Required boundaries and lifecycle

1. **Enablement and distribution.** Ship compatible disabled knowledge artifacts
   and a catalog that admits the supported feature combinations within bounded
   context. Explain active/pending/disabled/error states. Reconcile current pinned
   session artifacts through an explicit safe activation/handoff, preserving the
   conversation and unknown-effect rules. Configuration edits alone cannot hotload
   a package. Normal users must not repair fingerprints or copy prompts manually.
2. **Saved permission.** Store protected project consent separately from project
   configuration. Bind source/features, effect classes, storage/sharing, concrete
   service/model/billing identities and finite period budgets. Cover outer tool
   dispatch and inner host effects. Fresh/resumed sessions reuse covered consent;
   changed scope/service/limits require a concise change review. Revocation fences
   concurrent dispatch/publication with an atomic ordering and acknowledgment
   boundary, not independent checks that race. Artifact trust is separate from
   semantic consent; reviewed compatible upgrades should not re-ask unchanged scope. Deny rules,
   read-only modes, headless `--yes` and separate child authority still apply.
3. **Evidence and sustainable storage.** Retain stable source identities/versions,
   roles, exact support, provenance, observed/event time and derivation links.
   Evaluate maintained Elixir/OTP/Rust storage facilities before selecting an
   adapter; no mandatory database service. Replace the current small-namespace
   capacity bottleneck for ordinary collections. Bound disk, queries, jobs and
   shared project spend across concurrent sessions, including unresolved effects.
4. **Automatic capture.** Capture eligible conversation facts, decisions and
   relationships; distinguish user statements, quoted evidence, tool observations
   and assistant proposals. Validate citations, handle negation/uncertainty,
   deduplicate, expose conflicts and show a compact saved/changed/skipped receipt.
   Never treat recalled/generated text as independent corroboration. Provide
   complete bounded turn evidence and joins; today's short private views are
   insufficient for long-turn capture. Define eligibility/status for failed,
   cancelled and question-waiting turns; the current success-only hook cannot
   stand for every settlement. Cancellation stops pending capture.
   No recursive self-capture.
5. **Documents and recall.** Preview selected files/folders and exclusions; acquire
   bounded admitted bytes, track revisions/deletions and report unsupported or
   failed inputs. Include PDF/Word extraction, bounded parser resources and
   original-file/page/paragraph citations; no macros or automatic external fetches.
   Evaluate maintained parsers and approve/inventory any non-Elixir/Rust dependency
   before adoption. Retrieve once per accepted prompt, rank within a shared context
   budget and preserve inspectable source citations. Clear stale contributions
   after change/forget/expiry/failure and revalidate before every model dispatch,
   including same-turn continuations. Explain the limits on already transmitted
   text/native history. Required-source failures stop dependent work;
   optional failures disclose a limitation. Semantic modes require explicit profiles.
6. **Graph and research.** Derive typed entities/relationships automatically from
   eligible evidence, support reversible aliases/merges and conflicting assertions,
   and qualify temporal answers against retained versions. Share/transfer Research
   evidence through explicit contracts; do not assume effectful cross-extension
   calls already exist. P30 may advise retrieval/capture within the same policy.
7. **Correction, forgetting and upgrades.** Propagate source invalidation across
   notes/chunks/graph/vectors/context, including disabled stores before re-enable.
   Suppress managed lineage and known aliases against late capture, reindex and
   old-backup import. Explain journal/backup/
   external-copy limits; do not promise perfect semantic erasure. Provide preflight,
   export, interruption recovery and rollback for versioned P26/P27 migration;
   old writers cannot resurrect forgotten facts. Project moves/sharing are explicit.
8. **Responsive owned work.** Display completed answers promptly and let a new
   prompt proceed without waiting on unrelated capture. Bound Session-owned queues,
   concurrency and checkpoints; prioritize foreground work. Show pending/partial/
   failed/unknown outcomes. Close, cancel, revoke and owner death stop dependent
   work; unknown effects are never automatically replayed. No unattended daemon.
9. **Prompt assistance.** Retrieve authorized information first, group material
   questions and return answers to the executing model. Bound repeated clarification;
   headless required unknowns return an actionable incomplete outcome. Offer an
   explicit editable enhancement preserving original/proposed/accepted text.
   Bind accepted intent to a versioned host state/consuming request and refuse
   stale confirmation. Unaccepted drafts are not user decisions. Planning-only
   interaction has a host effect ceiling across tools/extensions/MCP/children/resume, with an explicit
   transition to execution. Entry accounts for already in-flight effects before
   acknowledging the ceiling; no stale queued work gains authority on exit.
   Queued input and interrupt semantics remain visible.

Domain policy, extraction, retrieval, graph logic and prompt assistance belong in
extensions/skills. Core changes are limited to reviewed gaps in authority, evidence,
storage/effect ownership, context validity, accepted intent and lifecycle. Do not
introduce a workflow framework, shell recursion or broad filesystem grants to
avoid those boundaries. The credential-free demo remains usable.

### Delivery order

| Package | Deliverable and dependency |
| --- | --- |
| P31A | Freeze journeys, interaction vocabulary, source/retention/capacity envelope, labeled acceptance data and host-contract gaps |
| P31B | Protected persistent consent, revocation, aggregate project reservations and effect/mode admission; follows A |
| P31C | Evidence versions, bounded storage, source access, suppression and migration; follows A/B, with early storage prototypes |
| P31D | Shipped artifacts, usable catalog, guided setup/status/disable and safe activation/upgrades; overlaps B/C |
| P31E | First full notes journey: enable → ordinary conversation → visible automatic capture → fresh-session recall → correct/forget; follows B/C/D |
| P31F | Text, PDF and Word file/folder ingestion, change tracking and cited retrieval with progress/recovery; builds on C/D/E |
| P31G | Automatic entity/relationship capture, conflict/alias correction and time-qualified retrieval; builds on C/E and shared F acquisition |
| P31H | Research evidence transfer and cross-store invalidation; integrate optional P30 retrieval/capture strategies when ready |
| P31I | Retrieve-first clarification, editable accepted prompt and enforced planning interaction; parallel after A/B and the intent contract |
| P31J | Full installed journeys, adversarial/quality/resource/human checks, upgrade rehearsal and coherent operator/developer manuals |

The smallest complete delivery is P31E, not a new `/enable` command over today's
manual setup. P31E requires responsive owned capture and usable capacity, even if
its first fixture is small. P30 and later features develop alongside that slice.
P31's engine-free workflow must pass independently; P30D/E qualify the optional
strategies without blocking normal knowledge use on a third-party account.

### Acceptance

P31A freezes workload sizes, error-cost thresholds and latency/resource budgets
before evaluation. The design includes an explicitly unmeasured starter capacity
profile for storage prototyping; freeze the supported envelope from those results.
Do not reuse P27's exposed workload or scores as proof of automatic capture.

- Fresh installed users complete enable/capture/later-session recall, document
  import, a relationship question, correction/forget, permission inspection/revoke,
  disable and upgrade. Include coding and non-coding work and Linux/macOS evidence.
  Record assistance, elapsed time and permission interruptions. Covered automatic
  work causes zero repeat approval prompts across sessions.
- Measure supported-attribution precision and important-fact coverage separately
  from entity false merges, retrieval, cited answers and temporal correctness.
  Include misleading instructions, hypotheses, negation, ambiguous names, conflict,
  stale evidence and assistant suggestions. Measure clarification necessity and
  task completion with human input, not only simulated users or callback tests.
- Prove no scope crossing, forbidden dispatch, stale publication or unknown-effect
  replay in deterministic adversarial fixtures. Cover concurrent sessions, reduced
  budgets, policy revocation during effects, long answers, cancellations during
  actual work, missing/partial sources, context invalidation and old-backup import.
- Sustain a fixed active dataset through repeated update/correct/forget cycles
  without exhausting permanent tombstone slots. Test resource bounds, recoverable
  migration, matching whole-package catalog admission and actual installed artifacts.
- Run source/native/demo/package and Linux/macOS checks for changed runtime paths.
  Qualify actual selected live extraction/decision profiles separately from fixtures;
  document unavailable services without silently substituting them. Rewrite affected
  manuals around the completed user journeys and contributor contracts; verify
  examples/links and preserve dated evidence. A working component is not P31 closure.

Deferred: voice/media (P32), team/cloud synchronization, universal historical-chat
mining, autonomous service installation, unattended background daemons, general
workflow graphs and automatic model-provider or paid-service switching. PDF and
Word ingestion remain required within the explicitly declared format boundary.

## P32: voice and realtime media

**Deferred; unimplemented. Previously P31; older archives call it P28 or P24.**
Keep the requested scope for a future delivery; it is no longer ahead of
architecture/security review or self-development.
Build on the owned text/provider and P23 accounting foundation. Start with a
chained STT → admitted text agent → TTS extension/client; then add a versioned
realtime provider/session capability for bidirectional transport, interruption,
turn control, playback acknowledgment and reconciliation of generated versus
played history.

Voice choice, STT/TTS/device adapters and UI belong in extensions/clients. Core
owns resource lifetime, admission, approvals, cancellation, flow control and
provider continuation integrity. Use a separate media data plane, ephemeral raw
audio by default, canonical transcripts/usage and explicit endpoint/device/billing
choices. Text subscription authentication does not establish audio eligibility.

Acceptance: synthetic split/slow/disconnected media, revised interim transcripts,
barge-in, stale/unplayed frames, owner death, approval waits and no-replay recovery;
source/package checks and separately recorded opt-in live account/device checks.
Evaluate maintained Elixir/Rust/OS facilities and approve/inventory external
dependencies before adoption. No codec, frontend runtime or service is selected.
See [media boundaries](../2026-10-18-before-manual-rewrite/docs/developer/runtime-capabilities.md#text-and-media-are-distinct-from-diagnostics).
