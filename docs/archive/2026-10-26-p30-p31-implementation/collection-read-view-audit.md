# Independent protected Collection ReadView audit

2026-10-26. Scope: committed `cce9907` Collection open/read/close seam, `collection/read_view.ex`, and focused tests. **No actionable defect found.** This is incremental component evidence, not whole-implementation, Session recall, semantic eligibility, or P31 acceptance.

## Independence and frozen bytes

Read the actual repository AGENTS.md before inspection. The auditor did not author this component. Copied Root's exact complete private graph `/tmp/ipse-collection-read-view-07` into `/tmp/ipse-independent-read-view-audit-20261026` before examining or executing it; sent the freeze acknowledgement before probes. All source/runtime/helper execution used this independent graph. No owner repairs were requested or made, so the before and after implementation bytes are identical.

The frozen inventory `source-beam-helper-before.sha256` contains **659** source/test/dependency/BEAM/helper files, SHA256 `460773089d147d69007fd06d7431621e33cd646717df4a531b768ce743a40915`. `frozen-verification.log` rehashes every original entry after execution: **zero mismatches**. Generated independent probes are added separately and do not replace original source.

Principal hashes:

| Item | SHA256 |
| --- | --- |
| Collection source | `9b875ad008fc0958a520ec3ae8956677d5db50d4fd89dcb47a518fa4d10c423b` |
| ReadView source | `08e2b43e3298a7db1730c7cbf726cc220439726a8fd49c8a19725b2e5931092f` |
| Collection BEAM | `b7b30a1f787536914c67d10a21285a4b2a139d706a9f38a796086d575f69abe1` |
| ReadView BEAM | `e9608d8b1cf8ad2fae0f58cde57425982a2456e55b773bcf3c7401340b3ecc94` |
| Shared and private native helper | `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29` |

No repository/index/shared build/native-helper mutation, model-service calls, network requests, qualification corpus/gold, credentials, or private transcripts were involved. The only additional VM is a synthetic native-lock contender using the same copied runtime and isolated HOME inherited from the test helper. Local native positives are specific to this supported Linux filesystem/profile.

## Actual checks

Re-executed the owner's focused baseline independently: **19/19 passed**, seed 811917, 4.6 seconds. `baseline.log` SHA256 `51aedb0d56e94a30d47bb08b3b3799816ce93253d5114d1f566cf6551e54c099`. This covers v4/v5 root witnesses, ordered absent/present batches, cursor scans, materialized/unmaterialized/legacy behavior, exact-root changes, selected native object hashing, cache integrity, owner/ref/effect markers, 16 actual global caches/one per owner, read/cache/ref/expiry bounds, actual native loss, upstream death and foreign-VM serialization. Read/deadline capacity controls include explicitly white-box counters, deadlines, or synthetic cache shapes; they are not a 60-second timed soak.

Authored **nine additional adversarial controls** using the owner fixture helpers; owner test bodies are excluded from this independent run. Final result **9/9 passed**, 19 excluded, seed 418907, 0.8 seconds. Finished driver `run-adversarial.exs` SHA256 `c78ca89a7e6032753c316f7685e5e5fd5323066fffe84772b7f688e0c14f3366`; generated complete test source is `src/test/ipse/extension/independent_read_view_adversarial_test.exs`. Full final output `adversarial-complete-max-values.log` SHA256 `3370833de1b41c161d96adb2402c1f6891ccf03d85471aec274495a9d1e5f69c`.

1. Actual `ProjectIdentity.with_binding → Consent.with_policy → Collection` uses one native controller at depth 3, preserves the exact outer Consent lease, and allows subsequent original-owner reading after both outer scopes return.
2. Closing metadata inside selected native IO leaves the actual lease owned at that point, but discards the otherwise successful data result; explicit reopen works. This confirms close is not falsely treated as IO quiescence.
3. A reentrant Collection read refuses at its lock-order guard; direct authenticated cache borrowing remains busy. Neither consumes another admission nor disrupts the in-progress native owner.
4. Dropping a selected cached reference cannot become authenticated absence; plausible inserted references, selected revision corruption, reordered scan keys, and changed header/root bytes invalidate the cache.
5. A fake server PID and an actual file-effect worker with a different original owner cannot borrow; the original owner's valid view remains usable.
6. Eight records at the **exact 6144-byte encoded value limit**, with 96-byte keys and heavy JSON escaping, preserve reverse requested order and return **52,691 bytes**, below 65,536.
7. A separate VM holds the actual Collection native lease. The selected read refuses/invalidate its cache; after explicit contender release, a fresh view returns exact original data.
8. Resources cancellation closes the actual native controller while the original owner and paused borrower remain alive. A new native transaction positively reacquires the same lease before the old worker resumes. Resumption returns `{:unknown, :collection_lock_lost}`, with no selected data, and invalidates metadata.
9. Killing the actual native IO borrower closes its controller, returns `collection_view_unavailable` without selected data while the original owner remains alive, invalidates metadata, and permits positive reacquisition of the same native lease.

## Diagnostic history and limits

Preserved all intermediate logs. `adversarial-initial.log` records an auditor harness syntax mistake from nested heredoc delimiters, repaired before execution. `adversarial-rerun.log` records 6/7 passing with an incorrect auditor expectation: Collection's stronger pre-held-lock guard rejected the reentrant call before it reached the cache's busy check. The pre-correction driver is preserved as `run-adversarial-pre-correction.exs`. The corrected test separately proves both guards and passes. No production guard was changed or weakened. Later logs record 7/7, 8/8, then 9/9 as independent cancellation/death controls and exact-limit values were added. Telemetry's informational local-function notices remain in raw logs. The initial private-preservation attempt refused an unused public telemetry source-directory symlink; its raw failure remains `preservation-initial-failure.log`. The partial evidence was byte-checked against its source before removal, and the public dependency source link was materialized as ordinary files for retry. No runtime BEAM/helper bytes or any of the 659 frozen entries changed.

Root's broader 69-test author receipt was inspected as context, not rerun here. No deterministic real-time 60-second soak, OS-memory bound, unavailable platform, hostile arbitrary same-VM Core sender, or arbitrary same-UID filesystem adversary is claimed. Selected immutable objects are rehashed; unrelated same-root manifest/object corruption remains the explicitly documented limitation. Unmaterialized roots explicitly refuse without an absence witness. A changed exact root invalidates the view; the future consumer must establish current selected validity. This owner-task cache grants no Session/active-job/current-consent/source/managed eligibility or cross-turn authority.

## Durable evidence and reproduction

The complete graph, source, BEAMs, helper bytes, owner receipt, read AGENTS snapshot, finished probes and all raw logs are preserved owner-only under:

`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-read-view`

`diagnostic-sha256.txt` enumerates every diagnostic path/hash. `durable-files.sha256` covers every preserved file by relative path, excluding itself. `PRESERVATION-RECEIPT.txt` records byte verification and directory/file permission checks. Original frozen manifests retain their original `/tmp` provenance paths; the durable relative-path inventory binds the preserved copies independently.

All durable directories are 0700 and files 0600. To reproduce, copy the evidence into a separate private working directory, restore executable permission **0700** on that working copy's `dependencies/ipse/priv/ipse-runner`, then set `IPSE_READ_VIEW_AUDIT_ROOT` to the working directory and run `elixir --erl '+S 2:2' run-adversarial.exs` or `run-baseline.exs`. The preserved helper itself remains data-only 0600 as requested. Do not execute or modify the durable evidence in place.
