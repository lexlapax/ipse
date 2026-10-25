# P28/P29 second review and corrections

Dated 2026-10-24. This follows the [first audit repair record](../2026-10-24-p28-p29-audit-repair/index.md).
The [independent review](independent-review.md) is preserved as supplied by the
developer. It reviews `c2a19cb` and rejects the diagnostic repair despite green
automated checks. The [plan](../../plan.md) owns acceptance; the
[operator](../../operator/index.md) and [developer](../../developer/index.md)
manuals own procedures.

## Corrections under verification

| Finding | Change and verification boundary |
| --- | --- |
| R1 | Configuration producers name operator/project scope with fixed causes and pre-dispatch recovery. Workspace-directory failures use their mapped reason. CLI run/config/doctor tests require the cause and reject misleading effect uncertainty. |
| R2 | Refuse term syntax, invalid/oversized UTF-8 and control bytes while permitting slash commands, endpoint hints and service labels. A real changed-skill terminal exercise and adapter/hint events require `/context refresh`, `Grok / xAI` and `POST /v1/responses` to survive rendering. |
| F7 residue | Bare, demo-setup and Grok-setup doctor checks use one strict validator. Unexpected warnings fail; skips need an explanation. Only the documented macOS native-policy warning is admitted. |
| F11 residue | Output-cap help includes API/local and Grok subscription routes. |
| Release admission | Require the application version and complete supported archive basenames, architectures and libc suffixes, both exact sidecars and no extras. Wrong-version/prefix/architecture controls are refused. |
| Release guard | Tie mutation guards to their named steps, require global read permissions and admission before create/upload, and refuse other publishing commands. Negative controls weaken each property. |
| Notes and inventory | Render links against the actual stable/RC tag. State that sidecars are separate assets. Inventory both workflows and the shared native policy; explain Transport's deliberate default overload. |
| Stream diagnostics | Withhold arbitrary prose but retain safe message identifiers and error codes. Positive controls reject an always-empty filter. |
| Active cancellation | Observe a granted shell actually running, cancel it, require unchanged grants and a started-effect receipt, then reuse both grants. The pending-approval test remains. |
| Protected paths | Report the overlapping system or credential/state category without account-specific paths. |
| Pre-existing short MCP values | Reproduce the `DEBUG=1` fingerprint collision and document the fail-closed limitation. All non-empty values remain private; no public-value exemption or weakened redaction policy is introduced. |

The actual measurement-launcher proof injects synthetic values for every registry
credential through a disposable owned service. Child output must contain only a
non-secret control value. All eleven OS checks pass with seven credential names
and zero inference requests, using the existing approved systemd facility.
Its [receipt](measurement.json) retains actual observed peaks and lifecycle checks.

The first focused run passed 95/97: two new assertions incorrectly assumed where
doctor stores its cause and which startup layer reports a missing key. Corrected
assertions check the actual summary and startup layer; the terminal test separately
exercises the real adapter text. The second run passed 126/127 (11 excluded): a
new release negative control raised MatchError instead of the asserted policy
failure. The guard now asserts command presence before comparing positions.
These failed iterations remain failures; no existing assertion or product timeout
was removed.

The final [focused receipt](candidate-verification.json) records 128 passed,
11 excluded, seed 397392, 96.8 seconds. It retains the earlier failed iterations.

Final focused, full native-inclusive, installed and hosted results are pending.
Candidate `b7d3bce` passes the installed archive proof. Its local preflight and
both hosted matrix jobs fail formatting in one new release-policy control, before
the full suite runs; the draft job is skipped. The correction changes whitespace
only. Those failed gates are retained, and baseline verification restarts at the
subsequent revision.
No tag/release creation, publication, new browser authorization or live inference
is part of this correction. Assisted Linux qualifications, missing human macOS/
upgrade walkthroughs, stable publication, Grok live access/registration and Gemini
foreign-history live acceptance remain open.
