# Independent atomic Collection / Normalizer audit

Date: 2026-10-26. This is an incremental implementation audit, not whole-implementation or P30/P31 acceptance.

## Frozen scope and independence

Read AGENTS.md before inspection. Root supplied committed atomic `Collection.execute_managed/6` and v5 receipt/import support from `8ec3361`, plus uncommitted `lib/ipse/extension/collection/normalizer.ex` and its focused tests. Repository HEAD at inspection was `8d50399bb72737d9d884a9d16ab0b1441abe0bfd`. The independent execution copy is `/tmp/ipse-independent-normalizer-audit-20261026`, cloned from Root's complete private runtime `/tmp/ipse-managed-normalizer-20261026-01`, then overlaid with the frozen two files. Root was notified when this freeze completed, before owner repairs.

Before Normalizer source SHA-256: `0d338093d4b3b60b5d4dc70a55a1bf6192fd2251293f4ec449eef861c7ee42a2`; before test SHA-256: `1b68429c86129fa4fe38fa3f5739df455ec9e707a1312ac7a53d841f6b25018e`; before Normalizer BEAM: `e53156cc450f426334e104c2ca4e6806490e27e343a134f3d6db4bfa1b8e89e1`. Before Collection source SHA-256: `ad7af9b93bff4181a57289fa6bad51d25ebda120862d8da09b7be32406de4f9f`; Collection BEAM: `45d730f196bb123a918d85bfbf79c2817cd50bddb93b53d3efe6d722a30fd0ed`. Shared and private helper remained `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.

Complete frozen 695-file source/BEAM/helper inventory: `/tmp/ipse-independent-normalizer-audit-20261026/before-source-beam-helper-sha256.txt`, SHA-256 `83c1a858c451086775941a89c8e6025b166e402446e80dfa6d8d834d837a6345`.

No repository source/index edits, shared helper/build mutation, model-service/network calls, qualification data, credentials or private transcripts were involved. Source proofs are synthetic supplied authenticated-host fixture inputs; this audit does not claim live SourceWindow admission or managed-read integration. Trusted direct admin `Collection.execute` access is not treated as a worker privilege escape.

## F1 — P1: an older complete backup discards permanent source clocks

**Reproduced independently before owner repair; Root confirmed P1.** The original API accepted a managed original commit with `advance_floor:false`. Normalizer added the permanent source anchor/live metadata without advancing the destructive import floor. A supported complete typed import of a genuine earlier empty floor-0 backup then replaced all records, including the new permanent anchor, at the same floor. Identical evidence recaptured at 91 days acquired a new first time and another 90 days of current eligibility.

Actual native reproduction: export empty generation 0; publish ordinary note/anchor/live at generation 1, floor 0, first `0`, deadline `7776000000`; complete typed import of the saved empty descriptor; recapture identical proof at `7862400000` succeeds at generation 4, floor 0, with new deadline `15638400000`. This is an import/retention correctness failure under trusted maintenance, not an unauthorized admin call.

Driver `/tmp/ipse-independent-normalizer-audit-20261026/run-rollback-probe.exs`; generated test `/tmp/ipse-independent-normalizer-audit-20261026/test/ipse/extension/rollback-probe.exs`; raw `rollback-probe-before-rerun.log`, SHA-256 `3d43ca2ea517e96d7144b5843d5684212039461ee77fa20b5c0873b678734970`. Result: 11/12 tests passed, with the independently added rollback assertion failing exactly as described. Initial `rollback-probe-before.log` records a harness-only generated-file relative-path mistake, corrected before the actual native reproduction.

**Closed independently for the after hashes below.** Root's repair changes the managed API contract: the **original** request must explicitly have `advance_floor:true` before the callback. The request is not silently rewritten. Every managed host anchor publication therefore advances import lineage. Normalizer's domain pages/live/normalization receipt become version 2; experimental version-1 domain pages refuse adoption because they lack that guarantee. Generic v5 storage receipts remain generic and grant no domain authority.

Independent positive isolation control already passes on the before runtime: with explicit true, publication reaches floor 1 and rejects the old floor-0 backup; prune advances floor 2, exact-deadline old-source recapture refuses; a genuinely new occurrence publishes at floor 3 with a new source clock. Driver `run-floored-restore-control.exs`, raw `floored-restore-before.log`. This distinguishes the unsafe optional-false contract from the already-correct explicit-floor path.

## F2 — P2: impossible infinite ordinary/pending live metadata is accepted

**Reproduced before owner repair.** A retained neighboring live row copied from a real normalized ordinary publication remains accepted after replacing `valid_until_ms` with null while keeping category ordinary and eligibility current. No valid literal ordinary recipe can emit that infinite deadline; a pending `never_current` row must also remain finite. The malformed row is silently retained when the host rewrites the packed page. Managed current-read wiring is not yet claimed, so this is presently a fail-closed metadata-validation gap, with a future indefinite-eligibility risk.

**Closed independently.** The repaired validator requires finite expiry for ordinary or never-current rows; null is allowed only for current/preference with current eligibility. The unchanged independent malformed-neighbor assertion now refuses both current and never-current infinity.

## F3 — P2: retained live pointers do not enforce Collection's key grammar

**Reproduced before owner repair.** A retained neighboring live row whose `record_key` contains a newline passes validation after recomputing its hash/shard. `Collection.valid_request?(%{"op" => "get", "key" => key})` correctly rejects the same key. Normalizer only checked nonempty binary length, so malformed pointers were retained in trusted host pages.

**Closed independently.** The repaired validator reuses `Collection.valid_request?/1` for retained record pointers, sharing the exact grammar. The unchanged independent newline-pointer assertion now refuses.

F2/F3 driver `/tmp/ipse-independent-normalizer-audit-20261026/run-integrity-probes.exs`; generated `/tmp/ipse-independent-normalizer-audit-20261026/test/ipse/extension/integrity-probes.exs`; raw `integrity-probes-before.log`, SHA-256 `8899f62ba8844fe15831678e604a3a90d09470f5d6776cecab0899890dc51578`. Result: 13/15 tests passed, with exactly these two independent assertions failing. The other independent probes reject fabricated source lineage and packed duplicates/holes, and demonstrate worker timestamps cannot replace the host clock while original value bytes remain exact.

## Protocol adaptation and closure controls

`run-domain-controls.exs` was authored before owner repairs. Its positive fixture explicitly requests a true original floor; test bodies for lineage/clock, packed predecessor validation, infinite TTL and bad pointer are retained. It also independently asserts that false-floor originals refuse before callback and experimental version-1 anchor pages refuse adoption. Before result: 2/6 pass, exactly the four expected assertion failures; 11 owner baseline tests deliberately excluded. Raw `domain-controls-before.log`, SHA-256 `6e9ef88cf5422a521ed0cd2675938aa2d9f316198a8654f7501a7d243c46f01c`.

The after protocol deliberately rejects old false-floor positive payloads. An adapted explicit-true positive fixture is not described as an unchanged old-payload positive. The original before scripts, source, BEAMs and failure logs remain separate and unchanged.

Root supplied repaired complete runtime `/tmp/ipse-managed-normalizer-20261026-02`; the auditor copied it to the separate `/tmp/ipse-independent-normalizer-audit-after-20261026` graph. The same `run-domain-controls.exs` driver, authored before owner repair and selected with `IPSE_AUDIT_AFTER_ROOT`, now passes **6/6** (11 owner tests excluded). Raw `domain-controls-after.log`, SHA-256 `f0f266ac3bf24906abe7cb93133d22dcb1cb93035653c3d7721511388925000e`.

The unchanged `run-floored-restore-control.exs` driver passes **1/1** against the after runtime (11 owner tests excluded): explicit original floor publication, older-empty-backup denial, preserved expiry after prune, and successful genuinely new occurrence at floor 3. Raw `floored-restore-after.log`, SHA-256 `83477233457eeaec5e81ade9c56a752e0149ef578f323a05b3076cdac5614524`. These controls passed before with explicit true as well; the defect was that true was optional and legacy domain pages could be adopted.

The after owner contract baseline passes **18/18** in the independent after runtime (`baseline-after.log`, SHA-256 `92022940fd2e77ae6644f32f086331dbafbc7732002beb3de66e04bf4398a404`). This uses the owner's updated true-floor/version-2 positive fixtures and new false-floor guard test, not the old false-floor positive payloads. Actual generic v5 complete import still passes **1/1**, 13 excluded (`v5-import-after.log`, SHA-256 `cf4fb2b7176850bd2f6e59fc9e5dded431018ff1622e1517a081490b5b64870b`). Generic admin binding remains distinct from version-2 domain authority.

The auditor did not author any owner implementation or owner tests. All three findings were demonstrated and sent before repairs; independent control bodies were frozen before the repaired bytes were supplied. No other actionable findings remain in this scoped review.

## Other checks and limits

- Frozen owner baseline executed independently: **17/17 pass** in 2.4 seconds (`run-baseline.exs`, `baseline.log`, SHA-256 `6ca092aaa4947953905d000429118f5c32a0c40c14a2c91a1fc3d151ac5bdbf2`). It covers generation/revision CAS, original/normalized/receipt digests, reserved extra-write shape, bounded callback reads and receipt size, duplicate no-reentry, actual native owner loss/unknown, separate pending/note clocks, narrowing/nonrenewal, retained anchor/live bounds, and actual paired publication/prune expiry.
- Focused actual complete v5 import receipt preservation: **1 pass, 13 excluded** (`run-v5-import.exs`, `v5-import.log`, SHA-256 `6c1506722c7f92159fc15da73e3473a0a7105a81171d7c00cf6ef63503fcc027`). Imported original operation identity cannot reenter the normalizer.
- Root's separate 53-storage-control, 344-second baseline was supplied as context; this auditor did not rerun that whole suite.
- No standalone activation/UI, native override creation/adoption/correction/acceptance, managed current-read/SourceWindow wiring, or reserved-worker-SDK denial is claimed here. Their explicit absence is not a newly discovered defect. The separate SDK-denial work belongs to another owner.
- This review has no whole-implementation, release, platform, paid-inference or semantic-quality acceptance claim.

## After hashes and diagnostic inventory

Repaired Normalizer source: `4eff99e231e64c0f0f9254abe0c6118126bf5d4781d6b816bf7922e69ecda4b6`; BEAM: `28b948d58de7df378a126769c227b5f28f600d974ac72bb90b671838ba5d4bb3`.

Repaired Collection source: `d4e6308af1202e5e16b6a21d809f4edd651fa169b145be192030eb897e8ba567`; BEAM: `7196bdd16c8ffaffa2c56dd47f886aff8c0a4cd72b110a083685c51dddfa6843`. The supplied after Collection also contains the separate owner's `scan_visible` change; this report does not expand its acceptance scope to current recall/authority wiring.

Complete after 695-file inventory `/tmp/ipse-independent-normalizer-audit-after-20261026/after-source-beam-helper-sha256.txt`, SHA-256 `fb2a0a2f317a8593ca94f00dea9d035d716da0130fa8220adf9afd9642a91352`. The shared/private helper hash remains `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.

`/tmp/ipse-independent-normalizer-audit-20261026/frozen-verification.log` rechecks all **695** before source/BEAM/helper files after closure: **zero mismatches**. No before runtime files were rebuilt or rewritten.

Every preserved driver, generated probe, raw log and source/BEAM inventory path/hash is enumerated in `/tmp/ipse-independent-normalizer-audit-20261026/diagnostic-sha256.txt`. Existing owner test source is inspectable in each separate source graph. The original failing rollback and malformed-live evidence remain intact.
