# Native optional-read component

Dated **2026-10-26**. This receipt covers an internal facility, not first-empty
managed recall, saved absence authority or Session integration. The
[plan](../../plan.md) remains authoritative for milestone status. Current API
and wire instructions are in the [native manual](../../../native/README.md#publish-protected-state-through-its-lock-owner).
The existing [read-view component](collection-read-view-component.md) deliberately
continues to refuse unmaterialized roots in this checkpoint.

Historical checkpoint: a later independent review found that an otherwise valid
reply followed by a buffered partial frame could return before the caller's final
check rejected the capability. The [framing repair receipt](native-framing-repair.md)
preserves that finding, the original failures and the subsequent author checks.
The claims below describe the original component and its original verification.

## Exact boundary

`Transaction.read_optional/4` returns `{:ok, bytes}` for a present protected file,
including an empty binary, or the distinct atom `:absent`. It shares required
read `G`'s directory/name/bounds, native read and host chunk-identity machinery.
The native process retains the actual logical locks while opening, validating,
reading and closing data descriptors; the host opens no data-file descriptor.
No dependency, quota profile, allocation rule, replay policy or permission grant
was added. The existing dependency inventory still describes the same Rust
standard-library helper and source modules.

The new command is explicitly `H` version 1: that version byte precedes the
unchanged `G` fields. A reply repeats the command sequence/depth, version 1 and
disposition 0 for absence (no extra bytes) or disposition 1 followed by the exact
existing present-read fields. The inner maximum is 16,419 bytes. Absence is legal
only for the first offset-zero chunk. The host rejects absent-after-prefix,
changed file identity, unknown versions/dispositions, surplus/partial bytes and
transport/owner loss without returning any assembled prefix. Old helpers cannot
interpret the command; no host `lstat`, ordinary `G` fallback or IO-error-string
classification is used.

Native absence comes only from the exact `ENOENT` returned immediately by one
no-follow/nonblocking `openat` on a validated allowlisted basename in the retained
selected directory. The basename cannot contain a slash. Missing or unsafe child
directories therefore fail before that decision. Dangling/live symlinks, links,
permissions, ownership, nonregular files and other syscall errors cannot become
absence. Selected named/retained directory and every logical parent/lock must
still validate before the reply. All data and temporary directory descriptors
close before it; the logical lock descriptors remain held.

The host's existing original-owner, immediate-caller, scope, absolute lifetime,
non-suspending transport and confirmed-cleanup behavior is retained. The caller
must still check and release its full owning stack before exposing a consumer
result. `:absent` is a lookup fact under that lock, not a durable absence witness
or permission to treat future missing state as eligible. Native read-atime
behavior follows the filesystem; the operation invokes no file creation, payload
write, rename or deletion. Same-user protected storage and trusted Core BEAM
callers remain the boundary; arbitrary hostile same-user writers or raw BEAM
senders are outside it.

The no-follow behavior was checked against the primary
[Linux open(2) manual](https://man7.org/linux/man-pages/man2/open.2.html) and
[Apple open(2) manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html).
The initial OpenGroup page fetch returned HTTP 403; it supplies no evidence.

## Private build and author controls

Shared `priv/ipse-runner` remained SHA256
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
No shared helper, build root, Collection, ReadView or CLI source was changed.
A private native build and matching Runner compile used helper SHA256
`6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d`.
Its helper is a regular single-link private copy; Runner's actual embedded build
hash and runtime protected child/supervisor verification remained enabled.

Private graph 01 copied the complete frozen read-view dependency graph (derived
from the earlier strict 127-module activation snapshot), then compiled only
Runner and Transaction against the private helper. Graph 02 froze the corrected
tests and matching private source/priv layout. This is a complete copied runtime
with a focused two-module compile, not a new whole-current-tree compilation or
activation verification. Its exact helper inputs, runtime owners and tests are
bound by [the source manifest](native-optional-read-sources.sha256).
The [copied application/dependency runtime manifest](native-optional-read-runtime.sha256)
binds all 571 application/dependency BEAM/app files and the bundled helper in
that graph. Loaded test modules and generated fault/probe executables are bound
by their exact sources and fixture recipes, not asserted to be retained sealed
binary artifacts. The primary host toolchain was Elixir 1.20.4, OTP 29, ERTS
17.1; native builds used rustc 1.99.0 (`b940084d7`, Arch package 1:1.99.0-3).
The extra copied project sources support fixture reproduction; they are not a
claim that every older retained dependency/application BEAM was rebuilt from
that ancillary source tree. Runner, Transaction, their helper inputs and the
executed test sources were explicitly compared with the final source manifest.

Checks actually completed:

| Check | Result |
| --- | --- |
| Production native build with `rustc --edition=2021 -D warnings` | Passed |
| Four new native unit groups | 4 passed |
| Complete private Rust suite, including actual existing PTY controls | 66 passed, 2 existing ignored entries; 9.01 seconds |
| Private Runner/Transaction strict compile | Empty compile/runtime diagnostics |
| New optional-read + existing Transaction + protected-helper suites | 34 passed (12 new, 20 existing Transaction, 2 protected-helper), seed 214282; 7.8 seconds |
| Test compilation diagnostics | Empty |
| Actual Elixir 1.18.5 Transaction compilation | Empty compile/runtime diagnostics |
| Actual Elixir 1.18.5 formatting of both owned Elixir files | Zero differences |

Host controls cover native missing/empty/exact-8-MiB transfer, ambient override
poisoning, unsafe files/directories/paths, exact caller/stack/generation,
version/trailing/offset raw requests, malformed and partial responses, changed
identity and absence after a valid prefix, root replacement, stopped-native
upstream death, scope cancellation and original absolute deadline. A Linux
procfs check positively observes the retained lock while excluding selected
data-file FDs from VM, supervisor, anchor and native owner after present/absent
acknowledgements. The native UID predicate is checked using actual metadata and
a deliberately different expected UID; this is not privileged creation of a
foreign-owned file or cross-user OS qualification.

A maintained fixture removes `H` from the command inventory to test unsupported
helpers. A separate supplemental probe used the actual historical `108c` bytes:
the old child returned uncertainty, no root file appeared and no absent result
was synthesized. Reacquisition with the new production-pinned helper then
returned `:absent` followed by successful check/release. The new supervisor
remained protected while the source-derived test child selector admitted that
exact older helper. This fixture selector is not a production override.

No model, credentials, qualification corpus or gold labels were used. Native and
host positives are local Linux observations; macOS execution, descriptor checks
and current first-empty consumer integration remain separate gates. The existing
two ignored native entries and unsupported filesystem profiles were not relabeled
as positive coverage.

## Preserved failures and evidence

The first host formatter rejected a draft `case` expression inside a `cond`
guard. Assigning the response limit before the condition repaired the syntax
before runtime compilation. The first optional host run passed all 10 initial
controls but emitted a test-only unused `port` warning. The parameter was renamed
`_port`; no production guard changed. Additional scope/deadline controls were
then added. A verification invocation tried the unsupported standalone
`elixir --warnings-as-errors` option and exited before tests with
`No file named --warnings-as-errors`. The corrected harness uses
`Code.with_diagnostics/1` and refuses any returned diagnostics. All original logs
remain available; none of these harness failures was presented as coverage.

| Private evidence | SHA256 |
| --- | --- |
| `/tmp/ipse-optional-read-native-full.log` | `d659575b6183e6f0ebd80e11c988381be613b123e4c79967af081c305e324f6b` |
| `/tmp/ipse-optional-read-01/tests-first.log` | `2a0dd43027d697f622792a1ff9dca8902bea8760254d40ec8103053b916fd6d2` |
| `/tmp/ipse-optional-read-02/tests-harness-flag-failure.log` | `165f2aad902be4e5aef2312edee87818944c8201ec2045bd08382fb55876ee77` |
| `/tmp/ipse-optional-read-02/tests.log` | `f7fa3d77648ae7787afe4212836328fa77b63ddf3d7b3ce61d8fe13b0bc9a253` |
| `/tmp/ipse-optional-read-02/historical.log` | `474d262535f587d81877e6c137823ac2557a627badb00b8e7327b9223194fcfe` |
| `/tmp/ipse-optional-read-compile118.log` | `aa002dee355589329b2b9137a7ffccb609ba1b8544d685d7b9c88f8bdb4adca1` |
| `/tmp/ipse-optional-read-format118-first.log` | `bef37b3c9c1183582e09749b8b0000b60b548497b7a7cf1b845d3f38eeafcf4b` |

The native manual was reviewed as a whole; the optional-read contract belongs
with actual-owner reads and the closed protocol. Its API/build/test commands and
limits were checked against the implementation and the private controls above.
Documentation/local-link checks passed after the archive/index update:
511 Markdown files and 4,605 local links, zero errors. This is a concurrent-tree
documentation observation, not behavior evidence for other components.
Independent review and any consumer
absence schema remain separate from these author checks.

The parent separately read the complete native/host diff and all 12 new tests.
That static review found no actionable defect, checking the exact raw errno,
first offset and selected directory, RAII closure, all-stack validation, closed
H version/disposition, no fallback, discarded prefixes and preserved actual-owner
and cancellation guards. It reaffirmed that final check/release belongs to the
caller. This is separate from a fresh independent adversarial facility audit.

## Durable private evidence

The finished evidence is preserved under the established owner-only root:

```text
/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/native-optional-read
```

`files.sha256` binds 1,111 copied source, application/runtime, finished-log and
artifact files by canonical relative path. `provenance.json` additionally retains
every original source path, byte count and SHA256, plus the explicitly omitted
non-runtime `telemetry/src` symlink (not followed). `executed-runtime.sha256`
and `executed-sources.sha256` preserve the public manifests. The preservation
script compared every source and destination byte, checked the complete declared
runtime before and after copying, verified effective ownership, regular/single-link
files and exact permissions, and synced every copied file and directory.
Every directory is `0700`; every data file, including executable images, is
`0600`. The additional preservation receipt is bound separately; it cannot be
inside a manifest whose own digest it reports.

| Durable metadata | SHA256 |
| --- | --- |
| `files.sha256` | `080d120cab9e47766551ec93c78fc881faa1b9ef3a933896c1a539e5b6624b35` |
| `provenance.json` | `5b6e20cb35f1928c30b9a715754bce0d1a52308d9ab19160d5efe48984980fc0` |
| `preservation.log` | `d57b3c3bf45f2600198a14b95b30331c2f22a2b73198fee4d609eb386923626c` |
| `docs-final.log` | `bd1fb65432c3f54ad878d8e2edb44bc81f16a92385f2a585b6b2cc2e7740d7fb` |
| `completion.sha256` (separate final log/receipt hashes) | `5cc5df053212c9585837dc0bbe2b1398e6b5a590840ede5684c0038743c6083d` |

Never execute from, chmod or otherwise modify this evidence in place. Reproduce
by copying it into a new private working directory, then set only the working
helper/executable copies to `0700`. Point the working test recipe and code paths
at that working runtime; preserve the recorded data bytes and their manifests.
The original `/tmp` origins remain provenance, not the sole retained evidence.
