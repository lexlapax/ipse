# Preserve uncertainty in extension MCP discovery

Focused follow-up, 2026-10-29. The [earlier bulk-discovery repair](index.md)
preserves unknown at `MCP.discover/3`; the separate SDK adapter
`Ipse.Extension.MCPCall.discover/5` still collapsed a bounded unknown result into
`invalid_extension_mcp_call`. The [plan](../../plan.md) owns acceptance.

The adapter now returns its existing sanitized `{:unknown, %{}}` result when
discovery or its bounded task returns unknown. Validation refusals retain their
typed error; successful discovery retains the exact descriptor/public binding.
No detailed transport message is forwarded to the worker. Host's existing
context setup already stops before action admission when discovery fails; its
outer invocation becomes unknown. This patch neither adds a retry nor changes
the existing discovery-intent or managed lineage rules. It does not claim that
the old tag alone caused replay or a tool effect.

## Counterexample and repair

One tagged integration case uses the actual local HTTP transport and a small
registration observer. It first verifies malformed request refusal with zero
requests, then holds a real initialization, kills the transport and awaits the
bounded adapter. Before repair it returns the generic validation error instead
of unknown. After repair it returns the sanitized unknown, the peer closes,
and no tool call is sent. A separate healthy fixture in the same case confirms
ordinary discovery/public binding and zero tool execution without leaking either
synthetic bearer or session token.

| Run | Actual result |
| --- | --- |
| 47093 | Original counterexample fails at the returned-tag assertion: expected unknown, received `{:error, :invalid_extension_mcp_call}`. |
| 47094 | Isolated compile of the frozen external-calls source succeeds with empty diagnostics. This source defines both MCPCall and ToolAction. |
| 47095 | The focused case passes; fifteen unrelated tests excluded. |

All handles are terminal. The case awaits a bounded adapter, so it does not
isolate whether the unknown reaches it first through transport cleanup or its
timeout; both must preserve uncertainty. It is a direct adapter/HTTP control,
not a genuine Session or managed-source authority test. The prior independent
Session/HTTPS receipts retain their separate scope and are not rerun here.

The [manifest](extension/manifest.sha256), SHA-256
`ffae8498fde218c740501a27c9175730814d25c59faaa18ee9872a622d34d326`,
pins two source files, three chronological logs, full copied runtime inventory
and unchanged helper hash. The private graph
`_build/extension-discovery-unknown-sol-20261029` copies the earlier frozen bulk
graph and recompiles the current external-calls file. Later native owner/tty
changes are excluded. The authored runtime change is the unknown branch;
recompiling the shared source also emits ToolAction, without a new ToolAction
behavior claim. Generated BEAMs remain under `_build`.

Loopback listening requires the permitted execution context; TLS and assertions
were not weakened. No native code, Host/Session source, worker schema, approval,
gate, provider or billing route changed. No model or external service was called.
Whole-source compatibility and the final adversarial audit remain required.
