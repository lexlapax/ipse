# Use reviewed extensions

Use extensions to add optional tools, commands, prompt annotations, answer
formatting, and selected event consumers. Review an extension's code and requested
grants before enabling it. Imported code runs with your OS permissions.

To use an extension, import its inert artifact, grant its declared capabilities,
configure an instance, and select that instance. Each step is separate. Importing
an artifact does not execute it or approve later effects.

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

Inspect the descriptors and effective selection, then run the demo:

```sh
ipse extension list
ipse extension inspect builtin:prompt-annotation:1
ipse config --config /private/path/extensions.json --no-project-config \
  --extension annotation --extension formatter
ipse demo --config /private/path/extensions.json --no-project-config \
  --extension annotation --extension formatter
```

The demo uses no account or model service. It performs its normal temporary file
and shell work. Expect the completed answer inside the configured tags. The
journal retains the attributed annotation and original provider data. The
annotation does not print as a separate terminal message.

`--extension INSTANCE` activates an already configured instance for the durable
session, including explicit resume, without editing the configuration. To enable
future sessions persistently, set its reviewed configuration to `enabled: true`.
`--no-extensions` disables selections for a new invocation and cannot combine
with `--extension`. These flags do not hot-load code or change a pinned session.

## Import an independently built artifact

Get the source, license, dependency list, manifest, schemas, and options from the
author. Review declared operations and direct filesystem or network access. Use
an already-built artifact compatible with your runtime. Import does not compile
or install dependencies.

```sh
ipse extension import /path/to/reviewed-artifact
ipse extension inspect DIGEST
```

Replace `DIGEST` with the printed 64-character artifact digest. Import verifies
lengths and hashes, then copies an inert snapshot under
`IPSE_HOME/extensions/artifacts`, normally `~/.ipse/extensions/artifacts`. Inspect
verifies that snapshot without executing it. The digest identifies bytes; it
does not authenticate the author or certify safety. Editing the original source
does not change the imported snapshot.

Use the digest in both the operator trust entry and instance configuration. Use
the artifact's actual capabilities and options in the complete configuration
pattern above. Follow [Extension lab](extension-lab.md) for a separately built
example. Do not add imported artifacts to Ipse's code path.

## Review trust and scope

Put trust entries in operator configuration. The capability ceiling must cover
every capability declared by the artifact. Project instances also need
`allow_project: true` in operator trust. `--trust-project-config` cannot replace
that grant. Children inherit only instances permitted by `allow_children: true`
and keep their own approval limits. Children cannot use MCP or delegate again.

Definitions merge by `instance`; a nearer definition replaces the whole instance.
Execution order is ascending `order`, then instance ID. Limits are eight effective
instances and sixteen trust declarations. Config inspection shows provenance and
option digests. Keep secrets out of options. In chat, `/session` shows pinned
identities and `/ext` lists the active export catalog.

An optional `expires_at` is an absolute Unix timestamp in seconds. The earlier
trust or instance expiry applies. Ipse checks expiry at startup and callback
intent and result admission. Already running work retains its execution deadline.
Expiry does not erase committed results or prior context. There is no live
revocation timer or hot reload.

Use this table to review requested grants:

| Capability family | What you allow |
| --- | --- |
| `transform.prompt`, `transform.presentation` | Bounded prompt annotations or completed presentation |
| `invoke.tool`, `invoke.command`, `invoke.service` | Manifest-declared typed exports |
| `invoke.result.pages` | Complete saved results from SDK-2 tools and commands, within separate document and journal limits |
| `host.state.read`, `.write`, `.scan`, `.bound` | Scoped state reads, separately approved writes, extended scans, or required logical bindings |
| `host.question`, `host.tools`, `host.model`, `host.services`, `host.context` | Explicit questions, built-in tools, approved profile inference, bound services, or context publication |
| `host.mcp`, `host.results` | Approved operator-bound MCP calls and bounded reads of their same-invocation saved results |
| `host.embedding` | Approved vector generation; `host.results` reads saved coordinate pages |
| `host.actions.mixed` | Up to 512 reads and 16 other calls under the existing operation grants and approvals |
| `host.history` and `host.history.*` | session metadata and separately selected historical private views |
| `host.usage`, `.scan`, `.children` | Accounting reads, extended scans, or direct-child accounting |
| `stream.text`, `stream.text.events` | Private visible text and optional frame identity |
| `lifecycle.record`, `lifecycle.tools` | Bounded runtime facts and admitted-tool source recording |
| `observe.local`, `observe.export` | Diagnostic metadata sinks under separate capture policy |
| `event.notify`, `event.feed`, `event.job` | Selected notifications, live feeds, or finite boundary jobs |
| `event.prompt.*`, `event.answer.*`, `event.tool.input`, `event.tool.result` | Exact private views, with the corresponding delivery prerequisites |

Every `host.*` operation also requires `host.actions`. A read grant does not
approve writes, inference, or transfers. A live private-view grant does not grant
history access. `lifecycle.record` alone starts no worker and grants no read or
action permission. Unsupported capabilities refuse explicitly.

## Invoke a tool or command

Enabled model tools have names such as `ext__INSTANCE__ID`. They require ordinary
full-argument approval unless you explicitly enable session-wide execution.
Headless effects are denied without `--yes`. Invalid arguments refuse before
code initializes.

To call a command without inference, enter its exact name and JSON object in
interactive chat:

```text
/ext
/ext ext__project-notes__recall {"query":"release checklist","limit":5}
```

The second command requires the [memory example](memory.md). `/ext` displays the
actual available names and schemas. Commands and standalone services run only
while the session is idle. A command result displays separately from the
assistant answer and does not enter model context. Invoking a command or approving
a tool does not approve a later write or model request.

Ordinary replies contain a schema-checked inline value. An SDK-2 artifact with
`invoke.result.pages` can instead return a `saved.result` descriptor with an
`output_id`, `byte_count`, `sha256`, and `historical_receipt: true`. The descriptor
means Ipse retained a complete result for explicit reading. It is not the domain
answer itself. Services, event jobs, transforms, and recovered question
continuations keep inline results.

The SDK object limit remains 16 KiB. Saved documents allow at most 4 MiB, with
8-KiB strings, depth 12, and 4,096 members per collection. Each session allows
64 begun saved-output attempts and 64 MiB of encoded source records. Interrupted
attempts consume those limits too. Your journal policy can impose a lower limit.
Capacity refusal does not publish a partial successful result.

Eligible SDK-2 tools and commands share a two-minute deadline starting at original
invocation admission. Initialization, approvals, effects, output transfer,
validation, and cleanup all consume that time. An approval wait can exhaust the
deadline. An output page does not restart it. Ordinary callback deadlines still
apply.

Ipse saves intent before startup and publishes a result only after validation
and confirmed worker cleanup. Crash, timeout, invalid output, or interruption can
leave an unknown effect. There is no automatic retry.

## Read a saved result

Keep the output ID from the descriptor and the original session ID. Use the
original state directory. If you did not set `--state-dir`, it is normally
`~/.ipse/sessions`. Close the original chat before reading its stable saved
journal from another process.

To print the complete JSON result, replace these three values and run:

```sh
IPSE_OUTPUT_ID='COPY_THE_64_CHARACTER_OUTPUT_ID'
IPSE_SESSION_ID='COPY_THE_SESSION_ID'
IPSE_RESULT_STATE_DIR="$HOME/.ipse/sessions"
ipse result "$IPSE_OUTPUT_ID" --resume "$IPSE_SESSION_ID" \
  --state-dir "$IPSE_RESULT_STATE_DIR"
```

Expect the original full JSON document. The command checks its source records,
byte count, digest, and schema. It starts no extension worker or model request.
Terminal escaping and the trailing newline can change the printed bytes while
preserving the complete JSON value. The descriptor's digest identifies the
retained source bytes.
To save that output locally, redirect it to a file you control. Treat the file as
private when the original result contains private text.

In the original interactive session, read a bounded root view with:

```text
/result {"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":[]}
```

Replace the example ID with the actual output ID. A view reports `kind`,
`target_type`, `offset`, `complete`, and `next`. Containers report
`total_children` and up to sixteen child summaries. Strings report `total_bytes`
and up to 1,024 UTF8 bytes in `text`. Object children use decoded-key byte order;
arrays retain their original order.

To choose a known child, put object keys and array indices in `path`:

```text
/result {"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":["evidence",0,"citation","quote"]}
```

That path is useful for a result with the shown structure. Choose actual keys
from the root view for another result. A large child has a `reference` instead
of an inline `value`. A shortened key name has `name_reference`. Both are cursor
objects that you can read in the same way as `next`.

To continue, copy the complete returned cursor into a request containing only
`cursor`. For example:

```text
/result {"cursor":{"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","source_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","path":[],"kind":"children","offset":16}}
```

The IDs and offset above illustrate the shape. Use the exact cursor from your
response. Do not replace its digest or reconstruct its ordinal path. `next: null`
and `complete: true` end the requested target. References inside that target
remain separate explicit reads. An invalid cursor or an offset inside a UTF8
code point refuses without starting a query.

The model's `saved_result_read` tool can read only results already disclosed
through model-visible tools in the same session. An output ID or cursor does not
grant access. Reading a command result with `/result` does not disclose it to the
model. Children and unrelated extensions gain no access to these saved results.

Saved results are historical receipts. Forgetting or expiring a note, deleting a
source, or replacing an index changes future retrieval. Those actions do not
erase bytes retained by an earlier result or journal. A historical read does not
prove that its source is still eligible or current.

If a read reports unavailable or invalid, check the session ID, output ID, and
state directory. A begin or seal record alone is not a published result. Retain
interrupted records for diagnosis. Do not edit the journal, replay the producing
command, or remove lock files to force recovery. Use [Recovery](recovery.md) to
inspect unknown work before deciding whether to start a new invocation.

## Understand prompt and answer transforms

Prompt annotations append attributed untrusted reference context. They cannot
change permissions. The journal retains the original input and expanded message.
Answer formatting changes completed presentation; raw text can stream first,
and original assistant data stays intact.

Each annotation, prefix, or suffix allows 4,096 characters within SDK byte limits.
Derived text allows 16 KiB. Earlier transforms can consume later input capacity.
Overflow refuses instead of truncating. A presentation failure retains the
original completed answer. Fresh workers have five-second initialization and
callback deadlines. Their private VM state is not durable memory. Transform
callbacks cannot request writes or inference.

## Use state, questions, and workflows

State grants provide scoped operator, project, or session storage. Project code
cannot choose operator scope. Put and delete actions require separate full
approval and the current revision. Each namespace allows 1 MiB and 256 records,
including tombstones. Each value allows 8 KiB. Deletion keeps revision identity to
prevent a stale write from restoring old data. Follow [Memory](memory.md) for a
complete note and logical-binding workflow.

`host.state.scan` extends reads through step 512 within two minutes. A page has
at most sixteen records and 12,000 encoded record-array bytes. It grants no
writes or external operations. Read receipts can retain private values even when
the returned answer is small.

Structured questions use the normal `answer CODE VALUE` flow. The worker closes
before the question appears. Resume restores the question without executing it.
An answer starts a saved continuation and grants no effect approval. Headless
and child sessions cannot choose answers silently. Interrupted continuation work
remains unknown.

Workflow tool access supports bounded file and shell calls under the ordinary
path, workspace-instruction, sandbox, and approval rules. Delegation is not a
host call. New nested guidance stops execution for review in `/context`. Calls
use 1–30,000-ms deadlines and fit 4-KiB text plus the escaped envelope. Oversized
reads return a known failure without partial data. Incomplete shell work can be
unknown. Configure MCP through its separate
[selected-item binding procedure](mcp.md#allow-a-reviewed-extension-to-use-a-selected-item).

## Accounted model calls

A reviewed artifact can request one-shot text inference through a named
[model profile](configuration.md#reuse-a-named-model-profile). It supplies its full instruction and input.
It cannot choose new credentials, providers, or endpoints through arguments.

The separate approval shows the full input, profile, provider, model, billing,
destination origin, and wire-target digest. Credentials and URL paths are omitted
from that display. Parent history and native continuation are not inherited.
Returned text and usage do not automatically enter the main conversation.

Calls consume model steps and optional shared [tree reservations](budgets.md).
Unsupported output caps refuse without fallback. Interrupted requests may consume
resources. Idle resume restores receipts without inference. Changed profiles can
refuse resume. Use [Embeddings](embeddings.md) for vector generation. Audio is
outside this text contract. The
[synthetic model-call example](../../examples/model-calls/README.md) needs no paid
service.

## Compose services and publish context

A caller needs `host.services` and explicit operator `service_bindings`. The
target must already be imported, trusted, and selected. Missing routes, schema
mismatches, or cycles refuse startup. Ipse installs no dependency implicitly.
Services return typed data and provenance; they cannot return nested effects,
questions, or paged output. Follow the
[service configuration reference](../developer/extension-composition.md#declare-the-value-contract) for binding
names.

A `host.context` publication replaces that instance's current session set. An
empty set clears it. Limits are eight items per set and 16 KiB globally rendered
context. Children and fresh sessions inherit none. Items are attributed untrusted
references. A receipt-backed excerpt proves recorded text, not truth or freshness.
Refusal preserves the previous set. Clearing context does not erase journals or
prior model transfers. Idle resume restores committed context without callbacks.

## Select event delivery deliberately

Notifications observe chosen prompt or answer boundaries. Metadata-only
`event.notify` contains no private text. Exact private-view grants select that
text separately. At most eight selected declarations use five-second callbacks.
A required prompt failure stops before inference. A required answer failure
marks settlement failed without retracting the answer. An optional known failure
can report its failure and continue. Idle resume does not replay delivery.

Live `event.feed` workers enroll on accepted new work. Each feed allows 1–32
queued or in-flight events with exact acknowledgments. Overload, invalid replies,
timeout, or resource loss closes coverage visibly while agent work continues.
Use `/diagnostics` to inspect coverage and cleanup. `/events off` stops feeds for
the current process. A new invocation can enroll new work; catch-up requires an
explicit workflow with deduplication.

Event jobs allow finite approved actions at selected prompt or completed-answer
boundaries. `before_request` recall can publish context before the request
snapshot. `after_turn` cannot change the saved answer and keeps the session busy
until settlement. These jobs do not create concurrent background turns. A denied
or conflicting action fails delivery even if the callback claims success. An
unknown job stops the lane. Questions can resume saved continuations without
repeating earlier effects. Jobs appear in neither `/ext` nor the model catalog.

History reads require `host.history` and exact private-view grants. Each scan
uses this session's frozen range. Older unrecorded views remain gaps. A completed
scan does not prove complete conversation coverage, and no scan starts on import
or resume. Writes require separate approval.

## Deliver visible text to a selected client

A trusted `stream.text` consumer receives visible provider text, excluding hidden
reasoning, summaries, and completed formatting. `stream.text.events` adds explicit
frame identity. No separate CLI flag is required. Read acknowledgments grant no
tools, writes, or model calls. At most four consumers share capacity.

Workers must be ready before dispatch. Optional consumers detach on failure or
five-second backpressure while inference continues. Replacement waits for
confirmed cleanup. To require delivery, set operator trust `text_required: true`
with `stream.text`. Every frame and completion must then be acknowledged before
answer admission. Lost required delivery stops the request and retains usage.
`/cancel` resets enrollment after cleanup; later work enrolls under the same
policy. Independent embedded handles need explicit release.

Stream completion is a delivery receipt, not durable answer acceptance. Another
required consumer can still cause failure. Live subscriptions do not survive
resume or replay old frames. `/diagnostics` reports counts without private text.

## Recovery and execution boundaries

Use the original configuration and temporary-selection flags to resume work.
Artifact, options, catalog, scope, order, lifetime, VM, API, and generation pins
prevent silent executable changes. Missing, extra, tampered, expired, or
incompatible selections refuse recovery. Committed results and context restore
without callbacks. Pending questions wait. Other interrupted work stays idle
with unknown outcomes.

Do not use `--no-extensions` to remove an existing session's pinned set. Restore
its original selection, retain a matching frozen runner, or create a reviewed
[handoff](recovery.md). Builtin license changes also change identity. Imported
artifacts retain their identity until rebuilt and imported.

Import does not overwrite an invalid digest directory. Let another importer
finish before using its busy lock. Keep lock files in place. Abandoned
`.staging-*` directories are inert; remove only confirmed abandoned staging.
Ipse provides no automatic repair or garbage collection.

Workers inherit no provider credential environment. Trusted code still has your
filesystem and OS permissions. SDK schemas, ownership, deadlines, and process
cleanup do not create an OS sandbox. Continue with
[Diagnostic capture](observability.md), [Recovery](recovery.md), or the
[developer extension manual](../developer/extensions.md) for an investigation.
