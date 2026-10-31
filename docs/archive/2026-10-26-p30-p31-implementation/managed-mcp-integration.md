# Managed MCP actual-use boundaries — 2026-10-28

This is focused in-progress evidence for P31C0, not milestone acceptance. The
[plan](../../plan.md) owns remaining work. A managed-derived ordinary MCP call
must revalidate its current source union and permission at the actual transport
effect, after ordinary approval. The stdio path admits the configured server's
start and then separately admits the exact effect request. The HTTP path admits
the initial connection/request and separately admits the exact effect RPC.
Each stage holds the source/permission leases through its acknowledgement and
records cleanup before the next stage. Catalog setup after an admitted start may
have happened before a later revocation; a refused effect RPC does not erase it.

For stdio, a native ready/grant/start acknowledgement gates process creation.
Deadline-bound pipe frames report complete, absent or uncertain writes. For
HTTP, a one-use, same-owner continuation opens a verified Mint socket and sends
the actual body within the admitted deadline; incomplete cleanup is unknown.
These controls do not certify a kernel-atomic wall-clock boundary across DNS,
connection establishment, scheduling between a clock check and a pipe write or
exec syscall, or an external clock change. macOS admitted stdio fails closed
pending its own implementation and qualification.

An independent source review found two defects after the initial controls: the
managed stdio transport allowed an unpinned helper override, and a lost startup
acknowledgement could be downgraded to a definite error. The current source uses
the build-pinned helper and a private atomic possible-effect marker set before
the startup attempt. A failed setup after that marker returns unknown even if
cleanup succeeds. A [focused repair run](managed-mcp-integration/ipse-managed-mcp-repair-46922.log)
passed both a substituted-helper Session control and an actual HTTP initialization
disconnect after receipt. The [repair compile](managed-mcp-integration/ipse-managed-mcp-repair-compile-46921.log)
had no diagnostics. The affected [HTTP current and post-start controls](managed-mcp-integration/ipse-managed-mcp-repair-affected-46923.log)
also passed on the repaired transport. The earlier Session controls used the preceding cohort and
did not establish these two properties; they are not retroactively recast as a
fixed-source qualification. The repair run's separate
[runtime inventory](managed-mcp-integration/repair-runtime-sha256.txt) pins its
host BEAMs and helper; the later HTTP cleanup repair uses a newer transport.

## Focused checks

The actual Session controls use synthetic provider replies, ordinary approvals,
protected source/consent state, local MCP fixtures, native helper and isolated
tmpfs homes. The combined helper SHA-256 was
`ba559266929f43175b782e6115791d92844a59651d1de18b72fdbe899a0cfb7a`;
the [runtime inventory](managed-mcp-integration/host-runtime-sha256.txt) lists
the private host BEAMs. The four transport modules compiled against that cohort
with [no diagnostics](managed-mcp-integration/ipse-managed-mcp-full-compile-46915.log).

| Control | Result and scope |
| --- | --- |
| [Native stdio](managed-mcp-integration/ipse-managed-mcp-stdio-46913.log) | Two passed: real helper start grant, elapsed start refusal, elapsed pipe refusal and a complete live write. The preceding [46912 failure](managed-mcp-integration/ipse-managed-mcp-stdio-46912.log) used a mismatched application helper in the private test graph. |
| [Stdio current call](managed-mcp-integration/ipse-managed-mcp-session-46916.log) | One passed: approved actual Session call, two admitted stages with confirmed cleanup, and Saved reconstruction. |
| [Stdio approval boundaries](managed-mcp-integration/ipse-managed-mcp-approval-46917.log) | Four passed: source-root change, revocation, real expiry and owner loss before approval produced no workspace effect. |
| [Stdio post-start revocation](managed-mcp-integration/ipse-managed-mcp-post-start-46918.log) | One passed: the server had started and was held during catalog discovery; revocation preceded release and no effect RPC or workspace write occurred. |
| [HTTP current and post-start](managed-mcp-integration/ipse-managed-mcp-http-session-46919.log) | Two passed: current approved call with both admitted stages and Saved reconstruction; revocation during catalog discovery prevented the later effect RPC. |
| [HTTP pre-start refusal](managed-mcp-integration/ipse-managed-mcp-http-refusal-46920.log) | Two passed: revocation or real expiry before approval produced no additional server connection or effect. Initial unbound discovery had already occurred. |
| [Exact request predicate](managed-mcp-integration/ipse-managed-mcp-predicate-46900.log) | Four component controls passed; matching is not authority by itself. |
| [Owned TCP](managed-mcp-integration/ipse-managed-mcp-mint-46907.log) and [TLS](managed-mcp-integration/ipse-managed-mcp-mint-tls-46909.log) | Four TCP and one targeted TLS component controls passed, including no connection on refusal, exact body, one-use ownership, socket closure and untrusted certificate rejection. Fixture callbacks are not Session authority. |

The [source snapshot inventory](managed-mcp-integration/source-snapshot-sha256.txt)
identifies the current transport, helper and test snapshots under the private
`_build/managed-mcp-full-20261028/sources` tree. The Session fixture evolved as
the cases were added; its final snapshot is not asserted byte-identical to each
earlier test run. The runtime BEAM inventory binds the tested host cohort. A final
fixed-source suite and independently frozen manifest remain required.

The review also identified HTTP close/controlled-peer ordering. The subsequent
repair retains unconfirmed cleanup when an in-flight managed wrapper is interrupted
or explicitly reports unconfirmed cleanup; a successful later DELETE cannot
upgrade it. Focused controls held a real socket in a controlled peer and exercised
[explicit close](managed-mcp-integration/ipse-http-cleanup-46924.log) and
[transport-owner loss](managed-mcp-integration/ipse-http-cleanup-ownerloss-46927.log):
each reported unconfirmed before subsequently observing peer and socket closure.
An [explicit-failure control](managed-mcp-integration/ipse-http-cleanup-result-46925.log)
and [five affected HTTP Session cases](managed-mcp-integration/ipse-http-cleanup-session-46926.log)
also passed. The socket controls inject the in-flight task into transport state;
they are not an actual Session owner-loss qualification. Independent review of
this repair found an additional ambiguous Mint return path that could lose socket
cleanup uncertainty. The current source conservatively preserves every unknown
Mint result and records an opened connection before socket observation. An
[injected observation failure](managed-mcp-integration/ipse-http-unknown-46929.log)
used a real loopback connection and verified the saved connection was closed;
its second fixture initially failed because the test application was not started.
The [corrected transport control](managed-mcp-integration/ipse-http-unknown-transport-46930.log)
used actual HTTPTransport and Resources with deliberately mocked authority, and
kept cleanup unconfirmed after a refused connection. These are component fault
controls, not Session authority evidence. The affected [actual Session disconnect](managed-mcp-integration/ipse-http-unknown-session-46932.log)
passed with an unknown journal outcome, owner termination, Saved reconstruction
and no further provider dispatch. Its [preceding fixture attempt](managed-mcp-integration/ipse-http-unknown-session-46931.log)
assumed the owner would remain alive after unconfirmed cleanup; that assumption
was corrected without weakening the production check. The later
[runtime inventory](managed-mcp-integration/unknown-runtime-sha256.txt) and
[source snapshot inventory](managed-mcp-integration/unknown-source-sha256.txt)
identify the current focused cohort under `_build/http-unknown-sol-20261028`;
the first failed fixture used earlier test bytes. An additional [actual Session
owner-loss control](managed-mcp-integration/ipse-managed-mcp-http-ownerloss-46933.log)
killed the owner after the server performed the synthetic write but before its
response; the socket closed, Saved restored, and an idle resume did not repeat the
effect. Its newly added test/fixture bytes postdate the prior snapshot inventory.
The separate [owner-loss snapshot](managed-mcp-integration/ownerloss-source-sha256.txt)
pins those bytes and uses the same later runtime inventory above.
The [stdio owner-loss control](managed-mcp-integration/ipse-managed-mcp-stdio-ownerloss-46934.log)
also passed: after a synthetic server write and before its response, killing the
Session stopped both transport and native server, and idle resume did not repeat
the effect. Its [fixture snapshot](managed-mcp-integration/stdio-ownerloss-source-sha256.txt)
uses the same later runtime cohort.

After the source-lock, Session-lock and managed-shell helper pinning and generic
missing-effect-cleanup changes, the four directly affected MCP Session controls
were [rerun together](managed-mcp-integration/ipse-managed-mcp-current-46936.log)
and passed: both post-effect owner losses, the substituted helper, and lost HTTP
startup response. The affected MCP modules [compiled without diagnostics](managed-mcp-integration/ipse-managed-mcp-current-compile-46935.log).
Their [runtime](managed-mcp-integration/current-runtime-sha256.txt) and
[MCP source/fixture](managed-mcp-integration/current-source-sha256.txt) inventories
bind the new private cohort. This does not replace remaining whole-source tests
or qualify loss during every individual native acknowledgement.

After the legacy namespace read/write guard was added, the affected current
stdio and HTTP Session calls [passed again](managed-mcp-integration/ipse-managed-mcp-namespace-46938.log)
on a [strictly compiled](managed-mcp-integration/ipse-managed-mcp-namespace-compile-46937.log)
cohort. Its [runtime inventory](managed-mcp-integration/namespace-runtime-sha256.txt)
and [MCP source/fixture inventory](managed-mcp-integration/namespace-source-sha256.txt)
are separate from the preceding runs.

Nested
extension `host.tool.call`, collection-store held-lock admission, delegation,
full HTTP/stdio owner-loss and unknown-outcome cases, installed packaging,
current whole-source regression and an independent adversarial audit remain open.
No live account, remote service, paid inference or release is claimed.
