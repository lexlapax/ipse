# Protected Collection read-view component

Dated **2026-10-26**. This is a component implementation and author-verification
receipt, not managed-recall integration or P31 completion. The
[frozen baseline](baseline.md) and [contracts](contracts.md) retain acceptance
authority; the [plan](../../plan.md) owns milestone status. Current contributor
instructions are in [persistence](../../developer/persistence.md#read-several-collection-pages-under-one-validated-index).

The later [empty-view component](collection-empty-read-view-component.md)
supersedes this checkpoint's unmaterialized-store refusal with an explicit
version-2 native absence witness. Its verification is separate; the earlier
present-only results and limits below remain historical.

## Supported boundary

`Collection.open_view/2` fully validates an existing wire-root version 4 or 5
under its actual native owner, then releases every storage descriptor and lock.
Its private cache retains exact root bytes/hash, manifest hash, storage summary
and current record references. Opening allocates one metadata process per
original task; a second open refuses until that task closes its existing view.
At most 16 caches coexist. Each permits 512 read admissions over an absolute
60-second lifetime, without renewal, and holds at most 8,192 references and 4 MiB
of encoded cache, sorted keys and integrity seals. Bounded map/binary/process
overhead is additional.

`view_read/2` accepts only closed `get_many` or cursor `scan` requests, with at
most eight selected keys. It runs inside the actual current file-effect worker,
reacquires the Collection native owner, checks the exact current root bytes,
reads selected objects with native `G`, and validates length, hash and value
shape. Native quota, final check and release precede a successful data return.
The reply refuses above 64 KiB. No durable operation IDs or operation receipts
are created by paging. A pre-held outer protected transaction retains its own
stack entry through open/read/release. Lock order remains Identity → Consent →
Collection; the cache server never borrows protected storage authority.

The handle is an owner-bound BEAM term containing an exact server/reference.
The server checks the actual caller PID, original owner liveness and its own
registered identity. An actual file-effect worker may borrow only with both
observed private Resources markers: the original owner and active-effect flag.
An owner binding alone, copied JSON, a stale reference or another task cannot
grant access. No general descendant permission or change to
`Resources.authorized_effect?/2` was introduced. Trusted Core and cooperative
protected same-user storage are assumed; hostile arbitrary BEAM senders or
arbitrary same-user filesystem writers are outside this boundary.

Owner/borrower death, absolute expiry, read exhaustion, corruption and failed
native reads invalidate the cache. Expiry during successful IO discards its
result. Cache close proves metadata-process exit, not native IO quiescence.
Resources and the native transaction continue to own actual cancellation and
cleanup. An upstream owner-death fixture positively reacquires the actual native
lease while the old borrower remains paused, then proves no selected data can
return when that borrower resumes.

## Explicit limitations

- A changed root invalidates the view. A future consumer must reopen and prove
  current selected record validity; an unrelated capture alone is not a reason
  to withdraw every recalled record.
- Selected immutable objects are rehashed on every read. Unrelated cached
  manifest blocks and unselected objects are not reread per page; same-root
  corruption outside the selection can remain undetected until a fresh open.
- An unmaterialized root returns `collection_view_unmaterialized`. Native `G`
  currently cannot distinguish missing roots from every open failure, so this
  component creates no absence witness. Materialized empty roots work with real
  root/manifest witnesses. Native optional-read support remains a separate task.
- Legacy roots 2/3 explicitly refuse views without adoption. Ordinary Collection
  reads retain their existing legacy behavior.
- This is an owner-task cache, not a cross-turn Session cache or SDK API. It
  grants no current consent, managed eligibility, source, expiry, lineage or
  active-job authority. Those checks remain mandatory at the consuming boundary.
- No model, qualification corpus, gold labels, credentials, PTY or helper rebuild
  was used. Helper SHA256 remained
  `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
  Positive native checks ran on the locally supported Linux filesystem profile;
  they are not macOS, general Ubuntu/ext4 or cross-kernel qualification.

## Failure history and checks

The initial pre-refinement two-module strict compile passed in private graph 01.
A later edit introduced a misplaced map comma; the formatter rejected it at
`read_view.ex:132`. It was repaired before graph 02 compilation or tests. The
first test run then passed 10 of 13 checks and exposed three failures:

1. The implementation incorrectly required a SHA256 floor anchor. Collection's
   actual durable floor anchor is a 32-hex operation ID. Both nonzero-floor
   managed and materialized-empty fixtures refused; the validator was corrected
   to the exact existing ID format.
2. The legacy fixture wrote decoded operation maps into wire version 3 rather
   than using the existing `Encoding.encode/1`. Its expected legacy view refusal
   therefore stopped earlier as an invalid collection. The fixture now uses the
   real codec and verifies ordinary legacy reading plus unchanged disk bytes.

The original failing log remains
`/tmp/ipse-collection-read-view-02/tests.log`, SHA256
`74653c458b8b2cf55ad194388d399de0a0cb8c81247399f329808667d1c41e5c`.
No failure was hidden by deleting a control or weakening a production guard.
Graph 03 passed the corrected and expanded 16 checks. Graph 05 passed 18 after
adding expiry-during-IO and borrowed-worker-loss controls. Graph 06 passed the
final 19, seed 214282, 4.1 seconds, adding an actual pre-held outer native stack.
The final focused log is `/tmp/ipse-collection-read-view-06/tests.log`, SHA256
`ab2131be84a1cb76e1da884f4711a0a0b034f498f01e713125f84c27b7ce93c0`.
After adding unconditional failure cleanup for the global-slot fixture's owner
processes, graph 07 repeated the exact final 19 checks successfully, seed 214282,
4.8 seconds. Its log is `/tmp/ipse-collection-read-view-07/tests.log`, SHA256
`a3cf91f0a7b7051b2033b071ae57dd27837aeb2709724b9c07141bd5fe2c6981`.

The controls exercise v4/v5 witnesses, ordered missing/present batches, scans,
materialized empty versus unmaterialized roots, legacy refusal, stale roots,
selected corruption, cache integrity, forged/cross-task handles, active owner
markers, absolute bounds, 16 global slots, actual native loss, upstream death
and separate-VM locking/publication. The capacity/counter tests use explicitly
synthetic metadata or white-box counter/deadline changes; they do not establish
authority from cache-shaped input or claim a 60-second timed soak.

Private graph 04 copied the immutable strict 127-module activation dependency
graph, materialized its private helper, then strict-compiled only the two owned
read-view modules. It did not mutate that upstream graph or claim its activation
behavior. Both compile/runtime diagnostic lists were empty. The source/test
binding is retained in [the manifest](collection-read-view-sources.sha256).
The same frozen graph passed all **69** checks in the seven Collection,
read-view, block, encoding, planning, migration and managed-publication suites:
53 existing controls plus the earlier 16 read-view controls. Seed 214282,
290.6 seconds. No source/build/helper changed while the suite ran.
`/tmp/ipse-collection-read-view-04/tests.log` SHA256 is
`4a25044d15a4a17e20b997fca183f5b29b9fbc1cdf22b20a857e8fb1a9f761e0`.

The persistence manual was read as a whole and the new subsection integrated
around the repeated-read task. Its exact Elixir example executed successfully:
`/tmp/ipse-collection-read-view-example.log`, SHA256
`ce66cc1a79e9081de20f00be596b85b7e06b82300cb5937f03140a06a9daefe2`.
Actual Elixir 1.18.5 formatting checked the three owned Elixir files with zero
differences; source-toolchain formatting also passed. Documentation/link checks
checked 505 Markdown files and 4,562 local links with zero errors after adding
the implementation-index link. The exact count is a tree-wide observation while
other components were being edited, not a claim that their behavior was verified
here.

The two runtime modules also compiled under actual Elixir 1.18.5 with empty
compile/runtime diagnostics. The first verification script used the deprecated
`Code.compiler_options(warnings_as_errors: true)` option and emitted two
harness-only warnings before compilation; that original log remains
`/tmp/ipse-collection-read-view-compile118.log`, SHA256
`28a261b502149419fbbc669781762d9348dc4a100e43527b46a85d47e6063148`.
The corrected verifier rejects nonempty returned diagnostics directly, without
that option; `/tmp/ipse-collection-read-view-compile118-clean.log`, SHA256
`f8abbb55a93350ed8d9c7a7bb8c7490f854fc0e404f76dbf52ae601f1c822809`,
contains no warnings. These are focused module checks against copied existing
dependencies, not a second whole-application Elixir 1.18.5 runtime suite.

The parent reviewer separately read the new cache module and complete Collection
diff, checking root/header/reference seals, exact caller/effect-owner markers,
one-cache/global bounds, borrow/finish/expiry, native reads/quota/release,
legacy/unmaterialized refusal and the explicit unrelated-corruption boundary.
That static review found no concrete actionable defect. A subsequent
[independent frozen component audit](collection-read-view-audit.md) reran all
19 focused tests and passed nine additional adversarial controls without an
actionable finding. Integrated recall/Session performance evidence remains
separate from these component checks. The owner-task lifetime, missing-root
limitation and exact-root conflict behavior must be preserved or explicitly
reviewed when adding that integration.
