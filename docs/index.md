# Ipse manuals

Choose the manual for the work you want to do:

- [Use Ipse](operator/index.md): install it, choose a provider, review actions,
  work with projects and recover a conversation. The guides include complete
  commands/configuration, expected results and recovery procedures.
- [Develop Ipse](developer/index.md): build a checkout, trace the turn loop,
  understand ownership and persistence, write extensions and verify a change.
  The chapters include worked examples and source-reading exercises.

If this is your first visit, the [README](../README.md) has a credential-free
quick start. Try the demo before configuring a model account.

## Choose a task

| I want to... | Start here |
| --- | --- |
| Start a conversation and approve a file change | [Use the terminal](operator/usage.md) |
| Set an endpoint, profile or project policy | [Configure Ipse](operator/configuration.md) |
| Connect tools from another service | [Configure MCP](operator/mcp.md) |
| Remember an explicit project note | [Use memory](operator/memory.md) |
| Inspect or recover interrupted work | [Recover a session](operator/recovery.md) |
| Find why a command failed | [Troubleshoot](operator/troubleshooting.md) |
| Understand which process owns an operation | [Follow a turn](developer/architecture.md) |
| Add a domain tool without changing the host | [Build an extension](developer/extensions.md) |
| Change a durable record or recovery validator | [Study persistence](developer/persistence.md) |
| Prove that a repair works | [Verify a change](developer/testing.md) |

## Project context

The [plan](plan.md) records priorities, selected scopes and acceptance decisions.
[The archive](archive/index.md) preserves dated source/verification/research
records and superseded documents with their provenance. Neither replaces current
operating instructions. [Naming](naming.md) explains the project name.

The [license](../LICENSE), [third-party notices](../THIRD_PARTY_NOTICES.md),
[contribution guide](../CONTRIBUTING.md), [agent rules](../AGENTS.md) and
[security/reporting policy](../SECURITY.md) apply to repository work.

## Maintain the audience boundary

Operator pages are user manuals. Teach a task with prerequisites, complete
examples, expected results and relevant recovery. Developer pages are contributor
training. Teach the runtime model and invariants, connect them to source, and
include a worked example or change exercise with focused verification.

Keep one authoritative chapter per topic and link related procedures. Rewrite a
chapter when behavior changes rather than appending feature summaries. Keep dated
results, CI receipts, milestones and campaign narratives out of both manuals;
put status in the plan and preserved records in the archive.

From the repository root, check the navigation and examples after an edit:

```sh
elixir scripts/check-docs.exs
```

The checker cannot judge the usefulness of prose. Follow the changed instructions
with isolated synthetic state, inspect the actual result, and review the entire
chapter before marking the work complete. Use the
[archive policy](archive/index.md#archive-policy) when replacing substantial guides.
