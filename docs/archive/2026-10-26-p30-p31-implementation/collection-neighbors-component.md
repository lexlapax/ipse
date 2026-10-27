# Native-confirmed Collection neighbors and shared observation limits

Historical component receipt, **2026-10-27**. This generic Core increment adds
bounded directory references to the existing Collection read view. It does not
implement managed metadata adoption, current eligibility or an SDK operation.
The [persistence chapter](../../developer/persistence.md#read-several-collection-pages-under-one-validated-index)
owns current usage; the [plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance)
continues to record the incomplete milestone.

`Collection.Directory` uses opaque OTP `gb_trees` APIs for a canonical ordered
key directory. `Collection.view_neighbors/2` accepts a closed prefix/fence/needle
descriptor and returns predecessor, selected lower fence and two successors,
with actual revision/hash/length/operation-ID metadata and no object values.
It checks the whole matching prefix, its zero sentinel and cached integrity,
then rechecks the actual native root and final owner/release/cache completion.
Native-confirmed absence remains explicitly uninitialized; a materialized root
without its sentinel refuses. References establish no managed-record authority.

Read views now share a **512-observation-unit** allowance alongside their
existing 512-call ceiling: requested key count for get_many, requested limit for
scan, and four for neighbors. Short/empty results and failed checks receive no
refund. Existing lifetime, cache, ownership and reply bounds remain. Integrity
checks still examine the full key directory and matching references; this is
neither whole-call logarithmic complexity nor a process-memory bound. The
existing managed-publication 32-read closure has not adopted these helpers.

## Qualified author graph

The sole qualified graph is `/tmp/ipse-neighbors-rootcheck-e12d8993c99f00ef`,
compiled from its private project cwd: **130 source files**, warnings as errors.
Its 2,312-file source/runtime manifest has SHA256
`889940cafbe726c0cb8b227d952acae603c9379a0ba67f7dfe9294cfd1ca5c3f`.
Every declared input remained exact after focused/broad tests, the manual
exercise and compatibility work. Git metadata and Mix's execution cache are
declared exclusions. Private helper selection was positively checked against
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.
The shared public helper was only hashed, never rebuilt or executed here.

- Focused Directory/neighbors/read-view/empty-view suites: **48/48**, seed
  20261113, max cases two; log SHA256
  `db8a2252e02d8ad5cbdd67543d4fba3884436dbbf8d3daec2f957606384b9733`.
- All 16 Collection test files: **157/157**, seed 20261114, max cases two,
  325.1 seconds. This includes existing mutation, migration, SDK, normalizer,
  planning, policy, encoding and block tests.
- The exact rewritten public Collection example passed with isolated synthetic
  state and the actual private runtime/native helper.
- Actual Elixir 1.18.5 and 1.20.4 formatting passed for the six source/test files.
  Elixir 1.18.5 compiled three source files/four modules with no diagnostics.
  Both used OTP 29; no actual OTP 27 execution is claimed.

The whole developer persistence and operator recovery chapters were reviewed.
The persistence rewrite integrates operation choice, ownership, native checks,
resource costs and a runnable example, and distinguishes generic metadata from
the future managed adapter. No operator command changed.

## Preserve earlier errors separately

Historical `/tmp/ipse-collection-neighbors-20261027-01` compiled from the wrong
cwd and resolved the shared helper alias. It ran no tests and is unqualified.
Historical `...-02` had an earlier 41-test log, but a Root orchestration guard
failure was incorrectly followed by an unnecessary dependent recompile,
overwriting its unsealed BEAM graph. Neither checkpoint is substituted for the
fresh manifest-bound graph above. Shared helper bytes were unchanged.

Earlier pure 7/10 then 10/10 logs retain a lowercase-hex fixture correction,
without an exact saved before-source claim. The first 1.18 compatibility driver
failed to expand a quoted Erlang code-path wildcard; the second loaded target
BEAMs and produced four redefinition warnings. The final driver materialized
dependencies excluding those targets and compiled with empty diagnostics.
All those errors and corrections remain author evidence, not passing receipts.

## Independent closure and durable provenance

The [independent audit](collection-neighbors-audit.md) found no actionable defect
within trusted Core/cooperative storage: unchanged **48/48**, fresh **15/15** plus
one controlled exact-deadline case, and the exact public example passed.
It checked all 2,312 owner/private/durable inputs without rebuilding BEAMs.
The durable owner-only evidence directory is
`p31-verification/independent-collection-neighbors` under this task's artifact
root; its report includes the full absolute path and replay instructions.
Its 2,401 payloads include 31 separately labeled author artifacts and diagnostics.

| Retained item | SHA256 |
| --- | --- |
| Original independent REPORT.md | `65fcd2c31944d94869226bd83fd0a4d657ad9ef35116dc430dd0515fe3204f50` |
| files.sha256 | `74a7a059d9c104f2657809bed89ca8f22717920799e4da13a02f432d7f356739` |
| provenance.json | `fb2f952cc3ff1e644804dad291e59957e57a5aa1e211f493cf12467f1c1bf665` |
| preservation receipt | `a80ec151b7572380b3b6d66b4ad1ee3b68ffdbe8b42873fcddda53d601267545` |

No native product source changed. Tests used this Linux host and synthetic
private storage only. This receipt supplies no full-suite, installed-package,
macOS/human, source-authority, model-quality, sustainable managed capacity or
whole-milestone acceptance.
