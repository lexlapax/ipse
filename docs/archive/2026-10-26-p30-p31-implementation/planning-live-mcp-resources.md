# Native planning with a live MCP read — 2026-10-29

This focused control extends the earlier
[declared-read work](planning-mcp-live-read-followup.md) and
[transition crash controls](planning-transition-design-followup.md#controlled-session-death-at-journal-boundaries)
with an actual held stdio MCP call. The [plan](../../plan.md) remains authoritative.
This is synthetic Session/terminal/resource evidence, not P31I completion,
human acceptance, an installed journey or production native-policy qualification.

One focused test passed with seed47014 in3.1seconds, containing two actual
native-terminal cases:

- **Read completion before entry.** The real CLI submits a lookup to the
  configured synthetic MCP server. While that call is held, native `/plan`
  input is refused by the busy CLI path and creates no transition. After
  releasing the read, its task, SDK client, transport, native helper and server
  stop. Only a fresh native `/plan` then enters planning; a fresh `/plan exit`
  returns to normal. The journal has one tool start, one entry and one exit,
  with the tool result preceding the entry receipt.
- **Owner death before exit.** The native CLI first enters planning, then
  dispatches an operator-declared lookup against the actual discovered server
  and descriptor. Native `/plan exit` while that read is held is refused.
  The fixture kills the real Session. Its task, SDK client and transport stop,
  the Port disappears, and the native helper and server are no longer running.
  Resume retains planning and an unknown interrupted result. There is no exit
  record, second server call, tool start or read intent.

Both cases check terminal restoration. The ordinary Session is configured with
approval `:allow` for this fixture; this does not establish a human tool approval.
The transition inputs pass through the actual operator helper and terminal
implementation and are not forged observations or direct transition selectors.
No model service is called. The server implements a synthetic read and writes
only fixture readiness/call records. This does not prove that an arbitrary server
honestly implements a declared read-only tool.

The observer snapshots live resources and installs monitors before the driver
may release or kill anything. It checks BEAM process termination and Port closure.
Linux `/proc` checks treat absent, zombie and exited OS processes as not running;
they do not claim that every exited process has already been reaped. This is
one call per case, not descendant-tree, descriptor-ceiling, failed-cleanup,
HTTP, stress or cross-platform qualification. Busy-command refusal is checked
through the CLI; this test alone does not establish every Session quiet-state
predicate under other callers or fault paths.

## Findings and retained attempts

The first actual startup attempts exposed an integration gap in the new release
owner marker: a declared-MCP Session can have an owner marker before its first
MCP epoch. Planning replay rejected that prefix. A narrow marker repair then
allowed explicit-session validation, but the real startup path still failed:
`Saved` also validates context with an inferred session ID, and its pre-epoch
prefix inferred an empty ID. The lifecycle owner repaired inference from the
header's source-origin binding. The marker grants no MCP authority and does not
authorize a missing start or epoch. These repairs belong to the separate
release-receipt integration work, not to a test-only gate override.

All five attempt logs are retained:

- [47010](planning-live-mcp-resources/planning-live-mcp-47010.log) fails fresh
  Session startup before a transition or tool dispatch.
- [47011](planning-live-mcp-resources/planning-live-mcp-47011.log) still fails
  startup after the explicit-session marker repair, exposing inferred identity.
- [47012](planning-live-mcp-resources/planning-live-mcp-47012.log) reaches a real
  lookup and busy entry refusal, then fails because the driver released the
  server before the observer captured its transport. A private capture latch
  repairs this fixture race.
- [47013](planning-live-mcp-resources/planning-live-mcp-47013.log) reaches read
  completion and fresh native entry/exit, then times out waiting for an observer
  Task result consumed by the CLI's event loop. The linked observer now writes
  a private bounded result file instead.
- [47014](planning-live-mcp-resources/planning-live-mcp-47014.log) passes the
  complete two-case test. The test asserts both fixture result markers and
  terminal restoration; successful subprocess output is captured by the test.

The passing suite was not rerun after success. Earlier intermediate fixture
sources were not separately frozen and their private workspaces were removed by
test cleanup; the logs remain failure evidence, not complete reproductions.

## Exact retained scope

The [manifest](planning-live-mcp-resources/manifest.json) pins four
[source files](planning-live-mcp-resources/source/test/ipse/mcp/planning_live_resources_test.exs),
five logs and669local runtime files. Its SHA-256 is
`6fae5c660f1492e9d1ce155011110ae9e410f7136938f8ea04194f7f5000048f`.
The ordinary helper is
`25689823e76d2c4af01348797675de0859b3ca44b003f9ba1fd9187e8bcdfb7f`.
The runtime is a **mixed copied graph** under
`_build/planning-live-mcp-review-20261029`: release-integration base, its later
`ReleaseReceipt` overlay and the second `PlanningMCP` repair overlay. It is not
a combined-current-source or fresh-checkout build receipt. The test compiles its
Rust PTY driver with edition2021 and warnings denied; that temporary executable
was removed by test cleanup and is not assigned an independently retained hash.

The focused command was:

```sh
ERL_FLAGS='+S 4' ERL_LIBS=_build/planning-live-mcp-review-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _}=Application.ensure_all_started(:ipse); ExUnit.configure(seed: 47014); Code.require_file("test/ipse/mcp/planning_live_resources_test.exs")'
```

No Session, native helper or production library source was edited by this test
increment. Broader transition crash/resource controls, unknown-cleanup admission,
full-source/platform checks and the release-receipt audit remain separate.
