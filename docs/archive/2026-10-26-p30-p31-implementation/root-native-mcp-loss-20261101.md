# Native MCP startup uncertainty and held-owner loss

Dated **2026-11-01**, author-run synthetic Linux verification on
`codex/p30-p31`, based on `a478fec`. This historical engineering record extends
the [pre-start/pinned-helper controls](root-native-prestart-pinned-20261101.md),
not milestone acceptance. The [plan](../../plan.md) owns remaining scope;
[MCP development](../../developer/mcp.md#trace-one-approved-call) and
[testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
teach the current fixture flow.

## Original faults and actual input

The original lost HTTP initialization, held HTTP owner-loss and held stdio
owner-loss tests retain their names, SDK artifact, policy/root observation,
registered provider sequence, service config, flags and exact effect arguments.
They now use the existing native PTY caller rather than a raw subscriber approval
message and `Session.approve/3`. Their obsolete subscriber helper is removed;
the independent no-native-channel refusal remains intact.

The observer requires the actual full native proposal, `review_input`, nonempty
version-3 dependencies, an absent target and rejection of a fake approval
reference before the driver supplies its fresh answer. It records that exact
dependency union as comparison data, never as a native permit.

Lost initialization sets the original drop flag during input wait. The actual
HTTP service must receive initialization and drop its response, then the Session
must terminate automatically. Exactly one `mcp.start` is admitted, with a typed
unknown outcome, no tool call or target and exactly two completed provider requests.
The fixture does not turn uncertain startup into a known pre-dispatch refusal.

Held loss waits for the actual service's original held-response marker, the exact
physical target, one tool call and separately journaled start/send before killing
the actual consuming Session. It observes the registered transport's exit. HTTP
must report closure of its held effect socket; stdio must stop its recorded real
server PID. The physical effect remains exactly once, with no observed result or
result release and no third provider request. Local cleanup does not undo work or
prove that a remote service stopped.

All three require actual original OS-lock release before reading stable history
and resuming the same Session, without deleting/replacing its lock. Strict Saved
restoration must retain reference dependencies exactly equal to the actual native
approval union. Idle resume preserves exact saved messages, its prior journal
prefix plus only one valid ownership marker, the recorded lineage-usability flag,
and unchanged tool/model counts and targets. HTTP additionally keeps its complete
connection log unchanged after settled cleanup and resumed close. The final signed
release claim belongs to the resumed owner; it does not settle the old effect.

## Retained counterexample and correct recovery assertion

Parent seed 791690 passed both HTTP cases but failed stdio: **2 passed, 1 failed**,
164 excluded, 91.1 seconds, exit 2. Its log is
`/tmp/ipse-native-root-mcp-loss-first-20261101.log`. The actual server stopped and
strict Saved reconstruction succeeded. A new assertion then incorrectly demanded
that `ManagedLineage.dependencies/2` remain usable after interrupted send cleanup.

Read-only reconstruction of the retained first stdio root found exactly one
version-3 source dependency, confirmed start cleanup, and no send-cleanup record.
There was no other pending output, discovery or Worker input. The runtime's
`managed_recovery` rule correctly marks that lineage unavailable. The diagnostic
script/log are `/tmp/ipse-native-root-mcp-loss-lineage-diagnostic-20261101.exs`
and `/tmp/ipse-native-root-mcp-loss-lineage-diagnostic-20261101.log`; their hashes
are in the [selected-input receipt](root-native-mcp-loss-20261101.json).

The final test compares the complete retained reference union directly with its
native approval snapshot, then derives the exact required usability result from
committed effect-cleanup records. Missing cleanup must produce
`managed_lineage_unavailable` before and after resume; confirmed cleanup retains
the usable union in these fixtures. It accepts neither arbitrary refusal nor a
discarded source. No cleanup receipt is forged and the original kill is not
delayed to force a later acknowledgment. Production behavior is unchanged.

## Terminal verification and limits

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_loss --max-cases 1 --seed 791691
```

Result: **3 passed**, 164 excluded, 100.6 seconds, exit 0. The log is
`/tmp/ipse-native-root-mcp-loss-retained-20261101.log`, including retained synthetic
roots. The unchanged child seed is 791678; parent and child counts are not added
together. The selected-input receipt hashes final test inputs and terminal logs
after execution, not as a prelaunch freeze or complete loaded-runtime inventory.

Whole testing, recovery and both MCP manuals were reviewed in this series;
developer edits integrate source retention, cleanup uncertainty and idle recovery
into the existing worked example. Operator behavior is unchanged. Formatting and
documentation results/log hashes are in the receipt. No runtime/helper/dependency/
limit changed, so no runtime/package rebuild or complete suite was repeated for
this test/documentation increment.

These automated Linux `7.2.11-arch1-1` tmpfs/PTY/loopback controls establish no
human, live-model quality, installed, non-Linux, TLS or remote-service result.
Combined-module, complete C0/capacity/lifecycle and full P30/P31 qualification,
plus final audit, remain open. The [complete frozen baseline](full-suite-20261101.md)
remains 3,653 passed and 54 failed at `f44b63c`; focused passes do not establish a
new complete aggregate.
