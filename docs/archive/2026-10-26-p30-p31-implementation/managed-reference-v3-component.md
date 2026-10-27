# Strict root observations for managed dependencies

Recorded 2026-10-27. This extends the pure
[`ManagedReference`](../../../lib/ipse/session/managed_reference.ex) contract;
it does not install a live Session barrier or create authenticated reads.
The earlier [version-2 record/absence work](managed-reference-v2-component.md)
and its historical behavior remain distinct.

A nonempty raw status, partial scan or search result cannot honestly be
represented as an eligible record or proof that a collection is empty. The
closed version-3 dependency instead carries `root_observation` with exact
host-derived request and committed-result SHA-256 values. It retains the
version-2 native absent/present collection witness, project, namespace, pin and
policy generation. A projected eligible verdict must retain both the exact
subject and the entire exact collection witness. A newer root cannot refresh
the old observation, even if an individual record is unchanged. Explicit
`root_changed` withdraws every dependent safely projectable occurrence.

These are pure transformations over inputs a trusted host must first authenticate.
They do not establish that a read happened or that a source is currently eligible.
Session still needs to mint the observation from actual read results, compute
the complete inherited union, journal and replay the admitted lineage, and
recheck it at every relevant inference and effect boundary. Unsupported opaque
continuations still require safe refusal. Existing version-1 and version-2
subjects keep their prior rules.

The reconstructed private graph described in [the kernel recovery record](kernel-profile-recovery.md)
compiled the production module as part of a strict 134-file build. On Elixir
1.20.4 / OTP 29, the unchanged older tests and two new root-observation tests
passed **26/26** with seed 20261216, max-cases 1. Controls cover nonempty raw
observations, changed root/generation/manifest/request/result, absent-to-present
transition, mixed record/root inheritance, checkpoint dependencies, withdrawal,
replay with `live_pending`, and tampered verdicts. The
[test output](kernel-7.2.11/managed-reference-v3-tests.log) has SHA-256
`1a577f26f69c133457fcdf1a73b3acae3c2066e27a852302bf843c64e5b73a95`.
The production module hash is
`a7f7e01eebd87154ec3bcd717bbcc0910ac915b9ac0877419b493671c641fb15` and
the test file hash is
`44c35b8ce539abbc1fd5db4130ba7a1da7c802517bdaf1e76a9ee9f195953877`.
The two files passed the current Mix formatter. These are owner-run pure tests;
they are not an independent audit, a native read test or P31 completion.

The active [plan](../../plan.md) retains the uncompleted current-read, source,
late-dispatch, child, compaction and withdrawal requirements. The
[developer context chapter](../../developer/workspace-context.md#page-admitted-evidence-without-inline-context)
explains the intended host boundary.
