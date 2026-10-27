Historical-only independent component audit, **2026-10-27**. Original report
SHA256: `65fcd2c31944d94869226bd83fd0a4d657ad9ef35116dc430dd0515fe3204f50`.
The [component receipt](collection-neighbors-component.md) records author checks
and durable provenance. The [plan](../../plan.md) retains milestone status.

# Independent Collection Directory / neighbors audit

2026-10-27. Incremental generic-storage component audit. No milestone acceptance or managed-reader/integration approval is implied.

## Verdict and independence

No actionable defect was found in the frozen Collection/ReadView/Directory component under its stated trusted-Core/cooperative-storage boundary. This auditor did not author the implementation or its owned tests. The exact owner graph was frozen before independent execution; no owner repair or public edit occurred during this audit.

The unchanged focused suites passed **48/48**. Independently authored fresh controls passed **15/15**, plus **1/1** exact-deadline control. The exact public persistence Collection example also passed against the copied runtime. All **2,312** declared source/runtime input hashes remained exact in owner and independent graphs before and after execution and in retained evidence.

## Exact graph and scope

Owner graph: `/tmp/ipse-neighbors-rootcheck-e12d8993c99f00ef`.
Independent graph: `/tmp/ipse-independent-neighbors-20261027`.
Manifest `source-runtime-before.json`: `889940cafbe726c0cb8b227d952acae603c9379a0ba67f7dfe9294cfd1ca5c3f`, exactly 2,312 regular project/build inputs. The owner's declared Git metadata and Mix execution-cache exclusions remain explicit. No sources or BEAMs were rebuilt for this audit.

| Input | SHA256 |
| --- | --- |
| Collection source | `632f6b2674374c87eb8e080ecdccfe599b6c9ee8002303631c40b124e9a0d92c` |
| ReadView source | `54e6b40ae9f3a0742a257a3666fa8e4a1aacb95bc1c261b9cc1e5ce85656c598` |
| Directory source | `1aea077f1727e893766e783c0a6e747492f9975dcb9bd54700d92c772d2a2a13` |
| Collection BEAM | `d2f52879b35847e8f969763cb86376799cd501304716336ae9a7c0935a4856a6` |
| ReadView BEAM | `5c1b89d4d0fcf3bd7102cb487206f2c450b056ffb33d0f10bd6788dd31266b83` |
| Directory BEAM | `814f40d752294283b7bed81221ede8ec07fc05051c1a20939817348c5c513001` |
| Executed private helper | `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b` |
| Neighbors test source | `e6fb56b5fad5f7570320c68a5570c6ce69d48048a72022f758fb79ea625e104e` |
| Directory test source | `8af5cbc2644607cfb9a903bf0c3ac941cb1558a54f1659a9ae25ba7bfce16d7b` |

The private app_dir/helper selection was exercised from the private project cwd. Public shared helper `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29` was hashed read-only before/after and never executed or changed. No shared build, helper, repository/index, owner graph, qualification material, private transcript, credential, provider/model/network service or operator/PTY facility was used or mutated. Native Collection H transactions used only synthetic private fixture paths.

Read actual AGENTS, the complete new Directory and ReadView modules, Collection's public wrappers/read-view/native load/root-check/result/final-check/release paths, all four focused test files and the whole current 731-line persistence chapter. The audit targets the new generic neighbor selection and weighted read-view budget, with its inherited owner/lifetime/cache/native invariants. The author's earlier unsealed/incorrect-CWD checkpoints were not used as executable evidence.

## Static findings

The descriptor is closed and exact: integer version one, ASCII record-key prefix ending in dot, width 32 or 33, lowercase hex needle of twice that width, and complete prefix-plus-fence length at most 96 bytes. Present selection requires the zero sentinel and validates every matching-prefix key, including names outside the selected four. Absent selection requires an actually empty cached index and remains distinguishable from a materialized empty root.

The ordered index uses opaque OTP gb_trees APIs, without destructuring its representation. Selection finds the greatest lower fence and bounded predecessor/selected/two-successor slots. Forward/reverse boundaries stop at the complete prefix. Full key/header seals and matching-prefix reference seals run before payload borrowing; native root matching runs again before metadata projection. Selected refs preserve original key/revision/hash/length/operation ID and carry no object values.

ReadView charges valid requests before lookup/native IO: neighbor four, get_many requested count, scan requested limit. The legacy 512-call ceiling remains alongside 512 observation units. Requests that exceed either allowance close/refuse rather than truncating results or renewing counters. Malformed descriptors refuse before borrowing and do not consume counters. The code retains exact caller/opaque ref/registry/active-effect validation, one view per original task, 16 global slots, absolute 60-second lifetime, 8,192 refs, four-MiB encoded installation budget and 64-KiB reply bound. Those metadata ceilings do not claim a total heap/RSS bound.

Each call acquires the actual native owner, H-reads the exact current root, runs native quota/check/release, then requires successful ReadView completion. Close/expiry/native-owner or scope loss can therefore withhold an otherwise completed metadata result. Native checks and release remain mandatory independently of cache completion. Hostile raw BEAM and arbitrary same-UID storage rewriting are explicitly outside the claimed boundary; private-state mutation controls exercise accidental/cooperative integrity, not containment of hostile Core.

## Executed independent evidence

Unchanged focused suites, `owned-first.log`: **48/48**, seed 20261114/max_cases 2, 12.3 seconds. Independent AST counting confirms 10 Directory + 12 neighbors + 19 read-view + 7 empty-view cases. This includes inherited slot/count/owner/native/expiry/cache/refusal controls and actual new neighbor owner-loss/expiry paths. The owner's separate 157-case broad suite is retained as `owner-broad.log` and remains author evidence; it was not unnecessarily rerun or relabeled independent.

Fresh actual public-API controls in `fresh-neighbors.exs`, `fresh-first.log`: **15/15**, seed 20261115/max_cases 1, 2.8 seconds. They call the actual frozen C/ReadView/Directory BEAMs and helper directly, without source-derived substitute modules:

1. Actual native neighbors at both maximum 96-byte key layouts: 32-byte fence with 32-byte prefix and 33-byte fence with 30-byte prefix. Eighteen selections match an independent numeric/list oracle across exact, between, first and last boundaries, with exact current-root SHA and bounded replies.
2. Separate pure sparse/dense numeric oracle over 134 needles, mixed-case punctuation prefix and unrelated lexical neighbors. It uses plain numeric/list expected positions, not a mirror of the gb_tree implementation.
3. Invalid exact-boundary descriptors, malformed UTF-8/hex, non-ASCII/oversized prefix, floating integers and atom/string extra-key substitution refuse with both counters still zero. A valid actual absent-root neighbor then succeeds.
4. **Actual** 512-unit exhaustion without seeding counters: sixty empty scans at limit eight (480), three missing-key batches of eight (24), one neighbor lookup (4), then an empty scan at limit four (4). The resulting 65 calls total exactly 512 units. A subsequent neighbor refuses before native projection; empty/missing results receive no refund, and no root was published.
5. Legacy 512-call ceiling still gates neighbors independently of remaining units. This separate boundary control seeds only reads=511, observes the allowed call reaching reads512/units4, then refusal.
6. All selected and unselected object files are removed after opening the immutable index. Neighbor refs still succeed and root bytes stay unchanged; an actual value read then fails. This establishes zero object-value reads directly, beyond the telemetry's value_reads:0 declaration.
7. Poison beyond the four returned boundaries in the full matching prefix causes refusal, while an unrelated prefix cannot be silently mistaken for the requested directory.
8. Mutation of an unselected but matching-prefix cached ref is caught before native projection, not merely when that ref later becomes selected.
9. Semantically identical JSON root re-encoding cannot reuse the cached byte witness. The view goes stale; explicit restoration/reopen revalidates a new view.
10. A dangling selected root cannot turn an absent-root view into an uninitialized neighbor fact.
11. Cross-task, forged opaque reference/server and ordinary-map handles reveal no refs and debit no owner counters. The genuine owner still succeeds afterward.
12. An actual Resources.file_effect callback shares original ownership and shows reads1/units4 already charged at the post-root-check projection boundary.
13. Closing the cache after successful root recheck withholds the otherwise complete metadata result at finish.
14. Killing the actual retained native controller after root recheck returns unknown collection_lock_lost, releases the cache, and permits an explicit fresh view; no metadata success escapes.
15. Actual scoped cancellation fences a paused native neighbor borrower and withholds its fact even while the file-effect worker can resume. Original owner/cache cleanup is observed.

A separate exact-deadline test, `fresh-expiry.exs`/`.log`, passed **1/1**, seed 20261116, 0.2 seconds. At successful native projection it sets the synthetic view deadline to exactly the current monotonic time. Finish withholds the otherwise valid absent result; the old handle stays unusable and an explicit newly opened view gets a different opaque ref. This is a controlled deadline-boundary fixture, not a claim that natural 60-second wall-clock expiry was waited out.

Telemetry info logs about local anonymous handler performance are retained; they are not test failures. No failed functional control was suppressed, corrected or relabeled as a pass.

## Whole developer chapter and exact example

The entire current persistence chapter was reviewed for ownership, ordering, limits and distinction between implemented generic storage and future managed policy. Its retained SHA256 is `843af292c42d6b6cf706b6769f9e384d1eadf2cc8641bd1c7c13a7c443ddaffe`; the after check proves the public chapter still equals the reviewed copy. No actionable documentation inconsistency was found.

The exact public Collection example was extracted from that copy and executed unchanged against the private runtime, private HOME and TMPDIR. It passed native absence, no fabricated root/manifest hash, generic publication, correct positional refs, no value member in the metadata ref, then exact selected value reading under the same root. `manual-exercise.log` records both its ordinary success line and `EXACT_PUBLIC_COLLECTION_NEIGHBORS_EXAMPLE_PASSED`. Other unrelated chapter examples were read, not re-executed by this audit.

The chapter correctly separates metadata refs from page contents/eligibility and distinguishes generic absence from managed absence authority. It also discloses full-key/matching-ref validation cost, encoded metadata versus tree/heap overhead, and that the existing managed-publication 32-read closure is not wired to the new selection/cost helpers.

## Setup failure retained

The first orchestration call requested a not-yet-created private project as cwd while trying to create that copy. The tool refused before executing a command or test. `setup-cwd-failure.log` records the error and correction: create from the existing cwd, verify the full copy, then run from its private project. This setup failure changed no source/runtime/probe assertion. All executed functional test runs passed on their first execution.

## Commands, hashes and preservation

Commands actually run from the independent working graph:

```sh
elixir verify-inputs.exs
elixir -pa '/absolute/private/build/lib/*/ebin' run-owned.exs
elixir -pa '/absolute/private/build/lib/*/ebin' fresh-neighbors.exs
elixir -pa '/absolute/private/build/lib/*/ebin' fresh-expiry.exs
elixir -pa '/absolute/private/build/lib/*/ebin' manual-exercise.exs
elixir verify-inputs.exs
elixir final-bindings.exs
```

All drivers use their own __DIR__, switch to their private project cwd, and allocate separate synthetic TMPDIRs. The manifest checker additionally compares the historical owner's absolute path; adapt only a disposable working copy or verify retained rows locally if that historical graph is gone. Dependency-source aliases are not required for direct no-compile replay. Restore working build/lib/ipse/priv against working project/priv and chmod only working helper copies0700; preserved executables are data0600. Never run or mutate durable evidence in place.

| Artifact | SHA256 |
| --- | --- |
| fresh-neighbors.exs | `96fb5e848c1030e4ef33cab312cca102df0961a8413222284a88b1e5dae7958b` |
| fresh-first.log | `139004bc8b22b7edd3a2af79f135f2271d53a17e8ba50295004cb64de76436ee` |
| fresh-expiry.exs | `d6901cfd7dec523778dbba325ddf5eda86ed7b733755f1f439db55912a0baa6d` |
| fresh-expiry.log | `f533de455172ac5b5d0ced40f1e6f36966eacbd33522dab17ec046cd0013d666` |
| owned-first.log | `75f2ab808886301b4262fd2838faa1f8ef7ce078b485d0dfcbb62c33e8bff9d7` |
| manual-exercise.exs | `47b18afc386bca8652b628ebd5de037da33f1aab9e378622c57ba569f00d500f` |
| manual-exercise.log | `acf60f4ec71d8bb94c15c38e5788d20fc92d777031be6628bd7fd42c6604e924` |
| after-inputs.log | `181dcfca5567588b6786a53a2528ba9c5eaa9d8080e3fa1b9597fd9f0d9c0812` |

`freeze-before.log` binds sources, executed BEAMs and helper before probes; `after-inputs.log` repeats the exact check afterward; `final-bindings.log` binds independent test counts, chapter and shared-helper read-only observation. The durable files manifest binds every retained graph/probe/log/report byte. Preservation validates every source/destination byte, all 2,312 manifest rows before/after, owner-only 0700 directories/0600 single-link files, materialized private priv runtime bytes and fsync. Its provenance records omitted external aliases and transient fixture directories.

## Limits

No SDK operation, current ManagedRead/Session eligibility, Normalizer-v3, authenticated page adoption, source proof, 32-unit publication closure integration, semantic quality, managed absence authority or whole P30/P31 acceptance was implemented or established. Directory/neighbor results are generic metadata, not a validity decision or permission grant.

The old 26 view controls were rerun and new generic paths were probed, but this audit does not substitute a final whole-implementation audit, full repository suite, packaging, actual supported older OTP runtime, other OS/native operator checks, real human journey or live/provider qualification. Author strict-130-source and Elixir1.18/OTP29 checks remain author evidence, not relabeled independent compilation or OTP27 execution. Natural expiry, broad heap peak and a narrowly isolated loss between the final native check and release were not separately forced; controlled deadline, actual owner/scope loss and mandatory check/release/finish source paths were verified. Cooperative storage and trusted Core remain the boundary, without hostile-BEAM/same-UID containment claims.

## Selected author provenance retained separately

At Root's request, `author-evidence/` additionally retains 31 byte-checked author artifacts: qualified-root compile/focused/broad/inventory/final-origin/manual logs and drivers; all three actual1.18 compatibility logs, scripts and final four compatibility BEAMs; historical01 wrong-CWD/origin diagnostics; historical02 unsealed41-test/strict/unnecessary-recompile logs; and early pure7/10 then10/10 logs. Their exact original paths, status labels and SHA256s are in `author-evidence/provenance.json`.

These remain author evidence. Historical01/02 are explicitly unqualified diagnostics, not alternate audit targets. Root disclosed that an earlier guard failure incorrectly continued into an unnecessary dependent recompile overwriting historical02 BEAMs; none of those inputs was used for this audit. The fresh2312 manifest-bound graph is the sole executed target. The early pure run's before-source was not saved, so those raw logs supply no exact before-source claim. The first compatibility attempt omitted dependencies through quoted Erlang wildcard handling; the second retained target BEAMs on its path and emitted four redefinition warnings; the final author script excludes those four targets from its materialized dependency closure and reports diagnostics empty for three sources/four modules on Elixir1.18.5/OTP29. This auditor copied those receipts without executing them or promoting failed attempts to passes.
