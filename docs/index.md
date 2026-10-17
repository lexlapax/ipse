# Ipse documentation

Start with the [README](../README.md) for the overview and credential-free quick
start. Use the guides below for operation, development, and project context.

## Operate Ipse

| Guide | Covers |
| --- | --- |
| [Arch Linux setup](operator/arch-linux.md) | Prerequisites, source installation, development setup, release requirements |
| [Usage](operator/usage.md) | Providers, login, approvals, operator clarification, project assessment and skills, resume, state, current configuration limits |
| [Model profiles](operator/model-profiles.md) | Named models, task roles, credential references, reasoning and child routing |
| [Configuration](operator/configuration.md) | Scoped JSON settings, precedence, project trust, local inspection and resume |
| [Research](operator/research.md) | Configurable search/retrieval, source ledger, citations and recovery |
| [MCP servers](operator/mcp.md) | Explicit stdio/HTTP configuration, TLS, credentials, server sandbox, approvals, recovery, and demos |
| [Local subagents](operator/subagents.md) | Explicit delegation, child approvals, bounds, journals, and recovery |
| [Supervised self-development](operator/self-development.md) | Mac trial setup, frozen runner, candidate worktree, review, resume and publication |
| [Context recovery](operator/recovery.md) | Content-free diagnostics, reviewed handoff export/fresh-chat import and unknown-effect review |
| [Diagnostic capture](operator/observability.md) | Default-off local/export policy, selected sinks, immediate stop, limits and recovery |
| [Request usage](operator/usage-accounting.md) | Durable counters, billing attribution, unknown outcomes and local inspection |
| [Extensions](operator/extensions.md) | Review/import, operator trust and selection, capability procedures, limits and recovery |
| [Troubleshooting](operator/troubleshooting.md) | Build, callback, account, lock, and recovery problems |

## Develop Ipse

| Guide | Covers |
| --- | --- |
| [Contributing](../CONTRIBUTING.md) | Contribution scope and handoff requirements |
| [Agent instructions](../AGENTS.md) | Rules, code map, documentation and commit requirements |
| [Architecture](developer/architecture.md) | Modules, ownership, persistence, trust boundaries |
| [Model-profile contract](developer/model-profiles.md) | Host routing, provider settings and child credential/native-history boundaries |
| [Configuration contract](developer/configuration.md) | Bounded loader, scope, schema reuse, provenance and resume policy |
| [Operator questions](developer/operator-questions.md) | Native question schema, explicit answers, approvals and durable recovery |
| [Context compaction](developer/context-compaction.md) | Preserved context, bounds, checkpoint and recovery contract |
| [Workspace context](developer/workspace-context.md) | Instruction scope, source bounds, snapshots, and refresh |
| [Native shell sandbox](developer/sandbox.md) | OS capabilities, fail-closed selection, and platform limits |
| [Protocol proposal](developer/protocol-proposal.md) | Proposed MCP, delegation, and remote-execution trust/recovery contracts |
| [Research contract](developer/research.md) | Provenance-bound source/claim records, bounds, compatibility and resume |
| [Extension proposal](developer/extensions.md) | P22 comparison, SDK/core boundary, lifecycle/trust/versioning and extension-only delivery gates |
| [Extension artifact contract](developer/extension-artifacts.md) | Inert manifest/store API, pinned identity and explicit independent worker SDK/lifecycle boundaries |
| [Session extension hooks](developer/extension-hooks.md) | Implemented prompt/presentation transforms, built-in registry, ownership, durable projections and no-replay recovery |
| [Lifecycle events and subscriptions](developer/lifecycle-events.md) | Shared source identity, committed-fact metadata, source-bound prompt delivery and remaining lifecycle/feeds/graph acceptance cases |
| [Prompt subscription contract](developer/extension-events.md) | Implemented inert declarations, metadata/private views, ordered read-only worker delivery and source-bound recovery |
| [Event jobs and recall](developer/extension-event-jobs.md) | Typed prompt handlers, approved actions, before-request context, after-turn maintenance and question recovery |
| [Extension invocations](developer/extension-invocations.md) | Inert tools/commands/services, scoped catalog identity, owned callbacks and durable result receipts |
| [Extension host calls](developer/extension-host-calls.md) | Finite continuations, separate write approval, scoped CAS state/tombstones and action-chain recovery |
| [Extension questions](developer/extension-questions.md) | Structured clarification, bounded checkpoints, explicit answered continuations and inert recovery |
| [Extension tool actions](developer/extension-tool-actions.md) | Approved bounded file/shell workflows, instruction preflight, output completeness and durable receipts |
| [Extension services](developer/extension-services.md) | Typed requirements, explicit operator routes, acyclic activation pins and owned value-service jobs |
| [Extension context](developer/extension-context.md) | Bounded session contributions, assertion/evidence provenance, request snapshots and cached recovery |
| [Extension adoption scenarios](developer/extension-scenarios.md) | Bundled/third-party/generated feature walkthroughs, artifact installation, temporary use and deferred host capabilities |
| [Runtime capability boundaries](developer/runtime-capabilities.md) | Framework comparison, usage/cost facts, text/voice streams and core versus extension ownership |
| [Usage accounting](developer/usage-accounting.md) | Implemented identities, normalized usage snapshots and recovery validation |
| [Private text streams](developer/text-streams.md) | Embedded/worker enrollment, opaque resource handles, acknowledgment, pressure and ephemeral recovery |
| [Knowledge extension family](developer/knowledge-extensions.md) | Default-off working/long-term memory, pluggable research, graph/RAG and composition/evidence contracts |
| [Observability contract](developer/observability.md) | Shared metadata capture, bounded owned sinks, lease recovery and remaining developer tracing gates |
| [MCP client contract](developer/mcp.md) | Reused packages, transport ownership, descriptor binding, schema policy, and recovery |
| [Local delegation contract](developer/delegation.md) | Parent/child ownership, explicit context, approvals, budgets, and unknown outcomes |
| [Dependencies](developer/dependencies.md) | Runtime/build/CI inventory, script policy, approval requirements |
| [Testing and evidence](developer/testing.md) | Verification procedures, current checkpoint and clearly scoped historical records |

## Project context

- [Plan](plan.md): priorities and acceptance criteria.
- [Naming](naming.md): the name and its sources.
- [Archive](archive/index.md): superseded documentation preserved for historical reference.

## Documentation ownership

Keep operating procedures in `operator/`, implementation and verification
guidance in `developer/`, and shared project context directly under `docs/`.
The README is the quick start; this page is the navigation map. Keep one
authoritative guide per topic and link to it from other entry points.

Before completing a sub-goal or milestone, follow the
[documentation completion rule](../AGENTS.md#finish-a-change): edit each affected
guide as a coherent whole and reconcile its structure, terminology and claims
with related guides. Integrate new behavior into the reader's workflow; keep
current instructions, proposals and dated evidence distinct. Verify commands,
evidence, file links and heading anchors, and update this map when documents move.
Preserve superseded material using the [archive policy](archive/index.md#archive-policy).
