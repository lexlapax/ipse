# Runtime diagnostics and tracing proposal

Research/design as of 2026-10-16; no new diagnostic CLI flags, trace exporter,
extension event bus or debugger endpoint are implemented by this document.
P19 now supplies local diagnostics, saved inspection, explicit handoff export
and request durations; see [recovery](../operator/recovery.md). P22 can extend
those same contracts rather than introduce a second
incompatible instrumentation layer.

## Existing facilities and gaps

Session has a private durable JSONL journal, client status/progress events,
allowlisted runtime/configuration/context information, compaction-failure reasons
and OTP supervision. `format_status/2` limits Session's formatted state to ID and
phase. MCP processes also implement formatted status. Dependency Telemetry is
locked at 1.4.2 through Finch/Plug, but Ipse currently emits no application
`:telemetry` events. There is no general extension/hook loader or supported
operator external trace-export interface. P19 adds content-free context accounting
and local request measurements, not general lifecycle hooks or remote export.

The current journal is recovery evidence, not a shareable sanitized trace. It
can contain private prompts, tool arguments/results and provider continuation.
Do not export it wholesale or use a blanket `inspect(state/config)` logger.
Even `Session.info/1` includes final response/question data and paths: build a
separate allowlist for operational diagnostics instead of forwarding it verbatim.

## Three layers

| Layer | Proposed use | Boundary |
| --- | --- | --- |
| Local diagnostic snapshot | Phase, active job category, budgets, context byte categories and last bounded failure | No inference, effects, tokens, transcript or environment dump |
| Structured lifecycle events | Correlated durations/outcomes across session, model, approval, tool, child, compaction and extension workers | Sanitized metadata, bounded local queue/file, no automatic external export |
| Developer BEAM tracing | Targeted process/function diagnosis on synthetic reproductions | Explicit local developer mode, narrow targets/time limits and cleanup; raw arguments/messages may be private |

Instrumentation must identify waiting for approval/question separately from
provider/tool latency. Record request kind (agent/compaction), selected profile,
provider/requested and reported model separately, step/child budget, elapsed time,
error category and original/effective/context-contribution byte counts. P19's
implemented categories are instructions, user/assistant text, recent/older tool
results, calls, native continuation, checkpoints, provenance and JSON envelope.
P22 adds attribution within instruction/context contributions, including optional
memory and extensions, rather than claiming those categories already exist.
Count bytes without displaying the text or hidden reasoning. Derive metrics labels
from bounded categories; keep unique session/call IDs for trace correlation rather
than unbounded metric-cardinality labels. Record parent/child links explicitly
across tasks/processes instead of relying on inherited process dictionaries.

## Reuse Telemetry, keep transformations separate

[Telemetry's contract](https://telemetry.hexdocs.pm/telemetry.html) runs handlers
in the dispatching process, does not guarantee handler order and detaches failing
handlers. Use a small internal adapter with fast trusted instrumentation handlers;
handoff slow sinks through a bounded owner-managed channel. Merely sending to a
process mailbox does not bound its queue. Define overload/drop accounting and
shutdown behavior. Never use Telemetry handler results to rewrite prompts, approve
tools or run memory I/O. P22's ordered transform dispatcher is a different contract.

If Ipse calls Telemetry directly, promote locked 1.4.2 to a declared direct
dependency and update its inventory/scope. No promotion/install is performed in
this research step. Existing OTP and Jason suffice for a first private local JSONL
diagnostic sink. Host-created fields use an allowlist; prompts, tool payloads,
authorization/headers, hidden reasoning, raw exceptions and stack locals stay out.
Sanitize failure categories before Logger/trace output, not after collection.

Diagnostics can drop samples with visible counters; recovery/effect events in the
durable journal cannot be silently dropped or replaced by the trace stream.
Keep file quota/rotation, owner-only permissions, bounded per-event bytes and a
known retention policy. Observation disabled must not change action results.

## Optional OpenTelemetry

[OpenTelemetry Erlang/Elixir](https://opentelemetry.io/docs/languages/erlang/)
provides API/SDK/OTLP-exporter packages; its documentation currently marks traces
stable and metrics/logs in development. Evaluate its packages behind an Ipse sink
adapter when external tracing is requested; do not implement OTLP from scratch.
Package versions/licenses/configuration must be inventoried before adoption.
No collector, cloud account or network endpoint should be mandatory.

For comparison, Codex exposes configurable OTLP trace exporters and a separate
raw-prompt logging opt-in in its
[official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).
For Ipse, remote export is a separately authorized data transfer with explicit
endpoint/credential references, verified TLS and no fallback. Project text or a
loaded skill cannot enable it. Keep initial traces content-free even when export
is enabled. Raw transcript capture is outside this proposed telemetry API.

## BEAM debugging without accidental state export

OTP 27+ [trace sessions](https://www.erlang.org/doc/apps/kernel/trace.html) allow
independent trace configurations and cleanup via session destruction; this fits
Ipse's OTP floor. Evaluate a bounded local developer helper using those facilities
or `dbg`, scoped to selected workers/functions and a fixed duration/event budget.
Test cancellation, trace-owner death and explicit disable. No distributed node,
remote shell, debugger HTTP listener or credential-bearing trace is enabled by
default. Check that required OTP applications/debug info are actually available
in each development/release profile before documenting commands as supported.

[`sys.get_state`](https://www.erlang.org/doc/apps/stdlib/sys.html#get_state/2)
returns callback state; formatted status redaction does not make raw state or
message tracing safe. The modern
[`GenServer.format_status/1`](https://elixir.hexdocs.pm/GenServer.html#c:format_status/1)
supports status/error redaction. Review Session's older callback and transport
error paths with synthetic secrets, while keeping the supported OTP/Elixir matrix.
This is an implementation review item, not a claim that current logs leaked data.

Prefer synthetic reproductions for raw BEAM inspection. Avoid printing real
provider payloads, tracing all processes or suspending a live owning session
during effects. Optional visual tools must not introduce unapproved host/UI
dependencies into packaged operation.

## Acceptance

P22's local event schema should version a fixed stage/outcome vocabulary and
bounded correlation IDs, elapsed monotonic duration, request kind, phase and
byte/count measurements. Record approval/question wait separately from active
provider/tool/extension work. Do not log model text, tool payloads, filesystem
contents, arbitrary extension labels or raw exceptions. Extension observers see
only the allowlisted event view; context/tool capabilities receive separate,
explicitly private callback values that must not enter the diagnostic sink.

Start with proposed configurable caps: 256 queued events, 16 KiB encoded event,
10 MiB local trace rotation and two retained files, owner-only permissions and
visible drop/disabled-handler counters. Validate these defaults against stress
fixtures before freezing the contract. The channel must enforce capacity before
enqueue, include bounded shutdown/drain behavior, and never block journal sync
or effect cleanup. No tracing consumer is required for ordinary operation.
Sanitized local debugging should expose current worker category, correlation and
elapsed wait, without exposing Session state or suspending the owner. Raw BEAM
tracing is a separate opt-in synthetic-development procedure with time/event caps
and automatic trace-session destruction on cancellation or owner death. Verify
required runtime apps and release debug information before offering that mode.

Prove known lifecycle ordering and correlation, separate approval wait time,
exact context-category accounting, synthetic-secret exclusion, valid bounded
JSON, timeout/cancel/owner-death cleanup, observer-overload behavior and no
instrumentation-driven replay. Verify disabled parity and fixture source/package
paths without accounts or collectors. External export and developer raw traces
need separate evidence. See [P19](../plan.md#p19-long-session-diagnosis-and-recovery)
and [P22](../plan.md#p22-extension-scaffold-and-lifecycle-hooks).
