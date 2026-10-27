# Independent Collection v3 Core envelope audit

Date: 2026-10-27. Disposition: **no actionable finding in the scoped candidate**.
This is a Core storage-envelope audit, not managed SDK integration, authenticated
source provenance, current eligibility, a lifecycle workload or milestone acceptance.
No product, test, native helper, shared build, public source or index was edited.

## Audited source and executed runtime

Owner freeze: /tmp/ipse-managed-v3-core-20261027-01. Root acknowledged all 2350
regular project/build rows and membership unchanged after its broad run before
the auditor copied it. Independent working copy:
/tmp/ipse-independent-managed-v3-core-20261027-01.

The unchanged copied BEAMs retain the owner's private compile-source origins.
The auditor did not rebuild them. Runtime checks verify actual audit-copy BEAM
paths, exact BEAM hashes, original compiled source and byte-identical copied
source, the entire identical 2350-row manifest, and the actual selected private
helper. Copies and original sources are distinguished in runtime-check.json.

| Bound input | SHA-256 |
| --- | --- |
| Collection source | 5b02c6dd265f9bcaf7d0201f4953d73bd106ba7dc2b8af4864e4ea75757a6fa7 |
| Executed Collection BEAM | 02cc1a0f0949532c95194447298016b4a06d06aaab221d4052a4e248c2bf624f |
| Complete 2350-row source/runtime manifest | 7e5744894b4cce77b483208cec1cf2d1b93a5b8746c2871bfd5db957b023d447 |
| Auditor's eight fresh native cases | a26cf9041746582aa3f3379a064df8ea4a62eb822b5b54dc285c2dabad1b5bad |
| Verified four-module source/BEAM/copy/helper binding | c0a4c6f62973b6f742db746f178d73b58fa732e44d8aed26047ebcf6cc93809f |
| Selected helper | d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b |

The four bound modules are Collection, Directory, ManagedPages and its Planner.
Binding their inputs does not mean this audit re-reviewed all those algorithms.
The auditor authored the earlier Directory component, so makes no new independent
Directory correctness claim here. The new C-v3 branch and its envelope are the
independent subject; Root's Pages/Planner work has its separate review scope.

## Static review

Read the complete owning eight tests, the related legacy managed tests, and all
changed/shared Collection admission, lock lifetime, original CAS/duplicate,
normalizer, native-root witness, read capability, metadata shape, mutation and
publication paths. Checked the following against the explicit Core contract:

- Existing execute_managed/6 selects version 2; the new explicit entry selects
  version 3. Original reserved metadata keys, missing floor advancement, invalid
  IDs/recipe hashes and excess original changes refuse before a callback.
- V3 normalization preserves exact original changes, generation and floor flag;
  duplicate normalized keys fail the ordinary closed commit validator. Extra
  changes are limited to five total, at most four nonnull writes and one delete.
  Keys match exact anchor64 or live-kind00..02+64 lowercase hex, plus format.
- A metadata delete requires a positive exact retained revision and cannot delete
  format. Ordinary mutation CAS additionally checks all normalized writes under
  the same actual native owner before publication.
- Native missing root requires exactly format, anchor-zero and live-zero,
  nonnull at revision zero. Materialized roots require retained format and forbid
  format rewriting/deletion; a generic host error is never an absence witness.
- The normalizer's bounded object receipt must carry exact integer version 3.
  The binding hashes original request, recipe and normalization; the durable
  operation receipt hashes the exact normalized commit and managed binding.
- Read closure owner/capability identity, the shared 32-unit exhausted latch,
  post-callback native check and final check/release remain in force. Known IDs
  return inspection data before callback admission, including cross-version use.

Synthetic metadata is intentionally accepted from a trusted internal normalizer.
Core does not verify MACs, source authority, a managed format's internal page
semantics or adoption. A retained format key alone does not grant any of those.
Those obligations belong to the future authenticated adapter/normalizer. Raw
same-user/hostile BEAM mutation is outside the existing cooperative host boundary.

## Independent execution

Elixir 1.20.4 / OTP 29: **34/34 pass**, seed 20261206, 5.1 seconds:

- Eight unchanged owning v3 tests.
- Seven unchanged legacy managed tests.
- Eleven unchanged managed-directory tests.
- Eight freshly authored audit tests, using the actual private native helper.

AST counts are retained in test-counts.log. Fresh positives and refusals cover
closed originals, reserved-key impersonation, normalized duplicate keys/altered
originals, receipt integer/JSON/2048-byte cap, wrong written metadata CAS with
unchanged root/original records, valid live kinds 01 and 02, foreign/expired read
closure reuse, native Port loss with no publication followed by fresh successful
acquisition, duplicate IDs across v2/v3, and simultaneous actual native-owner
contention followed by stale-CAS refusal. The concurrency case uses two tasks in
one VM with distinct actual native transactions; it is not a two-VM claim.

All 2350 admitted project/build rows and membership remained unchanged after the
run. The declared Mix execution cache is excluded. Alias paths are not separate
rows; admitted target and helper bytes are retained. Tests use private synthetic
records, no source-derived replacement runtime or simulated helper. No PTY,
provider, model, gold/qualification input or credentials were used.

Actual Elixir 1.18.5 / OTP 29 independently formatted Collection unchanged and
compiled that one source to one module with diagnostics []. This is not an
ExUnit run on 1.18, an OTP-27 claim or expanded filesystem support.

Root's separate owner logs record strict compilation of 133 source files,
38 focused and 177 broad passing tests. Those logs are preserved as owner
evidence; the auditor did not rerun or claim those as its independent scope.

## Preserved harness failure

The initial runtime binding probe passed the whole audit root, which contains
the helper/application, as its workspace. protected_helper correctly refused
that overlap. The first source and failure log are retained. The corrected
probe changes only the workspace to the private sibling tmp directory and then
verifies the actual helper and all input bindings. No test or product repair was
needed; all 34 tests passed on their first run. No failed scope was discarded or
relabeled as successful native execution.

## Limits and handoff

No Core repair is requested. The adapter must still authenticate every inherited
metadata page, enforce recipe/policy/current-source authority, bind the actual
operation/revision, reserve full metadata costs, and keep successful accounting
provisional through outer authority completion. This graph intentionally excludes
new deferred Consent/ManagedCall integration and actual NormalizerV3/SDK wiring.
The shared helper remains untouched. Reproduction must use a new private working
copy; durable helper files are preserved owner-only data and must not be executed
or modified in place.

## Durable preservation and owner evidence

The report above is the literal independently preserved `working-copy/REPORT.md`,
SHA-256 `e1549df8d87b93b6f25fddf3eb5e91c5e37ea540fc46dfc2f4e9e69b5521c9ed`.
The authoritative milestone ledger remains [the plan](../../plan.md).

Evidence base:
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification`.
Both preservation runs verified full source/destination bytes, lengths, hashes,
ownership, `0600` data and `0700` directories, all admitted manifest rows and
file/directory fsync. Original files were neither changed nor chmodded. Aliases
and `.git` metadata were explicitly not followed; admitted targets and actual
helper bytes are retained as ordinary data.

| Evidence subtree | Payload manifest | Provenance | Preservation receipt |
| --- | --- | --- | --- |
| `independent-managed-v3-core`, 2546 files, 2350 admitted runtime rows | `cd96946e8295977dbbc14bd0c5a3e39aac3121169d7818ac45841873a9f8f1a2` | `1e7e1ceea4a303550be41d0ae096a926e2dc8c1185d060a32adc8f0254e6e8ed` | `64939413d1f0da0622779ddc652714fac016db24534d105b906ee617ba96007c` |
| `managed-v3-core-owner`, one complete graph, 2538 regular graph paths mapped to 2356 complete unique byte blobs | `ecb95ce934ae6c73e3f352dead70c5d085f6e2c482e0172c855df1cbc55694b3` | `1bb4c5379f9e222fa702acf8285ecc2772cb9d1822ef7c3c3b80328d590d16bc` | `dacb176f1f03e1d6ed6cbed484699ad37a038a69f6c9ab0171ccc4ff5f3ecfd2` |

The complete owner graph retains its source/runtime, new eight-case test file,
strict compile log, 38-focused and 177-broad test logs, actual Elixir 1.18 source
compile/two-file format evidence and manual exercise log. Its graph manifest
maps every regular path, original mode and byte length to a full SHA-addressed
blob. Identical blobs are shared only after full byte equality; all original
source bytes and copied blobs were rechecked after the whole graph was copied.
The separate setup script `/tmp/ipse-prepare-managed-v3-core.exs`, compatibility
driver `/tmp/ipse-managed-v3-core-compat118.exs`, frozen manual chapter
`/tmp/ipse-managed-pages-manual-20261027.md` and exercise driver
`/tmp/ipse-managed-pages-manual-exercise.exs` are retained as explicitly inventoried
external inputs. The manual sizing exercise uses the same Pages runtime; it does
not demonstrate a wired v3 managed SDK or current-read authority.

Reconstruct any graph in a new private working directory using its verified
path/blob inventory. Restore only working-copy executable modes and necessary
verified aliases; never run or modify the owner-only durable evidence in place.
