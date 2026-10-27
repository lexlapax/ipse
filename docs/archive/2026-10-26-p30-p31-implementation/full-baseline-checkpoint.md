# Frozen full test baseline and stopped environment mismatch

Recorded 2026-10-27. This receipt preserves Root's completed frozen baseline and
its intentionally stopped predecessor. It is **not** a pass for the latest tree
or whole P30/P31 acceptance. The
[machine-readable provenance](full-baseline-results.json) binds the original
source/runtime inventories, exact copied logs, six selected module origins and
the artifact preservation incident below. No tests, native helpers, models or
PTY programs were executed for this documentation/preservation task.

## Corrected test-environment run

Root's `/tmp/ipse-full-test-baseline-ab100a66d350374e/full-test-first.log` ends:

```text
Finished in 1613.8 seconds (312.9s async, 1300.9s sync)

Result: 2474 passed, 4 skipped, 36 excluded
```

Root observed process exit **0**. The retained text log independently contains
the final successful result; there is no separate retained process-exit receipt,
so that distinction remains explicit. The seed was `20261117`, maximum concurrent
cases two. Excluded tags were `native_sandbox`, `macos_sandbox`,
`macos_filesystem` and `memory_scope`. Skips and exclusions are not passed tests.
This is no macOS/native-sandbox, account, model-quality, packaging or release
qualification receipt.

This graph was rebuilt with **`MIX_ENV=test`**, retaining the positive fixture
export check in `auth-fixture-exports.log`. Read-only BEAM export inspection during
preservation independently confirms both `Ipse.Auth.with_auth_transport/2` and
`Ipse.Auth.XAI.with_fixture/3` are present. Their source definitions are explicitly
conditional on `Mix.env() == :test`. The build log records compilation of 130
application files and generation of the application; it does not itself retain
the complete shell invocation. No command has been reconstructed as a new run.

The six-module runtime-binding script checked that Collection, ReadView,
Directory, ProjectIdentity, DomainAuth and Runner originated from private source
and BEAM paths, and that the private protected helper was actually selected.
The retained helper SHA-256 is
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.
Runtime was Elixir **1.20.4**, OTP **29**. Preservation checked these retained
bytes and BEAM export metadata without loading the application or invoking the
helper again.

The original inventory contains **2,337 exact regular project/build inputs**.
`inventory-after-full.log` records empty removed/added/changed lists. A fresh
read-only hash comparison during preservation also exactly matches the original
manifest. Original inventory deliberately excludes `.git`, symlinks and the Mix
`.mix_test_failures` execution cache; it makes no directory-mode claim.

## Stopped predecessor: wrong compiled environment

`/tmp/ipse-full-integrated-baseline-86ee3c62f73d9afa` retains the same declared
source copy, initial build diagnostics, qualified build/format logs and
`full-first.log`. The full test attempt used **dev-compiled BEAMs** with
`mix test --no-compile`; its test-only Auth exports were absent. The log reports
undefined/private fixture functions and subsequent fixture/provider timeouts.
Root intentionally stopped it. It ends with:

```text
02:26:18.709 [notice] SIGTERM received - shutting down
```

There is no final suite result and no pass. These failures are not removed or
converted into corrected-run successes. Read-only export inspection confirms
both fixture functions are absent in this predecessor's retained Auth BEAMs.
Its original 2,337-entry source/runtime inventory likewise remains exact after
the stop and at preservation. The corrected run rebuilt a separate graph; it
did not replace this evidence or rewrite a failed run in place.

## Exact revision scope

Both source-copy data maps contain **1,704 inputs**. The declared base is
`7d3f68c35a308569e8df4843db32efba0e111bd2`, plus the then-uncommitted pure adaptive
proof and its documentation. Opaque byte/hash checks against Git blobs find:

- 1,693 copied inputs exactly match the base; the other eleven are the declared
  adaptive source/test, dependency inventory and archive/index additions/edits.
- 1,703 copied inputs exactly match later pure-proof checkpoint
  `16df6608e973ae46f7c1e346c591afb87db199ed`.
- The sole remaining difference is that the copied adaptive archive draft lacks
  the subsequently added independent-audit preservation paragraphs. All six
  adaptive source/test files match the published checkpoint exactly.

This full pass therefore covers that frozen runtime and pure-proof source set.
It predates later managed-directory closure, actual accounting, NativeReview and
ManagedPages work. It supplies no test claim for those later bytes or their
combined integration. Sustainable actual domain turnover, managed publication,
typed retention, migration and platform acceptance remain their own gates.

## Owner-only artifact preservation

Both complete source/runtime/log copies are retained under:

```text
/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/full-baseline-20261027/
  corrected-test/
  stopped-dev/
```

Copied regular bytes were verified against the originals, including original
failures, scripts, ORIGIN records and Git metadata. Directories are owner-only;
regular files are owner-only while preserving executable status. Symlinks are
retained as link strings and are **not** followed by inventory or claimed as
materialized external payloads. In particular, `project/deps` points at shared
dependency sources, while executable runtime dependency BEAMs are separately
bound within `build`. No fixture content was interpreted or used as qualification
labels; source files were copied/hashed opaquely for provenance.

| Preserved input | Entries | SHA-256 |
| --- | ---: | --- |
| Corrected copy, `corrected-test-files.json` | 4,063 | `5e3ad439a51f4be573cc9ef8e95ebac1f740f597088c39cfdd4ca57334fc8674` |
| Stopped copy, `stopped-dev-files.json` | 4,686 | `6017111bf38dd31547af53dd93183d8c16df2352d5bdf789dad97e91d6c8877c` |
| Initial preservation provenance | — | `a274908e2bdba31dc8643939ff051454a80c46bf81bd7817cfd63501ac0e110e` |
| Corrected original runtime manifest | 2,337 | `0faaca91e4c5526e17b6b12f801dbe6f206983622f5533e16fe8a9be2cd6c393` |
| Stopped original runtime manifest | 2,337 | `bd3e2d1bbd2736647579fad99dc446130b3a9187fe13213575001445f7fdbbda` |

These are byte-verification and owner-permission receipts. No directory-fsync
durability guarantee is claimed.

## Preservation permission incident and bounded correction

The first archive permission pass mistakenly used wildcard directory recursion.
It followed the copied `project/deps` alias and changed **101 shared dependency
directories** to mode 0700 at POSIX ctime `1793095802`. Regular dependency files
were not chmodded by that pass. Shared `deps` itself remained 0755; non-following
inspection found no nested dependency aliases. The mistake and original code are
retained in `alias-permission-incident`, rather than hidden by a replacement pass.

The replacement walker was reviewed and executed only on the two exact copied
artifact roots. It uses `lstat`, recurses only into actual directories and skips
all symlinks before chmod or traversal. Its skipped-link receipt is preserved.

Exact shared pre-change modes were not recorded. Forty-eight older real copied
dependency roots independently contain all 101 relative directories at 0755.
Root approved an explicitly **inferred 0755 correction**, not a claim of known
original modes. The reviewed correction validated the affected JSON's exact hash,
101 unique normalized descendants, every ancestor as a non-symlink directory,
and every affected entry's owner/group, 0700 mode and incident ctime before any
mutation. It then changed only those 101 directories to 0755.

All **744 regular dependency files** have identical before/after hashes; the
snapshot SHA-256 is
`c1e203dcc360261802864bfaeebc6c2c1d5f426902eefb221d3c54614e86f397`.
New modes/ctimes and the inference premise are in `restoration-receipt.json`, SHA
`d5ab9f968b06cce15e349d4fa28c02559464b13b2fbad3e9287c998b58c9a1bf`.
The incident's complete file manifest is
`9072be709640a1eb3f9392bda658b6c1727dd6a7694529354a7187d691d5b907`.
Neither original ctimes nor known exact pre-change permissions are claimed to
have been restored. The corrected test outcome and original byte manifests are
unchanged by this preservation error and its correction.
