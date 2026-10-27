# Select and use extensions

An extension adds reviewed tools, commands, transforms, or event consumers.
Bundled features and independently built artifacts use the same selection and
grant rules. Imported code has your OS permissions. Review its source and
manifest before trusting it.

## Try a bundled transform

Save this complete operator file as `/private/path/extensions.json`:

```json
{
  "version": 1,
  "extension_trust": [
    {"artifact":"builtin:prompt-annotation:1","capabilities":["transform.prompt"],"allow_project":false,"allow_children":false},
    {"artifact":"builtin:answer-format:1","capabilities":["transform.presentation"],"allow_project":false,"allow_children":false}
  ],
  "extensions": [
    {"instance":"annotation","artifact":"builtin:prompt-annotation:1","enabled":false,"options":{"text":"Keep explanations concise."},"order":10,"lifetime":"persistent"},
    {"instance":"formatter","artifact":"builtin:answer-format:1","enabled":false,"options":{"prefix":"<answer>","suffix":"</answer>"},"order":20,"lifetime":"persistent"}
  ]
}
```

```sh
ipse extension list
ipse extension inspect builtin:prompt-annotation:1
ipse config --config /private/path/extensions.json --no-project-config \
  --extension annotation --extension formatter
ipse demo --config /private/path/extensions.json --no-project-config \
  --extension annotation --extension formatter
```

Expect the ordinary credential-free demo and a completed answer inside the tags.
The annotation is attributed reference context, not a separate printed message or
permission grant. Original provider data remains in the journal. Formatting
changes completed presentation; raw text may stream first.

`--extension INSTANCE` selects an already configured instance for the durable
session without editing the file. Set `enabled: true` for future persistent use.
`--no-extensions` disables new selections and cannot combine with `--extension`.
Neither flag hot-loads code or changes an existing pinned selection.

## Import a reviewed artifact

Obtain an artifact compatible with your runner's platform and OTP version:

```sh
ipse extension import /path/to/reviewed-artifact
ipse extension inspect DIGEST
```

Use the actual printed digest. Import snapshots and validates inert files;
inspection executes no extension code. A digest identifies bytes, not an author
or a safety assessment. Editing the original source does not change the imported
snapshot. Do not add imported code to the host code path.

Use the digest in both an operator trust entry and an instance definition, as
in the complete bundled example. Set its actual manifest capabilities/options,
and select the instance. Import, trust, configuration, selection, and approval
of later effects are separate steps.

Trust must cover all declared capabilities. A project instance additionally needs
operator `allow_project: true`; `--trust-project-config` cannot replace that grant.
Children inherit only instances with `allow_children: true`. They retain separate
approvals and cannot use MCP or delegate again.

Nearer configuration replaces a whole instance by ID. Execution order is ascending
`order`, then ID. There are at most eight effective instances and sixteen trust
entries. Inspect provenance and option digests with `ipse config`, and pinned
identities with `/session`. Keep secrets out of options. Optional `expires_at`
is absolute Unix seconds; the earlier trust/instance expiry applies. Admission
checks expiry at startup, intent, and result. It is not a live revocation timer,
and expiry deletes no committed results or context.

## Invoke a command and inspect its complete result

In chat, `/ext` lists actual names and schemas. A configured Memory instance named
`project-notes` provides this example:

```text
/ext
/ext ext__project-notes__recall {"query":"release checklist","limit":5}
```

Follow [Memory setup](memory.md) first. Commands and standalone services run while
idle and return separately from the assistant answer. A command result does not
automatically enter model context. Model-visible tools use names such as
`ext__INSTANCE__ID` and ordinary full-argument approval. Invoking a command or
approving its tool does not approve later writes or inference. Ordinary headless
effects require the broad `--yes` setting. A reviewed protected collection policy
has a separate narrow saved-consent path; its exact Session pin and current policy
must still pass every publication check. Invalid arguments refuse before initialization.

Most results are schema-checked inline values. SDK-2 tools/commands declaring
`invoke.result.pages` may return `saved.result`, with `output_id`, `byte_count`,
`sha256`, and `historical_receipt: true`. This descriptor identifies a retained
complete document, not the domain answer. Close the chat before reading its saved
journal from another process:

```sh
ipse result ACTUAL_OUTPUT_ID --resume ACTUAL_SESSION_ID \
  --state-dir /private/path/sessions
```

Use your actual IDs and original store. Expect the complete original JSON value;
whitespace/key order may differ from retained source bytes. The CLI verifies
source records, size, digest, and schema without starting a worker or model.
Redirect to a private file when needed.

For a bounded view inside the original chat:

```text
/result {"output_id":"COPY_THE_ACTUAL_64_HEX_OUTPUT_ID","path":[]}
```

The placeholder must be replaced. Containers expose up to sixteen children;
strings expose up to 1,024 UTF-8 bytes. Read actual child keys/indices through
`path`. Copy a returned cursor exactly into `{"cursor": RETURNED_CURSOR}` for
continuation. `complete: true` and `next: null` finish that target; references
inside it need separate reads. Malformed cursors and mid-code-point offsets refuse.

A model can read only results disclosed through its own session's visible tools.
Reading a command result does not disclose it. An ID/cursor grants no authority
to children or unrelated extensions. Historical results retain earlier bytes even
after note expiry, forgetting, or source deletion. They prove no current eligibility.

The SDK object bound remains 16 KiB. Saved documents allow 4 MiB, 8-KiB strings,
depth 12, and 4,096 members per collection. Sessions allow 64 begun attempts and
64 MiB of encoded source records; interrupted attempts count. Lower journal
limits can refuse capacity. No partial result becomes a successful publication.
Eligible SDK-2 calls share a two-minute deadline from original admission, including
startup, approvals, effects, transfer, validation, and cleanup. Pages do not reset it.
Services, jobs, transforms, and recovered question continuations remain inline.

## Ask for exact Session evidence

In a fresh chat, the model can use `source_list`, `source_read` and `source_quote`
to inspect admitted evidence from that conversation. No optional extension is
needed. After a real answer or tool result, ask for an exact source check:

```text
List this conversation's admitted sources. Read the original input and the relevant
tool evidence, quote the exact supporting words, and report missing coverage.
```

Expect occurrence/version IDs, origin and explicit coverage. Original prompts
retain their exact bytes; verified native question answers remain distinct from
assistant suggestions and unattended input. Tool outcome facts are separate from
untrusted output text. Origin records who or what supplied the bytes; it does not
prove truth or grant action permission. Reading a source does not save a note,
enable automatic knowledge capture or contact another service.

Each index page fits 4096 rendered bytes and up to 32 rows; each evidence page
fits 8192 rendered bytes. More pages may be needed. A quote must match uniquely
and exactly, including whitespace and Unicode. If it is ambiguous, include more
supporting words. `unavailable`, legacy/unverified and capacity gaps are explicit;
the model must not invent missing source text. A completed index page means its
indexed window is exhausted, not that every historical event has readable text.
Visible original answers over 8 KiB are unavailable under the retained answer-view
bound. Original inputs keep their independent 1-MiB limit.

The source window retains up to 1024 occurrences/8 MiB and refuses further capacity
without evicting earlier sources. A changed window or resumed Session rejects old
handles; request a fresh list. Read operations count toward normal turn/context
limits. Reducing inline context does not make admitted sources unreadable.
Older saved sessions keep their original tool catalog and may lack these tools;
start a fresh Session to use the new catalog.

A reviewed extension can receive the separate `host.sources` grant, together with
`host.actions`, to read private admitted sources from its current Session. Grant
only capabilities declared by its actual manifest; an existing `host.results`,
history or state grant does not imply this access. It grants no child or unrelated
Session transcript access. Extension readers have a finite 512-read/two-minute
bound and ordinary cancellation. [The developer protocol](../developer/session-sources.md)
explains exact requests and recovery checks.

## Approve state, workflow, and model work

A state read grant does not allow writes. Each put/delete requires approval and
the current revision. Namespaces permit 1 MiB and 256 records including tombstones;
values permit 8 KiB. Deletion preserves revision identity against stale writes.
`host.state.scan` allows at most 512 read steps within two minutes, with sixteen
records and 12,000 encoded array bytes per page. Receipts can retain private data.
[Memory](memory.md) provides a complete scoped-note workflow.

Protected collection access is a separate host contract. Declaring
`host.collection.read`, `host.collection.write` or the separate
`host.collection.managed` does not save permission, select a project, or activate
an older Session. Managed publication requires its explicit capability and
reviewed recipe; read/write grants do not imply it. A selected reviewed export can use
`saved_consent` only with its exact protected policy, evidence and execution-mode
ceilings. Every proposed batch is checked again at publication. This permission
does not approve ordinary files, shell commands, MCP or other services. A conflict
or interrupted publication needs inspection before an explicit retry; known
conflicts can consume conservative operation/byte allowances. The
[developer contract](../developer/collection-sdk.md) describes the generic SDK;
use a feature's documented operator setup before expecting this path to activate.
Raw collection reads and historical validity receipts prove no current note
eligibility; every-dispatch revalidation and withdrawal remain separate work.

A question closes the worker before displaying `answer CODE VALUE`. Resume restores
the pending question without executing it. Answering starts its saved continuation,
not approval of subsequent effects. Headless and child sessions cannot supply
answers silently. Interrupted continuations remain unknown.

Workflow file/shell calls use ordinary workspace guidance, approvals, confinement,
and 1–30,000-ms deadlines. Text is bounded to 4 KiB plus its escaped envelope.
Oversized reads fail without partial data; incomplete shell work can be unknown.
Delegation is not a host call. [MCP setup](mcp.md#allow-a-reviewed-extension-to-use-a-selected-item)
owns external selected-item bindings.

Text inference uses a named [profile](configuration.md#reuse-a-named-model-profile).
The artifact supplies its complete instruction/input, without selecting new
credentials or endpoints through arguments. Approval shows input, route, billing,
origin, and wire-target digest, excluding credentials and URL paths. It inherits
no parent transcript or native continuation. Returned text does not enter the
conversation automatically. Calls consume model steps and shared
[reservations](resources.md); unsupported caps refuse without fallback. Audio is
outside this contract. [Example builds](../../examples/README.md) include a
credential-free model-call exercise.

## Generate vectors explicitly

Build or obtain the reviewed embedding example, import it, and substitute its
actual digest in this complete local configuration. The example assumes an
already installed `embeddinggemma:latest` with native width 768; confirm those
facts for your service, or choose your actual model/width:

```json
{
  "version": 1,
  "embedding_profiles": {"local_embedding": {
    "operation":"embedding","provider":"ollama","model":"embeddinggemma:latest",
    "dimensions":768,"dimension_mode":"native","credential":"none",
    "base_url":"http://127.0.0.1:11434","timeout_ms":30000
  }},
  "extension_trust": [{
    "artifact":"DIGEST","capabilities":["invoke.command","host.actions","host.embedding","host.results","host.actions.mixed"],
    "allow_project":false,"allow_children":false
  }],
  "extensions": [{"instance":"embeddings","artifact":"DIGEST","enabled":true,"options":{},"order":0,"lifetime":"persistent"}]
}
```

Save it as `/private/path/embeddings.json`, inspect it with `ipse config`, then:

```sh
ipse chat --provider demo --config /private/path/embeddings.json \
  --no-project-config --cwd /path/to/scratch
```

```text
/ext ext__embeddings__embed {"profile":"local_embedding","inputs":["The release checklist lives in the handbook."],"timeout_ms":30000}
```

This makes real embedding requests despite the scripted main provider. Review the
separate approval's complete inputs, route, model, dimensions, origin, and digest.
Success returns request/model/usage facts and vector index, byte count, digest,
and page count. A 768-coordinate float32 vector has 3,072 bytes. The example
reconstructs vectors and reports metadata instead of printing coordinates.
A vector is not a citation or proof of answer quality.

At most eight operator-only embedding profiles select OpenAI API or Ollama.
ChatGPT subscription, Anthropic, and demo supply no embeddings. Width is 1..4096;
`native` omits the wire dimension field and checks returned width. `request` sends
the configured width and needs provider/model support. Mismatch fails, with no
silent shortening. Ollama explicitly disables truncation. For OpenAI use
`credential: "OPENAI_API_KEY"` and your chosen embedding model/dimensions.

Calls accept one to eight nonempty UTF-8 inputs, 4096 bytes each and 12,288 together,
within the escaped 16-KiB object. Timeout is 1000..120000 ms, narrowed by policy.
Provider context limits still apply. Check a custom `journal.max_record_bytes`
when capacity refuses before dispatch; four 4096-wide vectors cannot fit a 65536-
byte record. Select a smaller batch or appropriate journal policy and start a new
invocation. Default record capacity is 16 MiB; total limits remain separate.
Unknown settlement prevents readable vector publication and retains liability.
Version-2 [rate cards](resources.md#configure-a-rate-card) price embeddings separately.

## Request typed advice explicitly

An extension can request a predicate probability, a choice distribution or an
ordered score from one configured decision service. This is an explicit effect;
no automatic knowledge consumer is enabled by configuring a profile. The main
conversation provider stays separate. A ChatGPT subscription does not authorize
decision API billing.

From a built checkout, review and build the small command example, then import it:

```sh
IPSE_DECISION_ARTIFACT=$(mktemp -d)/artifact
elixir dev/build-artifact.exs decision-calls --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_DECISION_ARTIFACT"
./bin/ipse extension import "$IPSE_DECISION_ARTIFACT"
```

Use the printed digest in both `DIGEST` positions in this complete private
operator file. The OpenAI route requires eligible Decisions API access and
`OPENAI_API_KEY` supplied privately through the environment. This example makes
real API calls only after its separate approval:

```json
{
  "version": 1,
  "decision_profiles": {"advice": {
    "operation":"decision","provider":"openai","model":"gpt-6-luna",
    "expected_model":"gpt-6-luna","service_id":"openai-decisions",
    "credential":"OPENAI_API_KEY","timeout_ms":30000
  }},
  "extension_trust": [{
    "artifact":"DIGEST","capabilities":["invoke.command","host.actions","host.decision"],
    "allow_project":false,"allow_children":false
  }],
  "extensions": [{"instance":"advice","artifact":"DIGEST","enabled":true,"options":{},"order":0,"lifetime":"persistent"}]
}
```

Save it outside the workspace as `/private/path/decisions.json`, inspect it, then
start the scripted main route in a scratch workspace:

```sh
ipse config --config /private/path/decisions.json --no-project-config
ipse chat --provider demo --config /private/path/decisions.json \
  --no-project-config --cwd /path/to/scratch
```

```text
/ext ext__advice__decide {"request":{"op":"decision.create","version":1,"profile":"advice","input":"The selected release requires a signed checklist.","questions":[{"id":"required","type":"predicate","instructions":"Does the input explicitly require a checklist?"}],"timeout_ms":30000}}
```

Review the full input/questions, requested and expected model, service ID,
billing mode, origin and destination digest before `allow CODE`. Success displays
normalized advice and usage. A probability is advisory, not evidence of truth or
permission to perform an action. The command's result does not automatically enter
the main conversation. Denial makes no inference request.

At most eight profiles are allowed, and only operator configuration can define
them. `system_one` uses `TYPESAFE_API_KEY` and the hosted System One wire subset;
select the actual model you can access. `system_one_compatible` requires an
explicit loopback `base_url`, exact model and `credential: "none"`; protocol
compatibility alone proves neither engine identity nor self-hostable Jev.
No route is tried as a fallback. Hosted endpoints may be overridden only in
operator configuration; the chosen endpoint receives that route's credential.

Optional `pricing`, `processing_region`, `storage_region`, `cache_retention` and
`account_controls` are bounded operator disclosure strings. Omitted values remain
unknown; they do not acquire defaults or establish service guarantees. The
operator-selected `service_id` identifies the route consistently across aliases.
Resume keeps its saved profile facts and refuses a changed selection; start a new
session to adopt a reviewed configuration change.

Input and questions must fit the complete escaped 16-KiB SDK request, with no
string over 8192 bytes. Timeouts are 1000..120000 ms and narrow to Session/profile
limits. Unsupported question shapes, wrong returned models and malformed
distributions fail without replacement advice. Shared request/input/money budgets
apply; an output-token reservation refuses before HTTP because these endpoints
provide no enforceable output cap. See [resource controls](resources.md).

Cancellation closes local owned transport but cannot undo remote work. Interrupted
calls keep partial/unknown liability and never replay on resume. Inspect the
service before explicitly retrying. The API routes have synthetic protocol tests;
live account access and useful automatic consumer quality require separate
qualification. The [developer chapter](../developer/decisions.md) explains the
wire subset and verification controls.

## Try the synthetic source lab

From a built checkout with Elixir/OTP available:

```sh
IPSE_LAB_ARTIFACTS=$(mktemp -d)/artifacts
elixir dev/build-artifact.exs extension-lab --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LAB_ARTIFACTS"
elixir dev/verify.exs source lab --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LAB_ARTIFACTS"
```

Expect seven separately compiled artifacts and an isolated verification report.
The last deliberate service crash leaves `safe_to_continue: false`; exit zero
means the positive and negative expectations matched, not that cleanup always
succeeded. This fixture makes no real inference or retrieval. The literal corpus
and parser are teaching fixtures. [Example instructions](../../examples/README.md)
cover manual import and the file workflow; use bundled Memory for ordinary notes.

## Select services, context, and delivery

A service caller needs `host.services` and operator `service_bindings`; the target
must be imported, trusted, and selected. Missing routes, schema mismatches, or
cycles refuse startup. Services return inline typed values, without nested effects,
questions, or saved output. No dependency is installed implicitly.

`host.context` replaces one instance's current reference set. Empty clears it.
There are eight items per set and 16 KiB globally rendered context. In current
versioned sessions, a refused replacement invalidates that instance's previous
selection; historical reference messages remain intact. Legacy sessions retain
their earlier replacement behavior. Children/fresh sessions inherit none. Attributed receipt-backed
text proves recorded bytes, not truth or freshness; clearing it erases no prior
model transfer or journal.

| Delivery | Choose it for | Failure/coverage behavior |
| --- | --- | --- |
| Notifications | Selected prompt or completed-answer boundaries | Up to eight declarations, five-second callbacks; required prompt failure stops inference, required answer failure cannot retract the answer |
| Live feeds | Bounded selected event views | 1..32 queued/in-flight events with exact acknowledgments; loss closes coverage visibly while agent work continues |
| Event jobs | Finite approved work before request or after turn | Before-request recall can publish context; after-turn work keeps Session busy without changing the saved answer |
| History | Explicit frozen-range reads | Unrecorded older views remain gaps; import/resume starts no scan |
| Visible text | Selected live output consumers | Up to four consumers; optional loss detaches, required loss stops answer admission |

Each private prompt/answer/tool view needs its exact grant. Metadata grants expose
no private text. Live grants do not grant history access or effects. Jobs are not
model tools or `/ext` commands. `/events off` stops feeds for this Session process;
more input does not restart them. A compatible resumed process can enroll a fresh
lease after explicit input. Catch-up requires an explicit deduplicating workflow.

For text, `stream.text` excludes hidden reasoning, summaries, and completed
formatting. `stream.text.events` adds frame identity. Operator `text_required: true`
requires acknowledgment before answer admission. Optional consumers detach after
failure or five-second pressure. Replacement waits for confirmed cleanup.
Delivery completion is not durable answer acceptance. Resume replays no frames.
`/diagnostics` shows counts without private text. Diagnostic sinks have separate
[capture controls](observability.md).

## Recover without replaying unknown work

Intent is saved before execution. Results publish only after validation and
confirmed cleanup. A crash, timeout, lost output, or interruption can leave unknown
effects. A begin/seal record alone is not a published result. Do not replay a
producer merely to repair a read; retain originals and follow [recovery](recovery.md).

Resume requires the pinned artifact, options, grants, expiry policy, and compatible
runtime. Missing/extra/tampered selections refuse; `--no-extensions` cannot remove
an existing pinned set. Committed results/context restore without callbacks;
pending questions wait. Other interrupted work remains idle and unknown.

Keep import/session lock files in place. Wait for active owners and remove only
confirmed abandoned staging directories. There is no automatic repair or garbage
collection. Workers inherit no provider credential environment, but trusted code
still has your filesystem/OS permissions. Independent VMs and SDK bounds are not
an OS sandbox. Use the [developer manual](../developer/extensions.md) to author
or investigate a contract.
