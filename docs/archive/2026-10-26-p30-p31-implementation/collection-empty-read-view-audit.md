# Independent empty/present Collection read-view audit

Dated **2026-10-26**. Historical independent evidence, copied verbatim from
`p31-verification/independent-empty-read-view/REPORT.md`. Original SHA256:
`69fc1acc44d114436ab9d62cbee728c5dcf94106df645074fcd73deb2aafb3e7`.
This incremental review follows the [component record](collection-empty-read-view-component.md).
Current behavior belongs to [persistence training](../../developer/persistence.md#read-several-collection-pages-under-one-validated-index);
the [plan](../../plan.md) owns remaining milestone work.

```text
# Independent empty/present ReadView v2 incremental audit

No actionable defect was found in the exact frozen component reviewed here. All independent controls passed. This is an incremental audit of Collection/ReadView empty-root support, not whole-milestone acceptance or approval of managed recall, Session absence authority or the separate CLI repair.

The auditor did not author or repair Collection, ReadView or their owned regression tests. Root supplied a frozen graph; the auditor copied and verified it before fresh probes. The repository/index, shared build/helper and original graph were not edited. Only synthetic private local fixtures were used. No model/network/paid calls, credentials, private transcripts, independent qualification gold or global operator/PTY tests were used. No owner repair occurred during this audit; BEFORE and AFTER input hashes remain identical.

## Frozen inputs and independence

Source graph: `/tmp/ipse-empty-read-view-20261026-02/{project,build}`. Independent working copy: `/tmp/ipse-independent-empty-read-view-20261026`. Tests explicitly load the copied `build/lib/*/ebin`, run from the copied `project` CWD and use its private helper. All 1,105 regular source/runtime inputs matched both the original manifest and independent copy before testing, after testing and at preservation. Earlier ancillary source/runtime history does not claim a whole-current-tree rebuild; the reviewed component and matching helper/runtime are bound below. The separate CLI08 repair is excluded.

| Input | SHA256 |
| --- | --- |
| Root frozen manifest, 1,105 inputs | `0cc1159adc6345a3db65abaced1ccbba2df4a6f813a0340b41a269f300f8f764` |
| Own mapping of all 1,105 inputs | `3822f43aac754ba621d5ea96913f562db7efb808d88f81f4e40ab89351e03c0b` |
| Collection source | `15d3f0731e06dd95660e067ebbc33bc81bf1c9fc56b1e871511d8f83ed6d1de0` |
| Collection BEAM | `3dd4ece04831aec76499fdfa357827a4a13afb5df19e2e2ced3f7838de0847a5` |
| ReadView source | `e5095b24260dcf17852f4ea6576c2b0e4e535efa8d19ff1287e7728171b2ebf7` |
| ReadView BEAM | `2315980f2e4df0c8730bf38362e6b164d987a9738d606c6612dbc8da2be1d9a3` |
| Transaction source, previously independently closed | `8c769af647054df7d5cf3d468ed3dfd4666d3130d84d9855e6b77195272ea3ef` |
| Private native helper | `6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d` |
| Shared old helper, unchanged | `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29` |
| Complete reviewed persistence manual | `ca6b87931ed2e5adaf301f4d120f88eb170e1f9dce59dd67958bd9c0d47109aa` |
| Trimmed public Collection exercise | `a1d5d45ac5633cc45f6f2e4370e5de1ceb20f9f8870ded3c7c7401d99f40a179` |

Root's initial graph01 included a provisional floor<=generation condition removed before graph02 froze. The independently rerun final graph02 tests include the actual 20-source-operation import producing target generation4/floor20. This legitimate present root remains readable; the audit did not introduce or request a floor<=generation restriction.

## Checks actually run

| Check | Result | Raw evidence |
| --- | --- | --- |
| Both final owned ReadView suites on own private graph |26/26; seed407281;8.3s; compile diagnostics empty | `independent-baseline-26.log`, `run-baseline.exs` |
| Fresh independent adversarial controls |7/7; seed209417;1.4s; no assertion changes | `independent-adversarial-first.log`, `run-independent.exs` |
| Actual isolated old-helper compatibility control |Pass; `{:unknown,:collection_lock_lost}`; no root/result/remaining cache | `independent-old-helper-compat-final.log`, `run-old-helper-compat-final.exs`, `old-helper-compat-03/` |
| Exact public persistence exercise on own runtime |Pass; manual/code hashes match Root's reviewed bytes | `independent-public-example-final.log`, `replay-public-example-final.exs`, `public-example-reviewed.exs` |
| Complete manual review and relative file targets |Chapter read as a whole; all relative file targets exist | `persistence-reviewed.md`, public-example log |
| Original and copied regular inputs after execution |All1,105 unchanged; shared108c unchanged | `independent-final-integrity.log`, `verify-independent.exs` |

Root separately completed 135/135 tests from fourteen Collection/Normalizer/managed SDK/migration suites, seed20261106,300.7s. The author raw log is retained as `owner-broad-final-135.log`; this auditor did not rerun those fourteen suites or present them as independently authored controls. Root also supplied its strict 128-module compile, actual Elixir1.18 four-file formatting/two-module compile and public example receipts. Those retained `compile-first.log`, `compat118-final.log`, `doc-exercise-final.log` and `tests-first.log` are author evidence, separately identified from this auditor's runs.

Fresh controls cover:

- Exact version2 absent result and witness: zero generation/floor, null root/root hash/manifest hash, caller-order nil rows and empty scans. Subsequent reads create neither root nor operation receipts; the protected file inventory remains unchanged.
- Fourteen new-root rejection variants: both `get_many` and `scan` after absence admission, each with a dangling symlink, hardlink, zero-byte file, oversized file, duplicate-key JSON, NUL content and FIFO at the selected root. Every call refuses and invalidates its cache; original object metadata and outside synthetic payload remain untouched.
- A present root rewritten to semantically identical JSON with different whitespace becomes stale. Explicit reopening accepts the actual new bytes/hash. Deleting the last real record yields a present materialized-empty collection with actual root/hash and retained nonzero floor, rather than an absent witness.
- Exact cache validation rejects unknown keys, ambiguous versions/numeric types, project mismatch and fabricated record metadata. A structurally valid privately installed fabricated present cache cannot survive the actual native absent root; its first selected read is stale. Direct cache installation is trusted Core machinery, not an authority grant.
- Closing the cache inside an actual absent read's native critical section withholds the otherwise valid empty result at `ReadView.finish` and allows explicit reopening.
- Killing the original absent-view owner while its real native borrower is paused closes the metadata cache and native controller even though the completion borrower survives. Fresh opening/read succeeds; resuming the old borrower yields no successful result.
- Mutating absent cache header fields (`root_state`, hashes and collection root) fails integrity validation before any result.

## Actual old-helper control and harness diagnostics

The compatibility fixture copies the complete frozen Ipse application BEAM set, retains the exact unmodified Runner source, then compiles only Runner in a separate private project against copied historical108c helper bytes. Its child uses that private app_dir; the main frozen 6f graph is unchanged. It deliberately points `IPSE_RUNNER_PATH` at the new6f helper while the protected channel remains pinned to108c. Collection's actual optional H call refuses, no root is published, and the provisional cache is gone. This is a compatibility variant, not the main graph's pinned identity or a bypass of its helper verification.

The first compatibility harness stopped on the expected module-redefinition warning when intentionally recompiling Runner. Its successor sets only the private compiler's `ignore_module_conflict` option and has empty compile diagnostics. That successor then correctly refused as unknown `collection_lock_lost`, while the harness expected only an error `collection_unavailable`. The final harness explicitly admits those two refusal outcomes and still forbids any success/absence result. All three scripts, original logs and private variant graphs remain retained; no production source was changed to obtain the result.

The first public-example harness hashed the trailing code-block newline, producing a different digest before executing. The final harness applies the same trailing whitespace trimming as Root's recorded code hash, verifies the expected manual/code bytes, executes the unchanged public example and checks relative file targets. Both raw logs and recipes are retained. These are documented harness corrections, not production failures or relaxed success assertions. The fresh7/7 adversarial driver itself passed unchanged on its first run.

## Static review and limits

`Collection.load_for` uses native optional H directly for view opening and every selected read. It does not turn host `lstat`, required-read failures or native error strings into absence. Exact absent cache/result shape is closed at version2; present binding requires current native H bytes and their exact admitted hash. The ordinary Collection loader's extracted empty/pointer helpers retain their existing semantics. Full opening still validates present manifests, blocks and receipts; selected reads rehash only selected objects and retain all quota, lease-check, root-release and cache-finish gates. Cache seals cover the new header fields. Every completed borrowed read returning error/unknown invalidates the cache. The final successful finish gate prevents returning known data after cache close, expiry or borrower loss.

The persistence chapter teaches ownership, native lock order, empty/present witnesses and final checks as one flow. Its example is executable at the exact reviewed bytes. It accurately distinguishes actual absence from materialized empty state and names capacity, arbitrary same-UID/raw-BEAM and managed/Session integration limits. All relative file targets were checked; this audit does not claim a full repository-wide documentation anchor check.

No managed eligibility, saved absence authority, automatic capture, Session freshness or cross-turn recall was inferred from these storage results. The existing ManagedReferencev1 remains a separate present-only integration. Same-root corruption of unselected immutable data may remain undetected until full reopen, as documented. Synthetic trusted-host cache/header and root-byte mutation tests demonstrate rejection properties; they do not establish containment of arbitrary hostile Core BEAM or raw same-UID filesystem writers. Native H's ENOENT/FD/protocol machinery and general ReadView bounds rely additionally on the previously preserved independent facility audits and the final baseline suites; they were not exhaustively re-audited here. No whole implementation, platform, operator UI or semantic-quality claim is made.

## Durable reproduction

Evidence is preserved separately under `/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-empty-read-view`, with every created directory0700 and single-link data file0600. Full frozen sources/runtime/helper, tests, independent replay drivers, compatibility variants, owner receipts, raw diagnostics and exact manifests are retained. Non-runtime `project/deps` and unused broken telemetry source links are explicitly recorded and omitted; app runtime `build/lib/ipse/priv` is materialized as regular copies of the bound project priv data. No symlink is required or retained in durable evidence.

Never execute or chmod preserved evidence in place. Copy it to a new private working directory; chmod working `project/priv/ipse-runner` and `build/lib/ipse/priv/ipse-runner`0700, then run `elixir <copy>/run-independent.exs` or `elixir <copy>/run-baseline.exs`. The drivers select the working project CWD and runtime. For old-helper compatibility, reproduce its final builder in a separate working copy without existing generated compatibility directories, or copy the retained final fixture to a new private path and set only its working helper copies executable before running its replay. Frozen and durable manifests bind original bytes; generated fixture paths, original `/tmp` provenance and stale copied compile metadata are not instructions to mutate any original graph.
```
