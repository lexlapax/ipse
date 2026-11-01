# Continue known native and MCP results through the existing input fence

Dated **2026-11-01**, based on `a4e01d7` plus the fixed-source inventory below.
This is historical engineering evidence extending
[accepted-decision input](accepted-worker-input-20261101.md), not C0 or P30/P31
completion. Current reader contracts belong to
[effects](../../developer/extension-effects.md#follow-the-common-action-sequence),
[invocations](../../developer/extension-invocations.md#trace-the-session-and-worker-owners)
and [source-owner delivery](../../developer/session-sources.md#deliver-a-managed-export-input-under-its-original-owners).
Remaining acceptance belongs to the [plan](../../plan.md).

## Reproduced lost continuation

Two actual public-command controls select the existing explicit `--yes` mode.
Each first reads a current Collection snapshot, then performs a native write or
a selected stdio MCP write through the existing effect admission. Both physical
writes succeeded, but both invocations ended in error because the interim
`managed_action_output_withheld` gate stopped the committed result before the
Worker's next callback. The retained baseline reports **zero of two passed,
141 excluded, in 9.6 seconds**. The tests require successful continuation; they
do not relabel the old refusal as allowed behavior.

The first test command failed at compilation on a receive guard, before effects.
The corrected fixture also names the native operation `tool.call` rather than
deriving it from the test's `native` label. Both development logs remain in the
inventory; neither is qualification of the runtime change.

## One route and unchanged effect authority

All host-action continuations come from `Host.execute_export` through its private
`continue` chain. Session creates that entry using its actual configuration.
Host and Session now share `WorkerInput.configured?/1` for selecting the protected
route. For a pinned export with available lineage, known native-tool and MCP
action results no longer take the redundant interim gate: they commit normally,
then Host calls the existing managed input adapter with that exact result.
Session independently reconstructs the last action, full inherited/read union
and pending frame before any bytes reach the Worker. A result receipt is not a
delivery permit. The native write, source/control settlement and original timer
are unchanged.

The native-tool progress preview is a fixed status string, rather than raw
outcome data. Startup already suppresses managed arguments. Effect approval,
mode ceilings, execution/source admission, MCP discovery, private result binding,
unknown outcomes and final output admission retain their existing checks.
Unknown lineage and unconfigured routes still take the old gate. Managed
document-store result delivery retains its separate gate, as do unqualified
questions, nested approval displays, State/service effects and other Worker
input purposes. No permission, deadline, native ABI or dependency changed.

## Actual controls

The repaired two positives passed in **10.8 seconds**, with 141 excluded. They
require the exact physical file, committed successful action, exact ordered
action-chain and last-result input commitments, a delivered input receipt and
the actual VM callback trace. Native-tool previews must expose only status;
MCP results cannot appear through that native-tool preview channel. Saved must
reconstruct available lineage, and confirmed close/idle resume must preserve the
trace and repeat no effect or callback.

Four further cases pause the real Session at its actual committed native/MCP
action reply. The test changes the actual Collection root or revokes current
permission outside the completed effect scope, then releases the unchanged Host
continuation. The known effect remains in the journal and on disk, but no result
callback runs. Its exact pending input is journaled unknown, Saved preserves
unavailable lineage/unknown delivery, and close/idle resume leaves the effect and
trace unchanged. This disclosed BEAM pause supplies timing, not source authority,
approval or a manufactured native delivery witness.

All six controls passed in **17.1 seconds**, with 141 excluded. Their dependency
is authentic payload-free root metadata; these are not new record-content,
accepted-decision effect-stage, HTTP-fault, human, installed or model-quality
qualifications. The underlying original-source/journal/pipe transport retains
its separately scoped tests. The full goal remains active, including the
historically failing `save_history_expire` case recorded in the preceding
increment and the unchanged older whole-suite verdict.

## Fixed-source verification and inventory

The serial fixed-source qualification passed the build (183 production modules
and three inert bundles), formatting, strict compilation, **345 tests with eight
skipped and 27 excluded in 421.6 seconds**, the six nested controls in 17.2 seconds,
and all eleven genuine native approval controls in 173.3 seconds (twelve excluded).
The accepted-decision journey and Rust controls below retain their separate
scope; exact elapsed results are in their hashed logs. CI policy, an isolated-home
credential-free demo and the complete documentation checker passed. Documentation
was reviewed across the source, invocation, effects, testing and operator chapters;
the plan reconciles its former blanket nested-result refusal with this bounded
route. Original whole-suite failures remain open; these focused successes are
not a replacement aggregate.

No new package was built for this increment. Earlier exact packages qualify
their own recorded revisions; installed delivery and the next complete candidate
remain separate qualification work. No native source or ABI changed here.

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `lib/ipse/extension/host.ex` | 32826 | `fb2175b0b867d21ba08417f61ea3f8cdda5d91f069a76b912ad11a2acfe9f268` |
| `lib/ipse/session/invocation.ex` | 66998 | `f7b292df276418ab5594129c6e414fa522672f663c1de837967674f27e40b0c0` |
| `lib/ipse/session/worker_input.ex` | 20037 | `ddee45ac4b7c8365d322d6be274eb5f989c6b654d238df83fe366dfe3f9f6366` |
| `test/ipse/extension/managed_collection_call_session_test.exs` | 286480 | `3e4662d4a7ea64e4b425bae5c6a86c90f371d39981f3d73b8c1ab5be38396381` |
| `native/ipse-bound.rs` | 24481 | `685308b63cb4dd29715c38dbdd4b8a91303d961de3f97477e981bb0e10198911` |
| `priv/ipse-runner` | 969344 | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |
| `/tmp/ipse-nested-result-baseline-20261101.log` | 1933 | `58095e933cb90b8c982cd060c10eca29903b75e5e2d2d7ee3610a5eafdb24203` |
| `/tmp/ipse-nested-result-baseline-second-20261101.log` | 1181 | `6ab6ea94d43a31c4f60598244e3e0ebdf5d00ebfd5ebcd1ce61181d2ad0e2b2f` |
| `/tmp/ipse-nested-result-compile-first-20261101.log` | 25 | `60accf7cafd00a16315066623055b3152e9e019729d5dee5fe58de43dd5b9188` |
| `/tmp/ipse-nested-result-first-20261101.log` | 339 | `c3c3b7c7930f90b9914eda380e108e2d39a65a4d63b4cd1153d5ace2351eefec` |
| `/tmp/ipse-nested-result-boundaries-first-20261101.log` | 318 | `9b5dc736a0ed4284b75a4753c5848e277fdb1eef2f46cabe8a0d8c39acca94dd` |
| `/tmp/ipse-nested-result-build-final-20261101.log` | 845 | `f5c4e2fd5cb82cbd5fb2d9e5473d5959a80bb7ed9ec5dcda99c8724bb79eab75` |
| `/tmp/ipse-nested-result-format-final-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-nested-result-compile-final-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-nested-result-regression-final-20261101.log` | 5912 | `95a8b8b67e4bb31dca0c2e8df89e6ec38717ffc57ac2f85bdb0534cc8d639102` |
| `/tmp/ipse-nested-result-boundaries-final-20261101.log` | 318 | `7cbb4b84ed7a7fbf9b9301d3b6b3dcb6e5c53d3c610bec55d00c55a8009733b8` |
| `/tmp/ipse-nested-result-approval-final-20261101.log` | 327 | `93caaa67de4e1e765cbbceb2a681e6554773df0391c3258e0106304ef1bb91f6` |
| `/tmp/ipse-nested-result-accepted-final-20261101.log` | 287 | `d8eebbbb6bac21e1c6b1847d0530c423ad0bce1eff4e21ffcb04b650dbafb3a9` |
| `/tmp/ipse-nested-result-native-final-20261101.log` | 8602 | `82c5cd62cf9c112269d0b29697c78fe1a2ce9c8d900f70026bcd84fd2188ae98` |
| `/tmp/ipse-nested-result-ci-final-20261101.log` | 32 | `e856938f2d4ee3eb319a90056aca83ff6b7347ea57ff71bac975f84df18ae633` |
| `/tmp/ipse-nested-result-demo-final-20261101.log` | 2720 | `4df68060e37cee1f73aed8f0fb2f03986876f100c586345f5b885c32bf959d2d` |
| `/tmp/ipse-nested-result-docs-final-20261101.log` | 757 | `de215b7754195c4be0a77f7a3833a9f0480de8b1db2b43cfba9f5f6af30db3f8` |

