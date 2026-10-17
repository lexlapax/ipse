# Provider output ceilings

`Ipse.Provider.Limits` validates an optional `max_output_tokens` before Session
creation and before the normal provider dispatcher opens a request. Configuration
and profile validation use the same contract. This is P23's per-request output
control, not a shared request/token/money budget or a reservation ledger.

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
request output field through the current public interface; future budget policy
must represent that lack explicitly. Request admission quotas can remain useful
without inventing an output-token guarantee. Atomic host reservations and generic
accounted extension model requests remain P23 work.

## Verification scope

Credential-free fixtures check configuration precedence/refusal, profile and child
ceilings, normal/summary request bodies over real local HTTP, omitted-field parity,
explicit Ollama truncation with usage and no tool admission, and embedded idle
resume plus pre-repair policy mismatch. They establish Ipse's protocol behavior,
not live model/account enforcement. No paid inference, new package or rate service
is required. See [actual verification](testing.md#current-evidence-and-next-checks)
and [operator configuration](../operator/configuration.md).
