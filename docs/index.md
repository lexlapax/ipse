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
| Install, upgrade or remove a runtime bundle | [Install Ipse](operator/install.md) |
| Start a conversation, approve changes and manage session permissions | [Use the terminal](operator/usage.md) |
| Set an endpoint, profile or project policy | [Configure Ipse](operator/configuration.md) |
| Choose Grok API billing or prepare registered-client subscription access | [Grok configuration](operator/configuration.md#use-grok-through-xai) |
| Connect tools from another service | [Configure MCP](operator/mcp.md) |
| Remember an explicit project note | [Use memory](operator/memory.md) |
| Retain source text and retrieve exact passages | [Use a corpus](operator/corpus.md) |
| Record relationships with exact source quotations | [Use Graph](operator/graph.md) |
| Investigate provided text or selected search/fetch tools | [Use the Research extension](operator/research.md) |
| Gather sources with the main agent and export its ledger | [Run native research](operator/research.md) |
| Configure explicit vector generation | [Use embeddings](operator/extensions.md) |
| Inspect or recover interrupted work | [Recover a session](operator/recovery.md) |
| Find why a command failed | [Troubleshoot](operator/recovery.md) |
| Understand which process owns an operation | [Follow a turn](developer/architecture.md) |
| Add a domain tool without changing the host | [Build an extension](developer/extensions.md) |
| Change source retrieval, graph or investigation behavior | [Study knowledge packages](developer/knowledge-extensions.md) |
| Measure retrieval and cited answers without exposing labels | [Work through knowledge evaluation](developer/knowledge-evaluation.md) |
| Change a durable record or recovery validator | [Study persistence](developer/persistence.md) |
| Prove a repair against source or an installed runtime | [Verify a change](developer/testing.md) |

## Project context

[Release notes](releases/v0.1.0.md) describe supported use, limits and verification
status for a version. The operator install chapter owns lifecycle procedures;
dated evidence remains in the archive.

The [plan](plan.md) records priorities, selected scopes and acceptance decisions.
Its [P31 knowledge and prompt-assistance scope](plan.md#p31-usable-knowledge-and-prompt-assistance)
and [P30 decision consumers](plan.md#p30-advisory-decision-engines) describe proposed
work; the [dated delivery design](archive/2026-10-26-p30-p31-plan/index.md) explains
the selected experience and dependencies. Current knowledge procedures remain in
the operator chapters above.
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
elixir dev/check-docs.exs
```

The checker cannot judge the usefulness of prose. Follow the changed instructions
with isolated synthetic state, inspect the actual result, and review the entire
chapter before marking the work complete. Use the
[archive policy](archive/index.md#archive-policy) when replacing substantial guides.
