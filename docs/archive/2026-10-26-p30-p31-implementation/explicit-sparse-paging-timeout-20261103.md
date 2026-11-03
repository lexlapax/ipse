# Explicit sparse paging fixture timeout, 2026-11-03

Historical failed diagnostic, not evidence of successful paging or a milestone
completion. Current scope is in [the plan](../../plan.md). This was a synthetic
local Session fixture; no live account or human assessment was involved.

The focused command was:

```sh
IPSE_TEST_RECALL_MANY=1 IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS=15000 ERL_FLAGS='+S 2:2 +A 2' mix test test/ipse/session/native_note_recall_test.exs:55 --seed 974211
```

An initial sandboxed attempt failed before the test because Mix could not acquire
its local TCP lock (`:eperm`). With local loopback access, Mix compiled and ran
the selected test. It failed after 300.2 seconds, with zero passed and five
excluded. The captured terminal tail reached the native confirmation for note 33;
it did not show a paging result. The test requested a 600-second ExUnit timeout,
but the PTY driver independently kills a `recall-many` child after 300 seconds.
The observation does not establish whether the paging path would succeed or
whether the child was making progress after the last captured confirmation.

The uncommitted test used the following source fingerprints, alongside tracked
base commit `35d4dc8879986831783345d22148cc31b9f84bd3` and any other then-current
worktree/build state, which was not fully inventoried:

| Source | SHA-256 |
| --- | --- |
| `test/ipse/session/native_note_recall_test.exs` | `e0ea1a1a3e102a25a59a6ace922cf7b01395ee7a02223acfc6465164f6054e81` |
| `test/support/native_note_recall_many.exs` | `2107a91d0c9d1f38fa019e7849f7da5d151847a43671ba4fad4d58ee1f368b5b` |
| `test/support/operator_pty.rs` | `f230734a0a34487ce29bb55394f1dab178407885a34403d8160ab374b6c8d11c` |

The test wrapper printed the buffered terminal tail to the tool session; a raw
log file was not retained, so there is no log fingerprint. The synthetic
temporary home was removed by test cleanup. A future attempt needs its own
frozen source inventory, retained output and an independently justified setup
bound; this failure must not be described as a passing Session journey.

## Revised setup: fixture assertion failure

A single revised run split the 33 native reviews across five closed original
Sessions, with assertion counts of 1, 8, 8, 8 and 8. The test retained its
300-second PTY bound. It failed in 155.1 seconds because its synthetic provider
expected exactly 32 records on the first page; the actual response had 17.
The earlier claim that 33 keys are always the minimum for a second page was
incorrect: 32 is an upper limit, and the host also caps the encoded page at
4,096 bytes. The failure is in the fixture assertion; it does not establish a
successful explicit read or a product defect.

The complete synthetic Mix output was retained temporarily at
`/tmp/ipse-explicit-sparse-paging-rerun-20261103.log`, SHA-256
`22a381ebb58cab8a58580f84b5cb1f3a06dacc7a0ceebd08f54409ec00367645`.
The three tested fixture/helper hashes, in the same order as above, were
`fbe9a8599925454b5e8214127eb4fc8a22a999d6a71e839536ae54e1ef833e10`,
`5c6412bf85d5aa5022f209c21db91b4ce5ba0fb502ded3d9d3554246fbd3096a`, and
`f230734a0a34487ce29bb55394f1dab178407885a34403d8160ab374b6c8d11c`.
A separate short documentation check overlapped this run, so its elapsed time
is not an uncontended performance measurement.

## Corrected cursor walk: unknown Worker input

The final bounded attempt followed each actual cursor until the eligible key
appeared, without assuming a full first page. It used the same five-Session,
33-reviewed-note setup and the existing 300-second PTY bound. The test failed
after 300.2 seconds, with zero passed and five excluded; it did not complete the
explicit index/read journey. No production page size or authority was changed.

The synthetic Mix output was retained temporarily at
`/tmp/ipse-explicit-sparse-paging-final-20261103.log`, SHA-256
`bdca6c443ce96f9437d1271f985dbd7a4ef7d5dc02f7d74be9bce5f49889ed77`.
The selected command was the first command above with seed `974213`. The
test, fixture and helper hashes, in table order, were
`fbe9a8599925454b5e8214127eb4fc8a22a999d6a71e839536ae54e1ef833e10`,
`e842d4eeda110d952bc93e7e90e0657a85bfe74d136bf1b33fc4f02289f7ffef`, and
`f230734a0a34487ce29bb55394f1dab178407885a34403d8160ab374b6c8d11c`.
The exact final [test source](explicit-sparse-paging-timeout-20261103/final-native-note-recall-test.exs)
and [fixture source](explicit-sparse-paging-timeout-20261103/final-native-note-recall-many.exs)
are retained for review.
The other worktree and build inputs were not frozen.

Separately, a read-only copy of the in-progress synthetic consumer journal,
SHA-256 `6750e9077297aa80340ecc4f87f00129c8010cd72a401e2b029ab96e7e7e3c53`,
was retained outside the repository before cleanup. Its sanitized sequence is:

| Line | Observed event |
| --- | --- |
| 43 | `extension_action_result`, `failed`, `collection_original_source_missing` |
| 206 | `inference_dispatch_intent` |
| 211 | `tool_started`, `ext__knowledge__index` |
| 214–215 | `worker_input_intent`, followed by `worker_input_result`, `unknown` |
| 217–219 | unknown lifecycle tool outcome, cancellation and epoch close |

That snapshot establishes this ordering only; the running test did not itself
assert the line-43 code. Saved reconstruction of the source Sessions is distinct
from reopening them. Neither this snapshot nor the timed-out test establishes a
completed later-page read. The unknown Worker input requires separate diagnosis;
the interrupted operation must not be automatically replayed.
