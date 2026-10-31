# Bounded original-source lock reserve

Historical component evidence, **2026-10-28**, on `codex/p30-p31`. The
[plan](../../plan.md) owns acceptance. This records a source-use resource fix,
not completion of P31C0, full current-source verification, model recall quality
or multi-day endurance.

## Capacity and ownership

`StoredSources.with_verified` can retain up to 128 distinct original Session
sources through a current-use callback. Before this change each `Runner.lock`
consumed the same 32-entry resource limit as shell, protected transaction,
extension, MCP and HTTP resources. Consequently 32 separate sources could fill
the scope before the protected Identity/Consent transaction was acquired.

The host-only `Runner.lock_source/1` uses the same native helper, nonblocking OS
lock, owner Port, cleanup ticket and session-lock tracking as `lock/1` but
registers `:source_lock`. Only `StoredSources`, after its existing original
journal/lock path, file identity and private-permission checks, selects this
kind. Worker JSON supplies no resource kind or arbitrary source path. The scope
reserves at most 128 source-lock registrations and independently permits ordinary
registration only while its non-source resource count is below 32. Source proof
count, original-source identity, source sorting and aggregate journal-byte limits
remain unchanged. Each lease remains held through its callback and is checked and
released on unwind.

The older controlled-child mechanism may insert up to 32 child resources through
its separate bounded token path, even after ordinary registration reaches 32.
That pre-existing behavior remains. Ordinary registrations count those child
entries, so none can enter while the non-source count is 32 or more. A single
scope can consequently contain at most 128 source locks, 32 ordinary registered
resources and 32 pre-existing controlled-child entries. These are **per-scope**
limits, not a global machine/process quota; child scopes retain their existing
ownership and accounting rules. Each entry retains the existing independent
monitor, cancellation message and cleanup receipt. This increment does not
claim a system-wide concurrency or RAM qualification.

## Focused controls

The private runtime `_build/source-lock-reserve-20261028-03` derives from the
frozen retention CLI graph and copies the same actual helper
`113df584e83b7749a11a72509092cb9c2b32d6fdc3fcf91b0181335f5f8c2550`.
Its Runner source is the frozen production-profile Runner plus only the exact
current source-lock block. The current Resources/StoredSources cohort compiled
with empty compile/runtime diagnostics. The graph therefore does not contain
later in-flight shell/MCP Runner changes and is not a full-current-source build.
Actual files and native helper execution used private `/tmp` tmpfs fixtures.

| Run | Scope and result |
| --- | --- |
| [First bootstrap](source-lock-reserve/first.log) | Source modules compiled, but the copied test fixture could not find its relative Knowledge contracts file. No test or native lock ran. |
| [First test attempt](source-lock-reserve/second.log) | Two fixture mistakes: `open_owned_stdio` does not accept the `:shell` kind, and `Process.monitor/1` does not monitor a Port. The owner-loss case had opened 32 synthetic-source locks before fixture cleanup. No passing case is claimed. |
| [Second test attempt](source-lock-reserve/third.log) | **1/2 passed**, 0.9 seconds: controlled-owner death released 32 actual native locks and preserved all source journal bytes. The 128-source callback, live shell, protected transaction and both capacity refusals completed, but the fixture then expected the wrong `controlled_owned_effect` result tuple. |
| [Affected positive rerun](source-lock-reserve/fourth.log) | **1 passed, 1 excluded**, 0.9 seconds: the corrected assertion uses a fresh fixture. It held 128 distinct actual original-journal leases inside one owned child while a real supervised shell and protected native transaction were active. Source registration 129 and ordinary registration 33 refused; all 128 original locks and the excess path could subsequently be reacquired. |
| [Child accounting](source-lock-reserve/resource-budget.log) | **1 passed**, 0.1 seconds: an existing controlled child remains admissible with 32 ordinary registrations, additional ordinary registration refuses, and the independent source reserve remains available. |

The 128 original journals, source statements, proof recipes and project admission
metadata are synthetic fixtures. Their journal files have actual source-origin
identity; `StoredSources` opens, verifies and retains real native locks while its
callback checks a real protected transaction controller and supervised shell.
The owner-loss control kills the owning process with 32 leases held, observes
the controlled peer and all lease Ports exit, reacquires each lock and compares
every journal hash. It exercises the existing controlled-child cancellation
boundary, not a claim that arbitrary blocked file IO is forcibly killed.

The manifest binds the exact private Runner, Resources, StoredSources, test and
fixture snapshots, retained setup/failure/pass logs and runtime inventory. No
4000-note workload or aggregate suite was repeated. A full end-to-end recall
journey using 128 independently authenticated managed notes, installed behavior,
resource pressure on other hosts and current source integration remain separate.
