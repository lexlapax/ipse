# Independent review of release-receipt v6

2026-10-29. This review covers the pure
[signed-claim contract](release-receipt-contract.md) and its
[v6 evidence manifest](evidence/release-receipt-contract/manifest-v6.sha256).
It supersedes the earlier review's repair disposition for current selection,
decoding bounds and recording exhaustion. It does not qualify Session close,
native release observation, sidecar publication or concurrent adoption.

The v6 manifest and its complete runtime inventory verified. The focused suite
was independently rerun on that inventoried graph: **8 passed**, seed 29934.
The reviewer inspected `ReleaseReceipt`, its tests and `RuntimeLifecycle`;
no implementation was changed and no aggregate validation was run.

The reviewed repairs address the earlier findings:

- `intents/2` retains historical evidence, while `current_intent/2` and
  `classify_current/3` discard an old selection after a later owner marker or
  epoch start. A separate probe confirmed that a new epoch preserves the old
  historical intent but makes its current classification unknown.
- Recording exhaustion remains sticky across owner markers, preserves history,
  rejects later intents and produces no current selection. The focused test
  uses a sequence accepted by the actual lifecycle restorer at its event limit.
- IDs, digests, key fields and map size are checked before expensive decoding
  or hashing of the closed intent. Public keys and signatures have exact
  encoded lengths and canonical unpadded Base64url.
- Equivalent JSON formatting is accepted and now described accurately.

One semantic needs care during integration. An owner marker resets the receipt
scanner's owner-local epoch to nil. A probe using an unclosed owner-A epoch,
then owner B and a nil-epoch B intent, obtains a valid current signed claim for
B; the lifecycle restorer still reports A's unclosed epoch. This can represent
a later owner with lifecycle recording disabled, but the B claim must never be
used to relabel A's historical epoch as cleaned up. The current module does not
perform that relabeling or any adoption. Integration must explicitly bind
owner-local lifecycle enablement and retain prior-owner unknown outcomes.

No additional concrete defect was found in the scoped signed-claim primitives.
Current selection only describes the supplied snapshot. Durable owner markers,
concurrent-reopen fencing, exact observed helper/lock identity, positive native
cleanup, crash-safe sidecar publication and legacy-resume behavior remain open.
The signature cannot establish those facts by itself, and all related gates
remain unchanged.

The focused command used was:

```sh
ERL_FLAGS='+S 4' ERL_LIBS=_build/session-release-contract-v6-sol-20261029/lib elixir -r test/test_helper.exs -e '{:ok, _} = Application.ensure_all_started(:ipse); Code.require_file("test/ipse/session/release_receipt_test.exs")'
```

The additional probe is retained at
`evidence/release-receipt-contract/review-v6-probe.exs`; using the same `ERL_LIBS`
with `elixir` produced `RELEASE_RECEIPT_V6_NEW_EPOCH_INVALIDATION_OK` and
`RELEASE_RECEIPT_V6_NEW_OWNER_NIL_EPOCH_SCOPE_OBSERVED`. The documentation checker
passed with 745 Markdown files, 6,256 local links and zero errors before this
verification note was added.

This copied build graph is local evidence, not a fresh-checkout build recipe.
The review itself is uncommitted until included in a focused repository change.
