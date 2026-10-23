> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/operator/index.md). Relative prose links point to the original commit; commands and claims retain their original text.

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
Then follow [Using Ipse](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/usage.md) to select a provider, approve work, and resume a
conversation. For an Arch source installation, use [Install on Arch Linux](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/arch-linux.md).

## Set up your work

- [Configuration and profiles](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/configuration.md) explains private setup, named
  model routes, project policy, inspection and journal limits.
- [Subagents](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/subagents.md) explains delegated work, separate approvals, and the
  limits of sharing one workspace.
- [MCP servers](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/mcp.md) connects explicitly selected local or remote tools.

## Add optional behavior

- [Extensions](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/extensions.md) walks through review, import, trust, selection,
  invocation, and upgrades.
- [Memory](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/memory.md) stores and recalls explicit notes, including retention,
  deletion, and cross-session sharing.
- [Source retrieval](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/corpus.md) builds a lexical corpus and retrieves exact passages.
- [Graph](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/graph.md) records attributed facts and follows bounded relationships.
- [Research extension](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/research-extensions.md) investigates supplied sources or
  explicitly selected search/fetch tools independently of the main agent.
- [Embeddings](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/embeddings.md) selects a separate model profile and explicitly
  submits text through a reviewed extension.
- [Native research](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/research.md) runs a main-agent source-gathering task and
  exports its evidence ledger.
- [Extension lab](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/extension-lab.md) tries independently built examples with
  synthetic data and no model service.
- [Feature requests](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/feature-requests.md) helps you specify a skill, integration,
  extension, or necessary core change.

## Inspect and recover

Use [Recovery](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/recovery.md) after an interruption, a context refusal, or a change
that prevents resume. Use [Troubleshooting](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/troubleshooting.md) to diagnose setup,
provider, sandbox, and cleanup errors.

[Usage accounting](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/usage-accounting.md) explains recorded counters and optional
configured cost reports. [Budgets](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/budgets.md) limits admission for one session
tree. [Diagnostic capture](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/observability.md) records selected metadata locally.
These controls have different purposes. Disabling a trace does not delete
conversation journals or usage facts.

## Review and develop with Ipse

[Architecture review](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/architecture-review.md) requests a bounded read-only
assessment and checks its evidence. [Self-development](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/self-development.md) keeps
an installed runner separate from the Ipse checkout it changes.

Keep session journals, exports, authentication, and private configuration outside
version control. Prompts and tool results can contain private data even when a
command's normal display omits credentials.
