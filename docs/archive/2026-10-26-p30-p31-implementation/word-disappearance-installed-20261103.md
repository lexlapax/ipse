# Installed Word source disappearance and recovery

2026-11-03. This synthetic Linux check extends the earlier
[installed packed-numbering journey](word-packed-numbering-installed-20261103.md).
It does not complete P31F, establish real Word rendering fidelity or qualify
large document storage. The [operator procedure](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
describes the existing current-file check and recovery.

## Result

A default PDF-enabled Linux package built offline from an isolated Git export of
commit `e0daa8119c5da949c886f1c36715eaace04e0455` has SHA-256
`678b446a8351a9eed9a3ac6ce738064ce9981767842d7cf27dfef9fa60d0667d`.
The [installed verifier](word-disappearance-installed-20261103/task-installed.log)
passed all six existing cases: State, Collection, cancel, stale approval,
configuration race and piped input. The [report](word-disappearance-installed-20261103/report.json)
records the exact archive and fixture hashes, zero model calls and unchanged
extracted release inventory. The verifier used packaged Ipse code, a copied
precompiled ExUnit library and a synthetic PTY compiled before runtime launch;
this was not independent human use.

Both positive profiles acquired the same kind of synthetic 40-block numbered
Word source and checked the complete original citation, including literal
quotation, binary hash, packed offsets and numbering metadata. After an existing
replacement/refusal control restored the initial bytes, the added fixture moved
the original file aside without changing its device/inode/owner/size or bytes.
A query in the live Session returned refusal with no evidence or claims. It
closed and reopened the same Session while the source was absent, verified that
reopening added no extension invocation or action intent, or model request
admission, and confirmed the missing-source refusal again. Returning the held file to its
original path preserved its identity and bytes; the next query returned the
same complete evidence as before. The numbered `read_document` acquisition
invocation list remained unchanged through recovery.

## Provenance and limits

The exact [fixture patch](word-disappearance-installed-20261103/task-fixture.patch)
has SHA-256
`908301b33951601a66000b23266d12a7f5ff808a462996093cf8f9bc063c0bf9`.
Its e0 fixture preimage SHA-256 is
`8bcd53725549ad62398b9ad798731d5c82dc58f323176aa6100918ea8e5ad2c2`;
the formatted, tested output is
`0624b6939d400df29a68d8b208803f26726c3478b71ca7be2225e101732b08ad`.
The overlay changes the test fixture only and is not packaged runtime code.
A reviewer confirmed formatting changed only wrapping relative to the earlier
reviewed fixture.

The [package launcher](word-disappearance-installed-20261103/task-package-once.sh)
and [installed launcher](word-disappearance-installed-20261103/task-installed-once.sh)
record the one-shot offline commands. The isolated source was extracted from e0,
including its committed documentation archive. Its 8,591-entry regular-file
inventory had SHA-256
`a722713dec9ed270e1c1f7b05e6d232e4037fb82eba509111e2cc67c940167c2`;
the single tracked archive symlink was checked separately without following it.
The checkout was created with `git archive` from e0, but no independently
verifiable full file-by-file comparison with that commit was archived; the
report's commit label came from `IPSE_BUILD_COMMIT`. The fixture
preimage and unchanged verifier were independently verified. The full inventory
and extracted package remain in volatile scratch storage; their hashes identify
them but do not archive every source or binary. Both launchers
reported successful regular-file postchecks; the package launcher also checked
the symlink after building. The [package log](word-disappearance-installed-20261103/task-package.log)
records 52 bundled documents and no missing local targets. Project compilation
used warnings-as-errors; upstream dependencies emitted warnings.

The [evidence manifest](word-disappearance-installed-20261103/evidence.sha256)
has SHA-256
`13d73f7c656646a52dfbf5b3e1d308816382c34b3ea6609c08ec3e03812faefb`.
It retains the patch, launchers, bounded logs, status files and synthetic
report. Individual scenario logs contain synthetic terminal approval codes and
remain only in volatile scratch; their hashes are in the report. HOME remained
inherited and unchanged; task-specific IPSE_HOME and TMPDIR and explicit
synthetic Session operator paths were used. Source review supports that
isolation; no operating-system access trace was captured.

This test covers absence by renaming and restoration of the same file. It does
not establish deletion or symlink-redirection recovery in the installed package,
all platform backends, complete source-lifecycle behavior, semantic retrieval
quality or any annual workload. The [current plan](../../plan.md) owns status.
