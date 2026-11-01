# Preserve the full source union after interrupted effect cleanup

Dated **2026-11-01**, author-run synthetic Linux verification based on `098559f`.
This engineering record follows the
[complete frozen module baseline](managed-collection-module-20261101.md) and
[MCP loss controls](root-native-mcp-loss-20261101.md). It is not milestone
acceptance. The [plan](../../plan.md) owns remaining work;
[testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
teaches the source/cleanup/recovery distinction.

## Counterexample and retained evidence

The complete module reproduced the running-shell owner-loss assertion failure
after the original native command had started, the actual Session had died and
the observed helper/group/shell/sleep processes had exited. The final target
remained absent. Strict Saved reconstruction succeeded, but the test incorrectly
required `ManagedLineage.dependencies/2` to return an available lineage.

Read-only inspection of the actual retained shell journal found exactly one
version-3 reference dependency, one admitted shell effect and no effect-cleanup
record. There was no pending output/discovery or unknown Worker input. The
runtime correctly returned `managed_lineage_unavailable`, as its recovery rule
requires for unconfirmed effects. An initial probe selected a neighboring printed
root and failed its assertion; that probe changed no state. The corrected probe
authenticated the expected shell admission and physical markers in the actual
failure root. Both diagnostic attempts are retained and hashed in the
[receipt](native-loss-lineage-shared-20261101.json).

The whole module remained untouched until its terminal result. Pre/post checks
confirmed all 7,855 tracked files, 632 test-build BEAM/app files and the helper
unchanged, with the same clean commit. Only then was the repair applied.

## Shared assertion and original fault timing

The shell observer now records the full dependency union from the actual native
approval snapshot, just as the MCP loss observer already did. The shared
`native_root_loss_lineage/2` compares that exact union with the retained reference
after strict Saved reconstruction. It requires nonempty version-3 sources and
exact equality, rather than discarding dependencies when reconstruction becomes
unavailable.

It separately derives required reconstruction availability from the committed
effect-cleanup records. Missing cleanup must keep the lineage unavailable and
make `ManagedLineage.dependencies/2` refuse; confirmed cleanup returns the exact
retained union in these fixtures. That API result grants no current-use permission.
Fresh admission remains required, including after actual policy revocation.
Idle resume must preserve the same availability flag and exact messages, without
another effect, callback or provider request.

The original shell command, timeout, start marker, process observations, kill
boundary and 800-ms absence check remain unchanged. The revocation case still
requires its completed file, observed private stdout, withdrawn delivery and no
stdout result in the captured terminal. MCP still requires actual initialization
or physical service effect before loss, transport/socket/server exit and the
appropriate unchanged target/call/traffic counts. No source, cleanup receipt,
clock or native witness is manufactured; the kill is not delayed to obtain a
later acknowledgment. No production code changed.

## Terminal verification

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only native_root_running --only native_root_loss --max-cases 1 --seed 791693
```

Result: **5 passed**, 162 excluded, 161.4 seconds, exit 0. This covers both shell
execution faults and all three MCP loss controls. The log is
`/tmp/ipse-native-loss-lineage-shared-20261101.log`, with retained synthetic roots.
The child seed remains 791678; child totals are not added to the parent count.
The receipt hashes final selected test/recovery sources and logs after execution;
it is not a prelaunch freeze or complete loaded-runtime inventory for this
focused follow-up.

Whole affected testing/recovery and MCP manuals were reviewed in this series.
The testing chapter integrates the shared source-union and reconstruction
assertion into its existing native worked example, keeping current eligibility
separate. Operator behavior is unchanged. Formatting/documentation checks and
their log hashes are in the receipt. No runtime/helper/dependency/limit changed;
no runtime/package rebuild or complete suite was repeated for this test/documentation
increment.

The frozen module result remains **130 passed, 22 failed, 15 skipped** at
`098559f`. These five focused passes cannot be subtracted from it. The
[complete frozen suite](full-suite-20261101.md) remains 3,653 passed and 54 failed
at `f44b63c`. Remaining legacy fixtures/publication, nested approvals, capacity,
lifecycle, installed/platform/model-quality and full P30/P31 acceptance remain
open. These automatic Linux `7.2.11-arch1-1` tmpfs/PTY/loopback checks establish
no human, live-model quality, installed, non-Linux or confinement result.
