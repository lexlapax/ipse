> Historical reference only. Snapshot of `docs/developer/provider-limits.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../2026-10-22-before-structural-consolidation/docs/developer/provider-limits.md).

# Provider generation and response limits

`Ipse.Provider.Limits` validates an optional `max_output_tokens` before Session
creation and before the normal provider dispatcher opens a request. Configuration
and profile validation use the same contract. This is P23's per-request output
control, not a shared request/token/money budget or a reservation ledger.
Separately, host response admission bounds incoming bytes, intermediate parser
state and processing cardinality for every provider, including subscription
requests. A generation ceiling does not replace these receive-side controls.

## Public interface and wire mapping

Reviewed public interfaces on 2026-10-17:

| Provider | Accepted configured range | Request mapping and existing bound |
| --- | --- | --- |
| OpenAI API | 16..1000000 | Responses `max_output_tokens`; includes reasoning and visible output |
| Anthropic API | 1..1000000 | Messages `max_tokens`, narrowed against existing `max_tokens` or the adapter's 8192 default |
| Ollama | 1..1000000 | Chat `options.num_predict`; summary requests retain temperature/schema/thinking controls and narrow against their existing 4096 bound |
| ChatGPT subscription | Unsupported | Refuse a configured ceiling; never send the unsupported field, remove it silently or switch to API billing |
| Demo | Unsupported | A scripted demo is not a provider with an enforceable token ceiling |

These are Ipse's validation bounds, not promises that every model accepts the
whole range. A model/account/endpoint may reject a value or impose a lower bound.
An explicitly configured compatible endpoint must implement the selected provider
contract; wire fixtures do not establish its actual token enforcement. Omission
retains the previous adapter request shape and defaults. A cap limits generation;
it does not request that many tokens or increase an existing lower bound.

Primary sources:

- OpenAI's [Responses reference](https://developers.openai.com/api/reference/resources/responses/methods/create)
  and [reasoning guidance](https://developers.openai.com/api/docs/guides/reasoning)
  describe the output field and generated-token accounting.
- The [subscription preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations)
  explicitly exclude that field despite use of the public Responses endpoint.
- Anthropic's [Messages reference](https://platform.claude.com/docs/en/api/http/messages)
  and [stop reasons](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)
  define its generation bound and incomplete termination.
- Ollama's [chat reference](https://docs.ollama.com/api/chat),
  [Modelfile options](https://docs.ollama.com/modelfile) and
  [termination enum](https://github.com/ollama/ollama/blob/main/llm/server.go)
  describe generation options and the explicit `length` outcome.

## Selection, children and durable resume

The optional setting participates in ordinary file/profile/environment/CLI
precedence, field provenance and the execution fingerprint. It has no new default
key, so configurations that omit it retain their prior identity. The CLI restores
the saved setting before resolving a resumed session.

An inherited child keeps the parent's cap. A selected child profile receives the
lower of its own configured cap and the parent's cap, with an omitted child value
retaining the parent's bound. Validate this combined policy before delegation
approval/creation. A capped parent cannot route that cap to an unsupported
subscription child or to an OpenAI API child with a value below its minimum.
No model-proposed argument can widen or remove the inherited ceiling.

Session metadata pins the effective cap for embedded as well as CLI callers.
Resume compares it before tail repair or inference. A changed/removed cap refuses
without repairing the original journal; old absent/null caps compare as nil.
This metadata is policy identity, not proof of provider enforcement or a new
counter in the canonical version-1 usage projection.

## Truncation and accounting

OpenAI incomplete responses and Anthropic non-success stop reasons already refuse
assistant/tool admission while preserving reported usage observations. Ollama now
does the same for explicit `done_reason: "length"`: retain nullable input/output
usage, return a bounded incomplete-response error and admit no tool calls. Text
already streamed cannot be retracted; provider-native thinking is never exposed
as visible output. Do not retry automatically or label truncated tool arguments
safe merely because the transport ended normally.

These controls do not bound input tokens, request count, aggregate parallel work,
all provider-side charges or an invoice. ChatGPT subscription has no supported
request output field through the current public interface. Optional
[shared budget policy](budgets.md) refuses subscription output quotas, while
request/input-reservation/estimated-money quotas remain independently selectable.
[Accounted extension text requests](extension-model-calls.md) narrow these ceilings
through their selected profile and owner policy as well.

## Host response admission

The HTTP adapter uses the existing Finch/Mint stream callbacks for every status.
It receives at most 8 MiB, or a smaller explicit `max_response_bytes` bound, and
131,072 data chunks. Error bodies retain only their bounded diagnostic prefix.
These are host ceilings, not provider generation parameters or invoice limits.

SSE and Ollama JSON-lines parsing share a bounded line accumulator. It searches
only newly received bytes, retains reverse-order fragments and joins a line once
at its delimiter. OpenAI arguments, Anthropic text/tool JSON/thinking/signatures
and Ollama text/thinking similarly materialize once into the completed native
response. Ollama retains call batches in reverse order until completion.

Production consumers process each completed line/event immediately through the
reducers, before scanning later input. If a suffix exceeds a limit, earlier usage
observations remain available and an earlier provider error keeps precedence.
The collecting `feed` helpers alone do not publish a prefix after failure; use
the reducers for callbacks that produce accounting or other observations.

| Resource | Hard ceiling |
| --- | --- |
| Partial line, joined SSE data or one accumulated field | 8 MiB |
| Nonempty fragments per partial line or accumulated field | 32,768 |
| Data lines in one SSE event | 32,768 |
| Parsed lines per response | 131,072 |
| SSE events / decoded provider events per response | 65,536 each |
| Output items or Anthropic blocks | 256; indexes 0–255 |
| Tool calls in a provider response | 32, including incremental Ollama batches |

The first applicable ceiling wins; a nonempty Ollama EOF tail counts as a logical
line. The request deadline is checked during framing, before and after provider
callbacks, and before returning a successfully materialized response.
Exceeded limits refuse the incomplete response; they do not truncate it into a
successful assistant message or dispatch its tools. Already displayed text cannot
be retracted. Usage already reported stays accounted; unavailable final usage
retains the normal unknown-liability policy. No automatic retry, provider switch
or wider generation setting follows a refusal.

Deadline checks are cooperative. They refuse late successful admission when a
callback returns after expiry; they do not forcibly interrupt a callback, JSON
decoder or bounded materialization operation. Cleanup can outlast the request's
inference deadline, and already displayed text cannot be retracted.

CR, LF, split CRLF/UTF-8 and SSE multiline data retain their wire semantics. SSE
EOF never invents an event; Ollama can finish its final JSON line without LF.
Original native reasoning/signatures and call order survive successful assembly;
private thinking is not emitted as visible text. The implementation uses existing
OTP binary/list facilities, not a new transport or dependency. OTP can optimize
some [binary appends](https://www.erlang.org/doc/system/binaryhandling.html);
the repair does not assume that every concatenation copies. A retained-line
rescan probe reproduced disproportionate work, which scanning new bytes avoids.

## Verification scope

Credential-free fixtures check configuration precedence/refusal, profile and child
ceilings, normal/summary request bodies over real local HTTP, omitted-field parity,
explicit Ollama truncation with usage and no tool admission, and embedded idle
resume plus pre-repair policy mismatch. Adversarial stream fixtures cover partial
lines, ignored/multiline work, field fragments/bytes, item/block/call cardinality,
deadline refusal and success/error-status chunk exhaustion before EOF. Native
continuation and split-byte cases remain checked. They establish Ipse's protocol behavior,
not live model/account enforcement. No paid inference, new package or rate service
is required. See [actual verification](testing.md#current-evidence-and-next-checks)
and [operator configuration](../operator/configuration.md).
