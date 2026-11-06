# Shared-generation Job epoch fencing — 2026-11-06

This is a bounded P31C1b controller checkpoint. It extends the internal document
fence to shared-generation Jobs, not to every Source, Projection or producer
continuation. Current guidance is in the [Collection SDK](../../developer/collection-sdk.md#continue-a-supplied-shared-generation),
[storage chapter](../../developer/knowledge-storage.md#fence-document-stages-before-metadata-maintenance)
and [Corpus manual](../../operator/corpus.md#inspect-supplied-shared-projections).
General maintenance, GC, adoption, migration and populated capacity remain open.

## Implemented contract

The controller observes the actual snapshot epoch once, requires idle status for
mutations and conditions each existing primitive on that captured epoch. Native
job identity, physical revision and stored epoch independently bind append and
finalization. Rewriting a token and its public plan hash cannot change that
durable predecessor. Legacy epoch zero retains Job1/2/3 and token1 shapes.
Closed Job4/5/6 add a positive epoch to the corresponding group, ordinary
reduction and paged-reduction shapes; normal token2 carries that epoch.

Finalization normalizes only its logical schema dispatch and then restores the
epoch-bearing job version. Raw stored maps, hashes, IDs, recipes and source
anchors remain intact; directory formats remain unchanged. The host's existing
source guards admit only the corresponding closed new job shape and require the
stored job epoch to equal the exact mutation request condition. The actual
native root/namespace/owner/epoch fence still decides publication.

An explicit abort can retire the exact older job under a current idle epoch.
It preserves that job's identity/epoch and discards its old normal checkpoint.
A partial abort returns token3 with its own write checkpoint and frozen
`retirement_epoch`, also included in its abort-plan digest. Only abort accepts
that token. Same-epoch continuation resumes the actual stage/offset; a later
fence refuses it. Resetting a begin to unit zero is fresh work, not adoption of
old progress. Old stages and unknown operations remain; no capacity, refund or
reclamation promise follows.

## Actual checks

The final exact selection passed **5 tests in 81.6 seconds**, with 64 excluded:

```sh
MIX_ENV=test HEX_OFFLINE=1 mix test --no-compile \
  test/extensions/knowledge/collection_adapter_session_test.exs \
  --only generation_maintenance_session --max-cases 1 --trace --seed 826047
```

The actual ordinary-approval Session cases cover old/edited-token and active
refusal, exact older-job retirement, fresh epoch-aware begin, guarded group
append and both finalizers, cited source reading, full Saved and idle/no replay.
The same native-held host authenticator accepts the real staged group and
refuses a changed request counter and an extra-field observation. The latter
alters only a validator observation, not the native store.

Two retirement controls use metadata-only references, not a populated
thousand-source Collection. They force a partial retirement by deliberately
exhausting the in-memory effect allowance after a real successful native
write-parts result. One continues the exact returned token and verifies its
same slot, epoch and nonzero offset before known abort completion; the other
checks stale and rewritten retirement-counter refusal after another fence.
No provider, model, Terminal/Input review or original notebook is used.

The first run remains **1/4 passed**. Two finalization fixtures stopped at a
legitimate known `reducing` phase instead of following its continuation. The
retirement sample fit its first packet, so the intended open-write control never
fired and abort completed normally. Only the test loop/sample and an additional
same-epoch positive changed before the final run; production stayed identical.

Strict compilation passed. The normal working-tree build passed all **198 host
modules and four normal bundles**; whole-project formatting and an isolated
credential-free scripted demo passed. Source pre/post checks passed. These are
not a full regression, installed-user, model-quality or paid-account result.
Limited independent source review accepted the durable Job predecessor join;
the relevant whole developer chapters and Corpus manual were reviewed and
updated around current procedures.

## Limits and commitments

Source's public epoch-binding digest alone does not authenticate its opening:
counter-plus-digest recomputation can relabel an immutable prefix without a
durable opening claim. That separate Source gap and Projection integration remain
open. Existing producer claims and in-flight inference also lack complete
maintenance-epoch integration. Job write refusal proves no cancellation, zero
egress, refund or safe replay of those effects. No dependency, capability, grant,
provider route, storage ceiling or operation budget was widened here.

Only source and private log hashes are published, not their runtime or journal
contents:

| Owner or receipt | SHA-256 |
| --- | --- |
| Job controller | `a7ff774384b8225e8b10681015359a1d3c8df80dd8c9908621524f1abae291a1` |
| Finalization boundary | `3b8463243800c5fbbce475466bf2f4334b9af3176c0ee75c89082b991fbd3f8d` |
| Host source guard | `d8dfc7ec2b132cba451cebaca7c8e649bc1942ce492aabb494e5519bbc4f5fc5` |
| First failed test log | `820c590df75e54404b0ad0927e04a0cd9a979148aba2475fcfe743ab9a39808d` |
| Final five-case log | `0dfb60bd9ee7ac95b9b60e650dce4237d08eac425db8d553afbacedcc6220bc0` |
| Normal build log | `9f3466ed672c722a20901187d0ac03d37e8fe7ae64ece06937d7ad9304cb5410` |
| Empty whole-format log | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| Isolated demo log | `acd05b7a052e8840e9653b8dda12ccdbd891b0b8d4d5e91dee5e56021210ca45` |
