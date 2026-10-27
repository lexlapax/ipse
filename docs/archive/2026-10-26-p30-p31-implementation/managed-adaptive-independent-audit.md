# Independent adaptive Stage 1 audit

2026-10-27. Independent read-only component audit, not a whole P30/P31 audit or product qualification. No repository source edits, Git changes, dependency acquisition, provider/model calls, native/helper invocations, stored Collection reads/writes or qualification/gold reads occurred.

## Disposition

No actionable defect found within the declared **pure Stage 1** contract, subject to the explicit SAME-profile prior-occupancy precondition below. This disposition does not approve product adoption, metadata authenticity, import, lifecycle operation, managed current reads, four-thousand-record capacity or annual acceptance.

Two documentation precision points are now explicit in the author's record: local plans are conditional on previously validated old occupancy under the same geometry/catalog, and the original evidence retains per-page byte **counts and hashes**, not encoded page bodies. The independent regenerated bodies described below are additional audit evidence, not retroactive original artifacts.

## Frozen inputs and independence

Original graph: `/tmp/ipse-adaptive-proof-20261027-05`; original evaluation package: `/tmp/ipse-msgpax-http-evaluation-20261027-03`.

Independent working copy: `/tmp/ipse-independent-adaptive-20261027-01`, with `graph/` and `msgpax/` copies. `bind.exs` verifies every one of the original 741 declared source/BEAM/input/package/helper files against its author hash and corresponding independent copy. Before and after all checks, its canonical relative manifest is unchanged:

`fe717a6a143c1cf693cf8baf970f35e67ab90b363bf51c3de4c66b5813591861` (`inputs.sha256`).

The helper was inventoried, never invoked. The read scope included all six new developer/test files, relevant immutable IMB1 and Codec field validation, pure Notes-model entrypoints, the complete author record and package/dependency evidence.

| Source | SHA256 |
| --- | --- |
| Adaptive codec | `a380ce2b15168ba645eab64d1fcfe008d49aa84f842eadeeef5d8db43a5e4d31` |
| AdaptiveLeaves | `d5b11d8ae340102cc889e9cf77b42061f865895d2bdf0dc3b8269503ef3cbd38` |
| AdaptiveCases | `46df1518c003c2ae12b1093530bfcd1cfeae8d11872c2d7b22dfe3e4344fc3af` |
| AdaptiveMsgpax | `d64bc7bbb97d046f87d567bb3159c4d9973a2f4fe1c63c15a51a90cbef2dd51c` |
| Bounded runner | `250b019b3ffbe33393a76a4efab97e88c4c7165c1c2dfea9ad059a6b2edac51c` |
| Eight maintained tests | `7cc44951151f1d6c37eab84e18096aa419d681a13930ac099dfbf22c2afb80e0` |

## Executed checks

* Maintained **8/8 tests** reran through the copied bounded runner, Elixir 1.20.4 / OTP29, two schedulers, single test concurrency: `tests.log`, `tests.json`; 5.2 seconds reported by ExUnit. No model/native/store work was selected. All loaded functional-module MD5s match the original test report. The relocated ExUnit test module differs because its test file tags contain the working copy's path; the actual test source hash is identical.
* Fresh **7/7 independent tests**, seed20261115, single concurrency: `fresh.exs`, `fresh-corrected.log`, `fresh-result.json`. They cover all integer width boundaries through the safe maximum; canonical nonminimal ULEB refusal; empty zero-sentinel/nonnil-upper separation for all three kinds; safe-sum overflow and forbidden presence flags; closed capsule/challenge/input/reason controls; exact 256-byte UTF-8 legacy reason plus full target retirement; same-page/two-edit shrink and insertion against a complete oracle; catalog union/outside-member refusal; and the accepted old-occupancy precondition.
* Actual **Elixir 1.18.5 / OTP29** strict source compilation: ten source files, eleven emitted modules, no compile/runtime warnings or diagnostics (`compat118.exs`, `compat118.log`, `compat118-beams/`). Six source/test formatting checks also pass (`format118.log`). ExUnit is absent from that packaged release; **no 1.18 test execution is claimed**. This is not an OTP27 runtime check.
* `reports.exs` independently verifies all **41 page jobs plus four controls =45**, their declared inputs, successful or expected-negative exit status, before/after bindings, zero native/model/publication fields, <30-second completed-job durations and sampled memory under512MiB. Static runner review confirms a separate original-deadline timer, main/test 16-million-word heap guards and a sampled VM memory guard. These are developer guards, not atomic product allocation enforcement.
* All **72** joined original controls recompute; **24** fit their declared selected accounting. The annual3642 conditional calendar/shared/native/compact-retirement case totals2,616,423 with172,953 headroom. Fresh4000x6144 totals891,637 against589,824, a **301,813-byte miss**. Full legacy/distinct hashes/full target witnesses retain their negative dispositions. No quota, population, persistent/pin count or format reserve was reduced.
* All **459** original evidence-bundle members match declared lengths and SHA256; the enclosing archive matches `c0cd50e3c67939433480a162f9eb835e787cee9fc2ff48ff91bfd3b45626c8cf`. The preserved original empty-sentinel negative7/8 receipt/log was reopened. Msgpax tar/source/ISC license are covered by the741-row check; acquisition was not repeated.
* Regenerated **six representative page bodies**, first/middle/last of the512 anchor pages and128 catalog8 live pages: `regenerate.exs`, `regenerated-*.json`. Every regenerated canonical value's bytes/count/hash and identical-facts Msgpax comparison match its original measured page entry. Exact inverse rows match the bound fixture; an appended raw byte refuses. Logs are `regenerate-anchor.log` / `regenerate-live.log`. These are new audit artifacts; original page bodies were transient. Only two representative configurations were regenerated, not the entire41-job matrix.

The Msgpax adapter compares the same hashes, front-coded identities, exact clock pairs, complete legacy/native choice and retirement facts. Its arrays roundtrip/reencode on the exact same page memberships. The report correctly discloses that no Msgpax-specific optimized repartition was evaluated, so a measured miss is not a universal MessagePack impossibility proof. Generic parser acceptance of nonminimal/unsafe integers or duplicate-map collapse still requires a closed canonical product adapter. Synthetic43-character tags and the75-byte envelope authenticate nothing.

## Accepted local-plan precondition, positively probed

`AdaptiveLeaves.groups/decode!` checks canonical rows, directory/ranges and upper capacity but does not establish the old nonsingle leaf minimum. Fresh test7 constructs an underfull old leaf: full `validate_tree!` refuses it, while a local repair can normalize it to a valid result. This is deliberately **outside** the accepted local-plan input contract. The pure Stage1 contract requires previous `initialize/validate_tree` proof under the **same immutable geometry and catalog**. Changing the profile or supplying arbitrary imported/malformed old trees is unsupported. Future host integration must recheck old selected minima and bind that immutable profile, or prove an equivalent trusted producer invariant; a MAC alone is insufficient. No product integration was reviewed or approved here.

## Preserved independent harness diagnostics

1. Initial fresh suite: **6/7**, with two audit-harness warnings. The failed assertion incorrectly demanded that a stream clock primitive reject a valid canonical prefix when remaining bytes could belong to later fields. Fixed-width bytes read under a variable selector can begin a valid smaller integer; full page parsing establishes complete consumption. The corrected probe checks that precise prefix contract and retains full-page trailing-byte/flag controls. `fresh-before.exs` and `fresh-first.log` preserve the original. Unused-helper-default/bitstring-size warnings were removed in the audit driver; no component source changed.
2. Initial report verifier compared the relocated ExUnit test module MD5 as if its path-bearing tags were invariant. `reports-first.log` preserves that failed audit assertion; all functional modules matched. `reports-before.exs` and the corrected verifier retain exact source-hash checking plus the explicit test metadata exception.
3. Repeating the report verifier encountered its own already-created extraction directory. `reports-bundle-exists.log` preserves that diagnostic. Making only the scratch output-directory setup idempotent produced `reports-final.log`. Original bundle/input bytes remain unchanged.
4. Regeneration compiled AdaptiveCases without loading its unused model-only StorageWorkload dependency first. The resulting three compile warnings are retained in both regeneration logs; no missing function was called. The strict ten-source compatibility check loads the full dependency set and has no diagnostics. The regeneration results are not represented as warning-free strict builds.

## Limits and next gates

No Stage B external-reference omission was introduced: live pages retain all four hashes. Occupancy/range/local-edit arithmetic is not authenticated source causality or live domain retention. The annual declarations are exact byte-width fixtures, not a complete chronological year of Sources. Public6KiB payload accounting does not mean those payloads were materialized. The SDK's existing32-read publication closure, future weighted directory accounting, actual revision/CAS, all sidecar reservations, authenticated inherited pages and product inverse remain unwired. Native transactions, Identity auth and neighbor-selection components have separate reviews; this audit does not independently accept them.

No actual storage peak, filesystem portability, interruption/recovery/import journey, human/macOS use, model usefulness, or full milestone acceptance is established. The original failed3724 store and its oracle were not accessed or resumed. No production code changes are required for this narrow pure checkpoint; Root retains acceptance and integration decisions.
