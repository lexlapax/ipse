# Frozen 478-file regression and separate fixture repairs

Dated **2026-11-04**. Historical engineering evidence for source
`18e3e0b199c25015426499cbec89a57d1d106ae1`. The [plan](../../plan.md)
owns current acceptance; [testing](../../developer/testing.md) explains supported
verification. This run remains failed.

The four terminal groups cover 478 test files: **4,048 passed, one failed, one
invalid, 131 skipped and 123 excluded**. All 44 source/runtime/helper integrity
checks pass, and no owned process remains. Nested test counts are not added.
The original safe aggregate has SHA256
`078aa09e3ece78de410a871255e9c464ff9ac7eb06bad4a23d2b9ed3f6977236`.

Two fixture setup defects explain the failed and invalid cases:

- The capacity source extractor copied an unrelated private fault-injection
  helper without its dependency. It now omits only that helper, preserving the
  complete seven-source inventory, six exact module origins and publication APIs.
- Research's standalone compiler inherited old fixture BEAM directories, causing
  module-redefinition warnings. Its child code path now excludes directories
  containing either exact fixture module before compiling a fresh fixture.
  Other runtime paths and strict warning checks remain intact.

The original pollution control reproduces both warnings; the corrected path
strictly compiles with no diagnostic. The corrected capacity source graph also
strictly compiles without starting a native helper.

Later current-main checks are separate: the complete capacity file passes
**21 tests in 5.5 seconds**. Both Research cases pass alongside two managed-output
root-change controls (**four selected cases in 34.8 seconds**, 200 excluded).
The Research pure case executes its own 23 controls internally; these counts are
not added. [Research lifecycle evidence](research-fetch-origin-lifecycle-20261104.md)
records its wider source and ordinary-State checks.

These later results do not change the frozen aggregate or establish a new full
baseline. A stable integration candidate still needs the complete source suite,
package/platform checks and final adversarial review.
