# Extension architecture proposal

Research reviewed on 2026-10-16 against repository `3ad33b3`. This is the P22
design proposal, not an implemented API, loader, hook configuration or memory
service. Names and limits below are proposed contracts. Existing skills, explicit
MCP tools and provider adapters remain the available extension points.

## Recommendation

Use a small versioned Elixir behaviour and OTP-owned workers, with two distinct
interfaces: lifecycle observation and narrowly scoped data transformation.
Keep approvals, provider selection, journaling, compaction validation and process
ownership in the host. Reuse skills for instructions and MCP for explicitly
configured external capabilities. An extension may compose those facilities;
it should not replace the session loop with a mandatory workflow engine.

This recommendation is an architectural inference from the primary sources
below and the current implementation, rather than a claim that one upstream
plugin API can be adopted unchanged.

## What other harnesses do

| Harness | Observed mechanism | Lesson for Ipse |
| --- | --- | --- |
| OpenCode | Its main documentation describes local JS/TS modules or configured npm plugins, ordered hooks, tool before/after events and experimental compaction customization. Packages can install during startup. | Use explicit composition order and distinct lifecycle stages; keep executable loading/install an operator action. [Main docs](https://opencode.ai/docs/plugins/) |
| OpenCode V2 documentation | Domain-owned registrations distinguish prompt admission, model context and auxiliary requests; setup can return cleanup. V1 plugins require migration. | Version the API and separate prompt admission from each model call. Treat this as a separately documented V2 contract, not proof that every installed V1 supports it. [V2 API](https://opencode.ai/v2/docs/build/plugins/), [migration](https://dev.opencode.ai/v2/docs/build/plugins/migrate-v1) |
| Codex | Official hooks cover prompt, session, tools, permissions, compaction, children and stop/interrupt. Non-managed definitions require hash-based trust review. Matching command hooks can start concurrently. | Bind enablement to reviewed code/configuration identity; define which callbacks are ordered rather than inheriting parallel execution semantics. [Hooks](https://learn.chatgpt.com/docs/hooks) |
| Codex packaging | Plugins group skills, MCP and hooks. Hook scripts must exist on the execution host; enabling a plugin does not itself trust its hooks. Distribution/surface restrictions differ. | Separate packaging, installation, enablement and execution authorization. [Packaging](https://developers.openai.com/plugins/build/plugins), [supported surfaces](https://learn.chatgpt.com/docs/plugins) |
| Pi | TypeScript extensions provide lifecycle handlers, tools, commands, session entries and UI. Handlers distinguish observations from transformations; session data and cross-session storage are separate. Extensions share process OS permissions. | Explicit return contracts, durable non-context state and honest trust boundaries. [Extension guide](https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/docs/extensions.md) |
| Pi typed events | Input returns continue/transform/handled; tool-call results can block. | Use typed results only at stages where the host supports the requested effect. [Public declarations](https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/core/extensions/types.ts) |
| Claude Code | Command/HTTP/MCP and model-backed hooks have event-specific inputs and decisions across session, turn and tool stages. | Document event schemas and cancellation/failure semantics individually. [Hooks reference](https://code.claude.com/docs/en/hooks) |

These are documentation/source comparisons, not installed interoperability tests.
Upstream main-branch documents are moving references, reviewed on the date above.
No upstream JavaScript runtime, plugin package or hook script was installed.

## Minimal scaffold and loading

Proposed modules are `Ipse.Extension` (behaviour), `Ipse.Extensions` (registry and
dispatcher), and a supervised per-session owner/worker. An event envelope has
schema version, event ID, session/turn/call correlation, stage, monotonic timing
and an allowlisted payload. Callback contexts are purpose-built values, never
the entire Session struct, credential config, environment or provider-native data.
Elixir [behaviours](https://elixir.hexdocs.pm/Module.html#module-behaviour) supply
callback contracts; [Task.Supervisor](https://elixir.hexdocs.pm/Task.Supervisor.html)
supplies owned work. Runtime return values still require host validation.

Start with compiled Elixir modules registered explicitly at build time, including
two bundled examples. Operator configuration selects known string IDs, order,
enabled hooks, bounded options and timeout/error policy. Do not create atoms from
arbitrary configuration or compile/evaluate repository `.exs` automatically.
Adding a custom module initially requires a reviewed Mix dependency/source change
and rebuilt release. Document this limitation; do not describe it as dynamic
third-party installation or hot reload. Defer a signed/catalogued distribution
format until real extension needs establish its requirements.

Reuse P15 configuration precedence and provenance, but require explicit
operator enablement of executable extensions. Generic project-config trust alone
does not authorize new code, hooks or endpoints. A project may configure only
operator-enabled IDs within their declared scope; show the effective chain and
source. Pin API/module/build/config identity in the session manifest. Changed
identity refuses resume or requires an explicit new session; do not silently
reload code midway through work. Children receive a separately validated subset,
not the parent's whole extension state, context or external-service capabilities.

An in-VM extension is **trusted executable code**, with the VM user's access.
Allowlisted callback values and timeouts constrain the API, not arbitrary BEAM
code: a module could call File, spawn processes or inspect VM state directly.
Supervision does not sandbox it. Operator review is therefore essential. A
future out-of-process adapter would need an explicit isolation/effect protocol;
existing MCP is useful for external tools but is not a generic lifecycle-hook
standard or automatic authorization for external effects.

## Lifecycle map

Design an event taxonomy for every meaningful lifecycle boundary, but implement
and stabilize only the events exercised by the first adapters. Observe before
exposing mutation rights. Observation never includes hidden reasoning or auth.

| Stage | Useful observations | Proposed transformation/effect boundary |
| --- | --- | --- |
| Configuration and session | Resolution, validation, start, resume, explicit close | Inspect selected extension manifest; executable activation remains operator-owned |
| Prompt admission | Original received, derived projection ready or failed | Bounded preprocessor before inference; preserve original operator input |
| Context assembly | Instruction/skill sources and sizes, retrieval contributions | Later memory/context contributions with provenance and context budget |
| Model request | Start, first visible token, completion, error, cancellation, usage | P22 observes metadata; provider/model/billing and native continuation stay host-owned |
| Stream and completed answer | Visible output counts, final response saved, presentation ready | Initial postprocessor affects completed display only, not individual stream chunks |
| Tool lifecycle | Proposed, validated, approval requested/answered, intent synced, started, recorded/unknown/denied | P22 observes; future veto can restrict, never grant approval or rewrite a reviewed call |
| Operator questions | Waiting, invalid/stale answer, accepted, closed | Observation; answers cannot become effect approvals |
| Delegation | Proposed, child start/finish/failure/unknown, approval wait | Observation; preserve separate child ownership, limits and approvals |
| Compaction/checkpoint | Prepare, summary request/result, validate, synced commit, refusal | P22 observes; later contributions cannot bypass host validation or delete original evidence |
| Turn/session settlement | Done, failure, cancellation, owner death, close | Bounded best-effort notification; mandatory cleanup remains in supervisors/guardians |

Source integration seams are `Session.prompt/2` and prompt admission,
`system_message/1`, `launch_model/2`, normalized progress, `dispatch_tool/4`,
`launch_tool/4`, `tool_result/5`, question/delegation handling, compaction commit,
`finish/2` and cancellation. These are internal references, not public extension
callbacks. Avoid one giant callback with arbitrary access at every seam.

## Ordering, persistence and failure

Transforms run sequentially in explicit configuration order. Later transforms
see earlier validated projections. Observers receive sanitized immutable events;
their relative completion order has no effect on model or tool execution.
All slow work stays outside the Session GenServer in owned cancellable workers.
Reject synchronous reentry into the same Session while it waits for a callback.

Proposed initial bounds: eight enabled adapters, four transformations per stage,
16 KiB JSON event payload, 16 KiB added prompt contribution, 200 ms default and
2000 ms maximum transform timeout. Original prompts retain the host's existing
limits; a transformer cannot raise the context ceiling. Set a finite observer
queue and trace-file quota with visible dropped-event counts. Validate CPU/time,
encoded bytes, JSON shape and UTF-8; task shutdown is still not hard memory/OS
containment. Tune these proposed numbers from fixtures before freezing version 1.

Persist original user input, exact derived prompt/presentation, transformation
identity/order and source/config digests in bounded private events before use.
Keep original provider messages and tool results unchanged. Restore the committed
projection without calling extensions again; never replay effects on resume or
compaction. Compaction must account for extension contributions while preserving
operator intent and source references. An interrupted transform stays explicitly
incomplete, with no automatic model request. Do not promise exactly-once execution
of arbitrary extension code.

A required prompt transform that crashes, times out or returns invalid data stops
before inference; no silent untransformed fallback. A failed optional observer
is disabled/reported without failing an otherwise successful tool. A failed
display formatter visibly falls back to the saved original answer, since the
model/effects may already have completed. Callbacks cannot relabel failed/unknown
effects successful. Journal failures retain the existing host failure boundary.

Postprocessing cannot erase streaming text already shown. P22 therefore retains
the existing visible stream and labels a separate completed formatted view.
Buffering/replacing the stream is a later explicit presentation mode. Neither
mode alters hidden/native continuation or rewrites the model's saved response.

## First two extensions

1. **Prompt context template:** append a bounded operator-configured task/style
   annotation as a separately attributed context contribution. Keep the exact
   original prompt, show the active template, journal the effective projection
   and apply it once per admitted user turn. No files, network, nested inference
   or changes to tools/provider/approval policy.
2. **Completed-answer formatter:** apply a configured plain-text wrapper to the
   completed visible answer and retain both original and labelled presentation.
   No changes to tool calls/results, citation source records or future provider
   continuation. Verify ordering, crash fallback and resumed presentation.

These deliberately exercise the two requested pre/post seams without introducing
storage or service dependencies. Custom transformations use the same behaviour
and validated contracts; the examples are not a fixed mandatory workflow.

## Long-term memory and customized workflows

Include these as P22 follow-on adapter designs, not claims that the two examples
implement memory or a workflow system. Session journals, research ledgers and
compaction checkpoints are not cross-session long-term memory.

A memory adapter needs scoped operator/project/namespace ownership, explicit
recall and remember/forget/export operations, retrieval budgets and attributable
source IDs/dates. Recalled text is untrusted data, never a new permission grant.
Persist which version/snippet influenced a turn, so later memory edits cannot
silently change resume. Remember/forget and external retrieval use host-approved,
journaled effects, with explicit endpoints/credential references and no hidden
provider calls. Define conflicts, stale data, deletion, secret exclusion, locks,
bounded records and cancellation before storing real material. Start evaluation
with local files/existing OTP facilities versus maintained SQLite packages;
choose a store from demonstrated needs. No mandatory database, embedding service
or vector engine is selected by this proposal.

Workflows should initially be skills plus optional Elixir adapters proposing
ordinary host operations: clarify, plan, delegate, review, test and report.
Each action keeps its own budgets, approvals and journal. Any automatic
continuation must be explicit and bounded, stopping for operator questions,
cancellation and unknown outcomes. Avoid recursive hooks or an unconditional
turn-complete handler that starts another turn forever. Do not add a workflow
framework simply to express a few module/process transitions.

## P22 completion evidence

Require disabled-by-default behavior parity; config/trust/version/ordering tests;
both adapters end to end; invalid output, timeout, crash and owner-death cleanup;
slow/full observer queue behavior; original/derived text and provider continuation
integrity; no approval bypass or new effects; separate child policy; cancelled
and resumed transforms; corruption refusal; and credential-free package examples.
Run Linux source/native and hosted Mac/package checks, plus an independently
reviewed supervised trial. Record real limitations and dependencies, review both
operator/developer guidance and links, then commit/push completed increments.

Use the shared event contracts in [observability](observability.md). See
[P22](../plan.md#p22-extension-scaffold-and-lifecycle-hooks),
[configuration](configuration.md) and [recovery](context-compaction.md).
