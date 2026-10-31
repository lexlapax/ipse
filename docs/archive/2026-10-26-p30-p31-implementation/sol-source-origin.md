# Original journal identity integration, 2026-10-28

Historical verification of an uncommitted integration prototype. The
[plan](../../plan.md) owns current milestone status. Read
[persistence training](../../developer/persistence.md#separate-reconstruction-from-recovery-io)
and [operator recovery](../../operator/recovery.md#resume-compatible-work) for the
working behavior and its limits. This is not current managed recall, final P31C0
acceptance, or production platform qualification.

## Bind an actual new journal

Fresh Session creation requests `journal_origin_v1`. Journal records the
canonical directory, Session ID, device numbers, inode and UID obtained from the
newly opened file before writing its first header. Locked resume checks that
binding before tail repair. Writer independently validates its own descriptor
before accepting the file, and accepts a SourceWindow only when its origin
digest matches. Source queries check file identity, protection and expected
length before returning cached facts.

SourceIndex derives each bound source version from the recorded origin digest
and its historical content/provenance version. Rebuilding the same source gives
the same version. Another origin cannot revalidate it. Worker proof fields keep
their existing shape and do not disclose the private path. Legacy histories keep
their historical version rule and gain no origin on resume. Legacy collection
inspection remains available; source-bound publication refuses rather than
manufacturing authority from old receipts.

This uses existing OTP file metadata, retained advisory ownership and the existing
SourceIndex version/receipt projection. It adds no registry, runtime dependency,
automatic source relocation or legacy adoption. Copies remain readable for
diagnosis, but a copy, move or replacement cannot reopen as the original source.
A canonical directory alias can still designate the same original file.

The boundary is cooperative storage and trusted host code. It does not defend
against arbitrary same-user rewriting of both content and recorded facts. It
does not supply cross-Session lookup, current eligibility, source leases through
use/egress, attribution of quoted prose, withdrawal, proposal acceptance, or an
inference barrier. Those remain required integration work.

## Controls actually run

The isolated `_build/source-origin-sol` graph uses the same explicitly test-only
kernel override as the [native recovery regression](sol-recovery.md), not a new
production admission. Strict compilation of 155 modules passed; after the final
Writer change its changed module compiled strictly and matching inert bundles
were rebuilt. Test scratch was outside the graph in a private Btrfs directory.

The first focused selection, seed 46693, passed 93 of 95 tests. Both failures
showed that the origin guard refused legacy inspection before the fixture could
reach its managed commit. The guard was narrowed to managed publication and
other proof-bearing collection requests. The actual saved-consent publication
file then passed all 28 tests, seed 46694. A further Writer control refuses a
window reconstructed with a legacy or foreign origin before accepting the actual
window. The final seven-file selection passed **all 96 tests**, seed 46695,
max-cases 1, in 109.5 seconds, with exit 0.

The selection covers Journal creation/quotas, actual Writer and Session recovery,
original/copy/replacement checks, unchanged copied torn tails, source-window
identity matching, stable origin-bound versions, stored-proof mismatch, and
actual legacy/current saved-consent publication with metadata versions 2 and 3.
Fixtures use synthetic inputs and grants; no live model, paid account or device
fault was tested. Formatting and a credential-free demo with a fresh private
Ipse home also passed. No operator configuration was loaded by that demo.

The graph's **post-run** source-index tree is
`2c2c406a47c555cf47e2235a7ec448c64d007266`. A refreshed private index matched
the graph; this is a recorded source identity, not a claim of pre-run sealing.
The full regression of 2,883 tests in the recovery record predates this work.
No full suite, production-profile build or installed package containing this
integration has yet been verified.

| Retained evidence | SHA-256 |
| --- | --- |
| [Initial failed selection](sol-source-origin/initial-46693.log) | `fe70bdece77ccd1ee502d669183a3e0a7cc73fee44e176509f7b15cf70cf0c6b` |
| [Publication rerun](sol-source-origin/publication-46694.log) | `2bf1fa54ca793bd299b79309e92638f5fdcf5bb1e739f90be956e3dbe41b29d0` |
| [Final 96-test selection](sol-source-origin/final-46695.log) | `6608883d8ff2365eab3230592f2879945be625c0a7b40b7cf54f758cbe65f747` |

The [compile log](sol-source-origin/compile.log),
[matching bundle output](sol-source-origin/bundles.log) and
[isolated demo](sol-source-origin/demo.log) are also retained. Source identities:

| Source | SHA-256 |
| --- | --- |
| `lib/ipse/journal/source_origin.ex` | `adec1244c5a0a4b66e41c2571ac62172a2a6a170f425d874df015fa7ffac53fb` |
| `lib/ipse/journal.ex` | `6d44a70ffc3b7b92a112793043d892740619c808b810244455197f55514aa3ef` |
| `lib/ipse/journal/writer.ex` | `b0228e1f77677553e860419a8c2693cc5b0a464d142fab4e7bca579499fc874e` |
| `lib/ipse/session.ex` | `e1901648777608a47e64e75365e9a483c06f9f2311b665ffc016144f26d67699` |
| `lib/ipse/session/source_index.ex` | `7732a77ff674ecd6d5a0014dd35f85a85452691c3d31467e47cf3a3eaeaeb88a` |
| `lib/ipse/session/source_window.ex` | `b1311b7bd63e385d5762730d7d72afa508845d00b9dc0582535641c174bb36da` |
| `test/ipse/journal/source_origin_test.exs` | `05a01d2b8f7d48048f9dcf0e5d217ec07420505157246d15f271496bdb7afc03` |
