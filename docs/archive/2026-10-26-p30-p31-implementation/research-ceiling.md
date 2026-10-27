# Research ledger mutations under execution ceilings

Recorded 2026-10-27. This is a scoped repair and synthetic component check, not
P31I draft-mode acceptance. The [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance)
owns milestone status; the [operator research manual](../../operator/research.md)
describes the current ledger behavior.

Native `research_source` and `research_claim` append ledger records without
ordinary workspace-write approval. The previous Session tool dispatcher checked
ordinary mutating tools, but did not include these two ledger mutations when a
read-only, planning or draft ceiling applied. An explicit broad approval was not
necessary for the escape. Both actions now return a denied paired tool result
before a `tool_started` record or worker execution whenever the active or
enclosing ceiling is non-normal. `research_ledger` remains readable. Normal-mode
research behavior and its existing approval semantics are unchanged.

The pre-fix Session source SHA-256 was
`c7a669c9fbc28a908c6fcd74d0cc2311e6688a6fccc37ec9486dd98da69757ff`.
An author fixture in draft mode with `--yes` reproduced an open claim appended to
the journal; its [negative test output](research-ceiling/claim-before.log) is a
failure, not a pass. An independent reviewer also adapted a synthetic successful
MCP provenance fixture to use draft mode with explicit denied ordinary approval.
The [historical fixture](research-ceiling/source-before.exs) and its
[output](research-ceiling/source-before.log) report a passing assertion that
the vulnerable runtime **did** append `research_source`; the pass demonstrates
the defect, not correct enforcement. Both observations use synthetic data.

The fixed source SHA-256 is
`d07cfe69e2fc1357ecba5797a7fa8e7468b4c61ff73d5bfd7664f1cced506314`;
the [new test](../../../test/ipse/session/research_ceiling_test.exs) SHA-256 is
`5716fb6ccc0cd73605fd1ff41078da47a20d91038e16e9e49871f0c8ee573f05`.
It exercises six active/enclosing ceilings with yes, source and claim denial
before tool start, ledger read, and normal-mode behavior for yes, ask and deny.
The source-denial case is syntactically valid but has no successful historical
MCP source; its assertion checks dispatch denial rather than a failed provenance
lookup. A separately checked pre-fix successful-source fixture establishes that
the original escape could write a real synthetic source record.

After strict compilation in `/tmp/ipse-research-ceiling-audit/project`, the
author ran these six suites with the following command; [22 tests passed](research-ceiling/fixed.log):

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp mix test --no-compile \
  test/ipse/session/research_ceiling_test.exs \
  test/ipse/session/draft_ceiling_test.exs test/ipse/session/execution_mode_test.exs \
  test/ipse/extension/mode_test.exs test/ipse/tools/research_test.exs \
  test/ipse/tools/research_integration_test.exs --seed 20270118 --max-cases 1
```

The independent reviewer copied the fixed graph, verified its source hashes and
repeated the same suites: [22 passed](research-ceiling/independent.log). These
runs used the existing private helper and local synthetic fixtures, no provider
account or kernel-profile override. Logs identify actual outcome counts; they
do not establish native storage qualification, dynamic draft creation, cancelled
intent isolation, compaction, or an installed-user journey. The source and claim
reproductions are historical and must not be run as assertions of fixed behavior.

A subsequent frozen private snapshot of the then-current combined worktree,
including the same fixed `Turn` and test hashes, was [compiled](research-ceiling/current-source-compile.log)
from 143 Elixir files with warnings as errors. Mix needed loopback access: an
initial sandboxed attempt could not acquire its TCP lock, and the retained run
used the approved loopback-capable environment. The same six suites passed **22 tests**, seed
20270119; see [current-source output](research-ceiling/current-source.log).
This is a scoped regression, not a full project build or acceptance run.
