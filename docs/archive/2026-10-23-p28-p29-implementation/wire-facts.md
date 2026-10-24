# P29 official wire facts

Read 2026-10-23 before adapter implementation. These are documentation facts and
implementation decisions, not live account verification. The
[brief](../2026-10-23-p28-p29-design/p29.md#wp0-record-current-wire-facts-before-coding)
defines the questions. Examples below are small schematic reductions of the
official examples, with fixture identifiers and no credentials.

## OpenRouter

The [routing guide](https://openrouter.ai/docs/guides/routing/provider-selection)
defines `order`, `only`, `allow_fallbacks`, `require_parameters` and
`data_collection`. Pin one upstream in both lists, disable fallbacks, require
parameter support, and default collection to `deny`:

```json
{"provider":{"order":["openai"],"only":["openai"],"allow_fallbacks":false,"require_parameters":true,"data_collection":"deny"}}
```

Base provider slugs can match several endpoints; region/variant/tier selectors use
slash suffixes. The accepted initial profile grammar selects a base upstream,
not a specific regional endpoint. Do not claim region pinning. No adapter may
silently broaden the operator's selection.

The [streaming guide](https://openrouter.ai/docs/api_reference/streaming) shows
top-level `model` and `provider`, including on a mid-stream error. Such an error
has top-level `error` and `choices[0].finish_reason: "error"`; HTTP 200 alone
does not establish success. Comments are ignorable. Usage arrives before the
terminal marker; handle both empty choices and a content-free choice repeating
the finish reason. Schematic frame:

```json
{"model":"openai/gpt-4o","provider":"openai","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}
```

Implementation policy: require model/upstream identity before exposing content,
reject a reported mismatch throughout the stream, and require a terminal
`[DONE]` plus a successful finish reason. Preserve any observed usage on refusal.
Unknown alias equivalence is insufficient evidence to weaken a pin. During the
authorized 2026-10-24 live check, the public
[providers catalog](https://openrouter.ai/api/v1/providers) explicitly returned
`{"name":"OpenAI","slug":"openai"}`; the
[model endpoints](https://openrouter.ai/api/v1/models/openai/gpt-4.1-mini/endpoints)
returned `provider_name: "OpenAI"` with `tag: "openai"`. The initial strict-slug
implementation refused that route before displaying text. The adapter now accepts
this one verified pair, retaining the raw reported name. It does not case-fold or
guess aliases for any other name. The same pin subsequently passed live text and
tool continuation with collection denied. The request's upstream lists did not
change.

The [generation metadata endpoint](https://openrouter.ai/docs/api/api-reference/generations/get-request-&-usage-metadata-for-a-generation)
is `GET /api/v1/generation?id=...`; it reports `provider_name` alongside model,
tokens and cost. Do not add an automatic metadata request: the stream already
has an upstream field, and the extra call would need its own explicit lifetime
and egress policy.

The [reasoning guide](https://openrouter.ai/docs/guides/best-practices/reasoning-tokens)
documents `reasoning.effort`, including `none`, `low`, `medium`, `high`, `xhigh`
and `max`. Streamed `delta.reasoning_details` carries `reasoning.text`,
`reasoning.summary` and `reasoning.encrypted` records. Retain details unchanged
and in order for subsequent tool turns; never render them as visible text.
Plain reasoning text also stays private continuation data. Example native field:

```json
{"reasoning_details":[{"type":"reasoning.encrypted","data":"fixture-opaque","id":"fixture","format":"anthropic-claude-v1","index":0}]}
```

The [API overview](https://openrouter.ai/docs/api_reference/overview) documents
native-tokenizer usage: `prompt_tokens`, `completion_tokens`, `total_tokens`,
cached prompt details and reasoning completion details. It also returns `cost`.
Ipse's canonical spend remains the operator rate-card estimate; provider credit
cost is not an authoritative invoice or a substitute for a missing rate card.

## Gemini

The [migration guide](https://ai.google.dev/gemini-api/docs/migrate-to-interactions)
recommends Interactions for new work but explicitly continues support for
`generateContent`. P29 therefore keeps the brief's stateless GenerateContent
route. No server-side conversation IDs or stateful continuation are introduced.

The [API-key guide](https://ai.google.dev/gemini-api/docs/api-key) shows the
`x-goog-api-key` header. Ipse will read only the explicitly documented
`GEMINI_API_KEY` source, send it in that header, and remove both `GEMINI_API_KEY`
and `GOOGLE_API_KEY` from child environments. Google's SDK environment precedence
does not authorize Ipse to select a different key silently. AI Studio manages
project billing; key presence cannot establish a free or paid tier.

The [REST reference](https://ai.google.dev/api/generate-content) documents
`POST /v1beta/models/{model}:streamGenerateContent?alt=sse`,
`parametersJsonSchema`, and `thinkingConfig` with `includeThoughts`,
`thinkingBudget` or `thinkingLevel`. Thinking levels are model-dependent;
the REST enum uses `LOW`, `MEDIUM`, `HIGH`. The implementation maps the
operator's lowercase setting to that enum and omits thoughts from presentation.

Its usage definitions separate prompt, tool-use prompt, candidate and thought
counts. Thus canonical input is `promptTokenCount + toolUsePromptTokenCount`,
output is `candidatesTokenCount + thoughtsTokenCount`, cached input is
`cachedContentTokenCount`, and total is `totalTokenCount`. Missing needed
counts remain partial. Schematic SSE payload:

```json
{"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":1,"thoughtsTokenCount":0,"toolUsePromptTokenCount":0,"totalTokenCount":4}}
```

The [signature guide](https://ai.google.dev/gemini-api/docs/generate-content/thought-signatures)
requires returning original parts and signatures in position. Parallel function
calls may carry a signature only on the first call. A signature can also arrive
on a text part, including an empty final text part; retain the complete raw part
list rather than rebuilding it from visible text. Schematic native part:

```json
{"functionCall":{"name":"read","args":{}},"thoughtSignature":"fixture-opaque"}
```

The guide permits named dummy signatures for imported traces without signatures.
Initial implementation will preserve unsigned imported history and surface the
API's signed-history refusal with fresh-session/handoff recovery. It will not
invent private signatures or silently substitute a placeholder. Gemini-generated
signed history must round-trip unchanged, including parallel call ordering.

## Verification still required

The OpenRouter routing, streaming and reasoning documentation above was rechecked
on 2026-10-24 before adapter work. The streaming guide still gives the upstream
as a lowercase slug in its explicit error example and documents the repeated
terminal reason in the final accounting frame. Exact configured identity remains
the initial policy; no undocumented alias normalization is authorized by this
research. This is documentation verification without a live model request.

Turn these facts into loopback fixtures for fragmented streaming, identity pins,
parallel tool continuation, hidden reasoning, usage and every terminal refusal.
Run source/installed recovery and budget checks. Live text/tool checks remain
separately opt-in and cannot be inferred from documentation or fixtures.
