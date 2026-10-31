# Independent managed HTTPS peer-loss evidence review

2026-10-29. Scoped source/evidence review of the [peer-loss record](index.md),
not a P31 or whole-source acceptance. No runtime test or model call was repeated.
The [plan](../../plan.md) owns remaining work.

All entries in the six source, later-fixture, runtime, base and helper inventories
verified. The reviewed final test source and TLS fixture match their separately
frozen snapshots. The original three-case run passed, as did the separate lost
effect-response and untrusted-certificate cases. Earlier individual controls and
the initial interactive approval refusal are preserved without relabelling them
as the final fixture. The source snapshots are now also retained in the additive
[durable archive](source-snapshots.tar); [artifact hashes](artifacts.sha256) leave
the original inventories unchanged.

No concrete additional defect was identified within this scope. The actual nested
Session first records a managed Collection read and the applicable discovery or
send admission. For successful TLS connection cases, the synthetic peer performs
one write before holding or dropping its response. Owner/transport loss observes
the held TLS socket close. Saved reconstruction and idle resume do not repeat the
effect. Discovery-response loss retains an incomplete admission without a confirmed
discovery result; resume does not reconnect. The untrusted fixture certificate is
rejected under normal verification, with no effect. The fixture restores its
previous trust store; it never disables TLS checks.

The explicit `approval: :allow` selection is material. The earlier ordinary
interactive path was correctly denied by the current managed-argument display
gate. These controls do not qualify that display or release a managed result to
the extension worker. The effect-loss assertion accepts the closed alternatives
of an unknown action, a retained pending action or unavailable lineage; it does
not claim a committed successful result or remote rollback. No model quality,
human input, later source changes, all peer fault schedules or installed bundle
is established.

Bulk discovery is separate: nested extension discovery calls `discover_server`
directly. This evidence therefore does not test or repair the returned-tag issue
in bulk `MCP.discover/3`; see its [separate repair/review](../2026-10-29-mcp-discovery-outcome/index.md).
The retained helper/base graph and four overlays identify the tested cohort;
subsequent native Session lease/barrier changes are outside it. Broader coherent
regressions and the requested final adversarial audit remain open.
