# HTTP fixture lifetime correction, 2026-10-19

Historical verification record for the fixture change following `99c55a2`.
Use the current [MCP training chapter](../../developer/mcp.md#own-a-finite-http-exchange)
for transport ownership and fixture guidance. This correction does not complete
P27's domain inference or quality gates.

The [Linux job at `99c55a2`](https://github.com/lexlapax/ipse/actions/runs/39203905000/job/117902478547)
failed the owner-loss idle-resume test. One HTTP cleanup DELETE arrived after the
test had captured its old-connection traffic. The complete run reported 1,094
tests, one failure and 32 exclusions. That negative result remains evidence;
an unchanged rerun would not explain it.

`HTTPTransport.begin_close/2` cancels the active POST's guardian before starting
the separate bounded DELETE task. The fixture's POST-closed message therefore
does not establish completion of that HTTP session's cleanup. No production
transport change or deadline increase is needed for this ordering.

The revised fixture assigns unique synthetic session IDs and records every HTTP
method with its RPC fields. An owned, bounded lifecycle process can hold one
known session's DELETE before logging or acknowledgment. The controlled regression
kills the Session while its POST is held, confirms POST closure and the pending
DELETE, then releases and confirms that DELETE. Exactly one additional cleanup
record appears. A temporary assertion equating this completed log with the earlier
POST-closure snapshot failed deterministically. Removing that incorrect assertion
leaves the explicit ordering proof and the unchanged full-traffic equality after
idle resume. Existing interruption cases now await their exact old session's
DELETE before taking the snapshot.

Local macOS arm64, Elixir 1.20.3 and OTP 29 results:

| Check | Result |
| --- | --- |
| Controlled old snapshot assumption | Expected failure, exactly one late DELETE |
| Complete MCP extension Session suite | 20 passed |
| Source independent MCP proof | All 12 groups passed; zero model calls |
| Extracted-runtime independent MCP proof | All 12 groups passed; zero model calls |

The extracted proof used the unchanged local archive SHA-256
`96ca1aaebab676d87cff09f31f138aa37d942960582335b26d222c30e8c5817f`.
It confirmed unchanged archive and host files with development tools absent from
the runtime path. These focused checks do not establish a new published release
or corrected-source hosted Linux/macOS acceptance. The fixture retains complete
traffic comparisons, bounded waits and confirmed fixture-process shutdown.
