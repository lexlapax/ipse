# Use reviewed extensions

Extensions add optional tools, commands, prompt annotations, answer formatting,
and selected event consumers. They can also use explicitly granted host services
for state, context, questions, tools, and model calls. Every bundled extension is
optional. Imported executable code runs with trusted operator OS permissions;
review it before granting access.

The operating sequence is review, inert import, capability trust, instance
selection, then invocation. None of these steps implies the next. A generated
artifact, skill, or project file cannot grant itself permission.

## Try a bundled extension without a model service

Save this complete configuration as `/private/path/extensions.json`:

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

Inspect descriptors and the effective selection locally:

```sh
ipse extension list
ipse extension inspect builtin:prompt-annotation:1
ipse config --config /private/path/extensions.json --no-project-config \
  --extension annotation --extension formatter
ipse demo --config /private/path/extensions.json --no-project-config \
  --extension annotation --extension formatter
```

No account or model service is used. The demo performs its normal temporary file
and shell work. Expect the completed answer wrapped by the configured tags.
The effective prompt and journal retain the attributed annotation; it is not
printed as a separate terminal message. Original provider messages, tool outcomes,
and continuation remain intact.

Both instances remain disabled in the file. `--extension INSTANCE` activates an
already configured instance for the durable session, including its explicit
resume, without editing configuration. To enable future sessions persistently,
review an edit to `enabled: true`. `--no-extensions` disables selections for a
new invocation and cannot combine with `--extension`. These flags do not hot-load
code or change an already pinned session.

## Import an independently built artifact

Get the source, license, dependencies, manifest, schemas, and options from the
author. Review its declared operations and any direct filesystem/network use.
Use a compatible already-built artifact; import does not compile or install it.

```sh
ipse extension import /path/to/reviewed-artifact
ipse extension inspect DIGEST
```

Replace `DIGEST` with the printed 64-character artifact digest. Import verifies
declared lengths/hashes and copies an inert snapshot under
`IPSE_HOME/extensions/artifacts`, normally `~/.ipse/extensions/artifacts`. Inspect
verifies the installed snapshot without executing it. A digest establishes
identity, not authenticity or safety. Incompatible artifacts may be stored but
cannot activate. Source edits after import do not alter the snapshot.

For activation, use the digest in both an operator trust entry and an instance,
following the complete example above with the artifact's actual capabilities and
options. Do not add artifacts to Ipse's code path. A separately built example
walkthrough is available in [Extension lab](extension-lab.md).

## Review trust and scope

Trust entries belong only in operator configuration. Their capability ceiling
must cover every declared capability. Instances can be configured at operator
or trusted project scope. A project instance also needs operator trust with
`allow_project: true`; `--trust-project-config` cannot replace that grant. A child
inherits only instances permitted by `allow_children: true` and keeps its own
approval limits. MCP and recursive delegation remain unavailable to children.

Instance definitions merge by `instance`; nearer definitions replace the whole
instance. Execution order is ascending `order`, then ID. Limits are eight
effective instances and sixteen trust declarations. Config inspection shows
provenance and option digests rather than contents. Keep secrets out of options.
`/session` shows pinned identities and `/ext` lists the active export catalog.

Optional `expires_at` is an absolute Unix timestamp in seconds on a trust entry
or instance; the earlier deadline applies. Expiry is checked at startup and
before callback intent/result admission. Already running work keeps its ordinary
deadline. There is no live revocation timer, hot reload, or general live activation.
Already committed context/history remains.

Use these distinctions when reading an artifact's requested grants:

| Capability family | What you are allowing |
| --- | --- |
| `transform.prompt`, `transform.presentation` | Bounded prompt annotations or completed presentation |
| `invoke.tool`, `invoke.command`, `invoke.service` | Manifest-declared typed invocation exports |
| `host.state.read`, `.write`, `.scan`, `.bound` | Scoped state reads, separately approved writes, extended read scans, or required logical bindings |
| `host.question`, `host.tools`, `host.model`, `host.services`, `host.context` | Explicit questions, bounded built-in tools, approved profile inference, bound value-service calls, or context publications |
| `host.history` and `host.history.*` | This session's metadata and separately selected historical private views |
| `host.usage`, `.scan`, `.children` | Accounting reads, extended scans, or registered direct-child accounting |
| `stream.text`, `stream.text.events` | Private visible text and optional explicit frame identity |
| `lifecycle.record`, `lifecycle.tools` | Bounded runtime/wait facts and admitted-tool source recording |
| `observe.local`, `observe.export` | Diagnostic metadata sinks under separate capture policy |
| `event.notify`, `event.feed`, `event.job` | Selected notifications, bounded live feeds, or finite effectful boundary jobs |
| `event.prompt.*`, `event.answer.*`, `event.tool.input`, `event.tool.result` | Exact selected private views, in addition to the corresponding delivery prerequisites |

Every `host.*` operation also requires `host.actions`. A read grant does not
imply a write, model, or transfer grant. Live private views do not grant history
reads. `lifecycle.record` alone starts no extension worker and gives no read or
action permission. Unsupported capabilities fail explicitly.

## Invoke a tool or command

An enabled artifact's model tools use names such as `ext__INSTANCE__ID`. They need
full ordinary approval unless you explicitly used session-wide allowance.
Headless effects are denied without `--yes`. Invalid arguments refuse before
initializing code.

In interactive chat, `/ext` lists actual schemas and exports. To invoke a command
without inference, use its exact name and a JSON object:

```text
/ext
/ext ext__project-notes__recall {"query":"release checklist","limit":5}
```

The second command requires the [memory example](memory.md) to be configured.
Command results display separately from the assistant answer. Commands and
standalone services are admitted only while idle. Approving an enclosing tool
or invoking a command does not approve a later proposed write or model request.

Each callback returns schema-checked values. Ordinary invocations allow 16 host
operations, with separately granted state/accounting read scans extending only
those families. An SDK object is at most 16 KiB; ordinary callback text input is
at most 8 KiB. Up to 10000 invocations fit one session. Intent is saved before
startup, and a result commits only after validation and confirmed cleanup.
Crash, timeout, invalid output, or interruption can leave an unknown effect;
there is no automatic retry.

## Understand prompt and answer transforms

Prompt annotations append visibly attributed untrusted reference context. They
cannot change permissions. The original input and expanded message stay in the
journal. Answer formatting changes completed presentation, while raw text can
stream first and original assistant data stays intact.

Each annotation/prefix/suffix is at most 4096 characters within SDK byte limits;
derived text is at most 16 KiB. Earlier transforms can exhaust later input limits.
Overflow fails instead of truncating. Presentation failure retains the original
completed answer. Fresh workers have five-second initialization/callback
deadlines; their private VM state is not durable memory. Transform callbacks
cannot request state writes or model calls.

## Use state, questions, and workflows

State grants permit bounded operator/project/session storage. Project-selected
code cannot choose operator scope. Put/delete actions require a separate full
approval and current revision. Each namespace has a 1 MiB/256-record quota,
including tombstones; each value is at most 8 KiB. Deletion retains revision to
prevent stale resurrection. Approved logical bindings deliberately share data
across reviewed code/configuration versions; they neither migrate data nor grant
operations. See [Memory](memory.md) for a complete binding and note workflow.

`host.state.scan` requires read access and extends state reads through step 512
within two minutes. A page holds at most 16 records/12000 encoded record-array
bytes. It widens no write or external-operation authority. Long reads can retain
private values in journal receipts even when the returned answer is small.

Structured extension questions use the normal `answer CODE VALUE` flow. The
worker closes before the question appears; resume restores it without executing
the callback. An answer starts a saved continuation but grants no effect approval.
Headless and child sessions cannot choose an answer silently. Interrupted
post-answer work stays unknown and never replays automatically.

Workflow tool access supports bounded read/write/edit/shell calls, not MCP or
delegation. Ordinary path, `.git`, workspace instructions, shell sandbox, and
approval rules apply. New nested guidance stops before execution; review
`/context` before another explicit invocation. Calls declare 1..30000 ms deadlines;
results must fit 4 KiB text and the full escaped envelope. Oversized reads return
a known failure without partial data. Incomplete shell work can be unknown.

## Accounted model calls

A reviewed artifact with `host.actions` and `host.model` may request one-shot text
inference through a named [profile](model-profiles.md). It supplies its complete
instruction/input and bounded result/deadline. It cannot replace provider,
endpoint, or credential through arguments.

The separate approval shows full input, profile/provider/model/billing, actual
destination origin, and a digest of the wire target. Credentials and URL paths
are omitted from the destination display. Parent history, credentials, and native
continuation are not inherited. Only this request's text and normalized usage
return to its caller; they do not automatically enter the main conversation.

Calls consume model steps and optional shared [tree reservations](budgets.md),
including explicitly permitted child calls. Unsupported output caps refuse
without fallback. Interrupted requests may consume resources. Idle resume
restores receipts without inference; changed profiles can refuse resume.
Embeddings/audio need separate supported contracts. The
[synthetic model-call example](../../examples/model-calls/README.md) exercises this
without a paid service.

## Compose services and publish context

Bound services require explicit `service_bindings` in the caller's operator trust
entry and `host.services`. The target must already be imported, trusted, and
selected. Missing routes, incompatible schemas, or cycles refuse startup. No
dependency is installed or enabled implicitly. Current value services return
typed data plus provenance; they cannot return nested effects/questions. Ask the
author for the exact binding names and follow the
[service configuration reference](../developer/extension-services.md).

An explicit `host.context` publication replaces only that instance's current
session set; an empty set clears it. Up to eight items per set and 16 KiB globally
rendered context are allowed. Children and fresh sessions inherit none. Items are
attributed untrusted references. Literal receipt-backed excerpts prove recorded
text, not truth/freshness. Refusal preserves old context without eviction or
truncation. Clearing does not erase old journals or prior model transfers.
Idle resume restores committed context without fetching or callbacks.

## Select event delivery deliberately

Notifications observe chosen prompt/answer boundaries. Metadata-only
`event.notify` adds no private text; exact `event.prompt.*`/`event.answer.*` grants
select it. At most eight selected declarations use five-second callback deadlines.
Required prompt failure stops before inference. Required answer failure marks
settlement failed without retracting the answer. Optional known failure is
reported and may continue. Idle resume never replays unfinished delivery.

Live `event.feed` workers enroll on accepted new work, not idle resume. Each feed
has 1..32 queued/in-flight events with exact acknowledgments. Overload, invalid
reply, timeout, or lost resources closes coverage visibly while agent work
continues. Tool/wait sources need their lifecycle prerequisites; private tool
views need separate grants. `/diagnostics` shows coverage/closure/cleanup.
`/events off` stops feeds for this process. New invocations can enroll on new
work; incomplete catch-up needs an explicit workflow with deduplication.

Event jobs separately allow finite approved actions at supported prompt or
completed-answer boundaries. `before_request` recall can publish context before
the request snapshot. `after_turn` work cannot revise the saved answer and keeps
the session busy until its serial lane settles. Current jobs do not imply
concurrent background turns. Denied/conflicting actions fail delivery even if a
callback claims success. Any unknown job stops the lane. Questions can resume
saved continuations without repeating earlier effects. Jobs do not appear in
`/ext` or the model tool catalog.

History/catch-up reads need `host.history` plus exact private-view grants. They
are scoped to this session and a frozen paginated range. Older unrecorded views
remain gaps; a completed scan does not prove complete conversation coverage.
No scan starts merely on import, selection, or resume. Writes remain separate.

## Deliver visible text to a selected client

A trusted `stream.text` worker receives private visible provider text, excluding
summaries, hidden reasoning, and completed formatting. Optional
`stream.text.events` selects explicit frame/range identity. No separate CLI stream
flag is needed. Read-only acknowledgments grant no tools, state writes, or model
calls. At most four consumers share capacity.

Workers must be ready before dispatch. Optional consumers detach on failure or
five-second backpressure while inference continues. A closing worker can miss a
later turn with visible notice; a replacement starts only after confirmed cleanup.
To require delivery, set operator trust `text_required: true` with `stream.text`.
Every frame/completion must then be acknowledged before answer admission. Lost
required delivery stops the request and retains usage. `/cancel` resets an
extension-owned enrollment only after cleanup; later work reenrolls under the
same policy. Independent embedded handles require their own explicit release.

Stream completion means text delivery, not durable answer acceptance. Another
required consumer can still cause failure. Live subscriptions do not survive
resume or replay old frames. `/diagnostics` reports resource/cleanup counts
without private text.

## Recovery and execution boundaries

Use the original configuration and temporary-selection flags for resume. Exact
artifact/options, catalog, source/scope, order/lifetime, VM, API, and generation
pins prevent silently changing executable behavior. Missing, extra, tampered,
expired, or incompatible code refuses recovery. Committed results/context restore
without callbacks. Pending questions wait; other interrupted work stays idle
with unknown outcomes.

Do not use `--no-extensions` to remove an existing session's pinned set. Restore
its original code/configuration, retain a matching frozen runner, or export a
reviewed [handoff](recovery.md). Built-in license changes also change identity;
imported artifacts retain their own license/identity until rebuilt and imported.

Import does not overwrite an invalid digest directory. A busy lock requires the
other importer to finish; keep lock files for identity. Abandoned `.staging-*`
directories are inert. Inspect/remove only abandoned staging when no importer
runs. There is no automatic repair or garbage collector.

Workers inherit no provider credential environment, but trusted code still has
operator filesystem/OS access. SDK schemas, ownership, deadlines, and process-group
cleanup are not an OS sandbox. Review direct code effects accordingly. Use
[Diagnostic capture](observability.md), [Recovery](recovery.md), and the
[developer extension manual](../developer/extensions.md) for the next investigation.
