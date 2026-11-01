# Fund managed page inputs from the admitted output reservation

Dated **2026-11-01**, based on `c22b8c4` plus the fixed-source inventory below.
This is bounded journal-accounting work, not full managed capacity or P30/P31
acceptance. Current contracts belong to
[publication](../../developer/extension-invocations.md#reserve-capacity-and-commit-publication),
[input ownership](../../developer/session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
and [operator reading](../../operator/extensions.md#invoke-a-command-and-inspect-its-complete-result).
The [plan](../../plan.md) owns remaining qualification.

## Reproduce an admitted transfer losing its journal budget

Two actual Session controls obtain a generated managed-root result of about
20 KiB in five pages. After its real source-begin append and reservation, a
disclosed Session debug hook calls the real owner-only Writer reserve API.
It consumes other available events, leaving eight general events, or other
available bytes, leaving 4096 general bytes. This represents competing admitted
work without changing limits, journal offsets, deadlines or source authority.
The intended result remains successful complete publication.

The first attempt failed both cases in fixture setup on a nil optional tag;
that boolean handling and an unused variable were corrected. The actual baseline
then reported **zero of two passed, 164 excluded, in 22.2 seconds**. Both source
reservations had begun, but `WorkerInput.prepare` appended its next intent through
ordinary general admission. Writer correctly refused that unreserved append
while competing reservations held the headroom. Session stopped with
`journal_unavailable`; no final result published. Outstanding reservations meant
Writer did not write a quota-seal marker. The partial source and known input
prefix remain historical evidence, never a replay instruction.

## Reuse the existing owner and reservation

`Session.Invocation.open_output` now adds `WorkerInput.output_capacity/3` before
requesting its existing Writer token. Known empty ordinary lineage keeps the
original plan. Managed or unavailable lineage conservatively budgets each
source page's closed maximum-width input intent, longest result status and one
possible root transition under its existing 16384-byte record limit. Page count
uses the actual `ResultSource.request` stride. The template is capacity data,
not a serialized input permit.

During active `result.output` transfer, input intent, transition and result append
against that actual output token. Initial and action-continuation inputs retain
ordinary admission. Writer still owns append validation and unused-capacity
release; Host and Worker receive no token or journal handle. Record formats,
Saved reconstruction, native ownership, approvals, deadlines and dependencies
are unchanged.

This is deliberately pessimistic: unused transition allowances return with the
output reservation. Metadata consumes total journal bytes/events/record capacity,
while the existing 4-MiB document and 64-MiB encoded-source limits stay unchanged.
It does not reserve every unrelated append or promise that a source remains
eligible. Smaller operator journal policies can refuse earlier, before begin.

## Require usable results and early refusal

Both contention cases passed after the repair in **13.3 seconds**, with
164 excluded. They require complete materialization of all four generated items,
only the genuine competing token remaining, no quota marker or unknown input,
strict Saved reconstruction and confirmed close/idle without another callback.
The controller releases its competing token through the actual Session owner.

A third case uses an explicit 65536-byte journal and requires refusal before any
source record, with a live Session, no seal, zero outstanding reservations,
no unknown input and confirmed close. All three then passed **three cases,
164 excluded, in 13.3 seconds**. No failed outcome was relabeled successful and
no production resource ceiling or timer increased.

The controls use synthetic root metadata and a small real Worker result. Maximum
managed output performance, accepted-decision paging, complete document-producer
capacity and installed/platform/quality qualification remain separate. The
original whole-source aggregate remains unchanged. No paid inference or model
download ran.

## Fixed-source qualification

The serial fixed-source checks passed the build (183 host modules and three
inert bundles), formatting and strict compilation; **85 complete-result/Writer/
lineage regressions in 28.0 seconds**; **28 combined input controls, 139 excluded,
in 55.7 seconds**; **eleven genuine native approvals, twelve excluded, in
174.3 seconds**; and the accepted-decision journey, **one passed, seven excluded,
in 43.1 seconds**. CI policy and an isolated-home credential-free demo passed.
The documentation checker passed **1005 Markdown files, 8358 local links and
manual/archive rules with zero errors**. Private permission-denied directories
remain untouched.

The complete invocation/source/testing and operator chapters were reviewed and
reconciled around reservation, source quota, early refusal and fresh-session
recovery. The helper hash is unchanged from the preceding qualified candidate;
no Rust source or native ABI changed. No new package was built for this
focused change. Installed and maximum managed-output qualification remain open.

A bounded prefix inspection of both failing roots found exactly one source
begin, four chunks, five input intents/results (including the earlier host-action
input), no seal/final/limit marker, and a final chunk record. The final contention
roots retain the complete source and idle-resume journals. Exact hashes follow.


| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `lib/ipse/session/invocation.ex` | 67089 | `c5aa568054807297ed32919cebb4d6b8a69e2adc7a6ff5493d4b5519d8eaa6c4` |
| `lib/ipse/session/worker_input.ex` | 22441 | `b885db15a59d8214a64c76db3c0447485aff33db3beba76dbaf2f4e455157410` |
| `test/ipse/extension/managed_collection_call_session_test.exs` | 310649 | `7a37cca4c5cef67cca75565a7a28da844ff06cd385050e535328b3d727fb5d73` |
| `priv/ipse-runner` | 969344 | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |
| `/tmp/ipse-worker-capacity-baseline-20261101.log` | 2434 | `3003238c0879026947b53440c6a9c8bf1d4c667895c837c1d849bf6590e7bdd7` |
| `/tmp/ipse-worker-capacity-baseline-second-20261101.log` | 2569 | `1c3b53bd37eac44c94460e33ffea66eed38b309fe4d00259c175d9817fab7bd8` |
| `/tmp/ipse-worker-capacity-baseline-prefixes-20261101.log` | 438 | `4dc9807acfe086a2581941a811775401c3e1a9e7eaa9809c1a863970dc28e439` |
| `/tmp/ipse-worker-capacity-first-20261101.log` | 497 | `87198a24e40d48cfd37c7bba4413b282b25b160cfcdcf1be6c930e51d2d61cd7` |
| `/tmp/ipse-worker-capacity-boundaries-second-20261101.log` | 498 | `cf9b9473ca37ce2560e0ad0ab9b779171b6a61f05231f1e8a77db5335ff4d999` |
| `/tmp/ipse-worker-capacity-build-final-20261101.log` | 845 | `1d70c4154ed798ea5201f24156cf886300cc8feee969edde5bca17fca6ea368b` |
| `/tmp/ipse-worker-capacity-format-final-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-worker-capacity-compile-final-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-worker-capacity-regression-final-20261101.log` | 1847 | `6dd568508729ae81e301875590512621410e1c8e360fc49e73d4226457509c3e` |
| `/tmp/ipse-worker-capacity-combined-final-20261101.log` | 786 | `422f806993fddbc9d91b65c10b8a94da9a93d959278f9adc5ff27ed02b1764b6` |
| `/tmp/ipse-worker-capacity-approval-final-20261101.log` | 327 | `74bb27f94792f81ad403a5d03898fae6605e4006bf333687d34fd793dde9f653` |
| `/tmp/ipse-worker-capacity-accepted-final-20261101.log` | 287 | `36b7622628b5686f97c63dd92f015bcf2a131dafe4bca34afcc74f7600155017` |
| `/tmp/ipse-worker-capacity-ci-final-20261101.log` | 32 | `e856938f2d4ee3eb319a90056aca83ff6b7347ea57ff71bac975f84df18ae633` |
| `/tmp/ipse-worker-capacity-demo-final-20261101.log` | 2720 | `ae62ebae1cc10d9f2da4686ddc04512b9d193f65df64c4f50aa5e9266dd31f67` |
| `/tmp/ipse-worker-capacity-docs-final-20261101.log` | 757 | `face8922ff441a181551c231a8468f075367a0bdaaae4a7ab58c662cb6045155` |
| `/tmp/ipse-collection-sdk-2ff6ce9385800f1086c030e722dfbfa4/trace` | 168 | `7602489ddb3db68065b7b07a83a9aa2102d139a791e10edaf4ad87b1d3661138` |
| `/tmp/ipse-collection-sdk-2ff6ce9385800f1086c030e722dfbfa4/sessions/c86e57d75f7a23636d1734ae6520dc51.jsonl` | 49074 | `b87b7a2bc11faad547092b16e1b62e0f51abf01b84632d6a290f1ff743fd335c` |
| `/tmp/ipse-collection-sdk-37651bba1291b3c47c814c559f4bf421/trace` | 168 | `05fd8309afad24b60d7b42192a9d4e76ef410b7f2a5b924cfb0184120d4e1ec4` |
| `/tmp/ipse-collection-sdk-37651bba1291b3c47c814c559f4bf421/sessions/0fe3b70f47b5d70df6196c2a14993b18.jsonl` | 49074 | `58ba9dbdca69f8e6a9b52d546819e2c21cbce438255a979adbf07243434a6c2d` |
| `/tmp/ipse-collection-sdk-7af6b1ba49e7439f8429b5399fc84cef/trace` | 168 | `5314a6fa071a194abb6b0763f38ef995dbf80dca2a9c57e20de871d99388c804` |
| `/tmp/ipse-collection-sdk-7af6b1ba49e7439f8429b5399fc84cef/sessions/83eba84d7c1cbef733f37c45de20fde7.jsonl` | 68469 | `64b7d196d5314689c6c0c72bb83ff648eb0fe9d30db17185504981b3ccf6fbe5` |
| `/tmp/ipse-collection-sdk-8c88b40f7a4d6a9faaedb494d4e4249f/trace` | 168 | `faf6569b1a6298f76901d0604e89485429aaada6a0bd2f9552cf8e100d24f15f` |
| `/tmp/ipse-collection-sdk-8c88b40f7a4d6a9faaedb494d4e4249f/sessions/d9eb35c30058231324e910aa55b0e776.jsonl` | 68468 | `fdd625e21e90726bb5a11cf46ced0471e6c7c32dc3b8f1f386a1bed1f7d330a3` |
