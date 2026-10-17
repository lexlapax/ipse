# Extensions

Extensions add selected hooks, tools, commands and services to Ipse. Both
shipped examples—prompt annotation and completed-answer formatting—are
**disabled by default**. Independently built local artifacts use the same SDK
in separate Elixir VMs; they can be imported without rebuilding Ipse.

Review/import an artifact, grant its capability ceiling in operator
configuration, then select an instance for a new session. These are separate
steps: import does not execute code or grant trust, and a skill or generated
feature cannot authorize itself. Start with the procedures below; use the
capability sections to understand what a selected artifact may request.
For interruption or code/configuration changes, use the shared
[recovery procedure](#recovery-and-execution-boundaries).


## Import and inspect

```sh
./bin/ipse extension list
./bin/ipse extension inspect builtin:prompt-annotation:1
./bin/ipse extension import /path/to/reviewed-local-artifact
./bin/ipse extension inspect DIGEST
```

These local commands need no credentials or model. Imported artifacts live under
`IPSE_HOME/extensions/artifacts` (default `~/.ipse/extensions/artifacts`). Import
verifies declared file lengths/hashes and prints the pinned digest/manifest. It
never executes code, builds, installs dependencies, downloads or grants trust.
Incompatible artifacts can be stored. Inspect lists descriptors or verifies the
exact installation; it does not initialize an extension. Review code, licensing,
dependencies and options before granting trust. A digest establishes identity,
not authenticity or safety. Do not add artifacts to Ipse's code path.
See the [author contract](../developer/extension-artifacts.md).

## Configure selections

Merge these top-level fields into the operator's version-1
[configuration](configuration.md), preserving existing settings/profiles:

```json
{
  "version": 1,
  "extension_trust": [
    {
      "artifact": "builtin:prompt-annotation:1",
      "capabilities": ["transform.prompt"],
      "allow_project": false,
      "allow_children": false
    },
    {
      "artifact": "builtin:answer-format:1",
      "capabilities": ["transform.presentation"],
      "allow_project": false,
      "allow_children": false
    }
  ],
  "extensions": [
    {
      "instance": "annotation",
      "artifact": "builtin:prompt-annotation:1",
      "enabled": false,
      "options": {"text": "Keep explanations concise."},
      "order": 10,
      "lifetime": "persistent"
    },
    {
      "instance": "formatter",
      "artifact": "builtin:answer-format:1",
      "enabled": false,
      "options": {"prefix": "<answer>", "suffix": "</answer>"},
      "order": 20,
      "lifetime": "persistent"
    }
  ]
}
```

For independent code, replace the built-in reference with its reviewed
64-character digest and supply its declared options/capabilities. The operator
trust ceiling must cover every declared capability:

| Capability | Permits | Details |
| --- | --- | --- |
| `transform.prompt`, `transform.presentation` | Attributed prompt annotations or completed-answer formatting | [Hooks](#hook-behavior-and-limits) |
| `invoke.tool`, `invoke.command`, `invoke.service` | Manifest-declared typed invocations | [Catalog and commands](#tools-commands-and-services) |
| `host.state.read`, `host.state.write` | Scoped get/list or separately approved put/delete | [State](#scoped-state-host-calls) |
| `host.question` | Explicit structured clarification | [Questions](#structured-questions) |
| `host.tools` | Existing bounded read/write/edit/shell calls | [Workflow tools](#workflow-tools) |
| `host.services` | Calls through explicit operator service bindings | [Composition](#service-composition) |
| `host.context` | Bounded caller-scoped context publications | [Context/evidence](#context-and-evidence) |

Every `host.*` operation capability also requires `host.actions`. Unsupported
capabilities fail explicitly. Invocation exports need inert argument/result
schemas in the manifest. Keep credentials out of options. These mechanisms
do not select an automatic memory backend or retrieval provider.

Trust declarations are separate from instances and may appear only in operator
configuration. Project configuration cannot grant trust, including an empty trust
declaration. `--trust-project-config` does not relax that ceiling: an enabled
project instance also needs matching operator trust with `allow_project: true`.
Child sessions inherit only instances explicitly allowed by `allow_children`;
MCP and recursive delegation remain unavailable to children. Artifact options
are checked against their schema at executable admission.

Instances merge by `instance`; nearer definitions replace the whole earlier
instance. Order is ascending `order`, then instance ID. Limits are eight effective
instances and sixteen trust declarations. `ipse config` displays provenance and
option digests without printing their contents; `/session` includes pinned active
identities. Missing code is never installed automatically.

```sh
./bin/ipse config --extension annotation --extension formatter
./bin/ipse demo --extension annotation --extension formatter
./bin/ipse chat --extension annotation
./bin/ipse chat --no-extensions
```

The demo needs no model or credentials; it creates its usual temporary demo file
and runs the documented shell probe. `--extension INSTANCE` activates a configured
instance temporarily with lifetime `session`, without rewriting configuration.
Repeat it for multiple instances. `--no-extensions` disables all configured
instances for the new invocation and cannot be combined with `--extension`.
A persistent selection is an explicit configuration edit setting `enabled: true`,
not a side effect of loading a skill or generating code. A session lifetime is
scoped to that durable session ID, including its explicitly resumed process.

Optional `expires_at` on an instance or trust record is an absolute Unix timestamp
in seconds; the earlier deadline applies. Expiry is checked at startup and before
callback intent/result admission. A running callback has its normal deadline;
there is no separate expiry-preemption timer or live revocation command yet.
Already committed context/history is retained. Configuration is fixed for the
session; `/context refresh` does not reload it. Live activation/hot reload is not
supported, and these flags do not stop existing sessions.

## Tools, commands and services

An enabled artifact's declared tools appear as `ext__INSTANCE__ID` in the model
catalog. Every invocation needs normal full argument approval unless explicitly
enabled with session-wide approval; headless execution is denied without `--yes`.
Malformed arguments and duplicate native call IDs refuse code initialization.

In interactive chat, `/ext` lists the active catalog locally. Invoke a declared
command explicitly with `/ext ext__INSTANCE__ID {"text":"example"}` using its
actual schema. This needs no model request, displays the returned JSON separately
and does not overwrite the assistant answer. Embedded callers invoke standalone
services with `Session.invoke_export/4`. Worker composition uses the explicit
operator bindings below. Commands/standalone services are admitted only while idle.

Callbacks return schema-checked values. Explicitly trusted host capabilities
permit finite proposals for state, questions, tools, services or context. All
share a 16-operation invocation budget; ordinary returned JSON remains inert.
Intent is synced before executable startup; result is synced after validation
and confirmed worker cleanup. Invalid output/crash/interruption has an unknown
outcome and is never retried automatically. Up to 10,000 invocations fit one
session; overflow refuses admission. See
[SDK schemas, bounds and recovery](../developer/extension-invocations.md).

## Hook behavior and limits

Prompt annotations append visibly attributed, untrusted context to the effective
prompt. The original operator input and original expanded message remain in the
private journal. Annotation text does not grant action permission: normal tool
approval still applies. Completed formatting wraps visible answer text with a
prefix/suffix; original assistant messages, provider continuation and tool
provenance remain intact. Raw visible text streams as before; the CLI prints a
separate completed presentation afterward when formatting is selected.

Callback input text is at most 8 KiB and the entire SDK object at most 16 KiB
encoded JSON. Each annotation/prefix/suffix is at most 4,096 characters, subject
to SDK byte bounds; derived text is capped at 16 KiB. Multiple annotations can
exhaust a later callback's input budget. Overflow, invalid output, timeout, crash
or expiry fails explicitly, retaining committed input/output. It never silently
truncates the prompt or rewrites provider data. Presentation failure leaves the
original completed answer in history. Each transform uses a fresh owned VM and
five-second initialization/callback deadlines; private VM state is not a durable
session memory API.

## Scoped state host calls

Reviewed artifacts may declare `host.actions` plus `host.state.read` and/or
`host.state.write`. These capabilities are default-off and require operator trust.
There is no shipped automatic memory adapter in this increment. Workers can
request get/list/put/delete in host-derived operator/project/session namespaces.
Project-configured code cannot select operator scope. State is not automatically
sent to a model or another extension.

Every put/delete asks for separate full approval unless execution was explicitly
enabled for the session. Invoking a command or approving its enclosing model tool
does not authorize a later write. Headless/interactive denial creates no business
record. Reads need the read capability. Up to 16 host calls fit one invocation;
invalid/unknown outcomes stop it.

Data lives in `IPSE_HOME/extension-state-v1` with private files/native locks. Each
identity/scope has a 1 MiB/256-record quota including tombstones; values are at
most 8 KiB. Writes require the current revision. Delete removes the current value
and retains its revision to prevent stale resurrection. Historical journals and
delivered text remain.

After an interrupted write, inspect its namespace/key revision and operation ID
before explicitly deciding what to do next; it may have committed. Tampered receipts or
corrupt state refuse recovery/access without repair. Artifact/config-source
changes isolate new namespaces; no automatic migration or collector is available.
Do not remove lock files. See [protocol, paging and recovery](../developer/extension-host-calls.md).

## Structured questions

Artifacts explicitly trusted for `host.actions` and `host.question` can ask the
normal single-choice, multiple-choice or text questions. Recommendations are
never submitted automatically. The worker closes before the question appears;
an interrupted pending question restores and waits without executable startup.
No model request is needed for a standalone command/service question.

Your validated answer starts a new journaled continuation using the extension's
bounded saved checkpoint. It grants no permission for a subsequent write; normal
full approval still applies. Stale/invalid/oversized answers are rejected without
changing the journal. `/cancel` closes the question without answering. Headless
and child sessions cannot silently select an answer. Questions and other host
calls share the same 16-operation invocation budget.

If interruption occurs after an answer/continuation intent, resume stays idle
with unknown work and does not rerun the callback. Inspect receipts before
explicitly choosing a fresh action. See
[SDK checkpoint and recovery details](../developer/extension-questions.md).

## Workflow tools

Reviewed artifacts trusted for `host.actions` and `host.tools` can request the
existing read/write/edit/shell tools. Write/edit/shell need their own full approval;
answers or command invocation do not authorize them. Headless writes remain
denied without `--yes`. Unknown tool IDs, delegation and MCP calls are unavailable
through this operation. Child ceilings and parent mutation coordination still apply.

New nested workspace instructions stop the invocation before tool approval or
execution. Review `/context`, then explicitly decide whether to invoke again.
Existing instruction drift still uses `/context refresh`; there is no automatic
retry. Tools retain normal workspace/symlink/.git rules and the selected shell
sandbox policy. Separate workers and deadlines are not an OS sandbox.

Each call declares a 1–30,000 ms deadline; shell setup has the existing additional
supervisor allowance. Results must fit 4 KiB text and the complete escaped SDK
envelope. Read errors/oversized read results return known failure codes without
partial data, allowing a bounded explicit follow-up. Shell exit status stays
visible. Timeout, incomplete shell output or ambiguous
failure stops with an unknown outcome; inspect before retrying. Cancellation kills
the owned tool task and ordinary shell process group, with existing macOS cleanup
limits. See
[protocol and limits](../developer/extension-tool-actions.md).

## Service composition

Reviewed artifacts can declare typed required service aliases with `host.actions`
and `host.services`. Add `service_bindings` only to the caller artifact's operator
trust record, selecting exact caller/target instances, target artifact and local
service ID. Project configuration or a skill cannot grant a route. The target
must already be imported, trusted and explicitly selected; there is no automatic
dependency install/enable or fallback. See the [complete data contract](../developer/extension-services.md).

Both required schemas must exactly match the selected service export. Missing
routes, incompatible schemas and cycles refuse startup without running callbacks.
Child sessions require an explicitly allowed dependency subset as well. Disabled
instances stay inert; a route by itself starts nothing. No retrieval provider or
memory backend is installed by this capability.

Value-service contract 1 returns a typed result plus host provenance. Its worker
has normal callback deadlines and must close before result commit. Returned
actions/questions/nested calls are refused by this value contract; future
interactive contracts need separate negotiation. Standalone services retain
their explicitly declared invocation capabilities.

Both caller and target identity/lease are pinned; an expired target result cannot
be committed. See [SDK ownership and limits](../developer/extension-services.md#owned-value-calls).

## Context and evidence

An artifact trusted for `host.actions` and `host.context` can explicitly publish
context from its tool, command or standalone service. Publications replace only
that instance's current session set; publishing an empty set clears it. Fresh
sessions and children inherit no sets. This does not enable automatic memory,
select a retrieval backend or grant mutation/provider permission.

Each set has at most eight items with IDs, version labels, text, priority and a
source. Assertions remain unverified. Receipt-backed excerpts must match literal
text from an earlier successful host action in that invocation; provenance proves
recorded text, not truth or freshness. Main requests use attributed JSON context
after mandatory instructions. Global rendered context is limited to 16 KiB and
full SDK envelopes must fit; refusal preserves existing context without eviction
or truncation. See [request examples and exact limits](../developer/extension-context.md).

Idle resume restores committed contributions and request snapshots without
running callbacks or fetching again. A committed publication survives cancellation
of the remaining callback. Updating/clearing is explicit; clearing does not erase
old journals or already delivered provider text. Diagnostic inspection reports
only counts, bytes and digest. Saved data has no automatic freshness/TTL guarantee.
Changes to pinned code/config still require the documented recovery path.

## Visible-text clients

Embedded clients can explicitly use a bounded private visible-text subscription;
there is no new stream CLI flag or installed-worker subscription capability yet.
It receives raw visible model text; completed-answer formatting remains separate.
Slow consumers can backpressure their request and receive explicit incomplete
shutdown on timeout/cancel. Subscriptions are ephemeral and do not replay on
resume. See the [embedded contract](../developer/text-streams.md).

## Recovery and execution boundaries

Resume pins exact artifact/options, catalog, configuration source/scope,
order/lifetime, VM components, host API digest and generation. Required
missing/tampered/incompatible code, changed selection
or corrupt projections refuse resume before journal repair. Committed projections,
context and receipts restore without callbacks, retrieval or storage effects.
This includes a tool result committed just before its ordinary message record.
Interrupted intents are never automatically replayed. Pending questions wait for
an explicit answer; other interrupted work stays idle with unknown outcomes for
review. Source edits after import do not alter the installed snapshot.

Use the same selection flags/configuration when resuming a temporary instance.
`--no-extensions` cannot silently remove a pinned active set from an existing
session. Restore the original code/configuration, use a frozen runner for that
session, or export a reviewed handoff and start fresh. Exact host API pinning can
require a fresh session after a harness upgrade; no projection migration is
implemented yet.

Missing/corrupt/extra installed files refuse verification; import will not
overwrite an invalid digest directory. A busy import lock fails safely; retry
after the other importer exits. Preserve lock files for inode identity. After
interruption, `.staging-*` directories in the dedicated store are inert; inspect
and remove abandoned staging only when no importer is running. There is no
automatic garbage collector or repair command.

Workers inherit no credential environment. Trusted executable code still has
the operator's OS/filesystem access; ownership, deadlines and process-group
cancellation do not themselves provide an OS sandbox. Initialize/transform
callbacks must follow the SDK's effect-free contract; arbitrary trusted programs
cannot be constrained by a return-value schema alone.

Broader nested service contracts, worker stream access, lifecycle observation,
live controls and the independent installed memory/workflow proof remain
[P22 work](../plan.md#p22-extension-scaffold-and-lifecycle-hooks). Remote installers,
build assistants and live activation are future capabilities. Current import and
selection never install a dependency or silently switch providers.
