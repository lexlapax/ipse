Historical-only independent report, finalized **2026-10-27**. The literal report
below is preserved from the separate auditor's owner-only evidence. Original
report SHA256: `7b8017b033edb26f4384369473dd0454c258ef08d61a9083e0cd137a5d792249`.
The [component receipt](managed-reference-v2-component.md) records author checks;
the [current plan](../../plan.md) owns the open integration/acceptance gates.

# Independent pure ManagedReference v2 audit

No actionable defect was found in the exact frozen pure component. Independent baseline24/24 and fresh adversarial12/12 pass. This is an incremental schema/lineage/projection audit; it supplies no actual host proof, current freshness, Session integration or milestone acceptance.

The auditor did not author or repair production source or owned tests. Root's graph was copied and all1,104 source/runtime regular files verified before authoring fresh probes. No source fix occurred during the audit; original/copy hashes remain identical after tests and preservation. The repository/index/shared build/helper and prior evidence were untouched. Tests use synthetic pure values only: no native helper, model, network, paid account, credentials, private transcript or qualification gold was exercised. Preservation uses ordinary Elixir file/directory sync, not a helper protocol.

## Exact provenance

Original graph: `/tmp/ipse-managed-reference-v2-20261026-01`. Independent working copy: `/tmp/ipse-independent-managed-reference-v2-20261027`. Scripts select copied `build/lib/*/ebin` code paths and the copied `project` CWD. The authoritative manifest is copied byte-for-byte and uses relative paths; `freeze-independent.exs` and `verify-independent.exs` verify both origin and copy against every entry.

| Input | SHA256 |
| --- | --- |
| Original manifest, all1,104 regular inputs | `3041102f188fa49f8925ed78d8d9e0d25b4c100fb79087c955774cf42920dabc` |
| ManagedReference source | `6d853a23140da82362ffcce1cb8f31e01eeeca6824d7fee40678ed3293328b3c` |
| Owned test source | `fb06eff5f797c8bef411bb0f96f180b73a5cccdce391504758f0cbf176b59def` |
| ManagedReference BEAM | `b583b71a781f67e05fc859980dab77754b0b6e65f2c4f0d267f5fa25b9cbfaec` |
| Private helper, retained but not exercised | `6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d` |
| Shared old helper, unchanged | `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29` |
| Fresh original driver | `1b563743974f1ddc419fe43a29d147d7c20a88944a802aeaf190d98616cda79f` |
| Fresh corrected driver | `cc7bb5ba8a4e1ebf6baaa71a0fbba177cc9787acecb83a1408270a982a643005` |
| Explicit harness correction diff | `bf8330b3b6550442c965acfa4c06cb5a52f661f88a6c5a3ec9601f88fedefc22` |
| Complete reviewed workspace-context chapter | `f13c74050088eeee37565abbaa627defbccfcecb342124d6ef25ef88d1b494d2` |
| Owner component receipt at review | `b4935305641e64c4413c5f804d669743e6b630638a37fc3547beb50c069861d8` |

The copied graph derives from the earlier native CLI repair snapshot and replaces only ManagedReference source/test. The subsequent empty ReadView implementation and concurrent decision-policy increment are excluded. Retained ancillary sources and old compile metadata are not a claim that every other application/dependency BEAM was freshly rebuilt. The frozen runtime and new pure component are bound exactly by the manifest.

## Independent execution

| Check | Actual outcome | Raw evidence |
| --- | --- | --- |
| Owned focused suite on own frozen graph |24/24; seed371049;11.3s; test compile diagnostics empty | `run-baseline.exs`, `independent-baseline-24.log` |
| Fresh first adversarial driver |11/12; opaque-call fixture refused an unfinished native tool group before withdrawal | `run-independent.exs`, `independent-adversarial-first.log` |
| Fresh corrected adversarial driver |12/12; seed261507;1.4s | `run-independent-corrected.exs`, `independent-adversarial-corrected.log` |
| Source/runtime after execution |All1,104 original and copied entries unchanged; shared helper unchanged | `independent-integrity-after.log`, `verify-independent.exs` |

Full fresh commands:

```text
elixir /tmp/ipse-independent-managed-reference-v2-20261027/freeze-independent.exs
elixir /tmp/ipse-independent-managed-reference-v2-20261027/run-baseline.exs
elixir /tmp/ipse-independent-managed-reference-v2-20261027/run-independent.exs
elixir /tmp/ipse-independent-managed-reference-v2-20261027/correct-harness.exs
elixir /tmp/ipse-independent-managed-reference-v2-20261027/run-independent-corrected.exs
elixir /tmp/ipse-independent-managed-reference-v2-20261027/verify-independent.exs
```

The original driver had an unused private default argument warning and constructed a lone assistant tool call without its matching tool result. `Managed.plan` correctly refused that incomplete native tail before the intended unsafe-withdrawal check. The correction supplies a synthetic matching result and removes the unused default. It leaves every production assertion, including refusal of unsafe opaque/call/checkpoint withdrawal, unchanged. The original failing driver/log and exact diff remain retained. An initial correction-generator script had a delimiter syntax error before producing a driver; that original generator and its subsequent diagnostic are retained separately. No production source or runtime was changed to obtain12/12.

Root separately reports a strict128-source compile, owned24 focused tests,81 broader managed/reference/replay/wire/context/source-index tests, and actual Elixir1.18.5 format/compile success. The copied `compile-first.log`, `tests-first.log`, `tests-broad-final.log`, `compat118-first.log`, `compat118-final.log` and formatting inspection artifacts preserve those author receipts. This auditor reran the focused24, not the broader81, and does not label the latter independently authored evidence. The first author1.18 formatter harness newline issue remains documented in its own receipt.

## Fresh controls and observed behavior

1. Closed v2 maps reject every missing top-level, collection and subject key; unknown fields; implicit, float, string or unsupported versions; malformed selectors; bad key syntax; float zero clocks; fabricated absent hash/anchor/validity. The exact96-byte key boundary is accepted and97 bytes refuses.
2. v1 record/null-record and v2 record/absence receipts coexist in a canonical deduplicated union. Eligible refresh cannot silently reinterpret versions or upgrade a legacy null record to explicit v2 absence.
3. Exact missing-key absence can survive an unrelated later publication only with a supplied current receipt preserving the same complete selector. Record substitution, another key, key-absence to collection-empty substitution and same-generation changed-root refresh refuse. Every noneligible reason withdraws the whole admitted occurrence.
4. Materialized collection-empty subjects retain a present root and may carry imported floor19 above local generation3. Newer generation/current root succeeds; floor/generation regression, changed hashes at the same generation and present-to-absent regression refuse.
5. Newer roots cannot replace record key/revision/value hash, recipe, lineage, source versions, eligible status, actual project, pin or policy generation. Eligible without a current receipt and noneligible with a current receipt refuse.
6. Record expiry remains exclusive at the maximum safe integer: expiry-1 succeeds, exact expiry refuses eligibility, invalid safe-integer overflow refuses, and an expired verdict can safely withdraw at that boundary.
7. Inherited negative premises survive reformatting alongside another missing key and a positive record. Checkpoint union retains all three. Losing the original absence withdraws both the original and derived answer, releases no still-active dependency incorrectly, and never revives a withdrawn, missing or duplicated parent.
8. Negative withdrawal refuses opaque provider continuation, managed assistant tool-call arguments and checkpoint content without a separately safe reconstruction. The corrected tool-call case includes its matching native result so this test reaches the intended projector boundary.
9. v2 admission/projection replay checks exact message, plan, dispatch binding, verdict set and withdrawal receipt. Mutated event version/hash/withdrawals/current verdict, cross-request binding and changed admitted message refuse. Valid replay always returns `live_pending:true`.
10. Mixed v1/v2/negative batch verdicts cover every distinct old dependency exactly once. Reordering is canonical; missing, duplicated, extra or open-shape verdicts cannot erase lineage.
11. An actual encoded8,192-byte v2 dependency passes;8,193 refuses.511 exact-size dependencies fit the4MiB dictionary while512 refuse;15 exact-size dependencies fit a direct occurrence while16 exceed the128KiB encoded union bound. No eviction or truncation occurs.
12. Explicit negative v2 dictionaries retain2,048 distinct keys and refuse2,049. A direct occurrence accepts128 negative dependencies and refuses129 without dropping an entry.

The original focused suite additionally exercises1,024 occurrence-index admission, original v1 behavior, withdrawal ordering and tool-result shape, longer multi-turn taint/checkpoints, and the existing byte/count bounds. These were actually rerun unchanged.

## Static review, documentation and limits

Review covered the complete ManagedReference module, its owned tests, the v2 component receipt and complete developer workspace-context chapter. The changed discriminator feeds existing canonical union, state/plan validation, replay, expiry and withdrawal paths. Absence contains no invented validity and cannot carry a record under an absent root. Eligible refresh compares exact dependency version/project/namespace/pin/policy and complete absence selector; record refresh preserves its exact record plus recipe/lineage/source versions and current exclusive expiry. Same-generation collection identity is exact and floor/generation cannot regress. Existing bounded dictionary/index/occurrence/event and projection safety checks remain in force.

These are pure normalized-host contracts. Hash syntax does not prove physical root bytes; the function cannot prove a selector's result, authenticate a committed producer, infer genuine collection emptiness from an incomplete scan, or verify a caller's live observation. The host must normalize an actual complete result, authenticate its producer, supply the full inherited/read union and bind a fresh dispatch verdict. A structurally valid worker map has no authority. The module and reviewed documentation explicitly place those obligations outside this pure component; their absence here is not reported as a newly discovered missing feature.

In particular, an absence-to-present refresh with the same exact missing-key selector is a legitimate pure operation only after independent host proof that this key remains absent. A collection-empty selector requires independently established genuine emptiness. Record validity timestamps/lineage are supplied host facts, not a clock or proof minted by this module. Replay verifies history and always leaves current eligibility pending. This audit establishes none of the eventual native ReadView/SDK/Session/SourceIndex/current-read/dispatch wiring, every-dispatch live fencing, provider semantic quality, whole-system acceptance or other milestone gates.

## Durable reproduction and preservation

Durable evidence: `/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-managed-reference-v2`. All created directories0700 and regular single-link data files0600; full frozen source/runtime, independent drivers, raw first/corrected logs and author receipts are retained. `files.sha256`, `diagnostics.sha256` and `PRESERVATION-RECEIPT.txt` bind the completed files and preservation checks.

Unused `project/deps` and telemetry source links are explicitly recorded and omitted; the runtime's `build/lib/ipse/priv` link is materialized from the exact bound project priv bytes. No frozen regular input is omitted and no symlink is retained. Every copied file is byte-verified and synced; directories are synced through Elixir raw directory descriptors. Existing evidence is never overwritten.

Never execute or change preserved evidence in place. Copy into a new private working directory and run `elixir <copy>/run-independent-corrected.exs` or `elixir <copy>/run-baseline.exs`. These pure controls require no executable helper permissions. The verification recipes retain original `/tmp` origins as provenance; adapt only the verification root when the historical origin is unavailable, and keep the preserved relative-input manifest unchanged.
