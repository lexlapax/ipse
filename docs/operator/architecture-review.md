# Architecture-review checkpoint

P24 is completing its recorded independent coverage gaps before the baseline
security scan. On 2026-10-18 the operator authorized this focused completion and
the subsequent scan, selected high reasoning for Security Cloud's offered model,
and separately approved creating a persistent Ipse cloud environment. No scan
has run and architectural acceptance remains open.

## Current execution

The focused review uses the local, signed-in Claude subscription in a fresh
nonpersistent session. Its source is a credential-free Git export of
`86d4d69f32b5e4cdba8de41e1e9a1220dcb6db0d`; runtime and tests match `e8f7ad5`.
The exported repair delta starts at `a5912ab`. Only Read, Glob and Grep are enabled;
API credentials, project customizations, extra integrations and subagents are
disabled. Source contracts and test fixtures are available, while prior critiques,
implementation-side verdicts, ignored files, credentials and private journals are
excluded. The report will remain private outside Git. This snapshot-based pass
does not claim the earlier briefs' Git-history access method.

Its task is to inspect the SDK authority and OS sandbox omissions, related
persistence/accounting/context seams, actual test bodies and the recent repair
compositions. The supervisor must verify applicable findings and assess material
remaining coverage before scanning. An incomplete review is not acceptance, and
no additional review package is automatically scheduled.

Read-only Security Cloud checks confirmed repository access and available credits.
The operator approved environment creation after automatic approval review
required action-time confirmation. Environment onboarding is in progress with
the selected repository and no added secrets. Setup is distinct from a scan.
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
keeps baseline security and P25 gated on applicable repairs and adequate coverage.
