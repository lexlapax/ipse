# Document parser component and integration receipt

Date: 2026-10-26. Historical implementation evidence for P31; current operator
and developer procedures belong to the [operator](../../operator/index.md) and
[developer](../../developer/index.md) manuals. Scope and acceptance remain in
[the plan](../../plan.md); this receipt supplements the [baseline](baseline.md).

## Implementation and dependency decision

Text/Markdown and DOCX orchestration live in the knowledge extension. ZIP central
and local structures, expansion, member paths and XML bounds are validated before
xmerl parsing; external entities and declarations refuse. xmerl is the existing
OTP application, now explicitly included in the release. Maintained package
investigation and the initial implementation are recorded in commit 68d116b.
The DOCX follow-up and immutable `ipse-documents-v2` recipe are separately reviewed
by the root agent; this receipt does not independently qualify those changes.

The optional PDF helper uses exact lopdf 0.46.0 without default features. Its
Rust floor is 1.88; the dependency-free host OS helper remains 1.85. The frozen
[60-crate inventory](../../../native/ipse-pdf/DEPENDENCIES.md) includes purpose,
source, license expression and upstream notice files. All added package
implementations are Rust. There is no external compression/rendering library,
model, executable discovery or runtime download. The retained alloc-stdlib
license compensates for the source package's missing notice, with exact upstream
revision documented in that inventory.

## Build, package and host contract

Source builds default to `IPSE_BUILD_PDF=0`; explicit
`IPSE_BUILD_PDF=1 ./dev/build.sh` builds the locked parser. Standard
`./dev/package.sh` defaults to parser enabled; explicit `IPSE_BUILD_PDF=0` produces
a parser-free bundle and removes stale generated artifacts before compilation.
Installed parser-enabled users receive helper and notices and need no compiler.
The credential-free demo remains independent of parser availability and models.
CI/release workflows mirror optional build, native tests and source/installed
fixture proofs. No live inference or private qualification fixtures were used.

The host registry returns compile-bound bundle identity and adds protected
operator-home staging authority through `/2`. Before helper bytes or execution,
`/2` creates a single exclusive zero-byte probe inside the validated 0700 home,
checks its retained-FD owner against the home owner, rechecks home/probe inode
identity, changes the empty probe to 0600 and identity-checks its removal. It
writes no content and creates no directories. Private directory access protects
the empty inode before chmod; kernel FD ownership establishes UID. The descriptor contains `path`,
`sha256`, `uid`, `workspace`, `staging_root`, and `copy_helper` with its own `path`
and `sha256`. It accepts no environment override. Bundle paths derive from the
loaded host BEAM; prepending an artifact directory named `ipse-*` must not change
helper selection through Erlang's application-directory naming cache. The
extractor needs the complete host descriptor; a model-supplied path is no grant.
PDF selection remains off by default even in parser-enabled packages.

Four persistent protected slots admit work before source IO. The existing OS
copy operation uses retained no-follow/nonblocking descriptors and exact byte
bounds; a private 0600 snapshot is hashed, changed to 0500 and executed. Original
source replacement cannot change executed bytes. At most four 32-MiB images
(128 MiB) are admitted outside the knowledge collection's separate 64-MiB budget.
The guardian requires parser readiness before input, actual supervisor exit and
confirmed lease quiescence before cleanup. Unknown copy/probe termination or VM
crash leaves a quarantined slot; retained lock inodes are never removed. This is
the protected-host/cooperative-same-UID boundary, not protection against arbitrary
hostile unsandboxed code running as the operator.

The native supervisor forks the admitted image directly before any threads,
retains its lease in the child, enforces CPU four seconds/address space 384 MiB/
core zero, and verifies a larger allocation fails. Parsing has a five-second
job deadline and nonblocking final output a six-second total envelope. No
resource-cap relaxation occurs. Linux behavior is observed; macOS must either
pass its own enforcement tests or return explicit backend-unavailable. No local
macOS, real document quality, OCR, table-order or multi-column claim is made.

## Audit failures retained and repaired

The independent foundation audit first found pathname hash-to-exec and native
current-executable reopen windows. Verified private snapshots and direct fork
replace those paths. It subsequently found blocking final stdout, a final pipe
drain race, nested attachment omission, lopdf page-tree iterator truncation,
pre-ready lease cleanup, source FIFO substitution, pre-admission image allocation,
and unknown lease-probe lifecycle ambiguity. Focused regressions cover these
cases; unknown startup/probe state fails closed within four slots. The audit also
required bootstrap protection before UID execution; registry checks precede the
first bootstrap read/exec. Full findings remain in
[the foundation audit](foundation-audit.md), including DOCX fidelity repairs
owned and reviewed separately.

## Verification

The native suite passed three unit and nine subprocess protocol tests on Linux:
actual extraction, explicit empty/encrypted/embedded/malformed/limit outcomes,
page-tree validation, kernel resource enforcement, stopped/owner-loss cleanup,
lease readiness and blocked output. No terminal PTY suite was run concurrently.
The source fixture proof passed with compiler/toolchain names unavailable on its
runtime PATH; its six checks cover artifact module hashes, Unicode text, DOCX
revision handling, PDF default-off/explicit extraction and 60-crate notices.

The focused parser/staging/build/release Elixir run passed 25 tests; the final
registry rerun passed 4 tests, including parser-free clean compilation. The
parser-enabled package built successfully; its installed proof passed the same
six checks with no runtime compiler on PATH, and its credential-free demo ran.
The documentation checker reported 476 Markdown files, 4324 local links and zero errors.
These checks ran against pending integration sources; they are not a published
release or complete P31 acceptance. Temporary logs are under `/tmp/ipse-documents-*` and
`/tmp/ipse-pdf-native-final.log`; these local logs are not portable evidence by
themselves. The root integration receipt owns whole-repository acceptance.

## Corrective authority and hosted-build follow-up

Root independently reproduced an OPC authority defect: a package could declare
`main.xml` as its main story while the extractor returned an orphan
`word/document.xml` as complete. Commit `ecaa001` requires the canonical internal
root relationship and Word content-type authority before extracting any text.
Optional styles/annotations also need their canonical part relationships. Missing,
alternate, external, conflicting or non-Word authority refuses; development
fixtures now construct real OPC authority rather than treating missing files as
complete. Bounded style inheritance excludes hidden runs or refuses ambiguity;
visibility-bearing default character styles are conservatively unsupported.

The DOCX author suite passed **22 tests**. Root separately reviewed body/style/
relationship/content-type code and ran fresh canonical Unicode/hidden controls,
three alternate/external target controls, missing-root and non-Word-type controls.
They passed after repair. These are independently authored synthetic checks;
real Word fidelity and held-out retrieval quality remain open. The rebuilt
document artifact's source proof passed all six checks with the runtime toolchain
absent and PDF resource enforcement available on this Linux host.

The hosted `497a947` [run](https://github.com/lexlapax/ipse/actions/runs/40423458687)
failed on both platforms during build: Cargo's fresh-cache diagnostics, including
ANSI bytes, were merged into metadata JSON. The builder now captures stdout as
the JSON channel and leaves stderr as diagnostics. It never strips a diagnostic
prefix to accept malformed metadata. A fake-Cargo regression sends colored
stderr alongside valid JSON and verifies success; invalid stdout still refuses
before artifact creation. The four-test build suite passes after correcting an
environment-list fixture error. Hosted rerun and the final fixed-source/package
baseline remain separate evidence. Raw private logs include
`/tmp/ipse-parser497-hosted-failure.log`,
`/tmp/ipse-pdf-cargo-diagnostics-final-tests.log`,
`/tmp/ipse-docx-root-authority-audit-final.log` and
`/tmp/ipse-docx-root-source-proof.log`.
