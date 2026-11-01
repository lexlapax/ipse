# Reserve and seal an actual pending Worker input

Dated **2026-11-01**, based on `c6b3799` plus the inventoried changes below.
This component record extends the earlier
[retained stdin implementation](worker-stdin-ownership-20261031.md).
It is historical engineering evidence, not managed SDK or milestone acceptance.
Current contracts belong to [Session sources](../../developer/session-sources.md),
[verification](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
and the [native protocol](../../../native/README.md#direct-stdio-server-transport).
The [plan](../../plan.md) owns remaining scope.

The later [Session adoption record](worker-input-session-20261101.md) supersedes
this record's then-missing export adapter, while retaining the component results
and original limits below.

## Exact transport boundary

An explicitly protected Worker can reserve its next ordinary request without
sending it. It uses the same capability/schema checks and JSON encoder as ordinary
calls. The opaque same-preparer handle binds the actual Worker, artifact, owner,
tracked file-effect caller, next protocol ID, immutable frame and original timer.
A configured Session may query that exact stage/payload; this does not confer
source or effect authority. Ordinary Worker behavior and supervisor overrides
remain available when protected input was not explicitly selected.

Reservation binds the actual native supervisor PID returned by the Port. The
existing supervisor and transaction owner authenticate the operation, original
expiry and complete frame before the actual write description is lent. The
importer retains those bytes and requires its one-use write to match them again.
There is no worker-selected descriptor, alternate writer or fabricated delivery
witness. The existing retained source/control checks and ordered close remain.

The supervisor now remembers one increasing Worker sequence instead of retaining
256 operation IDs. Intervening ordinary requests can leave gaps. The sequence is
bounded by the existing safe JSON integer range and carries a nonzero eight-byte
nonce. The transaction's separate finite import budget remains per short scope;
no Worker action, traffic, JSON, result-page or callback limit was increased.

An early valid VM response is buffered without advancing producer state. Only
after pipe settlement can the trusted preparer explicitly release it. The future
Session adapter must settle all policy/source owners before that release and wait
for remaining computation outside those locks. Preparation, transfer, settlement
and compute share the original callback timeout without renewal. Owner or preparer
loss and timeout close the actual owned group; uncertainty supplies no replay.

This implementation changes no public SDK call site. Session has not yet bound
this pending input to its committed invocation/action result, complete inherited
dependency union or original consuming-session ownership. Accepted-decision v6
also still needs its original management-journal owner. Existing effect/display
gates remain closed; this record grants no new workspace, shell, MCP or delegation
permission. Final result fencing does not prove earlier input was fenced.

## Counterexample retained

The first actual-frame substitution control prepared a legitimate Worker echo
request, then supplied a different valid JSON payload with the same protocol ID
to the retained native writer. The expected result was unknown/refusal; the actual
result was **`:ok`**. An opaque host handle and its frame hash had not bound the
native bytes. The original failing log is retained in the inventory.

The repair seals complete bytes during the authenticated descriptor handshake
and checks them again at native write. This adds no hashing dependency or Rust
policy implementation. It preserves the existing 32-KiB JSON allowance plus the
four-byte Worker prefix. Private import/export lengths are updated on both peers;
old private ABI callers cannot silently qualify the new contract.

Earlier component runs passed 23, then 24 (including 257 handoffs), then 26 tests
before the substitution counterexample. They are developmental evidence, not
qualification of the repaired frame binding. The first repaired component run
passed **28 tests in 18.6 seconds**, with exit zero.

## Verification and limits

The pipe and Worker controls use actual kernel descriptors, native owner/control
processes and a separately compiled artifact VM. Lock/source contents in the
shared fixture are synthetic; they are not valid Session source proofs or policy
permission. The 257-handoff case uses one Worker and a fresh short transaction
scope per frame. It proves removal of the supervisor's unrelated count ceiling,
not 257 semantic publications or end-to-end capture capacity.

The initial broader regression overlapped the native Rust test program. Both use
the conservative per-user terminal lock. That run finished with **156/165 passed,
9 failed, 8 skipped and 27 excluded in 195.0 seconds**. The terminal-review failures
and overlap are retained; no passing aggregate is inferred from this run. A
serialized fixed-source rerun passed; its separate result is recorded below.

The native unit program finished with **81 passed, 2 ignored, zero failed in
11.15 seconds**. Its overlap prevents treating it and the first Mix cohort as a
serialized combined qualification. Production native strict compilation and the
complete source build passed before the repaired component run (182 host modules
and three inert bundles). No source/helper rebuild occurred during the Mix runs.
The later serialized native run passed **81 tests, with 2 ignored, in 11.27
seconds**; managed approval separately passed **11 tests, with 12 excluded, in
127.7 seconds**. Their sequential command completed with exit zero, followed by
successful formatting, strict compilation and CI-policy checks.

No live inference, model download, account, independent human, installed-domain,
macOS or semantic-quality qualification occurred. The full P30/P31 goal remains
active. Earlier whole-suite failures remain their original verdict; focused
passes cannot be subtracted into a new whole-suite result.

## Source and evidence inventory

The serialized fixed-source Runner/Worker and genuine lifecycle cohort passed
**165 tests**, with **8 skipped and 27 excluded, in 320.3 seconds** (max_cases 1,
seed 20261101), including all 17 genuine lifecycle top-level cases. Existing native
Session controls separately passed **2 tests in 0.1 seconds**. Managed approval and
the subsequent serialized native unit run have their exact summaries in the
inventoried logs. Formatting, strict compilation, CI policy and the isolated-home
credential-free demo passed. Documentation checked **998 Markdown files and
8294 local links, zero errors** before this inventory was added; private-directory
warnings were preserved without inspecting those directories. Relevant developer
and operator chapters were reviewed whole. Operator authority and procedures
remain unchanged. This is no new whole-suite aggregate.

Source and helper bytes:

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `lib/ipse/extension/worker.ex` | 26893 | `d08946321a2bdb2e6681510b1e1a1438689de99d6c883b1ab0764ef8fba7590d` |
| `lib/ipse/runner.ex` | 81027 | `e81310d36c19eedc123b33518a65c23a080183ba995d5a0cbf836fe9c412a753` |
| `lib/ipse/runner/transaction.ex` | 50211 | `b2244c10ef4f0b06bd634f575d06867ca35a9b5bddbcfffeee18d52d7a1c9eaa` |
| `native/ipse-stdio.rs` | 33878 | `970d936ff24747bce4924577dadc5dfc277eab6552771d4d422d9d8234a7b53a` |
| `native/ipse-lease-transfer.rs` | 16328 | `ae6adc19a13a08bd56311debc47060e592a8fbdc79637dc9ab3e98bac95d339a` |
| `native/ipse-lease-sink.rs` | 38789 | `8a63bb6bb65730673ff66e629613c4927f07762cbb8864cf85f555ec296063d3` |
| `native/ipse-transaction.rs` | 110800 | `0e9e5cebf128a2756713fbfa13ebb333e8d5d97931f4cb872683c5b294bf2ff3` |
| `test/ipse/extension/worker_test.exs` | 20223 | `b75165f05b1acfb591b11bc13c4ac4046b855a25bafcb460e1d1b351ce3f506a` |
| `test/ipse/runner/transaction_pipe_test.exs` | 11215 | `425b920a3bfafa51e0aafa1ccfa3072007ac266433512a215bfa82bff3c7d746` |
| `test/support/native_pipe_scope.exs` | 6318 | `ebd4f1598e75143d84094183795a4f74470e0c25942c324d4b13b5e6584f982c` |
| `priv/ipse-runner` | 969344 | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |

Logs remain at the exact local paths below; their hashes preserve successful,
failed and overlapping outcomes separately:

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `/tmp/ipse-worker-input-frame-binding-counterexample-20261101.log` | 831 | `80397c4b99b847e9bfb94c9dfcbaddfd849e95992d49c676f2baa45f8556284b` |
| `/tmp/ipse-worker-input-sealed-component-first-20261101.log` | 304 | `84d1da62abd07e27c5a527dc423ed9b9330bb6b1db44c6a4a8f194ebb52e13ad` |
| `/tmp/ipse-worker-input-regression-20261101.log` | 10675 | `ad681433e37e0d3c3941f49be1c41af0604e1922add250b62000a85b8a9fc79a` |
| `/tmp/ipse-worker-input-regression-serial-20261101.log` | 4470 | `e5880541858f01e950fd678feeae45afdd6e33b78d1fe1e146ed41c7bf95e515` |
| `/tmp/ipse-worker-input-session-controls-20261101.log` | 267 | `639cdcf5fd257dc9ae205f737d82ffa489c974f274bb9f28d575b902f0ba9c75` |
| `/tmp/ipse-worker-input-approval-20261101.log` | 327 | `5c0458ef4afd0787aa2dd55f0960557177645d8fdd48b8cd7f37d6c062dac4a5` |
| `/tmp/ipse-worker-input-native-tests-20261101.log` | 8602 | `ae051d1b4c583786959c1a19a24d1321dcf93298d33f641411e2eecbd633d5c2` |
| `/tmp/ipse-worker-input-native-tests-serial-20261101.log` | 8602 | `7d10fce9e8711647a8052a6891535d70d5d22c889bf6209f71edfcb18bcbf692` |
| `/tmp/ipse-worker-input-native-sealed-compile-first-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-worker-input-build-sealed-20261101.log` | 845 | `84fe317567463420d15e195f84bcbb113e4db430754247c4895ecb55c0067faf` |
| `/tmp/ipse-worker-input-format-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-worker-input-compile-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-worker-input-ci-20261101.log` | 32 | `e856938f2d4ee3eb319a90056aca83ff6b7347ea57ff71bac975f84df18ae633` |
| `/tmp/ipse-worker-input-docs-first-20261101.log` | 756 | `40d9a9411264d02f9be32202f41dd89dc6d21faf28f759bebc40a134c4f052ff` |
| `/tmp/ipse-worker-input-demo-20261101.log` | 2720 | `d0d163d485ec4787ccd9ae11bc5d71f7ca8ba1f3ea2a036b3966da849432402b` |

No uncommitted or moving-source package is represented as committed qualification.

## Committed package

After committing and pushing **`5ecb411`**, the tracked worktree was clean.
The committed source completed `./dev/build.sh`, then the deliberately parser-free
`IPSE_BUILD_PDF=0 ./dev/package.sh`. The package recorded source reference
`5ecb4111f913b063777caba4883e8e922449ad68`, with 52 documents and no missing local
targets. The rebuilt helper exactly matches the source-qualification inventory.

`elixir dev/verify.exs installed package` passed against that exact archive and
`examples/memory-corpus.json`. It confirmed unchanged inventories, private homes,
a precompiled harness and no system development toolchain on the runtime PATH.
CLI/help/demo, ordinary ownership/resume, bundled functionality and the explicit
Memory synthetic 100-record/100-query check passed without model dispatch.

This is the generic installed-runtime proof; it does not exercise the installed
private stdin/frame interface or managed Session/SDK delivery. It qualifies no PDF
parser, domain quality, human journey, release publication or other platform.
The exact archive and receipts are retained separately from earlier packages:

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `/tmp/ipse-worker-input-5ecb411-package-20261101.tar.gz` | 14989037 | `fd5a5fb3a9c056053b4ab10416f4877fbb80f271a7ef622a9ce90e5aa36f4c81` |
| `/tmp/ipse-worker-input-committed-build-20261101.log` | 845 | `fb3e0ff3d49ed0f14196369fbaad3ec210282ac90b373a5b85b7a8803c2ef4eb` |
| `/tmp/ipse-worker-input-package-committed-20261101.log` | 1476 | `09346854cae7a6ece9b5ecd9c030c2d213c9e038c2117229f1ebbcfa12707966` |
| `/tmp/ipse-worker-input-installed-package-20261101.log` | 2879 | `da6c39f77e37721d205bab67b797b6eccc5053a63104fa71f4f3c50451f2a3ff` |
| `/tmp/ipse-worker-input-docs-final-20261101.log` | 756 | `40d9a9411264d02f9be32202f41dd89dc6d21faf28f759bebc40a134c4f052ff` |
