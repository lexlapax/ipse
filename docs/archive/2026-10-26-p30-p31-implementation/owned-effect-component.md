# Controlled owned-effect foundation

Recorded 2026-10-27. The [plan](../../plan.md) owns milestone status. This is a
focused host component, not P30/P31 acceptance or an inference integration.
Its earlier [private investigation](effect-scope-design.md) and
[hook-free review candidate](child-scope-final.md) retain the counterexamples,
review scope and historical candidate hashes.

The reviewed candidate was applied to `Resources` and `Session.Lock` with four
matching tests. Before use, its internal entry point was renamed to
`controlled_owned_effect/2` and its code contract was narrowed: it is only for
a reviewed native-controller or owned-transport operation whose effects and
cleanup are fenced by the child scope. Its peer can be killed at a deadline;
it cannot replace `file_effect/2` for arbitrary file-server IO that may continue
after peer death. No runtime inference path calls this primitive.

The current Resources and Lock source SHA-256 values are
`9652286207c7f73eaba1280266b25f1e895466cf6dc0f90e8ba24ebfa4c2c898` and
`b638c5f04a03f7ba231f43bcea3dc2cb192e7717e7805e90cd7712cc75f92550`.
The four tests hash respectively to
`d7906b547ab26efb54caf70eb82106463fa057cf3ae91cabf893e4261813f524`,
`4b97fe3888d4d650c26999d532e16c2ca7b7caf0eeb7675a49bb77b8536be7b8`,
`62d05b827a523442e05e9361aad4f395b20b61748f3fcffa01fa867e04a90851`, and
`75edd2bce3a95e2df4347f988f56e18ffa17a25b9381ce788a030a2322d52897`
for lifecycle, close, retained guard and receipt tests. The test sources and
all application sources in the private fixed-source graph are inventoried in
the [source manifest](owned-effect-source.sha256), SHA-256
`359051c785b0712bd544913568f0f20808eb157039644fb92c54d4c5c018cb9d`.
Before and after manifests matched. This inventory does not attest the host
kernel, dependency binaries, or the complete repository state.

The new isolated graph used Elixir 1.20.4/OTP 29, `MIX_ENV=test`, a private
copy of the helper SHA-256
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`, and
a private build path. Formatting of the six changed source/test files and a
forced 137-file compile with warnings denied passed. The [focused output](owned-effect-focused.log)
reports **24 passed**, seed 20270209 and max-cases 1; its SHA-256 is
`941b8caeac2e96836a6351b3125e50de0e0a5d0c06b75bfc5298dec133970193`.
The native controls exercise isolated locks and cancellation, not protected
quota allocation or kernel 7.2.11 qualification. A fixture deliberately stops
and kills its own private helper; inspect it before reproducing.

Independent review identified and helped repair the earlier startup,
child-close, guard and delegated-authority defects. It then checked the exact
renamed Resources/Lock hashes above and independently reported **27 passed**,
seed 20270208, including three additional controls. The [independent output](owned-effect-independent.log)
hashes to `1f6191ac37df39a9f1e16c25ae9894bd067f5de590f9540694f970f8f4c81531`.
The additional [retained-guard](owned-effect-independent-guard.exs),
[normal-close](owned-effect-independent-close.exs), and
[suspended-guard stop](owned-effect-independent-stop.exs) tests hash to
`fe3867804ba18889cf584433ab68d36e4074e6539d36db9ae99f26c61f7ea1a7`,
`3850a52108caa3f79599f22a327879b2d731466e60a9a35a47b20b0325fff8b7`, and
`35d354e7f8f0403f5dba2ebfb01878c4bfd0418a76fbfad5942ce93325320d1d`.
The narrow contract does
not supply additional runtime authority. Exact private receipt references and
PIDs assume trusted same-BEAM host code; extension VM/JSON does not receive
them.

Full source baseline, actual Identity/Consent integration, Session egress
linearization, current-source revalidation and completion-witness cleanup remain
open. BEAM monitors are asynchronous. Neither process exit nor this component
alone proves no stale inference bytes were sent after an owner or policy change.
