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
Then follow [Using Ipse](usage.md) to select a provider, approve work, and resume a
conversation. For an Arch source installation, use [Install on Arch Linux](arch-linux.md).

## Set up your work

- [Configuration and profiles](configuration.md) explains private setup, named
  model routes, project policy, inspection and journal limits.
- [Subagents](subagents.md) explains delegated work, separate approvals, and the
  limits of sharing one workspace.
- [MCP servers](mcp.md) connects explicitly selected local or remote tools.

## Add optional behavior

- [Extensions](extensions.md) walks through review, import, trust, selection,
  invocation, and upgrades.
- [Memory](memory.md) stores and recalls explicit notes, including retention,
  deletion, and cross-session sharing.
- [Source retrieval](corpus.md) builds a lexical corpus and retrieves exact passages.
- [Graph](graph.md) records attributed facts and follows bounded relationships.
- [Research extension](research-extensions.md) investigates supplied sources or
  explicitly selected search/fetch tools independently of the main agent.
- [Embeddings](embeddings.md) selects a separate model profile and explicitly
  submits text through a reviewed extension.
- [Native research](research.md) runs a main-agent source-gathering task and
  exports its evidence ledger.
- [Extension lab](extension-lab.md) tries independently built examples with
  synthetic data and no model service.
- [Feature requests](feature-requests.md) helps you specify a skill, integration,
  extension, or necessary core change.

## Inspect and recover

Use [Recovery](recovery.md) after an interruption, a context refusal, or a change
that prevents resume. Use [Troubleshooting](troubleshooting.md) to diagnose setup,
provider, sandbox, and cleanup errors.

[Usage accounting](usage-accounting.md) explains recorded counters and optional
configured cost reports. [Budgets](budgets.md) limits admission for one session
tree. [Diagnostic capture](observability.md) records selected metadata locally.
These controls have different purposes. Disabling a trace does not delete
conversation journals or usage facts.

## Review and develop with Ipse

[Architecture review](architecture-review.md) requests a bounded read-only
assessment and checks its evidence. [Self-development](self-development.md) keeps
an installed runner separate from the Ipse checkout it changes.

Keep session journals, exports, authentication, and private configuration outside
version control. Prompts and tool results can contain private data even when a
command's normal display omits credentials.
