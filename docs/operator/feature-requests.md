# Ask Ipse to add a capability

Describe the result you need before choosing an implementation. Ipse can use
skills, existing tools, configured MCP, and reviewed extensions. Core changes
are appropriate when those mechanisms lack a generic guarantee the feature needs.
Keep optional domain behavior outside the agent loop whenever existing extension
contracts can express it.

## Prepare a bounded request

Start in a workspace using your explicitly chosen provider. This makes real
model requests after submission:

```sh
ipse chat --provider chatgpt --cwd /path/to/project
```

For example, ask for a proposal before executable work:

```text
I want an optional command that recalls explicit project notes for a release
checklist. It should run only when I invoke it, keep data local, and show source
excerpts. Propose the smallest supported mechanism. Identify configuration,
permissions, retention, limits, and recovery. Do not install or enable anything
until I have reviewed the code and configuration.
```

State whether the behavior is for one task, a project, or all your projects.
Name permitted services/models, data that may leave the machine, spending limits,
and any files it may change. Explain whether it runs on command, before a model
request, after an answer, or continuously during work. Timing changes the
available contracts.

## Choose the mechanism with the proposal

| Your need | Start with |
| --- | --- |
| A repeatable procedure using existing tools | A skill or scoped instructions |
| Access to an existing external service | Explicitly configured MCP capabilities |
| A typed model tool or explicit local command | An extension invocation |
| Prompt annotations or answer formatting | Selected extension transforms |
| Supported notifications, metadata feeds, or text delivery | Read-only extension consumers |
| Ordered recall or maintenance at a supported prompt/answer boundary | An extension event job with its separate grants |
| Ranking, note policy, reports, or a bounded workflow | An extension using supported host calls and bound value services |
| A missing shared ownership, approval, persistence, accounting, or transport guarantee | A small generic core enhancement |

A skill supplies instructions; it does not enable a service or execute its
scripts on load. An extension may expose tools, but main-agent MCP access does
not grant callback access. A reviewed extension needs `host.mcp` and an explicit
operator [MCP binding](mcp.md#allow-a-reviewed-extension-to-use-a-selected-item).
The separate workflow tool bridge supports bounded built-in file/shell calls.
Host calls cannot delegate recursively.

## Require the proposal to show its boundaries

Ask the implementing agent to map each required operation to the current
[extension contracts](extensions.md), not just say that the SDK is extensible.
The design needs exact inputs and timing, selected private views, effects,
operator grants/bindings, approvals, and provider destinations.

For storage, require scope, stable identity, revisions, retention, export,
migration, and concurrent-write behavior. Deletion of a store value does not
erase earlier recall, journals, exports, or provider transfers. For automation,
ask how cancellation, owner death, timeout, incomplete cleanup, and unknown
outcomes are handled. Interrupted effects must not replay automatically.

For inference, require named profiles and the supported accounted text or
[embedding action](embeddings.md). A text response containing numbers does not
satisfy the embedding contract. Host budgets do not
cover arbitrary worker network calls, external-service costs, or device access.
Executable extensions run with trusted operator OS permissions; their separate
VM does not turn them into an OS sandbox.

Require exact byte/action/deadline limits and behavior when exceeded. A feed
acknowledgment does not prove storage success. After-turn work cannot revise the
answer already saved. Current event jobs do not imply fully concurrent background
turns or subscriptions to every internal event.

## Review before installation and selection

For an extension proposal, request the source, manifest, schemas, license,
dependencies, options, declared capabilities, and focused verification. Include
normal behavior, denial, cancellation, uncertainty, resume, scope isolation, and
behavior with the extension disabled. Algorithm quality needs its own examples;
protocol correctness alone does not prove useful retrieval or reasoning.

Follow [Extensions](extensions.md) to import an inert artifact, inspect its digest,
grant an operator capability ceiling, and select an instance in a fresh session.
These are separate decisions. Generated code, repository text, and skills cannot
grant their own trust. Prefer temporary selection before changing persistent
operator configuration.

If a generic guarantee is missing, ask for the smallest reusable core change
and its compatibility/recovery plan. Do not bypass that gap with copied
credentials, hidden model calls, worker networking, or an unbounded background
process. The feature's complexity alone is not a reason to put domain logic in
core.

## Check the result and recover

Try the capability in a scratch workspace with synthetic data first. Compare the
actual output and effects with your request. Inspect `/ext`, `/session`, and
`/diagnostics` for the selected identities and outcomes. A source-only example
is not proof that an installed release can run the artifact.

If a callback or effect is interrupted, inspect receipts and the actual files or
store before another invocation. Changed artifact/options/configuration may
prevent ordinary resume. Preserve the original session and use a reviewed
[handoff](recovery.md) when moving to a newly reviewed version. Enabling a revised
extension must not silently rewrite old committed results.
