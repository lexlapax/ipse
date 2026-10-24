# Ipse user manual

Use Ipse to work on local files through a conversation. You choose the model,
workspace, and permitted effects. Choose and save a route with `ipse setup`, check
it with `ipse doctor`, then begin in a scratch directory with `ipse demo`;
it needs no account or model service. [Usage](usage.md) then takes you through a
real task, approval, questions, delegation, and resume.

```sh
ipse demo
ipse --help
```

Expect a scripted file/shell task followed by the available command syntax.

Examples use `ipse` for an installed executable. Use `./bin/ipse` from a source
checkout or `./ipse` inside an extracted release. Replace `/path/to/...` and
uppercase ID/digest placeholders with your actual values. Keep private
configuration, credentials, journals, and exports outside version control.

## Choose a task

| Task | Chapter |
| --- | --- |
| Download/check a bundle, install, upgrade or uninstall on Linux/macOS | [Install Ipse](install.md) |
| Install from source and prepare Linux native policy | [Arch Linux setup](arch-linux.md) |
| Preview, save or replace a private first-run provider choice | [Guided setup](configuration.md#choose-and-save-a-provider) |
| Work interactively or run once, approve effects, use skills, delegate, resume | [Use a workspace](usage.md) |
| Select providers/profiles and resolve operator/project policy | [Configuration](configuration.md) |
| Connect explicitly selected external tools/resources/prompts | [MCP](mcp.md) |
| Review/import/select extensions, read complete results, generate vectors, try the lab | [Extensions](extensions.md) |
| Retain explicit notes, update revisions, expire, forget, export/migrate | [Memory](memory.md) |
| Store sources and retrieve cited passages | [Corpus](corpus.md) |
| Extract attributed facts and follow relationships | [Graph](graph.md) |
| Investigate with the main agent, supplied text, or an explicit retrieval gateway | [Research](research.md) |
| Inspect usage/cost estimates and reserve shared model allowances | [Resource controls](resources.md) |
| Configure local diagnostic sinks and retention | [Diagnostic capture](observability.md) |
| Run offline setup checks, interpret refusals, inspect unknown effects, resume or hand off | [Recovery](recovery.md) |
| Review architecture, request a capability, or change Ipse with a frozen runner | [Development workflows](development-workflows.md) |

Approvals, process supervision, and native confinement solve different problems.
A proposal needs authority even when its code runs in another VM. An interrupted
effect can remain unknown after cancellation. Follow recovery before repeating
work; a missing result is not proof that nothing happened.

For contributing code, use the [developer training path](../developer/index.md).
Current priorities belong to [the plan](../plan.md); dated evidence and superseded
manuals belong to [the archive](../archive/index.md).
