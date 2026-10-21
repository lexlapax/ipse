# Shared verification and retained evaluator records

Historical reference, recorded on 2026-10-20. This directory preserves the manuals
before the common source/installed verification workflow. Current instructions
are [testing](../../developer/testing.md), [the extension proof](../../developer/testing.md#learn-a-complete-workflow-through-the-compatibility-lab)
and [knowledge evaluation](../../developer/knowledge-evaluation.md). The
[plan](../../plan.md) owns acceptance status.

The preserved chapters come from `111228c1eadf6816f76e3b3981030000907f2e5a`:

- [Testing before the rewrite](testing-before.md).
- [Extension proof before the rewrite](extension-proof-before.md).
- [Knowledge evaluation before the rewrite](knowledge-evaluation-before.md).

Their original bodies and historical instructions remain, with a historical
banner and relative inline links rebased to their original targets.
[The provenance manifest](manual-provenance.json) records source and snapshot
hashes. These documents are not current procedures or new passing-check receipts.
## Shared source and installed verification

The implementation verified on 2026-10-21 replaces repeated per-example launch
and installed-runtime setup with `dev/verification/`. Its finite scenario table
keeps each proof's assertions and supported platform cases. The runtime compiles
the trusted harness before starting the selected host, checks exact executable,
artifact, harness and utility identities, and refuses installed source fallback.
Native measured cases retain their separate service-manager environment and
compile-bound startup policy. The command is `scripts/verify.exs`; platform
probes remain explicit commands.

The source evaluation CLI uses the same owner to prepare its finite compiled
Research fixture pair. Temporary evaluation runtimes are disposed after normal
success or failure; a freeze retains its sibling runtime for reopening. Matching
caller-owned pairs can be borrowed from a shared BEAM directory. Reopening keeps
full source, runtime and launch verification and requires the actual captured
fixture before reading Research data. It does not compile a missing fixture.

Review found two integration gaps: package CLI checks inherited a PATH containing
the selected Erlang executable, and a fresh source Research CLI lacked its
compiled fixture. Both are repaired with executable regressions. Further narrow
review corrected shared-directory borrowing and the source-loaded-only fixture
case. A real service-loss control also exposed a model-service owner that always
requested cancellation after a native terminal frame. It now requests passive
completion after that frame and still requires the actual helper exit status.
Fresh controls pass; the exact OS event behind the original failed receipt
remains unproven, and that receipt remains a failure.

## Verification and limits

The [verification receipt](verification.json) binds 438 source identities at
inventory SHA256 `9eac8f08fd142133da44c118ef0685d7b581ff4920015c9d398132cedbcfe8bb`.
It records the following checks against unchanged runtime source:

- macOS: 1,433 passed, one skipped and 36 excluded; native enforcement, fresh
  packaging, 39 ordinary source and installed commands, and two model-service
  commands pass.
- Linux: 1,475 passed and 19 excluded with native sandbox tests included; native
  controls, fresh packaging and the same command matrix pass.
- Fresh Linux source and installed native runs each complete 350 scripted first
  outcomes, audit, tamper and scoring controls, plus all five authority-loss
  controls. Each checks its original source inventory again after execution.

The macOS receipt explicitly preserves an original controller error: it invoked
the Linux-only strict runner test on macOS after the full suite passed. That
unsupported invocation failed. A continuation verified the original successful
steps and unchanged source, then completed the supported remaining checks. No
product-source exception or repeated full suite was used to conceal it. Earlier
failed integration runs also remain in the continuation evidence.

The manual rewrites and command examples were reviewed with the implementation;
the documentation checker passed with zero errors. The final completion record
and plan edit follow the runtime checks. No hosted result is claimed for their
eventual publication commit.

These are credential-free execution and protocol fixtures. They use no private
workload or actual model inference and establish no model-quality improvement,
matched actual-model resource result or engine selection. The whole-codebase
consolidation and final P27 acceptance remain open in the plan.
