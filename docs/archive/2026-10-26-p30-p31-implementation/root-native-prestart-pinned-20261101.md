# Native HTTP pre-start faults and pinned stdio helper

Dated **2026-11-01**, author-run synthetic Linux verification on
`codex/p30-p31`, based on `3dce9c8`. This historical engineering record extends
the [MCP start/send controls](root-native-mcp-start-20261101.md), not milestone
acceptance. The [plan](../../plan.md) owns status; the
[MCP developer guide](../../developer/mcp.md#trace-one-approved-call) and
[testing chapter](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
teach the current fixture.

## Preserved original requirements

The original two HTTP pre-start tests and stdio helper-identity positive retain
their names, SDK artifact, original policy/root observation, registered provider
sequence, service config and exact effect arguments. Their old raw subscriber
approval expectation is replaced by the existing native terminal caller.
The observer requires the full actual proposal, `review_input`, nonempty
version-3 dependencies, an absent target and refusal of a fake approval reference
before the PTY can supply its fresh native answer. No literal upgrade or successful
approval witness is manufactured.

Both HTTP faults snapshot the complete accepted-connection log during that native
input wait, before changing permission. Revocation uses the original protected
epoch. Expiry waits past the original signed wall-clock deadline under the
unchanged six-second fixture policy. After the real answer, traffic must remain
byte-identical: no admitted tool effect, target or tool call may appear. The result
is observed but withdrawn, with exactly two completed provider requests.

The helper-identity positive creates the original executable substitute and sets
`IPSE_RUNNER_PATH` only after native display and before the answer. Its allowed
call must use the host-pinned helper: one physical service call, exact target,
separate `mcp.start`/`mcp.send`, same-effect-ID confirmed cleanup, current result
release and three completed provider requests. The substitute's
`--admitted-stdio` marker must remain absent. The child's prior environment
selection is restored in `after`, including failure paths.

All three preserve strict Saved equality, nonempty version-3 dependencies,
confirmed original close, idle resume with the exact saved messages and prior
journal prefix plus one validated ownership marker, and final signed release
claim. Actual model/tool counts and targets remain unchanged. HTTP's complete
traffic snapshot after settled original close must also remain identical after
resumed close, without filtering initialization or cleanup requests. The pinned
substitute marker stays absent after recovery. Resume repeats no work.

## Terminal verification

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_prestart --only native_root_mcp_boundary --max-cases 1 --seed 791689
```

Result: **7 passed**, 160 excluded, 220.0 seconds, exit 0. This includes the
three migrated tests and the existing four stdio/HTTP allowed/post-start-revocation
controls. The log is `/tmp/ipse-native-root-prestart-pinned-20261101.log`, with
retained private synthetic roots. The fixed child seed remains 791678; parent
and child totals are not added together. The
[selected-input receipt](root-native-prestart-pinned-20261101.json) hashes final
test inputs and the terminal log after execution, not as a prelaunch freeze or
complete loaded-runtime inventory.

## Documentation and limits

Whole testing, recovery and both MCP manuals were reviewed. Developer guidance
integrates pre-start traffic observation and the positive helper-identity check
into its native worked example; operator behavior is unchanged. Formatting and
documentation results and their log hashes are in the selected-input receipt.
No runtime/helper/dependency/limit changed; no runtime/package rebuild or complete
suite was rerun for this test/documentation increment.

These are automated Linux `7.2.11-arch1-1` tmpfs/PTY/loopback controls, without
human, live-model quality, installed, non-Linux, TLS or remote-service evidence.
Lost initialization response, held HTTP/stdio owner loss, full C0/capacity/lifecycle,
P30/P31 acceptance and the final audit remain open. The
[complete frozen baseline](full-suite-20261101.md) remains 3,653 passed and
54 failed at `f44b63c`; focused passes do not establish a new complete aggregate.
