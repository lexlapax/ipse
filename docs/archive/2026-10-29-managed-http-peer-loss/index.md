# Managed HTTPS peer-loss controls

Focused P31C0 evidence from 2026-10-29. This is not P31 completion or a whole-source
qualification. The [plan](../../plan.md) owns milestone acceptance; the prior
[managed MCP record](../2026-10-26-p30-p31-implementation/managed-mcp-integration.md)
retains the earlier stdio and HTTP controls, review findings, and repairs.

## Scope and evidence

A synthetic, locally trusted TLS server executes a nested extension MCP call and
holds its response after writing one fixture file. The Session has first performed
an actual managed Collection read; the test verifies both that read's journal
observation and the admitted `mcp.send` before interrupting anything. The test
explicitly enables `approval: :allow`; it does not bypass or qualify the current
guard that refuses to display managed-derived approval arguments under `:ask`.
The HTTPS server uses an ephemeral test CA, normal certificate verification,
and restores the previous process CA store after each fixture. No external
service or model account is involved.

The [final focused run](ipse-http-peerloss-tls-final-1029006.log) passed three
actual Session cases:

- **Session-owner loss after effect:** killing the Session while the effect
  response was held closed the TLS peer socket. Saved reconstruction succeeded,
  and idle resume did not send or execute the fixture effect again.
- **Transport loss after effect:** killing the active HTTP transport likewise
  closed the TLS peer socket; the Session reported an error and terminated, Saved
  reconstructed, and idle resume did not repeat the effect.
- **Discovery response loss:** the server received the admitted nested-discovery
  initialization request and closed before responding. The durable discovery
  remained incomplete, no effect call was sent, Saved reconstructed, and idle
  resume did not reconnect. This exercises nested discovery; it does not establish
  how bulk `MCP.discover/3` classifies an unknown server outcome.

A subsequent [effect-response disconnect](ipse-http-peerloss-tls-effect-drop-1029007.log)
passed on the same runtime after adding a separate fixture branch: the TLS server
performed one synthetic write and closed without returning its result. The Session
stopped, the retained state was unknown, incomplete or unavailable, Saved restored,
and idle resume neither reconnected nor repeated the write. The added
[test/fixture snapshot](effect-drop-source-sha256.txt) is separate from the
three-case snapshot; it does not retroactively alter those earlier test bytes.

An actual Session [untrusted-certificate control](ipse-http-peerloss-tls-untrusted-1029009.log)
replaced the fixture CA with the system trust store before admitted nested
discovery. TLS rejected the synthetic server, no effect or confirmed discovery
was recorded, Saved restored, and idle resume did not invoke the effect. The
preceding [1029008 run](ipse-http-peerloss-tls-untrusted-1029008.log) also passed
before the additional discovery-admission assertion. Its later
[fixture snapshot](untrusted-source-sha256.txt) is separate from both earlier
snapshots. The original process trust store was restored after the test.

The individual earlier [owner-loss](ipse-http-peerloss-tls-session-1029003.log),
[transport-loss](ipse-http-peerloss-tls-transport-1029004.log), and
[discovery-loss](ipse-http-peerloss-tls-discovery-1029005.log) controls passed
before the finalized fixture added explicit managed-read and effect-admission
assertions and was formatted. The retained [first attempt](ipse-http-peerloss-tls-session-1029002.log)
used an ordinary model call with interactive `:ask`; the current managed approval
display guard denied it before any MCP effect. It is not a TLS transport pass.
The final control instead uses the existing explicitly enabled nested path and
does not alter the guard.

## Cohort and remaining work

The private graph `_build/http-peerloss-sol-20261029` copies the frozen
[`document-decision-sol-20261029` runtime](../2026-10-26-p30-p31-implementation/document-decision-restoration/runtime-final.sha256)
and overlays only the copied MCP, stdio/HTTP transport and Mint transport source
files. The frozen base runtime inventory was checked successfully. The four
overlay modules [compiled with no diagnostics](ipse-http-peerloss-compile-1029001.log).
The helper SHA-256 was
`7e1913446865a16cdfb7c96ca0285dc9e117a018c36c7b1940ba249a72ffd067`.
The [host BEAM](host-beam-sha256.txt), [base runtime](base-runtime-sha256.txt),
[helper](helper-sha256.txt), and [source/fixture](source-sha256.txt) inventories
bind the tested cohort and final fixture snapshot. The source inventory covers
the overlay and fixtures, not the full current worktree. The separate earlier
individual test logs predate that final fixture snapshot.

These tests prove observed socket closure and no automatic replay for their
specific post-effect and discovery interruptions. They do not establish a
kernel-atomic wall-clock deadline, guarded release of a managed action result to
an extension worker, operator approval-display ownership, every HTTP/TLS failure
mode, later source changes, installed packaging, or P30/P31 adversarial acceptance.
If a remote effect might have happened, the operator must inspect it before any
new explicit attempt.
