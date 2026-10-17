# Observability, usage and streaming boundaries

The comparison was originally reviewed on 2026-10-16 against `cdaa003` and informs
the [P22 SDK](extensions.md) and [adoption scenarios](extension-scenarios.md).
Current implementation coverage is summarized below; later sections distinguish
delivery targets from existing contracts. External references were read as primary
documentation/source; no compared framework, source debugger, media service or
exporter was installed. Recommendations are architectural inferences, not
interoperability results.

## Current Ipse behavior

Provider adapters already emit visible `{:text, delta}` events. Session forwards
progress from its current job and CLI writes text as it arrives. The saved
assistant message/native continuation remains separate from the live display.
HTTP/SSE request handling and cancellation exist. P22 now adds an explicit
[private text subscription](text-streams.md) with bounded coalescing and
acknowledgments for embedded clients and selected installed workers. There is no
multimodal session interface or audio device/backend yet.
Explicit [v2 negotiation](stream-events.md) adds live epoch/stream/range identity
without changing v1 consumers or treating a delivery acknowledgment as playback.
Text deltas are chunks, not necessarily individual tokens.

P22 now implements [durable request accounting](usage-accounting.md): request/
attempt/parent identities, normalized cumulative usage snapshots, final/partial/
unknown outcomes, rejected-summary retention and inert resume. Ollama omitted
counters stay unknown. The old latest-successful usage map remains compatible.
P19 context measurements are encoded JSON bytes, not tokens. P23 now has a pure
[configured rate-card estimator](costs.md); its report integration, monetary
budget enforcement and P24 audio usage remain implementation work.

P19's local on-demand diagnostics and request timing are available. Optional
metadata capture, bounded sink workers, stop controls and opt-in synthetic
dispatcher tracing are implemented. Their authoritative
[configuration/debugging contract](observability.md) distinguishes recovery
journals from optional sinks and raw developer inspection.

## Comparison with other harnesses and frameworks

| System and primary source | Observed mechanism | Implication for Ipse |
| --- | --- | --- |
| [Codex configuration](https://learn.chatgpt.com/docs/config-file/config-reference) | Separate OTEL log, trace and metrics exporter settings, raw-prompt opt-in and analytics control; disabling analytics also disables custom metrics exporters. | Give each channel an explicit gate and explain how the gates interact; optional export must not disable recovery/accounting. |
| [OpenCode CLI](https://opencode.ai/docs/cli/) and [troubleshooting](https://opencode.ai/docs/troubleshooting/) | Session/model/project token-cost statistics, local logs with retention and a selectable log level. | Make local inspection and reporting usable without a tracing service; configuration needs operator-facing explanations. |
| [Pi provider layer](https://raw.githubusercontent.com/earendil-works/pi/main/packages/ai/README.md) | Typed incremental events and final messages carrying token usage and calculated cost. | Providers should expose facts; presentation extensions should consume normalized facts and retain final-message integrity. |
| [OpenAI Agents SDK observability](https://developers.openai.com/api/docs/guides/agents/integrations-observability) and [running agents](https://developers.openai.com/api/docs/guides/agents/running-agents) | Normal server-side SDK tracing is enabled by default with SDK/per-run controls. Streaming consumes events from the same agent loop. | Reuse one owned runtime/event identity; choose Ipse's explicit default-off export policy rather than inheriting another SDK's defaults. |
| [LangGraph streaming](https://docs.langchain.com/oss/python/langgraph/streaming), [LangSmith costs](https://docs.langchain.com/langsmith/cost-tracking) and [Studio](https://docs.langchain.com/langsmith/studio) | Distinct stream projections/modes; model-price mappings and direct cost metadata; graph/chat development views. | Separate runtime data channels, make prices replaceable/versioned and let a viewer consume supported events without requiring a workflow engine. |
| [OpenAI voice architectures](https://developers.openai.com/api/docs/guides/voice-agents) and [Realtime sessions](https://developers.openai.com/api/docs/guides/realtime) | Chained speech recognition/agent/synthesis, or speech-to-speech sessions managing interruptions/tools and WebRTC/WebSocket connections. | A voice extension can adapt a text workflow, but realtime connection/turn/ownership capability belongs in the host/provider boundary. |
| [Google ADK live sessions](https://adk.dev/live/sessions/) | Concurrent input/output, explicit queue close and separate ephemeral media versus persisted final transcripts/usage. Its documented input queue is unbounded and needs caller rate control. | Specify bounded flow control and persistence independently; do not put raw audio into ordinary diagnostic/journal events. |

These comparisons describe the reviewed documents, including moving upstream
branches. They do not establish compatibility with a locally installed version.
No external framework is selected as an Ipse runtime dependency.

## Core and extension responsibility

| Capability | Generic core/host responsibility | Extension or client responsibility | Delivery |
| --- | --- | --- | --- |
| Observability on/off | Capture/privacy/egress gate, IDs, bounded dispatch and immediate sink-stop | Local JSONL, OTLP and dashboard sinks, filters/presentation | Controls/local sink in P22; remote adapters later |
| Developer diagnosis | Sanitized snapshots, owned trace lease, cleanup and SDK conformance inputs | Timeline viewer, IDE integration and standalone worker tooling | P22 local procedures; richer viewers later |
| Usage accounting | Provider normalization, request/attempt identity, durable facts and idempotent aggregation | Reports, allocation, dashboards and optional export | Minimal facts in P22; P23 reports |
| Cost estimates | Expose billing mode and authoritative measured units | Versioned configurable rate tables and estimation strategies | P23 |
| Monetary/token limits | Request admission, atomic parallel reservations, cancellation and unknown-charge handling | Policy configuration and displays; extension may request stricter limits | P23 host enhancement |
| Visible text streaming | Ordered content channel, sequence/completion identity, flow control and cancellation | Terminal/web renderers and stream consumers | Existing CLI; P22 bounded subscription proof |
| Stateful stream rewriting | Preserve original messages, enforce required filter/failure policy and buffering limits | Parser/formatter/filter algorithm | Later explicit capability, not the completed-answer hook |
| Chained voice | Managed input/output resources, admitted text turn, profiles, approval/control separation | STT/TTS adapters, microphone/speaker/client UI | P24 |
| Realtime speech-to-speech | Session/transport/media lifetime, barge-in, played-output reconciliation and tool gating | Provider adapter and voice experience | P24 foreseen host enhancement |

An extension cannot reconstruct authoritative accounting, reliably cancel a
transport or enforce a budget merely by watching callbacks. Those are host
invariants. Conversely, provider-specific prices, charts, voice choice and UI
should not add feature-specific cases to Session or CLI.

## Usage facts and costs

P22 must establish a small canonical request/attempt record independently of
optional telemetry: session/turn/parent/child/request IDs, request kind (agent,
compaction or approved extension request), selected profile/provider/billing mode,
requested/reported model, outcome and measured units with provenance/status.
Normalize known token counts; leave unavailable values unknown. Preserve whether
provider fields are deltas, cumulative values, subsets or final measurements.
Reject malformed/negative counts. Cache/reasoning/modality details need explicit
unit semantics so subsets are not added to totals twice. Do not expose raw model
payloads, native reasoning or auth through the usage API.

Journal canonical facts before notifying optional consumers. Record usage even
when a paid summary's checkpoint later fails validation. Failed/cancelled requests
may have consumed resources: unknown is not zero. Use request/attempt identity
and finality/revision fields to avoid double counting late/final events, retries,
parent/child totals and resumed work. Legacy journals without facts report gaps;
do not infer invoice history from text length. Resume never reissues a request to
measure its cost. Presentation and aggregation must work with tracing disabled.

P23 adds a bundled optional report/cost extension over those facts. Price data
is operator-configurable and versioned by provider, billing mode, model, unit,
currency, effective date/source and rate-table digest. Support cached input,
output, audio/duration/tool units only where their semantics/rates are defined.
Persist the price identity used for an estimate, with decimal/fixed-point math;
never silently reprice old reports. Missing rates or units produce an explicitly
incomplete estimate. Optional price refresh has an explicit source and egress
configuration, not a mandatory service or hardcoded current price.

ChatGPT subscription usage must not be presented as per-request API charges.
Local Ollama token counts do not prove electricity/hardware cost is zero.
Distinguish observed tokens/units, estimated API-equivalent cost if requested,
provider-reported charges and actual account invoices. No billing mode/provider
switch follows from a budget or cost estimate. Provider capabilities and account
eligibility remain explicit; this research makes no new live billing claim.

Hard budgets require a P23 host capability: gate every covered request, including
children, compaction and supported nested extension requests; reserve bounded
liability atomically across parallel work, then reconcile recorded units. Define
unknown pricing/charge policy and explicit overrides before dispatch. Some
providers cannot guarantee a monetary ceiling for in-flight work; label such
limits advisory or conservative estimates, not exact invoice caps. Tool services
and executable extensions making out-of-band calls are not automatically covered.
Fully trusted code is not confined by an SDK accounting API.

## Text and media are distinct from diagnostics

The implemented [visible-text contract](text-streams.md) carries
stream/session/generation/request identity, monotonic sequence, text chunks and
one logical terminal outcome.
Sequence IDs reject duplicate/late deliveries; crash/disconnect may leave delivery
incomplete even when a request finished. Do not promise exactly-once delivery.
It is a private content capability, separate from sanitized diagnostic observers;
hidden reasoning/native payloads are excluded. Embedded and independent-worker
source fixtures exercise read-only consumption; the independent installed-package
completion gate remains separate. Preserve the
saved provider message and native continuation. A formatter cannot retract text
already displayed; the initial completed-answer wrapper remains a separate view.

The [lifecycle design](lifecycle-events.md) shares event vocabulary and correlation
while separating delivery contracts: diagnostics may drop with counters;
usage/effect/projection facts are durable; visible content is ordered
with bounded buffering/credit. Coalesce text only while preserving its concatenated
value/order. A slow/disconnected consumer must apply supported backpressure or
receive an explicit termination/error, not silently lose chunks or grow an
unbounded mailbox. If the provider transport cannot safely pause, cancel or
detach under a documented bounded policy. Do not claim current asynchronous
Session notification already proves these flow-control guarantees.

Stateful streaming transforms are a later negotiated capability with incremental
UTF-8/grapheme handling, cross-chunk state, bounded buffering and final flush.
Required redaction cannot fall back to raw text on failure, and display filtering
alone does not redact private journals or provider context. Test every channel
before claiming a privacy feature. Partial tool arguments are never actionable
tool calls or approval requests; execute only validated complete calls.

For P24, use the same generic owned-resource model for input streams and output
sinks, with explicit start/stop/interrupt and bounded lifetimes. Voice pipeline
extensions select STT/TTS separately from the main model, using approved profiles,
endpoints and credential references. Final admitted transcripts become ordinary
user turns; interim hypotheses/revisions do not repeatedly trigger inference or
grant approvals. Record provenance and a deliberate operator decision through
the existing question/approval control path. Audio saying "yes" is not by itself
an approval of arbitrary pending effects.

Realtime speech needs a foreseen host/provider capability beyond today's
single-request `complete/4`: bidirectional transport, activity/turn state,
interruption/cancellation, sequence/timestamps, output playback acknowledgment
and reconciliation of generated versus actually played content. Test disconnects
and retries without replaying tools or unheard audio. Never infer a Realtime
credential/billing entitlement from ChatGPT text subscription authentication.

Define a separate versioned media data plane with bounded frames/opaque host
handles and negotiated codecs/rates; do not serialize high-rate raw audio into
16-KiB diagnostic events, provider-text history or ordinary JSONL journals.
The host validates handle scope/owner/generation. Explicitly specify overflow,
underrun/gaps, endpoint/device consent, raw-media retention and cleanup on owner
death. Canonical transcripts, tool outcomes and usage remain durable; raw media
is ephemeral by default. P22 defines/negotiates the boundary and refuses unsupported
media capabilities. Actual microphone, codec, WebRTC/WebSocket or STT/TTS packages
are evaluated/inventoried in P24, with required dependency approval before adoption.

## Verification and milestone scope

P22 adds default-off/local/export control fixtures, sink-stop, secret exclusion,
request IDs and durable usage normalization/deduplication with unknown counts,
and bounded read-only text subscriptions (split chunks, slow consumer, cancelled
request, terminal outcome and unchanged provider history). Its extension conformance
runner uses synthetic inputs; it is not a journal/effect replay engine. Its bounded
trace CLI runs in source and extracted packages; source breakpoints remain a
separate development procedure with existing debuggers. No audio provider or
remote tracing account is needed for P22 fixtures.

P23 adds cost/report extensions and foreseen budget admission/reservation support,
with parallel child/summary accounting, rate changes, missing/partial usage and
resume cases. P24 adds chained voice first, then explicit realtime capability with
synthetic media/backpressure/interrupt/playback tests before opt-in live account
checks. A rich visual debugger can be an independently selected extension/client;
it does not require adopting a graph engine or become a P22 completion dependency.
Implementation of P22–P25 was subsequently authorized on 2026-10-16. Usage/cost
and media contracts here remain delivery targets until their evidence is recorded.
