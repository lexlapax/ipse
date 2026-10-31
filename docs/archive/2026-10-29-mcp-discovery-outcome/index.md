# Preserve uncertain bulk MCP discovery

Focused repair record, 2026-10-29, on `codex/p30-p31` at `7afc3f2` plus the
uncommitted implementation. The [plan](../../plan.md) owns completion. This
record is separate from the [managed HTTPS peer-loss controls](../2026-10-29-managed-http-peer-loss/index.md).
No model, paid account or external service was used.

The later [extension-discovery follow-up](extension-discovery.md) fixes the same
typed-uncertainty loss in the separate SDK adapter. Its source/runtime and
direct HTTP control are distinct from the original bulk/Session cohort below.

## Defect and repair

`MCP.discover_server/3` can return `{:unknown, message}` when local transport
cleanup cannot be confirmed. `MCP.discover/3` stopped its server reduction but
rewrote that tuple to `{:error, message}`. The message still said “unknown,”
while the typed result no longer preserved the uncertainty. An actual held
loopback initialization followed by transport death reproduced that downgrade.
No automatic replay exploit or successful tool dispatch was established.

Bulk discovery now returns the original unknown tuple and stops before the next
configured server. Session's discovery-result dispatch accepts both error and
unknown tags through its existing failure/revalidation handling. This does not
add retries, change request schemas or treat closed local sockets as proof that
a remote operation was cancelled.

## Actual controls and retained failures

| Run | Evidence |
| --- | --- |
| 47063 | The default sandbox refused the loopback listener with `:eperm`, before a protocol assertion. |
| 47064 | The first fixture dropped only the remote DELETE reply and incorrectly expected catalog failure. Discovery succeeded: local pool closure is distinct from a confirmed remote session deletion. This was a rejected test assumption, not the reproduced defect. Its source snapshot is retained. |
| 47065 | The corrected fixture registered the actual HTTP transport with a test observer, held initialization at the real peer and killed that transport. Bulk discovery returned error with an unknown message, contradicting the required unknown tag. |
| 47066 | MCP and Session compiled with warnings as errors and no diagnostics into a copied frozen runtime. |
| 47067 | The same actual transport-loss control passed after repair: unknown returned; one initialization, no DELETE from the dead transport and no request to the next server; a later explicit discovery of the healthy server succeeds once. |
| 47068–47069 | Initial actual draft-Session assertions incorrectly expected an explicit unknown setup-result row and the ordinary worker error message. Resource cleanup instead failed first, retained the pending setup intent and closed the lifecycle conservatively. Those first assertions are retained, not labelled product defects. |
| 47070 | Actual draft Session passed with its real cleanup-warning semantics: socket closure, pending discovery marked interrupted by Saved reconstruction, no catalog, idle resume and exactly one setup intent with no new network request. |

The direct bulk test uses a small registration observer so it can interrupt the
real transport without a production test hook. It is an actual MCP client/HTTP
peer control, not a genuine Session admission test.47070 separately uses the
actual Session/resource/journal path. Its cleanup failure preempts normal worker
result dispatch, so it does **not** isolate the newly widened result-handler arm.
That arm is a matching closed error/unknown dispatch change; broader coherent
regressions and final independent audit remain required.

The initial DELETE test does not justify changing the existing best-effort remote
termination behavior. A local cleanup receipt establishes only the owned local
resource boundary. Unknown remote effects still require inspection before new
explicit work, regardless of whether discovery itself returned a valid catalog.

## Exact cohort and limits

The [manifest](manifest.sha256) pins four source files, all chronological logs,
the rejected first fixture, source hashes and the final runtime inventory.
The graph copies the frozen document-decision runtime and overlays only MCP and
Session; the matching helper is
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`.
Later Session/Writer barrier or native export work is excluded.

Compile47066 and direct test47067 were launched without a completion poll between
them. Both later completed successfully. The exact old MCP necessarily fails
this returned-tag assertion;47070 ran after confirmed compilation. This is not
a claim that every intermediate process loaded one recorded whole-source cohort.
Final runtime/source inventories and the frozen earlier base identify the scope.

Loopback tests required the permitted execution context because the default
sandbox denies socket binding. TLS verification and test assertions were not
weakened. No native code, provider, permission, gate, billing route or managed
result-delivery capability changed. Full source/package checks, standalone
accounts, all HTTP faults and the requested final adversarial audit remain open.
