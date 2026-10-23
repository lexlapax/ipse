# Portable experiment foundation, 2026-10-19

Historical implementation and review record following `21d710c`. The source
commit containing this record owns the declaration, local seal and schedule
foundation. This is not a measured comparison or P27 completion verdict. Use
the [evaluation training manual](../2026-10-22-before-structural-consolidation/docs/developer/knowledge-evaluation.md#seal-identities-before-opening-inputs)
for current procedures and the [plan](../../plan.md#p27-optional-research-graph-and-rag)
for acceptance status.

## Selected quantity and architecture

After reopening both the host coupling and the Linux/systemd approach, the user
selected workload-charged RAM with an optional Linux benchmark backend. The
quantity is `linux_memcg_charged_peak_bytes_v1`, including cache and kernel
charges. It is not simultaneous process RSS or device memory. The approved fresh
comparison is CPU-only. Existing systemd user-service tools remain an approved
optional launch dependency; ordinary Ipse operation does not require them.
This resolves the pending quantity decision and refines the earlier
[aggregate-memory design](aggregate-memory-design.md). Its original investigation
and synthetic measurements remain historical evidence.

Two isolated design contexts proposed complete integration shapes, and a third
reviewed both. These were separate contexts using the same model, not a claim of
model diversity. The selected shape retains `EvaluationFreeze` as identity owner
and `EvaluationRunner` as domain owner. The runner owns schedule derivation and
allocation. Later measured entries will reuse complete `run_variant/9` lifetimes.
A separate model-service owner remains to be implemented. Kernel admission,
birth-before-exec and retained cleanup remain in the existing Rust helpers.
The verified dedicated-service admission prerequisite stays explicit for this
optional backend. No hostname, historical kernel version or tool-version
whitelist becomes part of the portable experiment.

## Implemented boundary

`declare` produces content-based experiment bytes from a clean source snapshot,
the public plan and inert artifact imports. The experiment retains prompts,
budgets, model and dataset identities, blind seed and selected measurement/cache
policy. It removes local source/artifact paths, profile origins and search port.
The private blind seed must stay away from independent semantic reviewers.

`freeze-measured` requires the independently retained experiment hash. Its closed
local resolution supplies artifact paths, literal private model origin, distinct
search port and fresh reports path. It produces a fresh execution identity,
copied artifacts, exact resolved profiles, source/runtime identity and observed
provenance. The fixed owner-only `attempts` registry is inside the seal and
disjoint from disposable reports. Its creation is an identity operation, not an
attempt claim. The semantic recipe has a separate digest without a cycle through
the final manifest or future concrete bootstrap.

The pure schedule derives all fourteen sorted-project/declared-strategy cells.
Every cell retains the original two-project count. Version two divides request,
token and monetary caps by that count, rounding down without redistribution.
Reservations and rate cards stay unchanged. Research shares use each project's
query count times `1 + max_sources`; the complete fifty-query declaration yields
550 calls. Legacy version-one allocation remains unchanged.

The existing prediction, frozen verification, review and score paths refuse
version-two seals before dataset or prediction reads. This unit opens no model
service or held-out input and claims no measured execution. Re-resolving an
experiment produces a new execution identity, not permission to replay an old
attempt. The interrupted 280/350 comparison and its unknown request remain
untouched.

## Review and verification

The independent foundation review found that the first allocation reused legacy
monetary caps unchanged in both project cells. The corrected shared allocation
function receives the plan version at both schedule and Session-selection call
sites. A three-basis odd/even/zero-cap control checks exact divided buckets and
their summed limits across every variant. Reservations and rate cards are
checked unchanged. The follow-up source review found no remaining actionable
foundation issue. One reviewer had authored the real-CLI fixture; its test
authorship was not independent of that reviewer.

Controlled coverage includes source/artifact relocation, distinct immutable
local seals, changed source/runtime/experiment/plan/artifact refusal, closed local
resolution, canonical report/registry boundaries, all fourteen cells, uneven
query distribution and refusal of incomplete matrices. The real CLI sequence
declares and seals an inert fixture, checks exact profile origins, rejects
legacy prediction before a missing dataset, and rejects a changed declaration
before output creation. The manual's actual hash-extraction and resolution
heredoc snippets also ran with synthetic inputs. These are identity and protocol
checks, not model-quality or resource results.

| Local check | Actual result |
| --- | --- |
| Required build and warnings-as-errors compile | Passed on macOS arm64, Elixir 1.20.3/OTP 29 |
| Full source suite, strict stdio cleanup enabled, unchanged 60,000-ms deadlines | 1,270 passed, one skipped, 34 platform exclusions; 748.6 seconds |
| Final focused identity, schedule, real CLI and resumed MCP checks | 21 passed, 11 excluded; 21.9 seconds |
| Global format checks | Passed with Elixir 1.20.3 and installed Elixir 1.18.5/OTP 27 |
| Credential-free demo and pinned CI policy check | Passed |
| Documentation links and audience/archive rules | 258 Markdown files, 2,770 local links; zero errors |

The first Elixir 1.18 format check rejected one long alias comparison. After the
full suite completed, its two pure sorted-key operands were extracted into local
variables in the same evaluation order. The final focused checks and both
formatters passed afterward. Independent review reversed that exact hunk in
memory and recovered the previously reviewed source hash, confirming no other
freezer bytes changed. A clean compatibility archive path also avoided loading
the unrelated Elixir 1.20 Hex archive under OTP 27. This did not change a project
dependency or global tool configuration. Hosted proof for the resulting commit
remains separate; no corrected-source hosted result is claimed here.

### Preserve the preceding hosted failure

The exact `21d710c` [hosted run](https://github.com/lexlapax/ipse/actions/runs/39358661468)
finished with Ubuntu passing every step and macOS failing at the source suite.
The macOS log reports 1,289 tests with two failures. Its later native, package
and installed steps did not run. This record does not relabel that run green.

One test performed two full CLI executions and two negative CLI checks under a
single 60-second test deadline. It timed out on the last negative check. Those
four independent behaviors now have separate tests with the same assertions
and default deadlines.

The other failure waited five seconds for resumed model input while MCP
discovery had not reported model-launch readiness. A temporary fixture injected
a six-second delay only into resumed startup. The original assertion failed in
6.1 seconds with the same four-message mailbox shape as hosted CI. Adding only
a pinned resumed-session `Thinking` readiness wait passed in 7.4 seconds. Both
original five-second model/completion checks and the 60-second test deadline
remained unchanged. Both controls confirmed that their specifically owned
initial and resumed fixture processes were absent after Session cleanup.

The repository correction adds that readiness wait. It changes no production
timeout or MCP transport behavior. The hosted mailbox establishes an unobserved
readiness boundary, not an exact CPU scheduling diagnosis. The injected delay
establishes the test's timing assumption. The causal probe retained producer,
original/transformed sources, logs, cleanup records and hashes in the private
continuation evidence. Its pre-repair source and fixture hashes were
`d6de4c2c461f1317f045d1fc5062f278bac85fecde2f33d0f576817617d41bc4`
and `1f7f787b345fd8a09f3265614f46adad382adadd90c948863cb9e0a6c03cbd99`.

## Completed hosted foundation gates

The exact `75b707798592273bae105fbb9d715f78e5bf431a`
[hosted run 39362693472](https://github.com/lexlapax/ipse/actions/runs/39362693472)
completed successfully on Ubuntu and macOS. Both jobs passed their source,
package and installed-proof steps. The completed metadata was read and retained
with the later owned-model continuation evidence. This supersedes the pending
corrected-source verdict above and preserves the earlier `21d710c` red run.
It does not verify the later model-service implementation.

## Remaining integration

Measured preparation must seal projected inputs and the full schedule. Native
and domain entries must claim permanent attempts before effects. Complete cells
must own fresh private model caches and CPU-only services, admit listeners
before HTTP, preserve original allowances, close Sessions/services/gateways and
reconcile liability inside measurement. Finalization must seal all 350 first
predictions before references or independent semantic review. Post-exit audit
must reconcile the three distinct peak subjects without adding or subtracting
them. Complete resource comparison, semantic quality and engine selection remain
open.
