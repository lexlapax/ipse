# Native root approval across MCP startup and send

Dated **2026-11-01**, author-run synthetic Linux verification on branch
`codex/p30-p31`, based on `331a5ab`. This historical engineering record extends
the [native root positives](root-native-approval-20261101.md) and
[waiting faults](root-native-faults-20261101.md); it is not milestone acceptance.
The [plan](../../plan.md) owns remaining scope;
[MCP development](../../developer/mcp.md#trace-one-approved-call) and
[testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
teach the current implementation and fixture.

## Preserved original tests and boundary

The original stdio post-start revocation, HTTP allowed call and HTTP post-start
revocation tests keep their names, SDK artifact, policy, version-3 root read,
provider sequence, selected service configuration and exact effect arguments.
They now use the existing actual native PTY approval caller instead of expecting
a raw subscriber approval message and calling `Session.approve/3`.
The original native stdio allowed call is their fourth paired control. Root
metadata is not replaced by a signed literal or by manufactured approval data.

Each observer requires the actual `managed_approval`/`review_input` phase, exact
arguments, nonempty version-3 dependencies, an absent target and refusal of a
fake approval reference. For either post-start fault it creates the existing
service gate during that input wait, after ordinary initial discovery. Only
then can the PTY supply the fresh native answer. The next actual catalog request
stops at the service's existing gate. Before revoking, the observer requires
exactly one journaled `mcp.start` admission, no target and no tool-call log.
It revokes the same protected policy and releases that catalog request.

Both faults require exactly one admitted start with same-effect-ID confirmed
cleanup, no `mcp.send`, no target, no `tools/call`, withdrawn result release and
exactly two completed registered-provider requests. Both allowed controls require
separate start/send admissions, exact confirmed cleanup for each, one physical
service call, exact target bytes, current result delivery and three completed
provider requests. All use the real config loader and transport. HTTP is an
explicitly selected insecure-loopback fixture, without any HTTPS-policy change.

Strict Saved restoration must equal live conversation messages and retain all
version-3 dependencies. Each consumer closes, resumes the same Session idle with
its original journal prefix plus only a valid ownership marker, and closes with
a signed release claim. Target and tool/model request counts remain unchanged.
The HTTP follow-up snapshots the complete accepted-connection log only after
confirmed original close, then requires identical bytes after resumed close.
No initialization or cleanup traffic is filtered out. An unchanged `calls.log`
alone would not detect an unexpected reconnection.

## Terminal verification

The first four-case migration ran:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_mcp_boundary --max-cases 1 --seed 791687
```

Result: **4 passed**, 163 excluded, 123.3 seconds, exit 0. The log is
`/tmp/ipse-native-root-mcp-start-first-20261101.log`. This precedes the additional
HTTP connection-log assertion; it already includes strict Saved and idle recovery.
After adding that assertion only the affected HTTP pair was rerun:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_http --max-cases 1 --seed 791688
```

Result: **2 passed**, 165 excluded, 66.2 seconds, exit 0. Its terminal result
and both log hashes are retained in the
[selected-input receipt](root-native-mcp-start-20261101.json). The final HTTP log
is `/tmp/ipse-native-root-http-resume-traffic-20261101.log`. Both runs retain
synthetic roots in their logs and use the unchanged child seed 791678; parent and
child totals are not added together. Final selected source/log hashes are recorded
after execution, not as a prelaunch freeze or complete loaded-runtime inventory.

## Documentation and limits

Whole testing, operator recovery and both MCP manuals were reviewed during this
series. The current developer edits integrate the native root start/send worked
example and exact HTTP recovery observation into their existing flow. Operator
behavior is unchanged. Formatting/documentation results and their log hashes are
in the selected-input receipt. No runtime/helper/dependency/policy limit changed;
no runtime/package rebuild or complete suite was rerun for this test/documentation
increment.

These automated Linux `7.2.11-arch1-1` tmpfs/PTY/loopback checks establish no
human, live-model quality, installed, non-Linux, TLS or remote-service result.
Broader HTTP pre-start, lost initialization/response and owner-loss controls,
stdio held-owner loss and helper-identity migration remain open, as do complete
C0/capacity/lifecycle, full P30/P31 and the final audit. The
[complete frozen baseline](full-suite-20261101.md) remains 3,653 passed and
54 failed at `f44b63c`; focused results do not establish a new aggregate.
