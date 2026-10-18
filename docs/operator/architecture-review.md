# Architecture-review checkpoint

P24's focused completion returned an incomplete report on 2026-10-18. The
operator explicitly approved proceeding to the baseline security scan while
keeping architectural acceptance open, without another architecture-review round.
High reasoning was selected for Security Cloud's offered model. A private Ipse
environment is published; Security Cloud's separate automatic environment and
one-time scan are explicitly approved and ready to launch. No scan has run.

## Focused pass and current gate

The focused review used the local, signed-in Claude subscription in a fresh
nonpersistent session. Its source is a credential-free Git export of
`86d4d69f32b5e4cdba8de41e1e9a1220dcb6db0d`; runtime and tests match `e8f7ad5`.
The exported repair delta starts at `a5912ab`. Only Read, Glob and Grep are enabled;
API credentials, project customizations, extra integrations and subagents are
disabled. Source contracts and test fixtures are available, while prior critiques,
implementation-side verdicts, ignored files, credentials and private journals are
excluded. Its partial output remains private outside Git. This snapshot-based pass
does not claim the earlier briefs' Git-history access method.

Its task covered SDK/OS omissions, related persistence/accounting/context seams,
test bodies and recent repair compositions. It ran for about 15 minutes and made
54 Read calls plus targeted searches. The provider's safeguard stopped the
write-up during its first finding; the final response explicitly declined to
regenerate the missing report. The requested complete finding entries and coverage
matrix were not delivered. A successful process exit does not establish a
successful review. Retain observed read ranges as partial evidence, not inferred
whole-file coverage. The incomplete opening supports scanning conditionally, but
does not close acceptance or the remaining omissions.

The supervisor is checking the returned policy concerns against actual contracts.
A synthetic optional-callback recovery probe passed; it does not establish the
separately mentioned pressure scenario. Nothing was repaired from an incomplete
claim alone. The operator approved scan-first order after this interruption;
P25 still requires assessed architecture and triaged baseline evidence.

## Security environment

Read-only Security Cloud checks confirmed repository access and available credits.
The operator approved environment creation after automatic approval review
required action-time confirmation, then separately approved publication. The
environment is published with Only me visibility, package-manager network access
and no added secrets/environment variables. Security Cloud's list/search still
returns no matching environment; publication alone is not proof of scan usability.
The scan UI instead offers automatic environment creation. The operator explicitly
approved that separate environment and the one-time GPT-5.6 Sol/high repository
scan with no secrets or continuous monitoring.
Setup passed build/strict compile/format/demo. Its plain suite reported 880 tests,
two cleanup failures and 32 exclusions. Both affected modules passed 63 tests
under an external retained Rust subreaper without source/assertion changes; the
full suite under that launcher remains unrun. Native enforcement is unavailable
on this cloud host. Setup is distinct from a scan or fresh-restoration proof.
Use the [security context](../../SECURITY.md) for the threat model and safe
evidence rules; the [evaluation protocol](../developer/self-hosting-evaluation.md#security-review-before-and-after-the-trial)
owns scan execution and triage. Confirm the scan's actual revision and terminal
results before recording baseline coverage.

## Retained assessment and verification

The consolidated assessment of source `a5912ab` and evidence `a21469e` returned
without acceptance. Its [used prompt](../archive/2026-10-17-a5912ab-architecture-review-brief/index.md)
is archived. The complete report remains private; Git contains sanitized
dispositions and synthetic evidence.

Applicable required-consumer cancellation and abnormal-death lock gaps were
reproduced and repaired. Pool loss retains a conservative Session stop and manual
idle resume. Further controlled probes repaired premature HTTP-slot release and
filesystem IO continuing after caller death. Separately tracked completion owners
now retain admitted filesystem critical sections through synchronous completion.
The repaired runtime passed frozen local source/native/package/installed checks;
the final source/tests at `e8f7ad5` passed
[hosted Linux/macOS verification](https://github.com/lexlapax/ipse/actions/runs/39108388987).

The [internal audit](../developer/architecture-self-audit.md) records actual
counterexamples, rejected alternatives and limits. The
[register](../developer/architecture-review-dispositions.md#consolidated-assessment-of-a5912ab)
owns dispositions and independent coverage; [testing](../developer/testing.md#current-evidence-and-next-checks)
owns exact receipts. Internal reads and green tests do not supply independent
acceptance. The [plan](../plan.md#p24-independent-architecture-validation-and-baseline-security)
records the approved scan-first exception. Architectural acceptance and P25 remain
gated on applicable repairs, adequate coverage and triaged baseline results.
