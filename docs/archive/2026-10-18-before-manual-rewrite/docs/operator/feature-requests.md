> Historical reference only. Snapshot of `docs/operator/feature-requests.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../2026-10-22-before-structural-consolidation/docs/operator/feature-requests.md).

# Choosing how to add a feature

Use this guide when asking Ipse to add a capability, whether for one task, one
project or every session. Prefer an extension when the existing host contracts
can express the behavior safely. A feature's usefulness or complexity does not,
by itself, determine whether it belongs in core. The deciding question is whether
it needs a new guarantee from the harness.

This guide owns the operator decision criteria. The [extension guide](extensions.md)
owns installation, trust, configuration and recovery; the [plan](../plan.md) owns
what is implemented, authorized or deferred. A researched design or an entry in
the plan is not an available API or permission to install it.

## Choose the smallest suitable mechanism

| Request | Preferred mechanism | Condition |
| --- | --- | --- |
| Teach a repeatable procedure, project convention or research method | Skill or scoped instructions | Existing tools suffice; loading text neither executes scripts nor grants permissions |
| Connect an existing search, database, Git/GitHub or other external service | Configured MCP tools, resources or prompts | The server exposes the needed operation; review its permissions, credentials, dependencies and remote effects separately |
| Add a typed model tool or explicit operator command | Extension invocation | Its arguments/results fit the SDK and its effects use supported approved host calls |
| React to a supported prompt/answer boundary or observe live facts/text | Extension notification, feed, event job or text consumer | The supported stage/view, delivery policy and grants match the need; read-only acknowledgments cannot request effects |
| Add ranking, note policy, a report, presentation or a bounded workflow | Extension, optionally composed with bound value services | Existing state, context, tools, questions and model contracts cover all required work |
| Change a guarantee shared by sessions or extensions | Generic core enhancement | An existing contract cannot safely provide the required authority, ownership, persistence, accounting or protocol behavior |

A tool and an extension are not opposing choices: an extension can expose tools.
MCP is a separate integration boundary. Main-agent MCP access does not mean an
extension callback can call MCP; current extension `tool.call` supports the
specified built-in file/shell tools and refuses MCP tool IDs. Value services
return data, not nested effects. A skill can explain how to use either mechanism,
but it cannot create a missing host capability.

## Test an extension proposal against the host contracts

For a future request, ask the implementing agent to establish all of the following
from the running version's documented contracts and code:

1. **Inputs and timing.** Identify the explicit invocation or supported event,
   the exact public/private view and when the result must be available. A feed
   acknowledgment is not a committed write; after-turn work cannot change the
   answer already saved. Do not assume that every internal event is subscribable
   or that jobs run concurrently.
2. **Authority and effects.** List every state, filesystem, external service,
   model and device operation. Map each to a supported grant, operator binding
   and approval. Repository text, generated code and extension output cannot
   grant trust, credentials, execution or a new destination.
3. **Ownership and failure.** Show how cancellation, owner death, timeout and
   incomplete cleanup are handled. Optional observation should follow its
   documented failure policy; required delivery must remain explicit. An
   interrupted effect stays unknown and is never automatically replayed.
4. **Persistence and change.** Specify scope, stable identity needs, revisions,
   concurrent writes, expiration, export/migration and code/configuration
   upgrades. Distinguish backend deletion from cached context, transcripts,
   backups and prior remote transfers. Resume must preserve committed facts
   without silently rerunning callbacks or replacing saved content.
5. **Bounds and accounting.** Fit the documented bytes, records, actions,
   deadlines, queue and context limits. Use configured model profiles and the
   host's canonical usage/admission path for supported inference. Do not hide
   extra model calls, paid service work or downloads in a callback. Unknown or
   uncovered costs remain explicit.
6. **Selection and evidence.** Keep optional behavior independently selectable,
   configurable and disabled by default. Prove disabled-side-effect parity,
   permission refusal, scope isolation, cancellation and recovery, then test
   against an installed release where applicable. Measure algorithm quality
   separately from protocol correctness and identify untested platforms.

If these checks pass using existing contracts, implement the feature as an
extension without changing the agent loop. Prefer ordinary approved tools or a
skill if no executable extension is needed. Trusted executable extensions still
run with operator OS permissions: a separate VM and capability schema are not
an OS sandbox. Being able to open a socket or write a file from trusted code is
not evidence that doing so satisfies the host approval/accounting contract.

## When a core change is justified

Core owns the guarantees that extensions rely on: session/task ownership,
approvals, credential and destination authority, provider transport and
continuations, canonical accounting/admission, journals/recovery, OS confinement,
and the SDK's bounded delivery and storage contracts.

Change core when a feature needs a missing guarantee in one of those areas,
or when a defect breaks an existing guarantee. Examples include a new approved
external-operation bridge, an accounted embedding request type, a genuinely new
stream/media transport, or a reviewed way to invalidate retained context across
sessions. A new database, ranking algorithm, graph representation or prompt
policy usually belongs behind an extension boundary instead.

A missing contract is a reason to design a small generic enhancement, not to
bypass it with shell, worker networking, copied credentials, a hidden model call
or an unbounded background process. The enhancement should be versioned where
compatibility requires it, reusable by more than one domain feature, and covered
for grants, bounds, cancellation, uncertainty and resume. After that foundation
is verified, keep the requested domain behavior in the extension. A core feature
must not become a mandatory memory engine, provider, database or workflow.

## Apply the criteria to likely requests

| Example | Extension or tool responsibility | Core boundary to check |
| --- | --- | --- |
| Prompt annotation or answer formatting | Selected transforms with bounded attributed text | Existing hooks suffice; annotations remain untrusted context and cannot rewrite core permissions |
| Short-term or long-term memory (P26A/P26B) | Explicit notes, lexical ranking, provenance, retention, suppression and migration policy | Stable logical storage, bounded reads and cached-context/recovery behavior must be proved; a storage tombstone alone does not erase earlier recall |
| Research and lexical RAG (P27A) | Search strategy, source/citation ledger, corpus/chunk policy and ranking | Existing main-agent configured MCP can be used now; autonomous extension MCP effects require a separately reviewed host bridge |
| Graph or hybrid/embedding retrieval (P27B) | Extraction, graph/index adapters, traversal and retrieval comparisons | Existing one-shot text inference is not an embedding API; new embeddings need explicit destination, vector bounds, usage/cost and cancellation contracts |
| Knowledge graph listening to prompts | Supported selected private event view, extraction and separately approved storage | Notifications/feeds alone grant no effects; same-turn recall needs an awaited job and committed context before inference |
| Token-cost dashboard or diagnostic exporter | Reports, configured estimates and selected sinks | Core remains responsible for canonical facts, budgets and bounded delivery; turning diagnostics off does not disable journals/accounting |
| Voice input/output | Configured STT/TTS orchestration and presentation where supported | Text delivery is available; device access, audio streams and realtime interruption/accounting require their own supported contracts (P28 remains deferred) |
| Project Git/GitHub workflow | Skill plus reviewed tools/MCP, or an extension that sequences supported calls | Ordinary approvals still apply; authentication, remote effects and publication are not implied by reading a project or installing a skill |

These examples describe ownership, not completion claims. Consult the current
[plan](../plan.md) and [verification record](../developer/testing.md#current-evidence-and-next-checks)
before depending on a proposed capability. Temporary selection applies to a new
session using reviewed configuration; live installation or hot activation is
not implied.

## What to include in a feature request

Give Ipse the desired result, when it should run, whether it is temporary or
persistent, the intended project/operator sharing scope, and any allowed external
services, models, retention or spending limits. Ask it to return:

- The proposed mechanism and the existing contracts that cover it.
- Any specific missing generic host guarantee, with the smallest justified core
  change and a compatibility/recovery plan.
- Required permissions, configuration, dependencies and approvals, including
  what leaves the machine and which costs are not covered by host budgets.
- Acceptance checks for behavior, disabled parity, failure/recovery and quality,
  with implemented, proposed and unverified claims kept distinct.

Ipse may help author an extension, but generated code still needs review,
explicit operator trust and ordinary action approvals. Installing, enabling and
promoting it to persistent configuration are separate decisions. See
[selection and execution boundaries](extensions.md#recovery-and-execution-boundaries).
