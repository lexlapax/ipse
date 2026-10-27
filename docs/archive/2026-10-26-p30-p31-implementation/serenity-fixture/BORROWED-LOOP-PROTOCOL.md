# Proposed single-process borrowed-loop protocol

Status: unreviewed source-derived design. No loop module or device has been
opened or loaded. `existing_loop.rs` is not connected to a live entry point.
This does not qualify 7.2.11 or establish a cleanup receipt.

Trust: Serenity's administrator/root-equivalent actors and Docker daemon do not
intentionally interfere with the fixture. Do not assume unrelated actors have no
loop FDs or cannot choose a free index. Only an index observed in sysfs before
acquisition may be borrowed; never create or remove that index. If loading the
currently absent loop module is later authorized and required, record it as a
persistent host effect; it is not proof of restoring the previous host state.

A future implementation needs a dedicated, independently supervised, single-threaded
loop owner to open and own exactly one loop block file description and the one
regular backing file description throughout the critical interval. It must
construct them locally with close-on-exec, never dup, fork, transfer with
SCM_RIGHTS, register fixed files, start io_uring/AIO, pass FDs to subprocesses,
or issue operations that may leave kernel references in flight. The backing FD
must stay open across loop close. A retained directory and exact inode plus a
fresh, run-specific durable pending/confirmed ledger must bind the created
backing file, pre-existing index, boot, sysfs and node identities.
A separate supervisor may launch mapper tools, but it must never receive or
inherit the loop owner's file descriptions; coordinate by authenticated,
bounded messages and do not enter close while any owned tools are still live.
The loop owner must be contained by an independently observed cgroup/namespace guardian; its
loss or a missing receipt is unknown, not permission to retry or delete.

1. Before opening the loop node, prove the module and this exact index already
   exist without using LOOP_CTL_GET_FREE (which may allocate) or LOOP_CTL_ADD.
   Retain the sysfs object and node identities; require the tested main-device
   numbering profile. Open the exact block node once with close-on-exec, and
   recheck the retained/named device identities. Do not infer that unrelated
   openers are absent from sysfs.
2. Create and retain the exact 512 MiB synthetic backing FD and durable intent.
   Only while status is ENXIO, issue one LOOP_CONFIGURE using that exact FD,
   AUTO_CLEAR, finite size and unique reference. The kernel checks unbound state
   under the loop lock; a race or error remains unknown. Read status on the same
   FD and require exact backing device/inode, reference, index, size and flags.
   Confirm the durable record before the mapper/mount phases.
3. First end the actual scoped stage and require independently proven
   cgroup/process cleanup. Prove controlled mount namespace and no propagation;
   complete a non-lazy local unmount using the reviewed namespace-bound strategy.
   Require exact mapper UUID/table and nondeferred mapper removal success, with
   any EBUSY/error remaining unknown. Separately handle live or escaped aliases.
4. With the same block FD and backing FD still held, recheck exact loop status.
   Durably record clear intent. Issue LOOP_CLR_FD once. Immediately issue
   GET_STATUS64 on that same FD. Only ENXIO is the proposed Lo_rundown witness;
   any bound result, other error or ambiguity stays unknown with the handle
   retained. Under the source-derived single-opener condition, Lo_rundown blocks
   new opens. Do not claim the generic ENXIO alone proves release.
5. Durably record close intent and invoke the ordinary close syscall on the one
   loop FD; never retry close. Independently confirm the exact worker's close
   result and scoped cleanup. Source indicates a final block-description close
   synchronously invokes the driver release, and retaining the backing FD avoids
   its fput being the last backing-file reference at that instant. This is only
   a candidate barrier: the absence of extra open-file-description references,
   exact running-build parity, interrupted close, in-flight I/O and actual loop
   behavior have not been proved. Fail closed if any proof is missing. A later
   unrelated binder on the reusable index is not our resource and must not be
   touched. Never call LOOP_CTL_REMOVE on this borrowed index.
6. Only after independently accepted evidence that our binding and kernel backing
   reference are gone, and exact scoped-process cleanup is confirmed, compare
   the held backing inode and named entry, remove only the unique owned file and
   sync its containing directory. Any unknown means preserve it and an
   operator-visible recovery record. No inotify close event alone authenticates
   the responsible open file description or proves completed final teardown.

Before any device effect, an independent auditor must review the actual system
calls, exact 7.2.11 source/build comparison, no-duplication enforcement,
owner/guardian protocol, mount and propagation proof, ledger, and negative tests.
A disposable kernel/VM would simplify isolation; Serenity currently has no
QEMU executable or cached QEMU package identified, and no package installation
or download was performed.
