Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../operator/index.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Ipse user manual

Use Ipse to work on local files and projects through a conversation. You choose
the model service, workspace, and permitted actions. Start with a scratch directory
before giving it a project that matters to you.

The examples use `ipse` for an installed executable. From a source checkout,
replace it with `./bin/ipse`. In an extracted release directory, use `./ipse`.
Paths such as `/path/to/project` are placeholders. Replace them with your own
absolute paths.

## Start a session

Run the scripted demonstration first. It creates its own temporary workspace and
uses no account, model service, or paid inference:

```sh
ipse demo
```

Expect a file write, a read-back, a short shell command, and a printed session ID.
Then follow [Using Ipse](../../../../../operator/usage.md) to select a provider, approve work, and resume a
conversation. For an Arch source installation, use [Install on Arch Linux](../../../../../operator/arch-linux.md).

## Set up your work

- [Configuration](configuration.md) explains operator and project settings,
  precedence, inspection, and journal limits.
- [Model profiles](model-profiles.md) gives named model configurations and explicit
  routing for main work and child reviews.
- [Subagents](../../../../../operator/subagents.md) explains delegated work, separate approvals, and the
  limits of sharing one workspace.
- [MCP servers](../../../../../operator/mcp.md) connects explicitly selected local or remote tools.

## Add optional behavior

- [Extensions](../../../../../operator/extensions.md) walks through review, import, trust, selection,
  invocation, and upgrades.
- [Memory](../../../../../operator/memory.md) stores and recalls explicit notes, including retention,
  deletion, and cross-session sharing.
- [Source retrieval](../../../../../operator/corpus.md) builds a lexical corpus and retrieves exact passages.
- [Graph](../../../../../operator/graph.md) records attributed facts and follows bounded relationships.
- [Research extension](../../../../../operator/research-extensions.md) investigates supplied sources or
  explicitly selected search/fetch tools independently of the main agent.
- [Embeddings](../../../../../operator/embeddings.md) selects a separate model profile and explicitly
  submits text through a reviewed extension.
- [Native research](../../../../../operator/research.md) runs a main-agent source-gathering task and
  exports its evidence ledger.
- [Extension lab](../../../../../operator/extension-lab.md) tries independently built examples with
  synthetic data and no model service.
- [Feature requests](../../../../../operator/feature-requests.md) helps you specify a skill, integration,
  extension, or necessary core change.

## Inspect and recover

Use [Recovery](../../../../../operator/recovery.md) after an interruption, a context refusal, or a change
that prevents resume. Use [Troubleshooting](../../../../../operator/troubleshooting.md) to diagnose setup,
provider, sandbox, and cleanup errors.

[Usage accounting](../../../../../operator/usage-accounting.md) explains recorded counters and optional
configured cost reports. [Budgets](../../../../../operator/budgets.md) limits admission for one session
tree. [Diagnostic capture](../../../../../operator/observability.md) records selected metadata locally.
These controls have different purposes. Disabling a trace does not delete
conversation journals or usage facts.

## Review and develop with Ipse

[Architecture review](../../../../../operator/architecture-review.md) requests a bounded read-only
assessment and checks its evidence. [Self-development](../../../../../operator/self-development.md) keeps
an installed runner separate from the Ipse checkout it changes.

Keep session journals, exports, authentication, and private configuration outside
version control. Prompts and tool results can contain private data even when a
command's normal display omits credentials.
