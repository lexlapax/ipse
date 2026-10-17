# Extensions

Ipse supports explicitly selected prompt/presentation hooks and manifest-declared
tools, operator commands and standalone typed services. Both shipped hook examples
are **disabled by default**. Independent local artifacts use the same SDK in
separate Elixir VMs. Import and discovery remain inert; configuration trust and
activation are separate.

## Visible-text clients

Embedded clients can explicitly use a bounded private visible-text subscription;
there is no new stream CLI flag or installed-worker subscription capability yet.
It receives raw visible model text; completed-answer formatting remains separate.
Slow consumers can backpressure their request and receive explicit incomplete
shutdown on timeout/cancel. Subscriptions are ephemeral and do not replay on
resume. See the [embedded contract](../developer/text-streams.md).

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

For independent code, replace the built-in reference with its reviewed 64-character
digest and supply its declared options/capabilities. Supported capabilities are
`transform.prompt`, `transform.presentation`, `invoke.tool`, `invoke.command`
and `invoke.service`, plus `host.actions` with `host.state.read`/`host.state.write`
or `host.question`/`host.tools`;
unsupported capabilities fail explicitly. Invocation
exports require inert argument/result schemas in the artifact manifest. Do not
put credentials in extension options. No automatic memory backend is selected.

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

## Recovery and execution boundaries

Resume pins exact artifact/options, catalog, configuration source/scope,
order/lifetime, VM components, host API digest and generation. Required
missing/tampered/incompatible code, changed selection
or corrupt projections refuse resume before journal repair. Committed projections
restore without invoking callbacks; interrupted intents are never automatically
replayed. A resumed session stays idle until fresh operator input. Source changes
after import do not alter the installed snapshot.

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
cannot be constrained by a return-value schema alone. Context contributions,
worker service composition, broader lifecycle observation,
live controls and the extension-only
memory/workflow proof remain [P22 work](../plan.md#p22-extension-scaffold-and-lifecycle-hooks).
See the [implemented hook contract](../developer/extension-hooks.md).

## Tools, commands and services

An enabled artifact's declared tools appear as `ext__INSTANCE__ID` in the model
catalog. Every invocation needs normal full argument approval unless explicitly
enabled with session-wide approval; headless execution is denied without `--yes`.
Malformed arguments and duplicate native call IDs refuse code initialization.

In interactive chat, `/ext` lists the active catalog locally. Invoke a declared
command explicitly with `/ext ext__INSTANCE__ID {"text":"example"}` using its
actual schema. This needs no model request, displays the returned JSON separately
and does not overwrite the assistant answer. Embedded callers can invoke a typed
service with `Session.invoke_export/4`; worker-to-worker composition is not yet
available. Commands/services are admitted only while idle.

These callbacks return schema-checked values. An artifact explicitly trusted for
host state capabilities can also propose the finite operations below.
Intent is synced before executable startup; result is synced after validation
and confirmed worker cleanup. Invalid output/crash/interruption has an unknown
outcome and is never retried automatically. Resume restores committed receipts
without callback execution, including a result committed just before its ordinary
tool-message record. Up to 10,000 invocations fit one session; overflow refuses
admission. See [SDK schemas, bounds and recovery](../developer/extension-invocations.md).

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

Resume restores receipts without running callbacks/storage actions. After an
interrupted write, inspect its namespace/key revision and operation ID before
explicitly deciding what to do next; it may have committed. Tampered receipts or
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
explicitly choosing a fresh action. Exact artifact/config/host pins and expiry
still apply. See [SDK checkpoint and recovery details](../developer/extension-questions.md).

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
limits. Committed receipts restore without rerunning effects. See
[protocol and limits](../developer/extension-tool-actions.md).
