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
| [Extension adoption scenarios](developer/extension-scenarios.md) | Bundled/third-party/generated feature walkthroughs, artifact installation, temporary use and deferred host capabilities |
| [Observability proposal](developer/observability.md) | P19/P22 diagnostics, lifecycle telemetry, optional export and BEAM debugging |
| [MCP client contract](developer/mcp.md) | Reused packages, transport ownership, descriptor binding, schema policy, and recovery |
| [Local delegation contract](developer/delegation.md) | Parent/child ownership, explicit context, approvals, budgets, and unknown outcomes |
| [Dependencies](developer/dependencies.md) | Runtime/build/CI inventory, script policy, approval requirements |
| [Testing and evidence](developer/testing.md) | Source/release checks, live acceptance, actual results |

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
[documentation completion rule](../AGENTS.md#finish-a-change): review both
audiences' guidance, update stale content, verify commands and evidence, check
file links and heading anchors, and keep this map current when documents move.
Preserve superseded material using the [archive policy](archive/index.md#archive-policy).
