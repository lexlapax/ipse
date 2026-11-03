# Combined P30 and Worker v4 candidate — 2026-11-03

Historical synthetic development evidence. This focused increment does not
establish a completed P31 recall journey. Current status
belongs in [the plan](../../plan.md). The earlier candidate and populated-trace
limits are described in the [coalescing review](worker-v4-coalescing-20261103.md).

## Scope and candidate files

The candidate applies the reviewed Worker-only v4 coalescing to committed base
`bde96d0ace685e0e9d7dd9a7d891d85a4517aadc`, retaining the P30 v7 pending
proposal path. The v7 observer body was compared byte-for-byte with the base;
v7 stays in the committed version gates and is handled by the original non-v4
observer. The coalescing path reads v4 records in bounded groups before other
versions, reconstructs results in the original order, and retains both fresh
protected passes, per-record checks, shared authority budgets and final root and
owner fences. Internal failure and observation order changes; this does not
claim identical timing or failure order.

The intended overlay consists of exactly these eight files. The SHA-256 values
are the **base preimages**, not hashes of the changed files. They are also in
[base-preimages.sha256](worker-v4-coalescing-bde96-20261103/base-preimages.sha256).

| File | Base SHA-256 |
| --- | --- |
| `lib/ipse/session/managed_use.ex` | `de63ae631305d8d23a5e4e2c864b3c935d62ad5300bc99a177fc52b325dc0a76` |
| `lib/ipse/extension/collection/observed_read.ex` | `34afc7cea4d3414c8c7cfb7db166b440310945847a144832cdb60ee7d14e974e` |
| `test/ipse/extension/managed_collection_call_session_test.exs` | `3dc666b86d0db96c81acf987843bd423313fae0615977cc361e087065d4b8216` |
| `test/ipse/extension/collection_normalizer_v3_integration_test.exs` | `dce67f134851789ccba1fd49a33eacd42444371a99c9e0e89e14c881a98e46c1` |
| `test/support/managed_literal_ab_seed.exs` | `ffe48358bb0c17febbab3ebb734ab688c152b00bdb0d93958e6ed09e2913f9a9` |
| `test/support/managed_literal_pair_runner.exs` | `3e4ea2d5560dbd08a7a28495ace0c9ce99deba4875c97c9ca55a449cbb8967cf` |
| `test/extensions/knowledge/shadow_pending_candidate_session_test.exs` | `4fc9886da045015aa18a614e7b885dc52f7595240838b238db481b86ef0d539b` |
| `test/support/shadow_pending_candidate_cli.exs` | `3924164445b3c933a821e839a166b3769327d399999d27e015475c455c86b2c2` |

The [formatted patch](worker-v4-coalescing-bde96-20261103/combined-formatted.patch)
reconstructed all eight exact tested files from those base preimages in a fresh
scratch directory. This does not verify every other source file or toolchain
input. The twelve-entry source manifest, 642-entry ebin/native-helper manifest,
77-entry bundle manifest, complete focused logs and nested result manifest are
in [the evidence directory](worker-v4-coalescing-bde96-20261103/). Its top-level
[evidence manifest](worker-v4-coalescing-bde96-20261103/evidence.sha256) has
SHA-256 `5b56bcd2765bd75a9d1a0bf6b9786dba3e6c42b6d837cc60240e56a476bde128`.
The compiled build artifacts themselves are not archived.

## Focused verification

A fresh isolated build used copied dependency sources without a dependency
fetch. The project compiled with `--force --warnings-as-errors` and built its
bundles. The earlier dependency compilation emitted third-party deprecation,
bitstring and unused-clause warnings; the strict project compile itself passed.
Source, compiled-runtime and bundle fingerprints were verified before and after
the focused checks. All tests used synthetic local fixtures and no paid model.

- The Knowledge capture wrapper [passed 1/1](worker-v4-coalescing-bde96-20261103/combined-p30-capture.log).
- The actual approved pending-v7 Session [passed 1/1](worker-v4-coalescing-bde96-20261103/combined-p30-v7-approved.log).
- The actual synthetic Session fixture with a natively reviewed literal and a
  pending proposal [passed 1/1](worker-v4-coalescing-bde96-20261103/combined-mixed-v4-v7.log).
  It compared ordered current values and proofs from the host's protected
  Worker and approval input-owner paths for a constructed v4/v7 union. It
  withdrew each real original source before a separate host call and confirmed
  that neither callback ran. This does not show an extension naturally sending
  a mixed v4/v7 union through a Worker pipe, nor a source loss interposed during
  an active pass.
- Existing v4 signed-batch [2/2](worker-v4-coalescing-bde96-20261103/combined-v4-batch.log)
  and native root/owner-fence [2/2](worker-v4-coalescing-bde96-20261103/combined-v4-fence.log)
  checks passed.
- The [33-distinct signed-record control](worker-v4-coalescing-bde96-20261103/combined-v4-33.log)
  passed 1/1. It rejected one 33-item batch and checked exact reversed key/value
  order for 32 plus 1 under one capability. Its source proofs are trusted
  synthetic fixtures; it does not exercise the Worker scheduler or real source
  ownership, count individual signature verifications, or interpose a root
  change between chunks.
- The fresh eight-source mixed-v3/v4 Session control
  [passed 1/1](worker-v4-coalescing-bde96-20261103/combined-eight-session.log).
  It checked original-order results and proofs against the unbatched approval
  path, counted two arity-only batch calls across the two Worker observations,
  and checked refusal for conflicting dependency, preexisting source loss,
  an artificially expired historical dependency and revoked consent. It counts batch calls, not native view opens.
  The [seed log](worker-v4-coalescing-bde96-20261103/combined-eight-seed.log)
  records synthetic native reviews; that fixture's consent was later revoked
  and the fixture must not be reused as fresh.

Independent review verified the merged source and evidence manifests and found
no concrete additional source-level blocker. These focused checks are not a
full suite, an installed-package qualification, or a successful 2,000-note
recall. A real-source 33-note fitting-set Session, mixed Worker-pipe and
interposition coverage, and current-runtime populated testing remain open.
The changed host's full identity differs from the old cohort's saved consent;
that policy cannot be silently substituted or bypassed.
