# Isolate synthetic conformance instructions

Historical investigation recorded on 2026-11-05. Its outcomes describe this
checkpoint, not the current package or installed-runtime status. Source provenance
is the default PDF-enabled package at `d0a3ca758c76c3217e769e129676ff3e88209d42`,
followed by the two-owner repair to `lib/ipse/extension/conformance.ex` and
`test/ipse/extension/conformance_test.exs`; exact source and evidence digests are
in [safe-result.json](safe-result.json). No previous manual body was copied.
Use the current [operator extension procedure](../../operator/extensions.md),
[conformance training](../../developer/extensions.md#turn-the-behavior-into-a-conformance-scenario)
and [test isolation guidance](../../developer/testing.md#isolate-subprocess-inputs-and-shared-resources)
for supported instructions. The [plan](../../plan.md) owns current acceptance.

The default PDF-enabled package built from `d0a3ca758c76c3217e769e129676ff3e88209d42`
failed its official bundled verification at the extension conformance hook case.
The synthetic case made no model request and recorded one transform before an
error; it expected one request, two transforms and the unchanged wrapped answer.
Confirmed process cleanup and valid saved journals did not make that case pass.
The archive's failed verification remains historical evidence.

A separate `keep: true` diagnostic on that exact extracted runtime established
instruction pollution: its temporary workspace was below the checkout and
inherited ten ancestor instruction sources. They contained 119,421 content bytes
and 122,687 formatted bytes, exceeding the unchanged 65,536-byte context budget.
Automatic compaction was disabled. The diagnostic exited zero because it retained
its evidence, not because conformance passed. No raw instructions, journal,
transcript, credentials or authorization code are included here.

The repair adds a valid fresh workspace boundary through a private `.git/HEAD`,
using the existing Workspace fixture contract without invoking Git. Caller
ancestor guidance is excluded; declared local guidance is retained. It changes
neither context limits, expected request/transform counts, final text, approvals
nor deadlines. The matching test first proves that oversized parent guidance
would be discovered, then checks the ordinary synthetic hook case and exact local
snapshot under the isolated boundary.

Verification outcomes are recorded separately in [safe-result.json](safe-result.json).
The initial main test launcher used `--no-start` and failed 11 of 12 cases because
required application supervision was absent. That invalid setup aggregate remains
failed. A separate ordinary-start single case passed; it overlaps the later full
file and must not be added to that total. Temporary diagnostic instrumentation
was removed and the production owner was recompiled with warnings as errors.
The normal-start full file subsequently passed all 12 tests in 3.7 seconds with
exit zero confirmed by the parent. A separate process/Input neutral check was
not part of that receipt. A fresh package build and official bundled verification
must qualify the repaired installed runtime separately; neither is implied by source
tests or the earlier successful package build.

This is a synthetic harness correction. It does not establish live provider
access, model answer quality, full Word fidelity or the installed 24-case Word
journey. The safe result pins both the historical two-owner source proposal and
the formatted production and test owners without exporting private logs or code.
