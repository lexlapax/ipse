# Local Word comparison: stopped attempt, 2026-11-06

This is a failed, partial local comparison, not a retrieval-quality result or
completion of P31. The [plan](../../plan.md) owns current acceptance. The earlier
[installed Word result](../2026-11-05-word-installed-row-context/index.md) remains
unchanged.

The declared comparison used frozen questions and supplied document bytes with
the selected local Qwen embedding route. Ingest and inspection completed for the
first document; indexing was refused and the run stopped. All 152 comparison
result slots remained undispatched. The first-result manifest and outer status
were retained; no Gold scoring was run. Outer source, artifact, runtime and
owned-process postchecks passed. The Session closed and Saved reconstruction
passed, but the idle/no-replay check did not pass. These are separate facts; a
confirmed close is not a successful idle check.

The retained journal has one admitted embedding attempt and no inference
dispatch intent. It therefore establishes no embedding request was sent on the
provider wire in this attempt; the generic failed result does not identify an
HTTP response. An admitted attempt is nevertheless conservatively charged in
the [live-call accounting](live-call-accounting.md): local liability rises from
4 to 5 of the authorized 1,000 calls. Metadata requests are a separate category,
not additional inference calls. No fallback, download or retry was performed.

The Session budget ledger had only its header while the journal contained the
admission. That mismatch explains why the saved accounting join cannot be
confirmed; neither record was edited. A later disposable native quota probe
independently returned `transaction_filesystem_unsupported` for a repository
Btrfs root and succeeded for a tmpfs root, with normal native closure and no
Session, model or metadata calls. The failed comparison used the repository
filesystem, but its generic result did not itself expose this native error; the
probe supports the filesystem diagnosis without proving the hidden failure
branch. A subsequent [budget correction](budget-reservation-pre-slot-20261106.md)
addresses the observed pre-callback accounting gap within its stated limits.

The first outcome and its private receipts remain preserved. A separately
qualified future run must use its own fresh storage and cannot turn this partial
result into a pass. No original notebook was read for this comparison.
