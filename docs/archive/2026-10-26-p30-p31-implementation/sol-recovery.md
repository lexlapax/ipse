# Owned staging inventory recovery, 2026-10-28

Historical implementation and verification record. The [plan](../../plan.md)
owns current milestone status; [native storage guidance](../../../native/README.md#inspect-protected-storage-allocation)
and [persistence training](../../developer/persistence.md) describe current
behavior. This increment does not admit a new kernel or complete P31B.

## Serialized migration retry

No earlier test or capacity process remained at resume. The two cases that had
timed out under four overlapping full suites were run alone in the frozen
`_build/planning-preexit-audit` graph, seed 46684, max-cases 1. Both passed in
305.6 seconds, with twelve nonselected tests excluded. The graph uses the
explicitly test-only 7.2.11 helper. This supports contention as a contributor to
the earlier failures; it does not establish that no other timing defect exists,
or turn the interrupted full runs into passes. The next full regression must run
without a competing suite.

The retained [serial log](sol-recovery/migration-serial.log) SHA-256 is
`81dbdf0f53920e7ee0950613e325ff322842e7740428553f402faffbdceaf1bd`.

## Settle retained stages before counting them

The native transaction owner already holds the logical lock and all scope writer
leases while measuring allocation. Its inventory previously counted a retained
`.pending-` file immediately, even when the previous owner had died before the
stage's final sync. The owned inventory and quota preflight now sync retained
staging files, re-read their descriptor metadata, and validate identity,
permissions and unchanged length before counting their blocks. A failed sync
refuses the inventory; it preserves the stage and grants no admission or replay.
Standalone allocation inspection remains a read-only observation.

This adds no helper-selection flag or runtime dependency. It preserves existing
namespace, count, traversal and quota limits, writer leases, and the production
kernel/filesystem allowlist. It does not prove the complete Btrfs allocation
bound, failure reclamation, power-loss behavior, running-kernel provenance, or
the available host's production admission. Those qualifications remain open.

## Controls and limits

A private native fixture replaces storage `sync_all` returns with an injected
error after calling the real sync. On the old source, the owned inventory still
returned success for a retained staging file; the expected-refusal test failed
(46685). On the repaired source it refuses, preserves the bytes and lock, and a
new owner using the ordinary helper can inventory and reclaim the stage. The
same fault fixture verifies that standalone allocation observation succeeds
without requesting staging synchronization. This is syscall-result injection,
not an actual Btrfs writeback error or device fault.

The final fixture supplies a deliberately synthetic zero file/directory allowance
so the admission error path can be tested without a supported filesystem profile.
Against the old native source, preflight incorrectly returned success (46689).
The repaired source refuses preflight and staging, creates no new stage, and
retains the interrupted file. This test fixture bypasses only the allocation
profile for that negative control; it grants no production admission and supplies
no evidence of a physical allocation bound.

The transaction suite passed 22 tests (46686), then 22 after the final controls
(46688), then 22 with the quota/staging controls (46690). A strict standalone
Rust test compile first reported that splitting the
standalone read-only path left `transaction_usage` unused in that test build.
A positive native interrupted-stage inventory control exercises that path;
the strict compile and nine native tests then passed without suppressing the
warning. A separate 22-test run (46687) preceded the final standalone-observation
assertion and is not the final test source.

| Evidence | SHA-256 |
| --- | --- |
| [Expected pre-fix failure](sol-recovery/inventory-before.log) | `6e5a239008882cf3e78c818322b4567e12cd38871eaa8b96febce1c5d3ee070a` |
| [Transaction suite before quota control](sol-recovery/inventory-after.log) | `176d2f6c7826a89109ee3c912c84e77567375bdce82db3d4d5badecd26fca18f` |
| [Expected old-source quota failure](sol-recovery/quota-before.log) | `5a36bd58e0f6a4fc6f6a02307a2f7c211d1bc0e99e0e14e58a2257aa240b6c42` |
| [Final quota and transaction controls](sol-recovery/quota-after.log) | `c97b0d57894e9e4d6f463ae1f5c5c81446aaaf3ff2aebaf6a2284a99afc858cb` |
| [Native storage tests](sol-recovery/storage-native.log) | `117485b0c9ec25d250f1b81850b71163a704bd6210684bad5064df255a3a72ab` |
| `native/ipse-storage.rs` | `d541df861de0d6d6271a608cbf8e4c882ede90ff8e21577d26f8ae0a2869b200` |
| `lib/ipse/runner/transaction.ex` | `95b9001f84a997af8c19dc82d7e5f70fb06ec594afec34ebc2299f38569deb9e` |
| `test/ipse/runner/transaction_test.exs` | `966b3f45466cb724a2f942da2c1115badc38a85dd01135422a43cb5d54ccff0e` |

The retained native harness log omits its final empty line. Its original output
SHA-256 was `33cdac3723eb2a441f0ad77ee94fb49407677b48ea92bd04d7709e3e7d9234d8`.
The source hashes identify the recorded increment, not a released artifact.
One full regression ran alone in `_build/sol-recovery-46691` (seed 46691,
max-cases 2), after strict compilation and matching inert bundles. It passed
**2,883 tests with 36 excluded**, in 2,027.8 seconds, with exit status 0.
The retained [full log](sol-recovery/full-46691.log) SHA-256 is
`62916efabf4f20e14dea0f90af822633498267c6995febddcf97e12d18cc7357`.
Its private
test source tree is `916b04052a8c142d1c7c9a508148361e46e9a006`, and its
production-profile tree is `cccd73a818b10c66d5046be41e524f16f7c5efea`. Its
helper SHA-256 is `86d6226c868b7095c6ba7460cc0b42832e98fb70feea0779fb3473ac7bb28a6a`.
The source index had no changed files after the run. It used the explicitly
test-only kernel override and does not qualify production storage on 7.2.11.
The later journal-origin work was absent from this frozen run. Source-currentness,
protected inference delivery, sustainable capacity and the installed notes
journey remain separate open work.

## Isolated production-profile build

`_build/sol-native-production` was populated from source base
`668e6a3b0c04be7b5148f644ad8740ae493b72b0` plus this focused native recovery
increment. It excludes the other uncommitted P30/P31 implementation and the
new journal-origin work. The normal build passed strict compilation of 141
modules and rebuilt the helper and inert extension bundles. The sandbox's
initial Mix TCP-lock refusal was retried with permitted local access. The
transaction suite passed **22 tests**, seed 46692, max-cases 1, in 4.8 seconds;
format checking and the credential-free scripted demo also passed. The retained
demo used a fresh private Ipse home and loaded no operator configuration.

This helper uses the unchanged production profile, whose source SHA-256 is
`46ccb439014ff3d2eadde512be7ec8f4f471d0aa4df0652914e6278013c9ce3b`.
Its binary SHA-256 is
`506040d49070ddf4e3bb317f62df1fa6d58bc702f112da2e893e04aaedba71b8`.
The transaction controls cover generic retained ownership and the explicitly
synthetic fault/allowance fixture above. Passing them on this host does not
admit its kernel, prove a physical quota, or verify a complete protected notes
journey. No installed release was built or published for this increment.

| Production-profile evidence | SHA-256 |
| --- | --- |
| [Build](sol-recovery/sol-production-build.log) | `810f986f432b92160464fa2db63ef80e8e67456bf7bff063e742f10fedc54a9b` |
| [Transaction controls](sol-recovery/sol-production-transactions.log) | `c6ee8812f4cc5faff17bc995e3a938b0df1ea5ad6bb94edb1aaab574e5af9fc5` |
| [Scripted demo](sol-recovery/sol-production-demo.log) | `f9fa6d2d300613c335a8eab278a370006c7bce9ecd45c3c45951fe87ab3f6918` |

The affected native contract, persistence training, operator recovery and
knowledge-permission chapters were reviewed as whole documents. The isolated
increment's final documentation check covered 637 Markdown files and 5,214 local
links with no errors. The wider working-tree check covered 667 Markdown
files and 5,350 local links with no errors, with existing inaccessible synthetic
receipt-directory warnings preserved.
