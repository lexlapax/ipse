# Same-owner document draft abort — 2026-11-06

This dated P31C1b implementation and verification record follows the
[native progress increment](document-native-progress-20261106.md).
The [Corpus workflow](../../operator/corpus.md#query-a-document-collection)
owns current commands; the [SDK guide](../../developer/collection-sdk.md) and
[storage training](../../developer/knowledge-storage.md#fence-document-stages-before-metadata-maintenance)
own the client and native contracts. The [plan](../../plan.md) owns remaining
scope. This does not complete document capacity, migration or P31.

## Behavior

The existing Corpus `source` command accepts `abort_collection_draft` with
exactly a native `head_id` and `kind` (`source` or `projection`) on a Collection
store. It captures one current idle epoch and inspects the actual owner-bound
head. It reduces the actual active reference before prepared references, with
at most three separately approved, journaled native CAS operations. An empty
head needs one real retirement operation. Every receipt must preserve the
opening identity, plan, body and logical unit, use the frozen retirement epoch,
and remove exactly the requested reference. The next effect uses the returned
native generation and revision. The last reduction consumes the head and slots.

This removes staged transport and reservation metadata. It preserves published
sources, selected roots and immutable public values, which remain allocated.
There is no arbitrary key list, new host grant or host operation, another
Session/artifact's adoption, general GC, or migration. State/MCP retain their
existing abort grammar and continuation owner. A fence between reductions
refuses the frozen retirement epoch. A known partial refusal reports incomplete;
unknown stops without a replay token. Missing heads do not prove nonpublication.

## Actual checks and first failures

All Session controls used disposable synthetic stores, ordinary programmatic
approvals, fresh private homes and the normal application. They used no Input
terminal, original notebook or real model. Their `NoModel` fixture raises if
ordinary inference is attempted. Counts below overlap and are not additive
full-suite totals.

| Selection | Actual outcome |
| --- | --- |
| Initial six native/Session controls | 4/6 passed, 74 excluded, 49.1 s; failed aggregate retained |
| Two corrected fixture cases | 1/2 passed, 78 excluded, 20.5 s; failed aggregate retained |
| Public route after the product fix | 1 passed, 79 excluded, 17.9 s |
| Existing State/MCP source compatibility | 4 passed, 44 excluded, 23.5 s |
| Source with all three actual prepared slots | 1 passed, 80 excluded, 25.0 s |
| Isolated synthetic client protocol | 6 nested cases passed, one outer isolation wrapper passed in 8.9 s |

The first selection exposed a fixture URI outside the public Source string
schema and an incorrect confirmed-cleanup expectation after deliberate native
port loss. The corrected fault case preserves `cleanup_unconfirmed`, observes
the actual lock owner exit, and checks Saved/idle without replay. Owner DOWN
alone is not native confirmation.

The second selection exposed a real public dispatcher defect: its snapshot
response went to ordinary `Store.resume` under phase `:source`. The repair gives
this action its own Collection phase. The public test now requires an observed
approval hook before denial can qualify; it then verifies denied native state
is unchanged and approved retirement releases the head and all slots.

Actual controls also cover a prepared Source, partial Source transport, two
prepared Projection references, wrong kind, foreign Session/artifact refusal,
a fence before the second cleanup, retained retirement epoch on a later
explicit command, unknown result without continuation and same-ID Saved/idle.
The three-slot variant first publishes a real prior Source and catalog, stages
its replacement into all three slots, then observes three known reductions,
operation-count delta three, all sixteen slots available, head removal and exact
prior Source/catalog/observed immutable values retained. Old normal publication
continuations refuse. Every cohort's source/runtime/link posts passed, and
independent scoped host checks found its owned processes and group absent.

The client-only cases separately check closed arguments, an actual proposed
empty-head retirement, latest-revision chaining, active/older retirement fences,
known partial refusal, unknown without replay and edited receipts. Those mocked
responses are protocol controls, not native storage evidence. Their parent
verifies that Knowledge modules do not leak into the host VM.

## Build and verification scope

The normal build compiled 199 host files strictly and rebuilt all four bundles.
Its first postcheck incorrectly parsed a NUL-separated inventory as newline-
separated and checked one file. That build exit zero is retained, but the guard
was insufficient. A fresh build with corrected `xargs -0` parsing passed all
553 source pre/post checks. A credential-free demo in a fresh home/workspace
then passed, with all 553 inputs unchanged. No assertion or product deadline
was relaxed. Canonical Elixir 1.18 formatting passed for the changed sources and
tests. The final indexed documentation check passed across 1,246 Markdown files
and 10,206 local links with zero errors after whole-manual review and command,
store-selector and lifecycle-scope repairs. The whole-source baseline remains
a separate gate.

An independent bounded source review found no further concrete abort, ownership,
epoch, receipt or public-dispatch bypass. It does not establish complete GC,
physical reclamation, cross-owner recovery, installed upgrades, full populated
capacity, model quality or a full-suite aggregate.

| Evidence | SHA-256 |
| --- | --- |
| Common C client in all native cohorts | `5386d3319d73e0c17ecd32151e7b788ede98d785f3ac97354b04dbce3a496fbf` |
| Repaired Corpus in passing public/compatibility/three-slot cohorts | `bdeb025423534fd3cb10c40e2ac7b68b333d059cfc09b76e7ee8857bcd15ca24` |
| Common native-cohort runtime inventory | `9014ddc446121b0a9fb2c402da490847fc3c6af5a6da9285145c62bd2d2ea00c` |
| Per-cohort receipt hash ledger | `858c78b0511f1e210214612db1f9884e87bc5dc0b1daed43d9c631f3355cb465` |
| Independent bounded source review | `7e1c75b512ec1381352d0c42773a26669acf2e9f62c15b9654092dd3e5899fa5` |
| Isolated client-protocol log | `5693c5d8499c43fd8ac279684f17ac60028e647e3de5e02388a40c528e040d35` |
| Corrected complete build-source inventory | `4f66b36a97823a0875fc8de7e064365496e01c8ace1068b567b80fe3391d3a8a` |
| Corrected normal build log | `6f56059f67b5e8dbe6d074fb9dbb3968f426031e534af8ec4e23b091014ffbd8` |
| Credential-free demo log | `18f47efb814e974d6bb754c2db5659abf4320af5f4788a0dbb51cce0da0a23cc` |

Private journals, approval values, wire contents and raw logs are retained
privately. This record exports scope and hashes only.
