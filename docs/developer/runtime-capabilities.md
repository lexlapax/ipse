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
