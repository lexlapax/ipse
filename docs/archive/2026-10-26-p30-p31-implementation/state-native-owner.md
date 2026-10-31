# State native-owner backend — 2026-10-29

This is an implementation and focused-control record, not acceptance of P30/P31
or authorization to restore timed State. The timed `write_before_ms` execution
and Invocation gates remain in force. The [accepted design and review](state-deadline-restoration-design.md)
describe the final locked decision, including why it does not guarantee the
physical rename completes before the same millisecond.

## Boundary

Ordinary State operations acquire the existing protected native transaction
owner for the namespace `.lock`. A private State mode binds an observed
`state.json` identity or absence to one staged body of at most 1 MiB. The same
lock-owning native process reads, stages, syncs, checks the final clock, renames
and syncs the directory. JSON, CAS, revisions and quotas remain Elixir policy.
Every known outcome requires the framed native release. Native loss, an invalid
response or a lost release acknowledgment is unknown; no mutation is replayed.
The new private timed decision is not reachable through the still-gated public
timed State API. No Collection allocation or kernel-profile option is applied.

Only mutating State begins perform bounded orphan cleanup under the retained
lock: at most 1,024 directory entries and 256 reserved `.state-pending-` files,
with an aggregate 256 MiB ceiling and owner/private/regular/single-link checks.
Cleanup does not classify an interrupted operation as having had no effect;
the record's operation ID remains the inspection mechanism. Read-only State
does not clean stages. Other names and unsafe reserved entries are preserved;
the latter make a mutation refuse. A prior implementation's separate Erlang
file-server writer that is still in flight during an upgrade cannot be fenced
retroactively. Do not mix old in-flight writers with this backend.

The native owner requires the protected helper's trusted path traversal,
private namespace directory and owned, private, single-link regular files.
This is stricter than the prior State implementation's permission-bit checks;
an owner-private legacy file with mode 0400 was read and then replaced in the
focused control. An old pinned helper without the State protocol refuses with
no legacy fallback. Tests ran on the available Linux host and filesystem;
other backends, arbitrary hostile same-user code, blocked kernel syscalls and
rolling migration from a live old file-server writer are not qualified here.

## Controls and provenance

[Evidence and source snapshot](state-native-owner/manifest.sha256) include an
unignored `source.tar`, native binaries, runtime inventories and exact logs.
The final `v6` graph incorporates the independent review's closed V-reply
decoder repair. That repair validates exact length, the safe clock range,
deadline presence and the relationship of the decision to that deadline. Its
focused pure decoder/real elapsed controls pass 2/2; a real hook-instrumented
native mutation that sends an empty completion returns unknown while the
replacement remains inspectable (1/1). The control confirms the actual
controller path rather than only the pure decoder. Test hooks exist only in
the separately compiled hook helper.

The earlier v5 cohort passed five State integration controls, the timed gate,
eight raw native protocol/deadline/death controls, two actual State caller-loss
controls, old-helper refusal and one explicitly pinned two-VM CAS control.
The v4 compatibility selection passed seven existing cases, including quotas,
retained tombstones, lock contention and corrupt input. In the actual loss
controls a contender is refused while the native holder is paused; killing the
caller before decision leaves the old value, while killing it after rename
leaves the new value and no confirmed original response. A pre-decision delay
across expiry gives the actual checked time and unchanged target; a delay
after the decision demonstrates permitted later physical rename. Substituted
target and stage identities, oversize input, second finish and zero deadline
are separately covered. Earlier test-fixture timeout, State error-mapping
failure, and an existing cross-process fixture's readiness timeout are retained;
the last failure was not diagnosed, and the separately pinned two-VM test is
not presented as an explanation for it.

Runtime inventories distinguish v4, v5, v6, hook and old-helper graphs. The
archive source snapshot is the final source, not a claim that it reconstructs
every intermediate graph; the v5 runtime and logs are retained independently.
The initial pre-review tar was replaced during preparation of this record.
The three v5 implementation files were subsequently reconstructed by reversing
the decoder and test-hook changes, and their hashes match the independent
reviewer's previously recorded values. They are preserved in `source-v5/`;
this does not claim the entire original tar was recovered.
The standard and hook binaries were built with:

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o /tmp/ipse-state-native-check7
rustc --edition=2021 -D warnings --cfg ipse_state_test_hook native/ipse-runner.rs -o /tmp/ipse-state-native-hook7
```

The final helper was installed into both the graph's `lib/ipse/priv` and the
copied Runner source's `source/priv`; the copied `source/lib/ipse/runner.ex`
was compiled with `lib/ipse/runner/transaction.ex` into the v6 graph. The hook
graph was compiled the same way with its matching helper. The focused repair
controls were run with:

```sh
ERL_FLAGS='+S 4' ERL_LIBS=_build/state-native-owner-v6-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 22, line: 66]); Code.require_file("test/ipse/extension/state_native_owner_test.exs")'
IPSE_STATE_NATIVE_HOOK_TEST=1 ERL_FLAGS='+S 4' ERL_LIBS=_build/state-native-owner-hook-v2-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); ExUnit.configure(exclude: [:test], include: [line: 86]); Code.require_file("test/ipse/extension/state_owner_loss_test.exs")'
```

Independent review and separate Memory delayed-approval journeys remain
necessary before any State-only gate change. Consent, Collection, document,
Review and managed-output gates are unaffected.
