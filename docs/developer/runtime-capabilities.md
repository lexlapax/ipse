# Choosing the right runtime contract

A contributor adding a capability must decide who owns its authority, lifetime,
and result. Ipse keeps generic admission, approvals, durable evidence, provider
routing, and cancellation in the host. Extensions implement domain algorithms,
reports, and presentation through explicit contracts. This division lets a feature
remain optional without making its effects invisible.

Read this chapter before adding a new callback to Session. Often an existing
command, action, or resource already supplies the needed boundary.

## Match the result to its channel

| Need | Existing owner/contract | Consequence |
| --- | --- | --- |
| Request facts and normalized counters | `Usage`, Session journal | Available with tracing disabled; unknown stays unknown |
| Request admission across children | `Budget` and protected ledger | Reserve before dispatch; interrupted liability remains |
| Cost reporting | `Extensions.Costs` and report family | Configured rates, exact basis, no billing authority |
| Metadata diagnosis | `Observability.Channel` | Bounded sampled delivery; gaps/drop counts allowed |
| Ordered visible provider text | `TextStream` | Private grant, acknowledgments, bounded pressure |
| Admitted completed answer | Lifecycle answer source | Distinct from transport end and presentation acknowledgment |
| Bounded domain effects | Owned extension actions/jobs | Ordinary approval and intent/outcome receipts |
| OS execution confinement | `Sandbox`, native helper | Independent of all SDK permissions and approval |
| Observe a local listener's process owner | `Runner`, optional Linux stdio proof | Admit the endpoint after the native observation; retain transport ownership |

An observer cannot enforce a budget after dispatch. A text acknowledgment cannot
write state. A tool's read-like name cannot waive external-call approval. Keep
these implications visible when designing an API.

## Trace a new text-derived feature

Consider a selected extension that counts words in visible output. It needs
`stream.text` and a read-only callback. It can keep private worker-local counters
and acknowledge frames. It receives no hidden reasoning/native continuation and
cannot return `host_call` from this callback. To save a domain record, expose an
explicit invocation or a separately admitted event job using state actions.

For a source-reading exercise, follow `Ipse.TextStream.push_delta/3` in
`lib/ipse/text_stream.ex`, then the negotiated frame projection in
`lib/ipse/lifecycle/ephemeral.ex`. Compare the end frame to Session's final answer
admission. A healthy optional consumer can receive completed transport while a
required peer later fails and prevents answer admission. The correct trigger for
an admitted-answer workflow is `answer.committed`.

```sh
mix test test/text_stream_session_test.exs test/lifecycle_answer_test.exs
```

These suites teach the distinction through real Session behavior. They also check
that private native history remains unchanged. See [text streams](text-streams.md)
for flow control and [lifecycle events](lifecycle-events.md) for saved sources.

## Add inference through admission

Model work needs an explicitly selected profile, credential reference, egress
approval, canonical request/attempt identity, normalized usage, and shared budget
admission where configured. The [one-shot extension model action](extension-model-calls.md)
supplies these for text helpers. It does not open a second conversation loop or
receive private data without separate grants.

[Embedding actions](extension-embedding-actions.md) supply the separate native
vector contract. They use selected operator embedding profiles, exact egress,
typed float32 result pages and operation-aware metering. Their generated-output
token dimension is explicitly inapplicable; applicable input/money liabilities
still share the same tree. Do not substitute text containing numbers for native
vectors or perform unaccounted worker network calls.

Counters describe measurements, not prices. OpenAI cache/reasoning values are
subsets; Anthropic cache totals have separate semantics; Ollama missing counters
stay unknown. Cost estimates identify rate-card digest/revision and keep API,
subscription equivalent, and local basis apart. Subscription text entitlement is
not API credit or authority for another endpoint. A refusal never silently changes
provider/billing mode.

Usage and budget state survive failed/cancelled work. Optional diagnostics can be
dropped; canonical accounting cannot. Out-of-band executable calls and arbitrary
MCP service charges are outside covered host model accounting. Explain that limit
when adding a backend rather than inferring coverage from a shared worker process.

## Check a directly owned local listener

A configured HTTP server can fail to bind while an existing server answers at
the same address. A matching metadata response does not establish that the new
process owns that endpoint. On Linux, `Runner.open_stdio/6` accepts
`owned_listener: {:ipv4_loopback, port}` with sandbox `:off` and an absolute
executable. It emits a native `P` fact after associating the caller's exact
`127.0.0.1` listening socket with the retained direct child's descriptors.
Follow the constructor's bounded `/proc/self/status` check before studying the
descriptor lookup. A sole `NStgid` value equal to the helper's process ID proves
that numeric procfs paths use the helper's PID namespace. An inherited ancestor
procfs refuses before server launch. A nested namespace with its own procfs is
supported; ordinary stdio does not require this optional capability.

Exercise the public API from a built checkout:

```sh
mix run scripts/verify-owned-listener.exs
mix test test/owned_listener_test.exs test/stdio_runner_test.exs
```

The Linux exercise reports seven checks, two metadata requests and zero inference
requests. Inspect its private `evidence` directory. The positive case checks the
native fact before querying its owned fixture. The occupied-port case first
proves refusal without a request, then queries the still-running ordinary fixture
as a positive control. Wildcard and delegated-only listeners refuse. A child
printing a forged proof remains opaque stdout, and a missing listener times out.
Ordinary stdio emits no proof. Other platforms refuse the optional mode before
the selected executable runs.

Exercise the two repaired identity races separately:

```sh
mix run scripts/verify-owned-listener-regressions.exs
```

This Linux control compiles temporary diagnostic copies of the native source.
It compares current behavior with one deliberately reverted repair at a time.
A real private-namespace listener must remain unproven in the caller's namespace.
Closing supervisor stdout while inspection is pending must retain the unreaped
child until helper teardown. Production source remains unchanged. Expect
`status: passed` and retained private evidence. Three further controls exercise
PID/procfs identity. Inherited ancestor procfs must refuse before the selected
executable writes its marker. Ordinary stdio must execute in that same setup.
A fresh PID namespace with privately mounted procfs must admit its actual owned
listener. Inspect the recorded namespace identities and cleanup receipts.
Unavailable user/network/PID/mount capabilities produce `status: incomplete`
with exit status 2, which does not establish coverage.
These synthetic controls use no model service, systemd or cgroup hierarchy.

Follow `open_stdio/6` into `native/ipse-stdio.rs` and `native/ipse-listener.rs`.
The sole wait owner retains the child unreaped while a background inspection
uses its numeric proc paths. Both socket-table reads describe the supervisor's
network namespace. Reading the child's namespace instead would admit a private
listener that the HTTP caller cannot reach. On output loss, a pending inspection
must keep that same unreaped identity until helper teardown.

Treat `P` as one ownership observation. Continue draining and monitoring the Port
while making bounded application-metadata requests; terminal or transport loss
ends admission. Its PID and inode are diagnostic fields, not signaling handles.
Cleanup still uses `Runner.close_stdio/2` and the ordinary process-group contract.
Use the [native protocol](../../native/README.md#observe-an-owned-loopback-listener)
for exact fields and bounds. Continue to use profile admission and canonical
budgets for inference.

## Keep unsupported capabilities explicit

Current runtime contracts do not provide microphone/speaker IO,
audio frames, STT/TTS, bidirectional realtime inference, playback acknowledgment,
or stateful streaming rewriting. A completed-answer formatter changes display
only after generation. It cannot promise live redaction, retract displayed text,
or redact journals and provider context.

A future media capability needs a versioned bounded data plane, opaque scoped
handles, negotiated format, ownership, interruption, and cleanup. It must keep
transcripts/accounting distinct from ephemeral media and define retention/consent.
Generated output and actually played output are different facts. A spoken "yes"
is not by itself approval of arbitrary pending effects. These requirements are
API design criteria, not available configuration fields.

## Propose a host enhancement only for a shared invariant

Write down the exact missing guarantee: for example, a new measured unit, source
view, owned resource, or cancellation boundary. Specify closed schemas, numerical
bounds, stale/wrong-owner refusal, and no-replay recovery. Unknown versions or
capabilities must fail before executable activation. Reuse existing modules and
maintained Elixir/OTP packages before introducing protocol machinery.

`Ipse.RuntimeInfo` is an example of a deliberately small projection. Its snapshot
exposes application/version, selected provider/model, separately reported current
and saved model names, and profile ID/role/effort. It accepts model identifiers of
1–200 bytes from a safe alphabet; malformed/unavailable values stay unavailable.
It does not copy arbitrary configuration or promise an exact backend revision.
Read `test/runtime_info_test.exs` before adding another model-visible runtime fact.

```sh
mix test test/runtime_info_test.exs
```

Every new exposed field needs a reason the reader requires it, a bounded validator,
and a test excluding nearby private data. Avoid placing credentials, raw endpoints,
private hashes, or whole process state in a convenient metadata map.
