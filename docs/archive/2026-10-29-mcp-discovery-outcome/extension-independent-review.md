# Independent review of extension discovery uncertainty

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the adapter repair](extension-discovery.md), manifest SHA-256
`ffae8498fde218c740501a27c9175730814d25c59faaa18ee9872a622d34d326`,
against the prior [bulk-discovery review](independent-review.md). No implementation
edits, runtime/model/network calls or passing test reruns were made here.

Accepted for preserving discovery uncertainty at the SDK adapter boundary. No
concrete scoped blocker was found. `MCPCall.discover/5` now maps a bounded
`{:unknown, _}` result to its existing sanitized `{:unknown, %{}}`. It neither
forwards transport detail nor retries. Request/tool/resource validation remains
before discovery, and successful descriptor, schema and public-binding checks
retain their existing interpretation. No permission, approval, gate or tool
execution path is added.

The existing bounded task catches exceptions and returns unknown; timeout/task
loss also returns unknown after shutdown. The new `with` failure arm preserves
that classification. Other validation failures retain their typed adapter error.
Private transport messages, bearer and session tokens are not copied into the
unknown value, which is always the fixed empty map. Successful public binding
still passes the existing private-data filter. The internal descriptor remains
host data; the change does not expose it as a worker result.

Host's existing MCP context preparation calls discovery before action admission.
Only an `{:ok, descriptor, binding}` reaches the Session binding step and then
the admitted action. Unknown stops that setup and the ordinary continuation
fails rather than executing the tool or feeding a successful action result to
the worker. The outer invocation's unknown behavior, discovery intent/resource
cleanup and managed lineage rules are unchanged. The old adapter tag is not
shown to cause replay or a tool effect, and this review makes no such claim.

[Verification](extension-review/review-manifest.exs) and
[its result](extension-review/review-manifest.log) validate all seven manifest
entries, both source snapshots against their source inventory, all669 runtime
files and the unchanged helper
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`.
All621 files in the earlier bulk graph's narrower inventory are present. Only
MCPCall and the companion ToolAction BEAM differ within that inherited set;48
additional expanded runtime/resource/source files are separately pinned by the
new inventory. The shared external-calls source emits both modules. The authored
repair is the unknown arm; no new ToolAction behavior or coverage is inferred
from recompiling it.

The verifier initially assumed identical inventory widths and stopped after
hash verification; [that diagnostic](extension-review/review-manifest-initial.log)
is retained. It was corrected to compare the inherited621-file set and verify
all48 additional bindings, without treating the expanded inventory as a product
failure. This was manifest checking, not another runtime control.

The retained47093 counterexample uses actual held loopback HTTP initialization,
kills the registered transport and observes the old adapter's generic validation
error at the exact expected-unknown assertion.47094 reports a successful isolated
compile with empty diagnostics. The same focused47095 case passes with the new
sanitized result. Its malformed request has zero egress; its held initialization
has one initialize and no tools/call; its separate healthy fixture returns the
ordinary binding with no tool execution and excludes both synthetic private
tokens from public output.

Because the adapter is itself bounded, that case does not isolate whether
transport cleanup or the timeout first supplies unknown. Both must preserve it.
It is a direct adapter/HTTP control, not a genuine Session, worker-source
provenance or managed-authority acceptance. Earlier Session and HTTPS controls
retain their own scope. Later owner/terminal graphs, whole-source compatibility
and final adversarial audit remain outside this repair.
