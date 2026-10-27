# Native read ownership and staging-frame ordering

Dated **2026-10-26**; internal component evidence for the
[implementation record](index.md). The [current plan](../../plan.md) remains open.
No inference calls were made.

## Keep data FDs with the lock owner

Review of the new collection blocks found a lifetime gap: ordinary host file IO
could retain an open data inode after its separate native logical-lock owner
died. A later owner could unlink it, hiding its still allocated bytes from a
directory inventory. A before/after lease check does not close that gap.

The native transaction now implements a bounded `G` read command. The same
process owns the logical lock and each data FD; each chunk closes retained and
named data FDs before its reply. The host checks total size, device/inode,
offsets and exact chunk lengths, assembles at most 8 MiB, and discards all bytes
after any failure. Only existing allowlisted root or immutable names are admitted.
Consent and Identity index reads use it; Collection adoption belongs to its
separate storage increment. Hash/schema/domain checks remain in Elixir. Native
allocation profiles and the conservative staging allowance are unchanged.

Direct strict compilation of Runner, Transaction, Consent and Identity passes.
All **66 protected owner/identity/consent tests pass**, seed **398703**, in
**135.5 seconds**. A later actual Linux descriptor control extends the transaction
suite to **20 passing tests**, seed **919331**, in **4.4 seconds**. It positively
finds the retained `.lock` while checking that the VM, supervisor, anchor and
native owner hold no data-file FD after the read acknowledgement. Exact eight-MiB
binary transfer, unsafe permissions/links/FIFO refusal, malformed native read
responses, cross-VM locks and owner-loss controls also run. This local procfs
observation is not a macOS descriptor test or a new filesystem-profile qualification.

The first transaction run passed 18/19; a clause-grouping compiler warning made
the child-VM exact-output assertion fail. Grouping the clauses repaired it. The
first combined run passed 63/66: its standalone override directory omitted the
complete sibling dependency layout used by three child-VM fixtures. A complete
private runtime repaired that harness. The first descriptor control assumed only
one supervisor child; the existing independent anchor makes two. Its corrected
bounded scan retains the positive lock-FD control and checks all those processes.
All original failures remain diagnostic evidence.

The native suite passes **62 tests, 2 deliberately ignored entries**, in
**9.04 seconds**. Its first sandboxed run passed 49 and failed 13 operator tests
because the protected temporary-root backend was unavailable in that sandbox;
the actual native/PTY run passes without changing the protection checks. The
new helper SHA-256 is
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
Raw logs use the `/tmp/ipse-native-owner-read-` prefix; the corrected complete
runtime is `/tmp/ipse-native-read-checkpoint-20261026-01`.

## Preserve acknowledgement bytes before a real exit

Investigation of the earlier hosted staging failure found a concrete ordering
bug. When the final `A` acknowledgement and terminal `X` frame arrive together,
self-requeuing the remaining bytes can place them after an already queued real
OS exit receipt. The parser then refuses a successful operation. A deterministic
source-derived parser fixture reproduces that failure, **1/2 tests passing**,
using a real terminated process's receipt. The repair carries buffered bytes
directly between parser phases. Both framing tests then pass; nonzero exit,
timeout and unknown schema fields still refuse.

All **11 framing, actual storage, backpressure and protected-helper tests pass**
under **two BEAM schedulers**, seed **899618**, in **6.1 seconds**. This includes
actual maximum-size and 128-file writes, stopped readers, cancellation and owner
death. Strict Runner compilation passes. The five-second exchange deadline is
unchanged. Logs use `/tmp/ipse-staging-coalesced-`. This closes the reproduced
local ordering bug; a new hosted result is still required before claiming that
the earlier Ubuntu failure is resolved on that platform.

The whole-repository baseline, installed checks, limited native quota profiles,
independent final audit and P30/P31 workflows remain separate open gates.
