# Generic current-use v4 batching candidate, 2026-11-03

This is a synthetic candidate review, not milestone acceptance. It follows the
[33-note one-shot failure](recall33-one-shot-20261103.md) and the
[Worker-input coalescing review](worker-v4-coalescing-bde96-20261103.md).
The prior failure's cause was not established. No 33-note or 2,000-note
success is claimed here. A subsequent [fresh combined-source 33-note attempt](recall33-combined-dcbb-20261103.md)
also failed before the loopback fixture read request bytes. The candidate was
withdrawn from current source while its patch and evidence were retained; its
focused controls do not establish a sufficient journey benefit for promotion.

The candidate reuses bounded v4 observation batching in both protected passes
of generic `ManagedUse.with_dependencies`. It preserves original result and
proof order, equality between observations, current and deadline checks, and
source and accepted-decision journal ownership through the callback. Other
dependency versions retain their prior observation paths; historical verdicts
remain per-item. Internal read and failure ordering can change. Generic use
has no additional retained Collection witness of its own: each selected read
keeps its existing exact native root check. The Worker-input adapter separately
has a final Collection-owner fence. No product timeout or authority limit was
increased.

## Provenance and integration

The tested isolated candidate used committed base `dcaba404918db85a2d71b248f3a5fc33e3a6364a`.
The four patch preimages also match `dcbb07dd451f1402d28391b716b2b177e35331a7`,
which adds replay containment after that base. Reconstructing dcbb's four files,
applying the [reviewed patch](generic-v4-batching-dcbb-20261103/generic-reviewed.patch),
and comparing to the tested files succeeded; see the
[preimage manifest](generic-v4-batching-dcbb-20261103/base-preimages.sha256)
and [reconstruction record](generic-v4-batching-dcbb-20261103/reconstruction.log).
These checks do not establish that the complete combined dcbb tree was tested
by the earlier candidate run.

| File | Patched SHA-256 |
| --- | --- |
| `lib/ipse/session/managed_use.ex` | `d2dcc6eb3fa4a416eb8146c92cdc1d18869ec371d1d1b30118afee747fe0018d` |
| `test/ipse/extension/managed_collection_call_session_test.exs` | `89f290fea904e0341adb989b7239c68c5eef55b088b65b41018fc82f4d8c0302` |
| `test/support/shadow_pending_candidate_cli.exs` | `86f8b7a8b12da5a74daf21c0edfa5bf7ccde40c339deaee77f2759df01b153b2` |
| `test/support/native_note_recall.exs` | `47d918968d0f183b61863ff595f85ac1175a82377b7708867a7fb6db2a7cf536` |

Independent whole-document review of developer session sources and knowledge
extensions, and operator knowledge permissions and usage, found one stale
sentence in the session-sources chapter. Its separately reviewed
[documentation patch](generic-v4-batching-dcbb-20261103/session-sources.patch)
replaces that sentence and distinguishes the two ownership fences. Its dcbb
preimage SHA-256 is `841dab8dd164179f270bac3c8c08d5be1c31e6109c72655e69e9d313f6ce51fa`;
its patched output is `7124c205a8d0171a17e901f2b8b15959ab5235a936f5d975d8c268e8b7dd88c3`.
The other reviewed chapters needed no correction for this change.

## Focused evidence and limits

The isolated project compiled with warnings treated as errors, and fresh bundled
extensions were built. Dependency compilation emitted third-party warnings;
this was not a warning-free dependency build. The retained
[results manifest](generic-v4-batching-dcbb-20261103/generic-results.sha256)
identifies logs and nested source, 642-entry runtime/native, and 77-entry bundle
inventories. The [evidence manifest](generic-v4-batching-dcbb-20261103/evidence.sha256)
has SHA-256 `cf43e0c6b95817115c14896e72bd751beeab06854729c74840cf5b8e89719a4b`.
These inventories do not archive the binaries or prove the entire toolchain.

- A synthetic three-note native Session delivered a structured user-role
  reference to the local provider. Keys, revisions, complete text, offsets and
  read operation IDs matched successful same-key Collection reads. The fixture
  also covered subsequent source withdrawal and idle resume. A separate held
  root-change run withheld the provider request. Neither is a populated test.
- A genuine-source v4/v7 host callback preserved current result order and
  withheld delivery when either source was already absent. This did not send a
  mixed v4/v7 union through a Worker or test mid-pass source loss.
- An eight-source Session and host callback counted two generic batch calls
  across the two observations, compared ordered results to the approval path,
  and refused conflicting dependencies, a missing original, an artificially
  expired historical dependency and already-revoked consent before the
  callback. These were preexisting conditions, not mid-pass interpositions.
- Focused managed-use, batch and batch-fence controls passed. A 33-distinct
  signed-record control read 32 plus one under one capability with trusted
  synthetic source proofs; it was not a 33-note Session or Worker scheduler test.

An independent source and evidence review verified the nested manifests and
retained focused outcomes. Generic mid-pass races, mixed v4/v7 provider delivery,
the complete combined source, and actual 33-note and populated journeys remain
separate qualification work. The [current plan](../../plan.md) owns milestone
status.
