# Bounding provider requests and response assembly

Provider limits protect two different boundaries. A generation setting asks a
provider to limit output. Host response limits bound how much work Ipse accepts
while parsing a response. Neither is an invoice ceiling. Learn both paths before
adding a provider field or changing a stream reducer.

## Follow an output ceiling to the wire

`lib/ipse/provider/limits.ex` validates `max_output_tokens` and implements
`narrow/2`. Absence adds no field and preserves the previous request. OpenAI API
accepts 16–1,000,000; Anthropic and Ollama accept 1–1,000,000. ChatGPT subscription
and demo refuse an explicit cap. Ipse does not silently drop it or switch billing.

The adapters map the effective ceiling as follows:

| Adapter | Request field |
| --- | --- |
| OpenAI API Responses | `max_output_tokens` |
| Anthropic Messages | `max_tokens`, narrowed against the adapter's existing value |
| Ollama Chat | `options.num_predict`, narrowed against existing summary options |
| ChatGPT subscription | Unsupported; refuse before dispatch |

Configuration and Session both validate the selected cap. Session pins it for
embedded callers and recovery before journal repair. Children inherit a parent's
ceiling; selected profiles may narrow it. Summary requests also narrow existing
summary limits, rather than widening a requested cap.

A small pure exercise shows the rule without model access:

```elixir
Ipse.Provider.Limits.narrow(100, 4096)
# => 100
Ipse.Provider.Limits.validate(%{provider: :chatgpt, max_output_tokens: 100})
# => {:error, ...}
```

Read `test/provider/limits_test.exs` for local HTTP request-body examples. Trace
both the ordinary turn and summary path. Their payloads establish that a setting
reaches dispatch, which a configuration-only test cannot prove.

Truncation is a response failure. Explicit length/incomplete completion signals
retain available usage but admit no tool calls. Already streamed text cannot be
retracted. Do not execute partial arguments, retry automatically, or label an
incomplete message successful because the HTTP transport ended normally.

## Trace bounded response assembly

The HTTP adapter receives at most 8 MiB, or a smaller explicit
`max_response_bytes`, and 131,072 data chunks. Error statuses retain only a bounded
diagnostic prefix. SSE and Ollama JSON-lines parsing share a line accumulator
that scans new bytes, retains fragments, and joins once at a delimiter. Provider
field accumulators likewise materialize completed text/arguments/native fields
once. Repeatedly joining or rescanning the whole retained prefix is avoidable work.

| Resource | Hard ceiling |
| --- | --- |
| Partial line, joined SSE data, accumulated field | 8 MiB |
| Nonempty fragments per partial line or field | 32,768 |
| Data lines per SSE event | 32,768 |
| Parsed lines per response | 131,072 |
| SSE events and decoded provider events | 65,536 each |
| Output items or Anthropic blocks | 256, indexes 0–255 |
| Tool calls | 32, including incremental Ollama batches |

The first applicable ceiling refuses the response. A nonempty Ollama EOF tail
counts as a line; SSE EOF does not invent an event. CR, LF, split CRLF, split
UTF-8, and multiline SSE must retain their protocol meaning.

Production consumers reduce each completed line/event before scanning a later
suffix. Thus earlier usage observations remain available if the suffix exceeds a
limit, and an earlier provider error keeps precedence. Collecting `feed` helpers
do not publish a successful prefix after failure. Use reducer APIs for observable
accounting callbacks.

The deadline is checked during framing, around callbacks, and before successful
materialization. Checks are cooperative: they cannot forcibly interrupt a JSON
decoder or callback. Cleanup may outlast the inference deadline. A late successful
callback still fails admission. Private thinking and native signatures remain in
native history where required and never become visible text.

## Change a bound without weakening admission

Run the focused protocol fixtures:

```sh
mix test test/provider/limits_test.exs test/provider/stream_bounds_test.exs
```

The suites cover wire omission/parity, truncation with usage, cardinality,
fragment/byte limits, error precedence, split-byte cases, and deadline refusal.
When adding a field, test a response fragmented across that field's boundaries,
an overflow after a valid usage event, and native continuation on success. A
larger field limit also needs a review of HTTP, parser, materialization, and journal
bounds; increasing one number alone may just move the failure elsewhere.
