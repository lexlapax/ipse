# P28/P29 second review and corrections

Dated 2026-10-24. This follows the [first audit repair record](../2026-10-24-p28-p29-audit-repair/index.md).
The [independent review](independent-review.md) is preserved as supplied by the
developer. It reviews `c2a19cb` and rejects the diagnostic repair despite green
automated checks. The [plan](../../plan.md) owns acceptance; the
[operator](../../operator/index.md) and [developer](../../developer/index.md)
manuals own procedures.

## Corrections

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

Candidate `b7d3bce` passes the installed archive proof. Its local preflight and
both hosted matrix jobs fail formatting in one new release-policy control, before
the full suite runs; the draft job is skipped. The correction changes whitespace
only. Those failed gates are retained, and baseline verification restarts at the
subsequent revision.

The requested [author adversarial review](self-review.md) reproduces and fixes two
further verification gaps: linked/empty/non-file archives and incomplete configured
doctor findings. Its [receipt](self-review.json) records 43 passing focused tests
and all twelve installed checks using the strengthened verifier. These additional
changes affect developer verification only; runtime and native source stay fixed.
A subsequent wire-format control found numeric OpenRouter stream codes were still
lost. The [parser receipt](numeric-code-control.json) shows `429` withheld before
and retained after repair, without private prose. The self-review records this
third finding separately; full runtime verification restarts for that text change.
A final cross-toolchain check found a [developer-verifier compiler defect](compiler-isolation.md):
the installed harness mixed a newer driver with older archive compiler libraries.
The repair uses the selected bundled compiler in a private environment. Its
[receipt](compiler-isolation.json) records 33 passing verifier tests and twelve
installed checks for each real toolchain, with failed fixture iterations preserved.
Product runtime and workflow source remain at `5d9650e`; the developer-tool
follow-up has a separate hosted verification scope.
No tag/release creation, publication, new browser authorization or live inference
is part of this correction. Assisted Linux qualifications, missing human macOS/
upgrade walkthroughs, stable publication, Grok live access/registration and Gemini
foreign-history live acceptance remain open.

## Final verification and release preparation

Final candidate `45cae30` includes the compiler-isolation follow-up. Its
[exact-source hosted rehearsal](https://github.com/lexlapax/ipse/actions/runs/40154297591)
passes on Ubuntu and macOS with Elixir 1.18 / OTP 27. Every ordinary CI step and
all independent installed/extension proofs remain in the matrix. Both artifacts
upload; collection and complete version/name/regular-file/checksum admission
pass. The tag-only draft-mutation and remote-inspection steps are skipped.
The [verification receipt](verification.json) and
[selected hosted summaries](hosted-summaries.json) keep exact sources, actual
counts/seeds, exclusions and failed/canceled runs distinct.

The [preceding runtime baseline](runtime-5d9650e.json) at `5d9650e` passes **1,783
native-inclusive tests, 0 failures, 19 excluded**, seed 392647, 1069.4 seconds.
Build, format, warnings-as-errors compile, docs, action policy and an isolated
demo pass. Host code, native helpers, configuration, dependency versions, release
workflow and packaging scripts are unchanged in `45cae30`; only the developer verifier, its test and corresponding
records/manuals differ. The compiled commit identity is expected to change.
The follow-up has 33 passing verifier tests and twelve installed checks for
each actual compiler/runtime family, with its failed iterations preserved.

The exact local `45cae30` archive passes all twelve installed checks, with
private homes, utility-only runtime PATH and unchanged inventories. Its
[actual CLI examples](installed-errors-current.json) retain precise configuration
causes, no misleading effect uncertainty and no session creation. Earlier
[B7](installed-errors.json) and [5d](installed-errors-final.json) examples retain
their original identities. The bundled floor runtime also launches on the local
Linux host and its repaired developer verifier passes; this is automated archive
coverage, not a new human walkthrough.

Both final hosted platform archives/sidecars and the local newer-toolchain Linux
archive are retained separately under `dist/release-readiness/45cae30`, with build
identity, checked runtime notice bytes and a rendered release body. The earlier
`5d9650e` rehearsal and files remain preserved. The
[release-readiness handoff](release-readiness.md) includes a review prompt and the
remaining tag/draft/inspection/publication actions. Its
[offline controls](offline-release-flow.json), with
[historical fixture source](offline-release-flow.exs), exercise unchanged workflow
shell bodies against a fake CLI, not real tag-push API/token permissions.

Independent acceptance, stable tagging/publication and recorded human/live
qualifications remain separate. No new authorization or paid inference occurred.
The private short-MCP-value collision remains documented; no privacy exemption
was introduced. Operator/developer chapters, release notes and entry points were
reviewed as whole documents and reconciled with actual verification.
