> Historical reference only. Snapshot of `docs/operator/extensions.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../operator/extensions.md).

# Extensions

Extensions add selected hooks, tools, commands, services and read-only consumers.
The bundled prompt annotation, answer formatter and local trace sink are all
**disabled by default**. Independently built local artifacts use the same SDK
in separate Elixir VMs; they can be imported without rebuilding Ipse.

Review/import an artifact, grant its capability ceiling in operator
configuration, then select an instance for a new session. These are separate
steps: import does not execute code or grant trust, and a skill or generated
feature cannot authorize itself. Start with the procedures below; use the
capability sections to understand what a selected artifact may request.
For interruption or code/configuration changes, use the shared
[recovery procedure](#recovery-and-execution-boundaries).
For a new feature request, first use the [extension-versus-core decision guide](feature-requests.md).
It distinguishes skills, configured tools and extensions from missing generic
host guarantees; the capability procedures here describe what each grant permits.

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

Extension authors can use `ipse extension check --fixture PATH` with a dedicated
operator configuration and ordinary reviewed selections. This executes code through
synthetic Sessions; it is separate from inert import/inspection. See
[conformance inputs and boundaries](../developer/extension-conformance.md) for
scratch state, assertions, explicit answers, approvals and failure handling.

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
| `host.state.scan` | Bounded value pages and extended finite state reads; requires `host.state.read` | [State](#scoped-state-host-calls) |
| `host.state.bound` | Refuse activation without an operator-granted logical storage binding; requires `host.state.read` | [State](#scoped-state-host-calls) |
| `host.question` | Explicit structured clarification | [Questions](#structured-questions) |
| `host.tools` | Existing bounded read/write/edit/shell calls | [Workflow tools](#workflow-tools) |
| `host.model` | Separately approved one-shot inference through a named profile, with canonical usage and shared admission | [Model calls](#accounted-model-calls) |
| `host.services` | Calls through explicit operator service bindings | [Composition](#service-composition) |
| `host.context` | Bounded caller-scoped context publications | [Context/evidence](#context-and-evidence) |
| `host.history`, `host.history.*` | Explicit reads of this session's metadata or separately granted private views | [History](#explicit-history-and-catch-up) |
| `host.usage` | Explicit bounded own-session canonical accounting pages, with `host.actions`; no content/child read or effects | [Usage and cost reports](usage-accounting.md) |
| `host.usage.scan` | Extended finite accounting-read allowance; requires `host.usage`, adds no new data or mutation access | [Report scope and limits](usage-accounting.md#understand-scope-and-totals) |
| `host.usage.children` | Registered direct-child discovery and frozen canonical accounting pages; requires `host.usage`, adds no transcript, arbitrary-path or child-execution grant | [Child accounting](../developer/usage-accounting.md#registered-child-accounting) |
| `stream.text` | Acknowledged private visible-text delivery through a scoped worker handle | [Text clients](#visible-text-clients) |
| `stream.text.events` | Explicit v2 frame/source format; requires `stream.text`, grants no effects | [Text event identity](../developer/stream-events.md) |
| `lifecycle.record` | Record bounded session epochs and operator waits independently of diagnostic capture; no callback or read/action grant | [Runtime facts](../developer/lifecycle-events.md#runtime-epochs-and-operator-waits) |
| `lifecycle.tools` | Record bounded admitted-tool sources; requires `lifecycle.record`, grants no read/action authority | [Tool sources](../developer/tool-events.md) |
| `observe.local`, `observe.export` | Read-only metadata sink with separate operator capture policy | [Diagnostic capture](observability.md) |
| `event.job` | Source-bound prompt handlers using normal finite approved actions, before requests or after answers | [Event jobs](#event-jobs) |
| `event.notify` | Declared read-only prompt/answer notifications; metadata only without a private read capability | [Event subscribers](#event-subscribers) |
| `event.feed` | Supported selected event views after explicit enrollment, bounded queue and visible incomplete closure; acknowledgments only | [Live feeds](#live-event-feeds) |
| `event.tool.input`, `event.tool.result` | Separately selected structured tool input or result; source prerequisites remain required | [Tool views](../developer/tool-events.md) |
| `event.prompt.original`, `event.prompt.effective` | The selected original or final-effective user-text view | [Event subscribers](#event-subscribers) |
| `event.answer.original`, `event.answer.presented` | The selected original or completed presented answer text | [Event subscribers](#event-subscribers) |

Every `host.*` operation capability also requires `host.actions`; `stream.text`
is a separate read-only capability. `lifecycle.record` enrolls metadata recording
for the new process without starting an extension worker; history reads,
subscriptions and effects need their own grants. Unsupported
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
permit finite proposals for state, questions, tools, services or context. The
ordinary invocation budget is 16 operations; separately granted accounting/state
scans extend only their own read families. Ordinary returned JSON remains inert.
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
session memory API. These transform callbacks cannot request state writes or
model calls. The separate explicit invocation/action contracts below support
scoped effects.

Read-only event subscribers use their own manifest declarations and trust grants,
as described below. Separate event jobs can propose approved storage and recall
actions; notification access alone does not authorize them, model requests or
transfer to another system.

## Event subscribers

Choose a boundary notification for prompt/answer processing or a live metadata
feed for ongoing observation. They have separate declarations and controls;
neither grants storage, tools or inference. Ordinary extension trust, selection,
project/child ceilings and disabled behavior apply to both.

### Prompt and answer boundaries

An imported artifact may declare notifications for original input, final
effective user text or a completed answer. Select it with the existing extension configuration/flags,
after reviewing its code and declared capabilities. `event.notify` alone receives
metadata; private views additionally require the corresponding `event.prompt.*` or `event.answer.*`
grant. Installing the artifact does not activate it, and diagnostic capture may
remain off. See the [SDK declaration and limits](../developer/extension-events.md).

Prompt callbacks run after all prompt transforms and before MCP discovery or
model requests for that input. Answer callbacks require an explicit `after_turn`
schedule and run after presentation is saved. Original and presented answer views
are separate read grants; neither exposes native provider continuation. Each
callback uses a fresh owned VM and can only acknowledge the event.
A required prompt failure stops before inference; a required answer failure
marks settlement as failed without retracting the answer. An optional
failure is recorded and reported, then ordinary work can continue. There are at
most eight selected declarations; the existing SDK byte bounds and five-second
initialization/callback deadlines apply. Overflow refuses without truncation.

Idle resume runs no subscriber, and an unfinished delivery is never retried
automatically. A new explicit input creates new occurrence/delivery IDs.
Native clarification resume retains the selected prompt/answer context, so an
explicit answer can continue to answer delivery without repeating earlier prompt
notifications. Missing/corrupt source checkpoints refuse instead of dropping work.
Live diagnostics show admitted/pending delivery and unconfirmed cleanup without
private text. A timeout may stop the VM without confirming final cleanup; close/cancel
reports that uncertainty. Notifications cannot perform host actions or alter the
current prompt or completed answer.

### Live event feeds

Reviewed artifacts may separately declare `event.feed` for supported model,
tool, context, question, wait, child, extension and turn metadata. Their workers
see allowlisted counts/categories and source IDs by default. Explicit
`event.tool.input`/`event.tool.result` grants select bounded tool arguments or
result text; metadata and private views retain the same occurrence ID. All admitted-tool
types need `lifecycle.tools` and `lifecycle.record`; wait sources need
`lifecycle.record`. Historical tool views need their separate `host.history.tool.*`
grants. No private view is inferred from older unrecorded history. Use the ordinary
import, trust, enable/disable and `--extension` selection controls. Diagnostic
capture can remain off. See the [feed author contract](../developer/extension-feeds.md).

Workers enroll once on accepted new work or an explicitly validated answer;
opening/resuming an idle session starts none. Earlier facts are outside enrollment.
Each declared feed has 1..32 queued/in-flight events and exact acknowledgments.
Overload, invalid replies, timeout or lost resources close coverage visibly while
agent work proceeds. Installing a feed does not approve graph storage, model
requests or external transfer. Historical reads and later writes retain their
separate grants and approvals.

`/diagnostics` shows readiness, admitted/acknowledged counts, pending capacity,
closing reason and cleanup confirmation. `/events off` revokes feeds and performs
bounded cleanup; `/cancel` and session close also stop them. A stopped feed stays
stopped for this process. Use reviewed configuration in a new invocation to enroll
on new work; idle resume never replays old callbacks. Incomplete deliveries need
explicit bounded catch-up and deduplication. Cleanup uncertainty is reported
separately from turn success, and an acknowledgment alone is no storage-success claim.
Tool-source diagnostics also show recording/fact counts and incomplete outcomes
without disclosing arguments or text. Missing/oversized views close affected
private feeds visibly; they preserve original native messages and normal approvals.

## Event jobs

Reviewed artifacts may separately declare `event.job` handlers for prompt or
completed-answer facts. Select them through the ordinary trust/configuration
and `--extension` mechanisms. Review the handler, schedule, private view and each
requested host capability; an enabled notification never silently becomes an
effectful job. Jobs do not appear in the model tool catalog or `/ext` commands.
See the [job SDK contract](../developer/extension-event-jobs.md). The wider internal
metadata vocabulary does not enable extra subscription types: current manifest
delivery covers the two prompt facts and `answer.committed`. Answer jobs run only
after the answer and receive only their selected view. Separate
[diagnostic capture](observability.md) consumes metadata without granting private
views or actions.

`before_request` runs after prompt transforms and before inference. A recall job
can read scoped state or a bound service, then publish bounded attributed context
for the frozen request snapshot. Required failure stops that attempt before
inference. `after_turn` runs after the answer/presentation is saved; its work
cannot revise that answer, and published context is available only to a later
request. The session stays busy until this serial maintenance lane settles;
fully concurrent background turns are not supported.

Writes and other effects retain normal full approval, including headless denial
without explicit enabling. A question answer is not write approval. The host
computes completion from action receipts: denied/conflicting/failed actions
produce a failed delivery even if the callback claims success. Optional known
failure may continue; any unknown job outcome stops the lane because effects may
have occurred. Diagnostics report content-free delivery outcome counts.

An explicitly answered pending question can resume its saved continuation and
remaining plan without rerunning the event callback or earlier effects. Ordinary
idle resume starts no jobs, and interrupted work is never automatically retried.
Store deletion does not erase original journals or prior provider transfers.
The [independent extension lab](extension-lab.md) provides a synthetic installed
memory/graph/workflow walkthrough. Production memory/graph policy remains a
separate plan requirement.

## Scoped state host calls

Reviewed artifacts may declare `host.actions` plus `host.state.read` and/or
`host.state.write`. These capabilities are default-off and require operator trust.
Workers can request get/list/put/delete in host-derived operator/project/session namespaces.
Project-configured code cannot select operator scope. State is not automatically
sent to a model or another extension. The independently selected
[explicit memory extensions](memory.md) build note policy on these generic calls;
they do not enable automatic capture.

Every put/delete asks for separate full approval unless execution was explicitly
enabled for the session. Invoking a command or approving its enclosing model tool
does not authorize a later write. Headless/interactive denial creates no business
record. Reads need the read capability. Up to 16 ordinary host calls fit one
invocation. Separately selecting `host.state.scan` adds value pages and permits
only state reads through step 512 within a two-minute admission deadline. Pages
hold at most 16 records/12,000 encoded record-array bytes. Invalid/unknown outcomes
stop the invocation; a long read does not widen write or external-operation grants.

Data lives in `IPSE_HOME/extension-state-v1` with private files/native locks. Each
identity/scope has a 1 MiB/256-record quota including tombstones; values are at
most 8 KiB. Writes require the current revision. Delete removes the current value
and retains its revision to prevent stale resurrection. Historical journals and
delivered text remain.

After an interrupted write, inspect its namespace/key revision and operation ID
before explicitly deciding what to do next; it may have committed. Tampered receipts or
corrupt state refuse recovery/access without repair. Legacy namespaces change with
artifact/configuration-source identity. For reviewed durable stores, the operator
may explicitly set `state_bindings` on a trust record, selecting an instance,
version-1 logical ID and allowed scopes. That ID shares data across reviewed code
or configuration versions; reusing it grants the selected code access to existing
data. Projects and workers cannot grant or override it. `host.state.bound` requires
this binding; it grants no read/write operation itself. Binding changes do not
copy/migrate state, and exact execution identities still govern resume. No generic
automatic migration or collector is available. Do not remove lock files. See
[binding configuration](memory.md#configure-explicit-memory) and
[protocol, paging and recovery](../developer/extension-host-calls.md).

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

## Explicit history and catch-up

Reviewed tools/commands/jobs may request `history.read` with `host.actions` and
`host.history`. Metadata access alone reveals no raw text; historical original,
expanded or effective prompt and original/presented answer views each need their
own `host.history.*` grant. Live `event.*` read grants do not grant past access.
Select only the views the artifact needs, using ordinary operator trust and
temporary/persistent instance configuration. No scan starts merely on import,
selection or resume.

Each read is limited to this session. A returned snapshot fixes the range;
extensions explicitly pass it to continue, so newer appends do not change that
scan. Pages are small, show skipped/unavailable records, and never silently
substitute another view or truncated text. Older sessions may lack original,
effective or completed-answer boundaries; a completed scan is not proof of complete
conversation coverage. Read/view errors return fixed codes without private paths.
See the [request, bounds and gap contract](../developer/extension-history.md).

An extension supplies the actual catch-up/reindex workflow. Its writes still need
separate normal approval, and forgetting needs the store's revision/tombstone
policy. Historical text does not automatically enter provider context. Explicitly
answered questions can continue a pinned range; idle resume never scans, retries
or replays past effects. This API does not enable cross-project or other-session
access, a database or an automatic memory service.

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

## Accounted model calls

A reviewed artifact with `host.actions` and `host.model` can request one-shot text
inference from a named [model profile](model-profiles.md). Configure that profile
normally, then import/trust/select the artifact and invoke its tool, `/ext` command
or enabled event job. The artifact supplies the complete instruction/input and a
bounded result size/deadline; it cannot replace the provider, endpoint or credential
through call arguments. No model/service is downloaded or chosen automatically.

The call has its own approval, showing the full input/instruction and
profile/provider/model/billing facts, actual destination origin and full-target
digest. Paths and credentials are omitted from that destination display; the
endpoint comes from operator configuration or the provider default. Project
configuration cannot redefine an operator profile or supply an endpoint.
Approving its enclosing tool or answering a
question does not approve inference; `--yes` grants session-wide action authority
and headless denial never dispatches. Prompt/history/memory access still needs
separate grants. Only this call's text and normalized usage return to its caller;
helper text does not enter the main conversation or visible-text stream.

Calls consume model steps and the same optional [tree budget](budgets.md) as main,
summary and child requests. Explicitly permitted child instances can use configured
profiles; model-egress approvals do not take file-mutation leases. Existing mutation
conflict checks remain active. Output ceilings and deadlines narrow inherited
policy; unsupported subscription output caps refuse without provider/billing fallback.

Use cancellation to stop owned active work. Failed/interrupted inference may have
consumed resources, so retained quota and unavailable usage do not imply zero cost.
Idle resume starts no model/worker and restores committed receipts; changed profile
catalogs refuse resume. Disable future use by removing the artifact's selection
or grant for a new session. Existing pinned sessions require their saved configuration.
Embeddings and audio need separately supported contracts.

The [request and recovery contract](../developer/extension-model-calls.md) owns
bounds and failure codes. The [credential-free artifact example](../../../../../examples/model-calls/README.md)
demonstrates source/package verification with a synthetic loopback provider; it
does not establish live provider/account or model-quality coverage.

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
recorded text, not truth or freshness. Main requests use attributed JSON in a
labelled user-role reference message; core rules alone occupy the system message.
Global rendered context is limited to 16 KiB and
full SDK envelopes must fit; refusal preserves existing context without eviction
or truncation. See [request examples and exact limits](../developer/extension-context.md).

Idle resume restores committed contributions and request snapshots without
running callbacks or fetching again. A committed publication survives cancellation
of the remaining callback. Updating/clearing is explicit; clearing does not erase
old journals or already delivered provider text. Diagnostic inspection reports
only counts, bytes and digest. Saved data has no automatic freshness/TTL guarantee.
Changes to pinned code/config still require the documented recovery path.

## Visible-text clients

Embedded clients may explicitly subscribe while idle. An installed artifact
trusted/selected for `stream.text` receives the same bounded private frames in
its owned worker; select it through the usual configuration or `--extension`.
V1 stays the default. An artifact additionally trusted for `stream.text.events`
selects v2 frames with live stream/range identity; embedded clients request
`Session.subscribe_text(session, 2)`. This changes the format, not effect authority
or the permitted content. See [event identity and limits](../developer/stream-events.md).
There is no separate stream CLI flag. Consumers get raw visible model text,
excluding summaries, native reasoning, credentials and completed formatting.

Worker callbacks acknowledge an opaque scoped handle and sequence; they cannot
turn a stream reply into tools, state writes or model requests. At most four
consumers share channel capacity. Selected workers must be ready before provider
dispatch; capacity/startup refusal stops that attempt. Once enrolled, optional
consumers detach on failure or five-second backpressure timeout while inference
continues. Healthy peers stay enrolled. A closed stream reports incomplete delivery.
If that optional worker is still closing when you send the next prompt, Ipse
continues without delivering that turn to it and reports its absence. A later
prompt can initialize a replacement after confirmed cleanup. It does not overlap
two workers for that instance or restart a failed consumer within a turn.
Large provider deltas are split into bounded UTF-8 frames while preserving their
exact text and saved response. This does not enlarge buffers or bypass the
pressure deadline.

To require delivery, add `"text_required": true` to that artifact's operator
`extension_trust` entry, whose ceiling must include `stream.text`. The artifact
and project options cannot enable this policy themselves. Required consumers
must acknowledge every frame including completion before answer admission;
loss or a five-second deadline stops the request with a required-delivery error.
Already paid usage remains recorded. Embedded clients use
`Session.subscribe_text(session, 2, required: true)` for the same policy.
Unexpected required-consumer loss between turns still blocks the next main
request; broker loss cannot silently downgrade delivery. For an extension-owned
consumer, `/cancel` closes it and releases its enrollment after confirmed cleanup.
The next task initializes a new consumer under the same required trust policy.
This reset works while idle too; an unexpected callback failure alone never
releases the requirement. Unconfirmed worker cleanup stops the Session instead.
Embedded operators can release their separate live/lost handles while idle with
`Session.unsubscribe_text(session, handle)`. Extension cancellation does not
release those embedding handles. Dead-broker recovery without a usable handle
requires a reviewed fresh Session. These live enrollments do not survive
resume. A summary request cannot clear an existing main-delivery requirement.
Omitting the setting leaves delivery optional; it does not bypass startup checks
or turn an unconfirmed worker shutdown into confirmed cleanup.

Stream completion reports delivery of provider text, not acceptance of the answer.
A healthy optional client may finish receiving while another required client later
fails and the turn ends in error. Use the Session result for success, or subscribe
to `answer.committed` for durable answers. Text completion has no later correction
frame; see the [delivery and admission contract](../developer/text-streams.md#flow-control-and-ownership).

Subscriptions/frames never replay on idle resume. Fresh operator input can enroll
a new resource; no failed frame is retried. `/diagnostics` reports active count
and unconfirmed cleanup without text/options. Cancel/close stops workers; owner
death also stops blocked callbacks. Terminal delivery is best effort, and
unconfirmed cleanup is reported. See the [SDK and embedding contract](../developer/text-streams.md).

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
implemented yet. The MIT → Apache-2.0 transition also changes the bundled
license bytes bound into built-in artifact identities. Sessions that selected a
built-in under the earlier license need their preserved runner or an explicit
reviewed handoff into a fresh session. Imported artifacts keep their own declared
license/identity until explicitly rebuilt and imported; the transition does not
rewrite them.

An expired instance also refuses activation/resume; disabling it cannot rewrite
the saved active set. The read-only `diagnose` and operator-written `handoff`
commands remain available without activating extension code, subject to valid
saved journal/source records. See [saved inspection and fresh-session recovery](recovery.md).

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

Use the procedures above for implemented subscriptions, jobs, ordered recall and
diagnostic controls; use the [lab walkthrough](extension-lab.md) for separately
built memory/workflow artifacts. The [coverage audit](../developer/lifecycle-events.md#supported-lifecycle-coverage)
defines supported stages/views; [P22 status](../plan.md#p22-extension-scaffold-and-lifecycle-hooks)
records passed hosted verification of the lab. Remote installers,
build assistants and live activation are future capabilities. Current import and
selection never install a dependency or silently switch providers.
