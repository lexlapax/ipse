# Conservative budget reservation fixtures, 2026-11-06

Historical verification record for two test-only corrections. Current guidance is
in [resource controls](../../operator/resources.md),
[registered-service configuration](../../operator/configuration.md#serialize-a-shared-inference-service),
[accounting](../../developer/accounting.md#reserve-before-dispatch-and-settle-before-admission)
and [the dispatch implementation guide](../../developer/configuration.md#trace-registered-service-admission-and-reconciliation).
This record does not qualify a complete default regression or a milestone.

The frozen default regression exposed stale expectations that an unentered
provider callback left no budget booking. The current implementation durably
reserves before service selection, slot waiting and Ollama model prechecks.
Failure before a budget dispatch intent retains the full reservation. These
fixture changes preserve that behavior; they change no production code, policy
limit, provider selection or automatic-retry rule. The original full-regression
outcomes remain unchanged.

## Behavior checked

`test/ipse/inference_dispatch_test.exs` now checks two fixed policies:

- With one allowed request, a final-gate refusal makes no provider callback but
  retains one request and 32 input/output tokens as unsettled liability. A fresh
  admission is refused before the service gate. No booking is reused or refunded.
- With two allowed requests, a distinct fresh admission completes the only HTTP
  wire. The earlier booking stays unsettled. The final ledger books two requests
  and 33 input/output tokens: 32 retained plus one measured for the completed
  request. The policy digest is unchanged.

The final gate runs before native slot admission. Its refusal cancels the waiting
entry and creates no recent service receipt. Only the later completed wire
creates a `settled` receipt. This is distinct from a callback that entered a slot
and then proved unstarted.

`test/ipse/session/ollama_model_pin_test.exs` keeps the actual preflight mismatch:
six synthetic metadata calls, zero chat requests, no prompt canary in requests,
no tool execution and no observed usage. Its close/Saved checks now expect one
request booking, one unsettled liability and one unknown liability. Other test
branches retain their zero-unknown-liability expectation. Known measured usage
and idle-resume checks remain in the whole file.

## Separate executions and retained failures

Both successful executions used the existing private Host03 build, with normal
App startup, `--no-compile --no-deps-check`, one scheduler/async thread, maximum
one test case, seed 481639 and fresh private HOME/operator/tmpfs paths. The outer
bound was 180 seconds plus ten seconds kill grace; product and test deadlines
were unchanged. Existing Hex archive bytes were reused, without fetching or
installing anything.

| Execution | Actual result | Scope |
| --- | --- | --- |
| Setup 01 | Exit 1 before App/tests | An empty private archive directory lacked the Hex SCM |
| Dispatch 02 | Exit 2; 7/9 passed, 1.1 s | New accounting assertions passed; two added `not_started` service-receipt expectations were incorrect |
| Dispatch 03 | Exit 0; 9/9 passed, 1.2 s | Complete dispatch fixture file after correcting only those service-history expectations |
| Ollama 04 | Exit 0; 9/9 passed, 1.8 s | Complete model-pin Session fixture file |

The two complete-file results are separate scopes, not an additive replacement
for the frozen full-suite denominator. The setup failure and failed focused
aggregate remain retained.

Every execution's runtime, source and harness input posts passed. The guards
covered the complete Host03 build, dependencies, `priv`, raw links and file
identities; from execution 02 they also covered the reused Hex archive. This was
1,550 immutable leaves initially and 1,683 with that archive. The exact known
Mix failure-cache path was permitted bookkeeping; it was not a general mutable
runtime exemption. No main or frozen runtime was compiled or changed.

Ollama 04's source-list preparation also printed a missing-path diagnostic for
an extra, nonexistent `provider/ollama/models.ex` entry. Seven actual source
entries were guarded. The correct `provider/ollama_models.ex` still matched the
original Host03 source pin, SHA-256
`cd2bf7bb90f0912192f6dd74b4c09c517c855e0ebe6b075575dd6df5bfe996a0`.
Its compiled BEAM was included in the complete pre/post runtime guard. This
additional source-list diagnostic was not hidden by another test run.

Independent actual-host read-only cleanup exited zero and confirmed that all
four owned process IDs, groups and scoped BEAM/helper processes were absent.
These checks deliberately made no global Input or fixed-listener neutrality
claim: the separate default regression owned those resources. All HTTP calls
were synthetic loopback fixtures. No real provider, paid inference, model
service, TTY acquisition or original notebook access was involved.

## Provenance and evidence commitments

Private evidence is retained under the dated `inference-budget-fixture-20261106-01`
verification directory. Only safe result summaries and hashes are recorded here;
no Session journal or private content is exported.

| Evidence | SHA-256 |
| --- | --- |
| Final dispatch fixture | `0e38f659dc15a5b2a606641a065e3c0751380b32dea0d08266357ff76e67abc0` |
| Final Ollama fixture | `2be3d9d04eab34b71ac66aca3ec73f7fae21634814aadb17865fac21f80e0935` |
| Setup 01 output | `36c6d86cfe8fc23118dfc04d6e55f907eebe87ffa12ecc05d946b36d4de76e9a` |
| Failed dispatch 02 output | `d85b734c17ba98580642c85477da49683dc3786be8258ec66a6b551cbefe247f` |
| Passing dispatch 03 output | `fa48a57307b47e806713542de48fc6d13398e34d0e7df59e0a7de132026903f6` |
| Passing Ollama 04 output | `db6d93ad810152b639def10d7f94e66babc5dd492768e796dd5bca2a108f73f6` |
| Independent scoped-neutral status | `26b9cc6af5b8d9b72cac7c071205863cad7d1b53d15091e742f3205018b3db42` |
| Private result summary | `29cec43a1012a6488fd51d5a4ecc3b2cbdbc45dd78c3a2d6d75b1f721a12aed6` |
| Private final-receipt manifest | `061eea896e249cfe07b48dd1e887156045319ed13a4df593086cbaba9f4cfaf3` |

The whole current developer Configuration and Accounting chapters and operator
Configuration and Resources chapters were reviewed against this ordering.
They already teach pre-slot reservation, failed-precheck liability, immutable
session policy and no automatic refund/replay. No manual correction was needed.
These checks establish synthetic protocol/accounting behavior, not provider
billing, physical model identity, full-suite success or product-quality readiness.
