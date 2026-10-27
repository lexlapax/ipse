# Nonrepairing activation inspection repair

Dated **2026-10-26**, following activation checkpoint `60fbf65`. The independent
audit accepted one **P2**: a supposedly nonrepairing `Config.Activation.current/2`
entered ordinary Identity and Consent transactions, reclaiming pending files
before returning inspection data or a malformed-control error. The
[original component receipt](activation-overlay-component.md) remains historical;
this record supersedes its nonrepairing inspection claim. The
[configuration chapter](../../developer/configuration.md#apply-a-protected-selection-without-changing-base-configuration)
owns current API guidance.

The independent report is retained at the task's durable
`p31-verification/independent-activation/activation-audit-2026-10-26.txt`, SHA256
`c5585ba356b79f5eaa55b39c59290596b8971bf8a94d6b1978b2da48da14ecb1`;
its preservation manifest SHA256 is
`d54c6bd4577d29cdd022199ec4aa0d4685d74baf263d66f553e497299d0af0f5`.
It remains a frozen independent finding, not a claim about repaired bytes.

## Actual repair and authority boundary

`ProjectIdentity.with_existing_binding/4` reuses the existing-only retained native
G-read path, compares the exact validated binding under its lock and checks the
actual lease before/after the host callback and at release. It never invokes the
ordinary transaction, joins a worktree or reclaims pending files.

`Consent.existing_snapshot/2` and `with_existing_policy/6` require existing safe
directories, an existing control object and retained lock. They read the selected
control bytes through the retained native owner, validate the complete closed
state, preserve quota/name/owner bounds and check retained control/lock identities
and the native lease through the callback and actual release. The policy callback
also requires exact epoch/hash, nonexpiry and no accounting quarantine. It returns
data only; it does not reserve, admit, publish or turn a stale pin into permission.

Neither path creates directories, initializes missing ledgers, reclaims pending
files or repairs malformed state. Filesystem absence can return nil solely for
off/no-authority inspection; it is not a Collection absence witness or grant.
Existing linked-worktree validation still uses the previously approved bounded
native metadata capture/cleanup exception. Host lstat is a presence/identity
precheck, never a substitute for native validation of returned protected data.
The cooperative same-UID boundary and original-owner monitoring are unchanged.

`Config.Activation.current/2` now uses only these existing-only readers.
`readiness/2` returns `{binding, snapshot, ready}` advisory data and never a prepared
runtime. A true result requires exact current protected policy and the same
`apply_overlay(:fresh)` artifact, sidecar, capability, route, base-catalog and timeout
checks. It neither joins a new worktree nor grants authority. Child/explicitly
disabled, absent, expired or out-of-scope selections are not ready. Selected invalid
data refuses. The result is an instantaneous observation: admission and effects
must recheck current facts independently.

Author self-review also found a readiness accuracy gap before this checkpoint:
the shared overlay checks did not compare the actual prepared Registry identity
digest with `settings.identity_sha256`. Actual Session admission already refused
that mismatch, but readiness could have reported true. The final shared overlay
guard requires exact identity equality; a coherent changed protected identity
remains inspectable through `current/2` while readiness/fresh refuse. This also
prevents new-worktree authorization under that stale identity.

Ordinary `ProjectIdentity.with_binding`, `resolve`, `Consent.snapshot`,
`with_policy` and mutation/recovery paths retain intentional reclamation. Shared
Consent decoding/name validation was extracted without changing those contracts.
Positive controls verify that ordinary recovery still removes safe pending files
while existing-only reads preserve them. No helper facility, dependency or budget
was added; the repair uses the existing G protocol and helper SHA256
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.

## Frozen reproduction and checks

The initial repair checks use separately owned complete graph
`/tmp/ipse-activation-nonrepair-20261026-01/{project,build}`. The final identity-bound
repair uses the separate immutable graph
`/tmp/ipse-activation-nonrepair-20261026-02/{project,build}`, derived from the
previous complete 128-source activation graph with only the three production
repair modules overridden. Parent CLI/native-H work is not included or claimed.
`MIX_ENV=test` full strict compile passed **128 files**. The
[runtime binding manifest](activation-readonly-repair-runtime.sha256) has
**294 source/app-EBIN/helper paths**, SHA256
`f9d146567058468f9083c64e73e1570626d1e61386cbe8a6df9a5aa70345d4c3`.
It was created before the frozen replays and checked afterward and after all
regressions; every entry remained unchanged. Both helper paths retain the exact
108c digest. Fixture data was temporary synthetic state, separate from source,
BEAM and helper files.

The unchanged independent driver, SHA256
`629682114d634943e3625b4bd667de344ead6edb1f1729e56fbf9b42224c15b3`,
was rerun without editing its assertions. It reported `pending_after: true` and
unchanged logical index bytes, then exited **1** at its original
`false = File.exists?(pending)` assertion. This expected failure is preserved in
[the original-driver log](activation-readonly-original-repro.log). It establishes
changed repaired behavior; it is not misreported as a passing old driver.

A separate driver changes only that assertion from false to true. Its SHA256 is
`ca2bd1023b0c2a82b68c20c72949b2c92d8be1ea18f0eba6aa5cc81e209143a5`.
All three original scenarios passed: Identity.pending with no control tree,
valid Control.pending, and malformed-control.pending. Every pending file survived
and logical bytes stayed unchanged; the malformed read still returned an error.
[The preservation log](activation-readonly-preservation.log) retains exact output.

| Private log | Actual result |
| --- | --- |
| `01/compile-first.log`, `02/compile-first.log` | Full strict test-environment compile, 128 files in each graph |
| `01/tests-first.log` | 16 direct/parent tests passed, including fourteen actual child Session/readiness scenarios |
| `01/tests-regressions.log` | 108 cases passed, 19.2s, seed 20261026 |
| `01/tests-final.log` | 109 cases passed, 24.5s, seed 20261026; added existing-binding native-loss control |
| `02/tests-final.log` | Final exact graph: 109 cases passed, 22.6s, seed 20261026, including coherent identity mismatch |
| `02/compat118-final.log` | Elixir 1.18.5: six owned code/test files formatted identically, three production modules compiled with empty diagnostics; host OTP29 |
| `01/integrity-after-replay.log`, `01/integrity-after-regressions.log`, `01/integrity-final.log`, `02/integrity-final.log` | All 294 entries verified against each graph's own manifest |

The 109-case command names the ten suites from the original component plus
`test/ipse/extension/consent_test.exs` and
`test/ipse/extension/consent_existing_test.exs`. It covers complete closed-state
and quarantine refusal, exact-policy mismatch/expiry, retained-object replacement,
missing lock/no repair, malformed pending preservation, ordinary recovery, real
native-process loss, actual Session replay and nonjoining readiness. Native-loss
author tests kill the actual stdio supervisor process and require controller loss,
unknown return and no advisory data escape; the independent original audit
separately killed the actual descendant flock holder. Neither uses a manufactured
exit receipt.

## Final tested changed-file identities

| File | SHA256 |
| --- | --- |
| `lib/ipse/config/activation.ex` | `e5e6bbd9ce1bd7608bbf6101d45b09d8656e2e56421f4d143af743fa8a3d38ca` |
| `lib/ipse/extension/project_identity.ex` | `3f4fa94ff329fa05621c60e46189182ae9ae09f4dd85439cadcb00736ccf1e5a` |
| `lib/ipse/extension/consent.ex` | `dff082071f01eb48281a3499a30d28579cd1dc0ccdf14f84af4c34c88671393f` |
| `test/ipse/extension/consent_existing_test.exs` | `6c847ba43f938de6a9164140928196fe2cbd4d07942472387d60e67c56a1e177` |
| `test/ipse/extension/project_identity_existing_test.exs` | `804688c45df687fa27e5ce7d128273e4b73a29c16c91f0610627d76f81684b88` |
| `test/support/activation_overlay_vm.exs` | `0edc45433cf5f094064d0ff27e4cf7745a1b6f035339abc2c79b11813946684b` |

The affected configuration and collection SDK manuals were reviewed and updated
around reader API choice, advisory readiness and intentional recovery. Standalone
CLI review training belongs with the separately verified CLI checkpoint; this
repair adds no dangling links to its unpublished guide. No model/network calls,
downloads, private qualification inputs, shared helper rebuild, PTY tests,
full suite, installed release, OTP27 execution or macOS evidence is claimed.
Independent closure and the combined milestone audit remain separate.
