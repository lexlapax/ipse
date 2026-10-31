# Native lock-owned Session headers

Dated 2026-10-29. This focused Linux change responds to the
[fresh-header owner-loss finding](session-start.md#fresh-header-owner-loss).
It is not managed-output admission or P30/P31 acceptance. The
[current plan](../../plan.md) remains authoritative.

The later [independent review](session-header-native-independent-review.md)
found incorrect Session close-mode handling, an unbounded overall header
transfer and missing compatibility controls. The Linux implementation is not
accepted until those findings are repaired and verified.

The same pre-existing ordering affected an ordinary fresh Session: its journal
was created before it acquired the session lock. In the instrumented
[legacy control](evidence/session-native-header/legacy-contention.log), a real
Session was stopped at its actual file-server write, and another native helper
acquired the same lock before that write completed. Resuming the file server
wrote 1,493 bytes while the contender retained the lock. The hook only provides
a rendezvous; the Session, file server and locks are real.

Linux fresh Sessions now use a separate pinned `--session-header-v1` owner.
The Session registers the fresh ID and acquires that lock before creating its
header. The owner exclusively creates a same-directory pending inode and reports
its device, inode and UID. The host obtains and validates `SourceOrigin` from
that inode, encodes the ordinary bounded journal event, checks the existing
record and reserve limits, and streams the exact bytes to the native lock owner.
The owner checks the retained lock and pending inode during the transfer,
synchronizes the file, publishes it with no-replace rename, and synchronizes the
directory before acknowledging completion. The pending and final names share
the same inode. This mode does not export its lock. Resume uses the prior legacy
lock path; the export-capable Session candidate remains disabled.

Loss after creating or writing the pending inode is unknown, not a successful
header. An interrupted pending file is not a `.jsonl` Session and is not
automatically replayed or deleted. A rename may have happened when its reply is
lost; a complete published header can be inspected and explicitly resumed after
the lock has actually released. The helper retains its lock while its own write,
sync and rename execute, including after BEAM owner loss. This prevents a
different Session from acquiring that lock during those syscalls. It does not
prove filesystem durability beyond the actual successful sync calls, and it does
not make same-UID untrusted code a supported storage adversary.

The [focused native controls](evidence/session-native-header/test-final-v4.log)
passed 13 cases across the prior test-only command variant and the dedicated
normal helper mode, including exact inode facts, partial owner loss, refusal of
an existing symlink, a substituted pending inode, a 16 MiB record, and the
ordinary helper's refusal of the old export-mode command. The separate
[collision control](evidence/session-native-header/collision.log) verified
no-replace publication, and the [no-export control](evidence/session-native-header/no-export.log)
checked that the new mode refuses descriptor export. The first fixture run
had three assertion/parser issues; that [failure](evidence/session-native-header/test-initial.log)
and the focused retry are retained. The maximum-size data is synthetic and
proves transfer capacity, not JSON or Session admission.

The [genuine Session control](evidence/session-native-header/session-positive-final.log)
checked a prompt, actual SourceOrigin/file identity, lock exclusion and resume.
The [owner-loss controls](evidence/session-native-header/session-loss-final.log)
used a test-only native rendezvous before and after the real write and sync. A
competing helper was refused both before and after the write while the native
owner held the lock; owner death during the write left only a pending header.
Owner death during sync retained exclusion through publication, after which an
explicit resume succeeded. These hooks bracket the syscalls; they do not suspend
the kernel inside a filesystem syscall. The initial loss fixture mistakenly
used a glob that skipped hidden pending names; its failure is retained. The
[credential-free demo](evidence/session-native-header/demo.log) completed in an
isolated synthetic home and workspace using the matching helper.

The [source snapshot](evidence/session-native-header/source.tar),
[manifest](evidence/session-native-header/manifest.sha256), and separate
runtime inventories record the exact source, helpers, logs and test graphs.
The historical graphs are local evidence, not a fresh-checkout build recipe.
The first strict integration compile reported a bitstring warning; the corrected
compile passed. The matching helper must be rebuilt and pinned with `Runner`;
an old helper cannot perform this protocol. Non-Linux fresh startup keeps its
earlier ordering and is not qualified by these Linux controls. Candidate close
receipt and final owner-fenced managed output remain separate open work.

The final core controls ran with the commands below, using the recorded helper
paths. The native test helper's race hooks exist only when explicitly compiled
with `ipse_session_header_test_hook`.

```sh
rustc --edition=2021 -D warnings native/ipse-runner.rs -o _build/session-native-header-sol-20261029/ipse-runner-standard-v4
rustc --edition=2021 -D warnings --cfg ipse_session_header_experiment native/ipse-runner.rs -o _build/session-native-header-sol-20261029/ipse-runner-header-v4
rustc --edition=2021 -D warnings --cfg ipse_session_header_experiment --cfg ipse_session_header_test_hook native/ipse-runner.rs -o _build/session-native-header-sol-20261029/ipse-runner-race-v4
IPSE_HEADER_HELPER=_build/session-native-header-sol-20261029/ipse-runner-header-v4 IPSE_HEADER_RACE_HELPER=_build/session-native-header-sol-20261029/ipse-runner-race-v4 IPSE_HEADER_DISABLED_HELPER=_build/session-native-header-sol-20261029/ipse-runner-standard-v4 ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-gate-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/native_header_experiment_test.exs")'
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-integration-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/native_header_session_test.exs")'
IPSE_HEADER_SESSION_RACE=1 ERL_FLAGS='+S 4' ERL_LIBS=_build/session-header-integration-race-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/native_header_session_loss_test.exs")'
```

## Framed close and transfer deadline follow-up

The independent review found that the fresh Session stored its runtime mode as
legacy even though its guard used the framed header protocol. Its close reply
could therefore precede and ignore the guard's release result. Fresh Linux
Sessions now retain the actual `:header_v1` mode. Close stops and observes the
Writer, then aggregates its result with the framed release and other cleanup;
a missing, dead, failed or malformed helper release is unconfirmed. Existing
legacy resume keeps its previous mode. The
[real dead-helper control](evidence/session-header-audit2/dead-helper-retry.log)
and the [malformed-release control](evidence/session-header-audit2/session-race-initial.log)
both returned unconfirmed. The initial dead-helper fixture suspended the guard
too early, blocking a Writer record before it reached the intended boundary;
its [failure](evidence/session-header-audit2/focused-initial.log) is retained.

A successful fresh close can return `:ok` after actual Writer shutdown and a
valid framed release. Its previously written lifecycle closure still records
`cleanup_confirmed: false`, because the Writer has to stop before lock release.
The [Session control](evidence/session-header-audit2/session-final.log) verifies
that explicit resume succeeds, lifecycle event description exposes the false
value, and saved diagnosis does not contain a `cleanup_confirmed` field. This is
an interim conservative record, not a durable positive release receipt. A
post-release receipt and its recovery semantics remain open before this repair
can be considered complete.

One monotonic 30-second admission and response deadline is shared by native
begin and all header transfer frames. Synchronous host preparation between
frames can block past it, as can native filesystem calls; this is not a hard
wall-clock bound on startup. The same deadline is passed to the lock guardian;
its calls no longer wait indefinitely for the reply. The
[slow/stalled peer controls](evidence/session-header-audit2/deadline-final.log)
show an unconfirmed result when individually responsive frames exceed their
shared budget and when a single response stalls. These are synthetic protocol
peers, not slow filesystem tests. A native syscall already in flight may finish
after the host deadline; timeout does not prove cancellation or no effect, and
the native lock owner retains the lock until its own operation ends.

A [genuine fresh Session on the older pinned helper](evidence/session-header-audit2/old-helper.log)
refused before creating either a lock or journal; no legacy fallback occurred.
The matching-helper [credential-free demo](evidence/session-header-audit2/demo.log)
still completed. A test-only hook made the real Session and native helper take
the no-replace failure branch and left a pending file without publishing a
journal ([control](evidence/session-header-audit2/session-race-initial.log)).
This injects a failure; it is not a test on a filesystem that actually lacks
`renameat2` no-replace support. The available writable mounts were tmpfs and
btrfs and `/dev/fuse` was absent, so a genuine unsupported-filesystem control
remains open. Directory traversal, no-replace rename and directory fsync are
required for this Linux path; no unsafe fallback is used. Non-Linux behavior
remains unverified.

The [source archive](evidence/session-header-audit2/source.tar),
[manifest](evidence/session-header-audit2/manifest.sha256), and three runtime
inventories preserve the current matching-helper, interposition and older-helper
cohorts. The export candidate and managed-output paths remain gated. Neither the
diagnostic evidence nor a successful ordinary close solves the separate native
owner-fenced output problem.
