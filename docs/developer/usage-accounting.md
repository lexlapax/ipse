# Durable request accounting

`Ipse.Usage` and `Ipse.Usage.Normalizer` implement P22's mandatory, content-free
request facts independently of optional tracing and extensions. P23's pure
[configured cost calculator](costs.md) consumes explicit normalized snapshots;
host accounting does not fetch rates, quote prices or enforce a budget yet. See
[operator inspection](../operator/usage-accounting.md) and
[future costs/streams](runtime-capabilities.md#usage-facts-and-costs).

## Identity and admission

Session synchronously journals closed version-1 `request_admitted` before starting
a model or summary task. It carries random 128-bit hexadecimal request/attempt/
turn IDs, session ID, kind, selected provider/model/profile, billing mode,
admission time and optional SHA-256 of an explicitly configured endpoint. Raw
URLs and credentials are excluded. There is one attempt per request and no
automatic retry; adding retries requires an explicit contract enhancement.

Children carry the originating model request ID and parent session ID, including
when selecting another profile. Their journals remain separate; the parent
snapshot is not a recursively aggregated report. Operator-question continuation
retains its recorded turn identity on resume. Original assistant/native messages
remain unchanged: the enclosing journal event binds to the request ID. Accepted
summary checkpoints similarly bind to their request. Restore checks these bindings.

## Counter semantics

Adapters send internal usage observations only to the current owned Session job.
These cumulative snapshots are never added as increments. Distinct normalized
observations receive consecutive sequence numbers; identical snapshots are
suppressed. A request retains at most 64 observations. Final success always uses
the actual returned usage, including missing fields, rather than promoting an
earlier partial snapshot to exact final usage.

`request_finished` commits before assistant processing or summary validation.
A rejected summary retains its completed provider request and usage. Cancellation/
failure retains the last recorded observation with `finality: partial`; an abrupt
owner crash leaves an unknown outcome. Failed work may consume resources. Older
sessions without `usage_version: 1` stay explicitly `legacy_unmetered`; no historical
zero-token balance is inferred.

Counts are integers from zero through 10^12. Missing/null stays null; reported
zero stays zero. Invalid types, negatives, overflow or inconsistent totals
invalidate counters instead of producing a plausible bill. The closed normalized
record separates nullable counts, derived fields, quality and fixed issue codes.
Unknown provider fields are discarded. Provider prose, hidden reasoning, signatures,
auth and raw endpoint URLs never enter this API.

Primary references checked on 2026-10-16:

| Provider | Interpretation and source |
| --- | --- |
| OpenAI/ChatGPT | Inclusive input/output/total counts; cached input, cache writes and reasoning are breakdowns, not additional totals. [Responses reference](https://developers.openai.com/api/reference/resources/responses/methods/retrieve) |
| Anthropic | Input total is uncached input + cache reads + cache creation, derived only when all three are known. TTL creation details, thinking and server web-tool counts remain separate. Output includes thinking. [Messages reference](https://platform.claude.com/docs/en/api/http/messages), [prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) |
| Ollama | Prompt/generated evaluation counts, optional cached prompt count and nanosecond total duration. Omitted counts stay unknown. [Chat reference](https://docs.ollama.com/api/chat) |
| Demo | Scripted operation is `not_applicable`, not metered inference. |

Billing attribution is subscription for ChatGPT, API for OpenAI/Anthropic, local
for Ollama, and none for demo. These are routing facts, not prices or entitlements.
When input/output totals are known and total absent, their sum is marked derived.
Reasoning/cached subcounts are never added twice. Provider metering is neither a
visible-text token measurement nor an invoice.

## Recovery and bounds

The reducer rejects unsupported versions, unknown accounting fields, orphaned
outcomes, conflicting IDs/revisions, out-of-order observations, mismatched session/
provider/model/parent scope and invalid assistant/checkpoint bindings. Exact
repeated admissions, latest observations and terminal records are idempotent.
Deleting accounting required by a saved assistant/checkpoint refuses recovery.
These checks are not a signature or tamper-proof audit log.

Resume validates accounting before truncated-tail repair. Idle resume dispatches
no providers and appends no synthetic settlements. The ledger permits 10,000
unique requests per session, then admission stops with fresh-session guidance.
Inspection reports total/unknown counts and only the latest 16 request records
in journal admission order. Full records remain in the private journal. The old
latest-successful `info.usage` map remains compatible; `info.accounting` contains
the canonical facts.

No dependency is added: Jason, the shared bounded plain-JSON adapter, OTP
crypto/clock and existing owned Session tasks are reused. A small pure reducer
implements Ipse-specific durable admission, revisions and no-replay recovery;
a workflow/accounting framework would not replace those ownership semantics.

Fixtures in `usage_normalizer_test.exs`, `usage_test.exs`, `usage_session_test.exs`,
`compaction_session_test.exs`, `parallel_delegation_test.exs` and provider HTTP
tests cover normalization, revisions/deduplication, final versus partial facts,
crash outcomes, pre-repair refusal, rejected summaries, parent attribution and
native integrity without paid accounts. P23 costs/budgets and P24 audio usage
remain separate implementation work.
