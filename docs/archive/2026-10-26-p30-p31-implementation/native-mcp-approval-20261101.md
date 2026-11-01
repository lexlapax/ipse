# Native MCP approval from an actual stored statement

Dated **2026-11-01**. Author qualification on top of `b9c123e`, extending the
[actual-note shell journey](native-shell-approval-20261101.md). This is historical
synthetic evidence, not full C0 acceptance or an independent audit. Current
procedures belong to [MCP development](../../developer/mcp.md#trace-one-approved-call)
and [operator MCP](../../operator/mcp.md); the [plan](../../plan.md) owns scope.

## Configuration, actual approval and service effect

The existing native statement fixture now has two explicit MCP scenarios:
`save_managed_approval_mcp` and `save_managed_approval_mcp_source_stale`.
They write a private selected configuration, loaded through `Config.runtime`
and `MCP.Config`, for the existing local stdio `write_note` server. The selected
executable, arguments, tool allowlist and environment are ordinary operator data.
Other scenarios retain no MCP configuration. No server, runtime, helper,
dependency, policy limit or deadline changed.

The consumer recalls a genuinely captured signed note under its original
Session source, then uses the existing complete native approval display and
fresh `allow CODE`. The positive requires exact workspace file bytes and exactly
one server `tools/call`, measured by `calls.log`. Its own model-call ID has
separate `mcp.start` and `mcp.send` admissions, each with confirmed same-effect-ID
cleanup. One observed result and one current release precede the service reply
in the next provider **tool-result message**. Original journals, nonempty managed
dependencies, strict Saved reconstruction, exact saved/live messages and two
completed provider requests remain required.

The paired control changes the actual original journal while the native input
waits, after display ownership released. Approval then produces no call-bound
effect admission, target file or `calls.log`, with only the original completed
provider request. Discovery can already have started the explicitly selected
server; these assertions do not claim zero discovery effects. Both consumers
close and resume idle with the exact saved-message projection, unchanged journal
prefix plus one validated ownership marker, signed final release claim and
unchanged target/call log. No MCP call or model request replays.

The shared fixture also strengthens existing write positives to require their
actual effect admission/cleanup/result records, saved/live message equality,
nonempty managed dependencies and idle consumer recovery. Owner-loss keeps its
separate stopped-consumer behavior. These additions do not replace native input
or construct a successful transport witness.

## Executed controls and coverage decision

| Selection | Seed | Terminal result |
| --- | ---: | --- |
| New actual-note MCP positive and source-withdrawal pair | 791676 | 2 passed, 25 excluded; 33.8 s; exit 0 |
| All native approval cases with final shared assertions | 791677 | 15 passed, 12 excluded; 251.3 s; exit 0 |

Logs are `/tmp/ipse-native-managed-mcp-first-20261101.log` and
`/tmp/ipse-native-managed-mcp-approval-regressions-20261101.log`. The
[selected-input receipt](native-mcp-approval-20261101.json) hashes final fixture
inputs and these completed logs after execution. It is not a prelaunch freeze
or complete loaded-runtime inventory.

A proposed migration removed three old subscriber-based write/shell/MCP
positives temporarily. Coverage review found a distinct precondition: those
tests use root-only metadata, while this journey consumes signed note contents.
The removal was reversed before commit. The old test file is byte-identical to
`b9c123e`; none of those positive requirements was deleted, skipped or changed
into a refusal pass. Their native-terminal migration and remaining root/expiry/
revocation/owner-loss boundaries stay open. A sandboxed `git restore` attempt
could not create its index lock; restoring the known own-only draft directly
from `git show HEAD:path` succeeded without changing the index or other files.

## Limits

These automated PTY/stdio/HTTP-model-fixture controls use Linux
`7.2.11-arch1-1` and the qualified tmpfs profile. They establish no HTTP-MCP,
human, real-model quality, installed runtime, non-Linux or confinement result.
No real inference, download, new dependency or external review ran. The complete
MCP operator/developer chapters were reviewed and their native-knowledge approval
flow integrated into existing procedures. The runtime and bundled artifacts
remain unchanged, so no build/package or complete suite was rerun here.
Whole-checkout formatting and the documentation checker exited 0. The latter
checked 1,018 Markdown files and 8,444 local links with zero errors. Logs are
`/tmp/ipse-native-managed-mcp-format-20261101.log` and
`/tmp/ipse-native-managed-mcp-docs-20261101.log`.

The [complete frozen baseline](full-suite-20261101.md) remains 3,653 passed and
54 failed at `f44b63c`; focused passes cannot be subtracted from it. Full consumer,
capacity, lifecycle, installed, quality and final-audit gates remain open.
