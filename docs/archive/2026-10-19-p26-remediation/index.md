# P26 review and remediation, 2026-10-19

Historical investigation and review record. Remediation is in progress; no new
completion verdict is established. Current user guidance is in the
[memory manual](../../operator/memory.md), contributor guidance in the
[memory training chapter](../../developer/memory.md), and acceptance status in the
[plan](../../plan.md#p26-optional-working-and-long-term-memory).

The [first external review](review-1.md) targets
`10b9dd66d06ef28718b58530a7e5b01c7c50397a`. The original report was supplied as
`/tmp/ipse-p26-review.md`; its body is preserved unchanged with an archive preface.
The reviewer removed their scratch probes and detached worktree. Their package,
native and hosted-log verification limits remain part of the record.

The user authorized P26 remediation and repeated external review as needed,
followed by P27 remediation/completion with similar review. P27's interrupted
comparison stays preserved in its [continuation record](../2026-10-19-p27-knowledge-packages/continuation.md).

Before requesting external re-review, the user required an internal adversarial
review and repair. Its [frozen scope, findings and lead judgment](internal-review.md)
are recorded separately. Three source-reachable edges and one root-observed
missing-target outcome reproduced as five failing regressions, including actual
fixture-model disclosure. Repairs pass 29 focused memory/Session/binding/scan
tests in 12.3 seconds. The earlier full baseline passed 1,150 tests with 32
exclusions in 681.9 seconds; it predates these additional repairs and cannot
replace their refreshed verification.

## Accepted issues under repair

| Finding | Required result | State |
| --- | --- | --- |
| Model inspection exposes expired/dependency-blocked text | Metadata-only inspection outside the same visibility policy as recall, with stable generation and no hidden writes | Failing-before regressions reproduced; first focused repair checks pass |
| Export changes recoverable blocked notes into permanent suppression | Faithful current-record backup/restore with explicit expiry behavior and unchanged suppression priority | Export mismatch and expired-import refusal reproduced; handler and real Session restore checks pass |
| Collecting a missing source crashes the worker | Bounded `not_found`, no write or suppression, and a usable Session afterward | Handler regression reproduced; handler and real Session continuation checks pass |
| Scope ceiling mismatch is admitted; test name overclaims | Refuse incompatible selected built-in scope at admission, cover the actual mismatch and valid configuration | Failing-before regression reproduced; first focused repair checks pass |

The observation that forgetting an absent ID creates permanent suppression is
existing intentional behavior. Its quota and typo consequences need an explicit
operator explanation. No finding is closed by documentation alone.

Initial local verification used macOS arm64, Elixir 1.20.3 and OTP 29. The first
four regressions failed before repair; an additional direct expired-text assertion
also failed. The first inspection/collection/admission repairs passed the four
focused memory/Session/binding/scan files, 23 tests in 5.7 seconds. This is not a
full baseline, installed proof, platform matrix or external acceptance.

The user explicitly selected exact record preservation for backups, including
expired notes. Export no longer converts active records into suppression. An
approved import may restore an expired record without changing its expiry; model
reads still hide it and later writes cannot renew an expired target. Existing
suppression remains permanent and has priority on import.

The restore-fidelity regression first failed because export rewrote record values.
After removing that conversion, it failed at the expired-import boundary with
`source_expired`. Both boundaries now pass, including exact re-export and matched
later visibility/update behavior in live and restored stores. The final focused
memory/Session/binding/scan run passes 26 tests in 9.9 seconds. Real Session cases
inspect expired, orphaned and transitively blocked notes from a fresh model
conversation, verify a readable control, continue after missing-source collection,
and restore a blocked child before its parent arrives. Full refreshed verification
and external acceptance remain open.

## Corrected local verification

The final runtime source is the third internal review's frozen tracked diff. The
following checks ran after its expiry and migration repairs on macOS arm64,
Elixir 1.20.3 / OTP 29:

| Gate | Actual result |
| --- | --- |
| `./scripts/build.sh` | Passed |
| `mix format --check-formatted` | Passed with local 1.20.3 and CI-floor 1.18.5 formatters |
| `mix compile --warnings-as-errors` | Passed |
| Five focused State/memory/Session/binding/scan files | 41 passed, 19.6 seconds |
| `IPSE_TEST_STDIO_PROBE=1 mix test` | 1,160 passed, 32 platform exclusions, 676.3 seconds |
| Standalone macOS Rust policy tests | 4 passed; one existing unused-function compiler warning |
| Explicit macOS sandbox, stdio and filesystem subset | 30 passed, 6 Linux exclusions, 24.3 seconds |
| `mix run scripts/measure-memory.exs` | Passed, 100 records/100 queries, six sessions/two projects, zero encoder/model calls |
| `./bin/ipse demo` | Scripted demo passed; no live model-service verification claimed |
| Fresh `scripts/package.sh` and bounded `scripts/verify-package.exs` | Passed, including installed memory corpus, isolated HOME/IPSE_HOME and utility-only PATH |
| Literal operator-manual example proof | Exact JSON configuration and eight CLI commands passed in isolated HOME/IPSE_HOME with the demo provider and explicit fixture `--yes`; remember, recall, inventory, forget, collection and suppression export checked |
| CI policy and documentation checks | Passed; handoff checks cover 241 Markdown files and 2,632 local links with zero errors |

Source and installed lexical corpus SHA-256:
`3f11a10a4364b2ba4ae652a82ba14111e3dc88bec2387291df445334b8cca77c`.
Both report Recall@5 and exact-span precision 1.0, no model dispatch and no model
cost. Source p50/p95 were 244,102/247,626 microseconds and observed VM bytes
82,143,643. Installed values were 248,155/260,812 microseconds and 77,869,459 bytes.
These are synthetic lexical measurements and VM samples, not semantic quality or
peak-memory claims. nDCG@10 is unmeasured because this tool returns at most five.

The tested fresh macOS archive SHA-256 is
`87a4d7196e31a12f083675c4f045416ab4736aae6874c44d8cb7e5cd01d50d26`.
It was built from the reviewed runtime source before this final receipt update;
the later documentation commit does not change those runtime sources. The old
local archive was preserved as an ignored owner-only copy at
`.ipse/continuations/p26-pre-remediation-package/ipse-0.1.0-darwin-arm64.tar.gz`,
SHA-256 `d5d2517e87cf358cfe6b6d82060719e6be52ce0e5fcf7920fc4729df7d5c8a4f`.
Neither archive is a published release or committed private payload.

## Linux verification and review handoff

The user authorized Linux exclusions on `lexlapax@serenity` at
`~/projects/lexlapax/ipse`. Verification ran in the isolated detached worktree
`/tmp/ipse-p26-b1dc820-Xiuxg2/source` at exactly
`b1dc82094afdae8708cdb45dea16beb6c948f88b`. The main checkout remained at
`d300b68`; existing processes and unrelated worktrees were left untouched.
The host used Arch Linux, Elixir 1.20.4 / OTP 29 and Rust 1.99.0.

Build, format, strict compilation, documentation checks, the full suite and the
scripted demo all passed. The suite included `native_sandbox` and excluded only
the `macos_sandbox` and `macos_filesystem` tags: 1,177 passed, 15 excluded in
617.4 seconds. Documentation at the candidate checked 240 Markdown files and
2,626 local links with zero errors. Logs remain outside the source worktree in
`/tmp/ipse-p26-b1dc820-Xiuxg2/`, named `build.log`, `format.log`, `compile.log`,
`docs.log`, `test.log` and `demo.log`. This run did not build or verify a Linux
package.

The automatically triggered [candidate GitHub run](https://github.com/lexlapax/ipse/actions/runs/39295194794)
was still running when the local and Serenity checks finished. It adds supported
Elixir 1.18 / OTP 27 compatibility coverage; both local hosts used 1.20 / OTP 29.
Its completion is not required before handing the candidate to the external
reviewer. A pending run is not a passing result, and any later failure still
needs investigation.

The [external re-review request](external-review-prompt.md) pins corrected candidate
`b1dc82094afdae8708cdb45dea16beb6c948f88b`. It follows the completed internal
review/repair and local platform checks. External acceptance remains open.

## Second external review and follow-up

The user supplied the [second external report](review-2.md) from
`serenity:/tmp/ipse-p26-review-r2.md`. It accepts the candidate's P26 code scope
subject to one low-severity receipt correction and the unresolved hosted gate.
Its independent Linux full suite passed 1,177 tests with 15 exclusions, and its
Linux package build and extracted-package checks passed. These are the reviewer's
receipts, distinct from the root's earlier source-only Linux run.

The failed-deadline validator accepted a receipt naming the failing operation as
the previous writer. Adding that tamper case to the existing State test reproduced
the defect: zero of one selected tests passed. The validator now requires a
different previous operation ID, and all seven State tests pass. Refreshed full
verification remains required. The manuals also explain that an approved
newer-generation import may replace a live note with an expired record or a
version-one record, making it hidden immediately or until migration respectively.
The developer test instructions now include the generic State receipt tests.

Hosted run `39295194794` is terminal and failed `mix test` on both jobs.
Ubuntu timed out in the seven-variant suppressed-source fixture; macOS also timed
out in the CLI freeze fixture. Later steps were skipped. The reviewer observed
the same seven-variant timeout at pre-repair revisions `a3007ee` and `8183920`.
That establishes an inherited failure, not a passing gate. No waiver has been
granted. Investigation retains the existing 60-second test deadline, assertions,
cleanup and runtime authority boundaries.

The [follow-up investigation and internal review](review-2-follow-up.md) records
the before/after receipt check, measured fixture work, assertion-preserving test
separation and the initial focused review. At the user's clarification, a fresh
three-reviewer panel then challenged the entire P26 milestone, including unchanged
implementation; all returned PASS with no actionable findings. The explicit
60,000-ms focused run passed 60 tests in 207.0 seconds. Build, both formatter
versions and strict compilation pass. Full baseline, refreshed native/package
checks and a new hosted candidate remain pending.

## Prior hosted evidence audit

During remediation, the final step metadata for prior P27 source
`8183920ebdce0d8fcc03abdcb8f41d57849163cb`, run `39275849251`, was read again.
Both jobs are terminal. Ubuntu failed at `mix test` and skipped subsequent gates.
macOS completed every applicable build, test, native, package and independent
proof step successfully, including the previously pending knowledge and sandbox
steps. This closes that old metadata-observation gap. It does not verify the P26
repairs or explain the Ubuntu test timeout saved in the P27 continuation.
