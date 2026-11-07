# Synthetic Word replacement Session check, 2026-11-07

Historical focused evidence; current milestone status is in [the plan](../../plan.md).
The worktree contained this test and separate uncommitted draft-withdrawal and
terminal-diagnostic changes. The Collection artifact had been built at `3b6f35aa`;
this was not a clean or final-candidate verification.

With a fresh synthetic workspace and temporary home, the focused command was:

```sh
IPSE_DOCUMENT_NATIVE_TMPDIR=/tmp HEX_OFFLINE=1 ERL_FLAGS='+S 1:1 +A 1 +SDcpu 1 +SDio 1' mix test test/extensions/knowledge/document_acquisition_session_test.exs --only workspace_word_replacement_history --max-cases 1
```

The first focused run failed its initial query because the fixture used a
namespace query without first building the namespace index. The corrected test
uses the existing source-selected query and passed **1 test, with 37 excluded**.
Before those runs, an inadvertently broader tag selection was interrupted; it is
not a passing run. The stopped process released the shared input lock and test
port before the focused run. The focused runs started with the established memory
gate and shared-resource checks.

The passing test acquires a synthetic Word source, stages a replacement, checks
that the old selected head remains while the original bytes are restored for
use, completes the replacement, checks the selected new citation and retained
old records, refuses a stale continuation, and checks same-ID idle Session
reconstruction. It does not establish crash recovery, large-scale capacity,
cleanup, migration, installed behavior, general Word fidelity, or a complete
document lifecycle. The operator's decline of the retained-notebook recall check
remains in force; this test did not use that notebook.
