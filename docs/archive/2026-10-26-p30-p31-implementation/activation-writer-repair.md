# Existing ancillary writer precondition

Dated **2026-10-26**, following nonrepairing-reader checkpoint `1001230`.
Independent closure confirmed its three pending-preservation fixes and accepted
an additional **P2**: native quota acquisition opens `.writer.lock` with CREATE.
An otherwise valid Identity or Consent directory lacking that ancillary file
therefore gained a new file during inspection. No concurrent attacker was needed.
This record supersedes the corresponding noncreation claim in the
[earlier reader repair](activation-readonly-repair.md), retaining its successful
pending-file evidence. The [configuration training](../../developer/configuration.md#apply-a-protected-selection-without-changing-base-configuration)
owns current reader behavior.

The independently preserved report is
`p31-verification/independent-activation-repair/activation-repair-audit-2026-10-26.txt`,
SHA256 `3f01b9e90dfe87643963545a70493d0d6e9d37f895cae6684b8f7cbbf678c257`.
Its FINAL-MANIFEST is
`a804b2bfcca2fbf3e47f9a7c67e315b207bfcec252920178d72400785e520b3b`.
That accepted finding and its original 701-path before/after evidence remain
historical independent bytes, not an audit of this later repair.

## Exact repaired path

Both existing-only owners now require a safe preexisting ancillary writer lock
before acquiring quota: current UID, mode 0600, one link, regular file, zero size.
Missing or unsafe `.writer.lock` refuses without creating it or interpreting the
absence as an off/authority witness. `ProjectIdentity.existing/2` uses this same
guard, so the first Identity lookup inside `Config.Activation.current/2` is
covered, as are `with_existing_binding/4`, `join_existing/3`, Consent's existing
snapshot/policy reader and public readiness.

Exact retained writer identity is checked immediately before and after quota and
after the read/callback. Replacement with another safe file cannot yield advisory
data. A changed writer after potentially mutating join work reports unknown;
read-only callback results refuse rather than returning their data. Original
native lease/release, retained main lock/control/index, quota and owner checks
remain. Missing ancillary state also refuses before intentional linked metadata
capture begins. Ordinary `Identity.resolve` and explicit Consent mutations retain
their create-capable recovery behavior, with positive tests recreating the
ancillary file.

The existing native quota facility is retained; no quota is skipped or weakened.
This fixes the accepted non-racing cooperative-host contract without introducing
a helper protocol or rebuild. It is **not atomic no-create enforcement against
arbitrary same-UID concurrent deletion** between a precheck and the native
create-capable acquisition. Such a stronger contract would require a distinct
native existing-only facility. This is the same explicitly retained limitation
as the main `.lock` precheck. No raw same-UID tamper containment is claimed.

## Frozen graph and unchanged independent probe

The unique private complete graph is
`/tmp/ipse-activation-writer-20261026-01/{project,build}`, derived from the previous
128-source repaired graph with only Identity/Consent production bytes changed.
`Config.Activation` remains exact checkpoint `1001230`. Root CLI/native-H work
is not included in these checks. The shared helper was not rebuilt; both private
copies retain SHA256
`108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.

The initial 294-path source/app/helper manifest was established before frozen
probe and pending replays and verified unchanged after regressions. A final
[701-path manifest](activation-writer-repair-runtime.sha256) additionally binds
every actual dependency EBIN file. It was written before the final independent
and pending replays and checked afterward; every entry remained unchanged. Its
SHA256 is `2ebf96feba4c77dad4e7920d5e06c14304314c73772dfa9d26a84c80626d271d`.

The auditor's exact `writer-lock-probe.exs`, SHA256
`964d6847904d9b76dda18d29f2fbdaeb79cd6b87ea3c225e25e96caddb585cb3`,
ran unchanged against the frozen repair. It exited 0 and reported:

```text
missing_writer_lock: {:identity, {:error, :project_identity_unavailable}, false}
missing_writer_lock: {:consent, :error, false}
```

Fresh assertions require those refused reads and both false existence results.
[The unchanged probe output](activation-writer-repair-probe.log), SHA256
`de63f35b59579d90cc960ac1427a2de3f7737d43331e5a53a1ab22d46729eb0d`,
is preserved. The original three pending-preservation scenarios also passed
again: Identity.pending, Control.pending and malformed-control.pending survive,
with logical bytes unchanged. No old driver or frozen independent report was
silently edited.

| Log in the private graph | Actual result |
| --- | --- |
| `compile-first.log` | Full strict MIX_ENV=test compile, 128 files |
| `tests-first.log` | 21 parent/direct cases passed, 10.3s, including fifteen actual child Session/readiness scenarios |
| `tests-final.log` | 113 cases passed, 23.7s, seed 20261026; same twelve explicit suites as the earlier repair |
| `compat118-final.log` | Six owned code/test files format identically on Elixir1.18.5; three affected/prerequisite modules have empty compiler diagnostics, host OTP29 |
| `writer-probe-frozen.log`, `writer-probe-final.log` | Unchanged independent probe refuses both missing writers; both remain absent |
| `pending-preservation-frozen.log`, `pending-preservation-final.log` | All three previous preservation scenarios pass |
| `integrity-after-regressions.log`, `integrity-final.log` | Initial294 and final701 manifest entries respectively unchanged |

Fresh regression cases exercise missing ancillary files through every existing
Identity entry, Consent snapshot/policy and actual current/readiness; unsafe
mode, nonempty, hard-linked and symlinked writer objects; post-callback writer
replacement; unchanged logical state; and intentional ordinary recovery. Existing
actual native-loss, closed policy/quarantine, source/replay, route and child
ceilings remain covered. These are synthetic local fixtures, without model calls
or human terminal claims.

## Final changed source identities and limits

| File | SHA256 |
| --- | --- |
| `lib/ipse/extension/project_identity.ex` | `ecc2e3750d04cd2cb288ac5bdbc74c3361136c41e82ae89d40a91bf9df5da6de` |
| `lib/ipse/extension/consent.ex` | `3803b34c9d0c61dbb40057da5b25f0a5f47cbe8837028697e52ea6edbfc5ac9f` |
| Unchanged `lib/ipse/config/activation.ex` | `e5e6bbd9ce1bd7608bbf6101d45b09d8656e2e56421f4d143af743fa8a3d38ca` |
| `test/ipse/extension/project_identity_existing_test.exs` | `54397a0c0c59c4fb16b575156f6e96271a845ae2f626a481aae19d7bcc43b46a` |
| `test/ipse/extension/consent_existing_test.exs` | `bdb002f3b1d802d5aa4b94e25ecadbde1dbac62679a44d7ab8fc4b28289de09b` |
| `test/support/activation_overlay_vm.exs` | `a9ad9357b9ba028cb914da625845758ea6378d4beeb6e18f905fbc8834575fdb` |

The existing configuration and collection SDK chapters were reviewed for this
reader contract; they explain the required ancillary state, refusal and
cooperative concurrency limit. Root's standalone CLI training/guide remain with
its separately verified checkpoint. No dependency, native/helper/shared build,
PTY run, paid/live request, download, qualification corpus, full suite, installed
release, OTP27 or macOS check belongs to this repair. A later
[independent closure](activation-writer-audit.md) verifies the exact repaired
graph and retains both original exploits. Whole-implementation acceptance and
the standalone CLI audit remain separate.
