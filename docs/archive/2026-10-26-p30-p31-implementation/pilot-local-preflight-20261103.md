# Local capture pilot synthetic preflight — 2026-11-03

This record covers the source-checkout local capture-pilot launcher and its
synthetic verification. It follows the [candidate-audit pilot](pilot-candidate-audit.md)
and its [content-free usage repair](pilot-usage-privacy.md). The
[plan](../../plan.md) owns P31A acceptance, and the current contributor procedure
is [Inspect capture proposals](../../developer/capture-pilot.md). This preflight
made no live model request, downloaded no model, and did not inspect or write the
real user's one-shot authorization ledger. It establishes neither semantic
quality nor real protected capture.

## Source and isolated build

The tested snapshot was a `git archive` of commit
`c37e14520764ee7df256074b76a1d7d1e8b79024`, excluding `docs/archive`, with
the following six source/test overlays. These hashes identify the tested files;
this receipt and the later manual edits were not in that snapshot.

| Overlay | SHA-256 |
| --- | --- |
| `dev/pilot-knowledge-local.exs` | `2dedc3430b98c8a032ea19e59376a94517a4072b41ffa20c2ed664cc74a4dcdc` |
| `dev/knowledge/local_pilot.exs` | `2d1455e5a0ac65a6848cbe85b0d6e4aa38fed005e01acf693b1b6ba4c10f55b0` |
| `dev/knowledge/pilot_reservation.exs` | `004757fa5e619d5de4bd15e58e4ac468220dc475a30f083dd191f9f2470bed46` |
| `test/dev/knowledge/pilot_test.exs` | `d94b4acb869947cfe33178b19c4577dee377d080fd7acd7a7d7ce93da71438eb` |
| `test/dev/knowledge/local_pilot_test.exs` | `caaf5b869f82394aae00dc4a2f6dfc16a0633fb10b7e4762ae0f656c3342dd31` |
| `test/dev/knowledge/pilot_reservation_test.exs` | `df15174b4ce67bf18f8a242e9f4ef70a24ecc770649d5b1eaeda8bab21a85976` |

The [1,241-file source manifest](pilot-local-preflight-20261103/source-sha256)
has SHA-256 `56c45b3bd38cda8b7e7dd1cc12f4f413253f45add9f089b390bdc523dcdc4a4e`
and matched before and after the final batch. The separately copied
[743-file dependency-source manifest](pilot-local-preflight-20261103/deps-clean-sha256),
excluding generated `_build` directories, matched the
[post-build manifest](pilot-local-preflight-20261103/deps-clean-after-sha256)
byte-for-byte; both hash to
`843a8bffba4b4e070bd25b4bc54da54c6e4e9a1404bbe085c3676da5a911bcee`.
The retained single source manifest independently checks the retained snapshot;
it does not separately prove the timing of the reported before/after comparisons.
The installed Hex 2.5.1 archive was copied into the isolated Mix home;
[its file manifest](pilot-local-preflight-20261103/hex-sha256) hashes to
`ec044cc5c9e91da3870b0c68af374e2d100fbaf351e54db3830447d2391b591a`.

The cache-free build used isolated build, Mix, Hex, Ipse and temporary homes,
the copied dependencies, two Erlang schedulers and `HEX_OFFLINE=1`. The native
helper, offline dependency compile, strict application compile and four bundled
extension builds passed. Mix's local TCP lock needed sandbox escalation; no
dependency fetch was made. The dependency build emitted third-party warnings;
the application compile separately passed `--warnings-as-errors`.

For this build, the native runner SHA-256 was
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
The Provider, Usage, Ollama Models and Jason BEAMs respectively hashed to
`e56ee270ef0e978934c659f405bdaa529ee180951932f539f206719ed7251537`,
`ea32a641fe7e3e4480634ae4113dc87c4c9a64f69dbe90e61e77ff8dfc70f299`,
`0517eef88f23c1783437d717fdf43ecf1fbc75df702c157a91c889d49e605ce1`, and
`d859bd044c631bd1813570ec9547c8396c21638c5bc3178666ef2fea46d42b31`.
These identify files in the controlled build; they do not attest the exact
bytes executing in a future VM. Build logs are retained for the
[native helper](pilot-local-preflight-20261103/native-build-clean.log),
[dependencies](pilot-local-preflight-20261103/deps-build-clean.log),
[application](pilot-local-preflight-20261103/app-build-clean.log) and
[bundles](pilot-local-preflight-20261103/bundles-build-clean.log).

## Focused checks and retained failures

With the final clean build, the following command passed **27 tests**:

```sh
mix test test/dev/knowledge/pilot_test.exs test/dev/knowledge/local_pilot_test.exs test/dev/knowledge/pilot_reservation_test.exs --seed 311032
```

The [test log](pilot-local-preflight-20261103/focused-tests-clean.log) covers
the finite fake-provider loop, mocked request wrapper, owner-only reservation,
native protected-lock contention, missing or malformed state and killing the
reservation-owning Erlang process within the same BEAM VM. It does not simulate a whole-machine power
loss or a second BEAM VM crash. With confirmation and audit variables absent,
the [launcher refused with exit 1](pilot-local-preflight-20261103/cli-refusal-clean.log)
before using the real account ledger. The retained refusal log contains the
message but not an exit-status record or invocation environment; those details
are reported observations rather than independently reconstructible from that
log. Scoped
`mix format --check-formatted` on the six overlays passed in the preceding
batch; its [log](pilot-local-preflight-20261103/format.log) is empty.

Earlier attempts remain evidence rather than being replaced:

- A standalone pure test VM [failed before tests](pilot-local-preflight-20261103/pure.log)
  because compiling `Ipse.Provider` required `Mix.State`; no Mix process was
  started for that attempt. A later [pure loop](pilot-local-preflight-20261103/loop-pure.log)
  passed 16 tests using a previous clean-built Provider BEAM whose relevant
  source matched this snapshot; that is reused-build evidence only.
- The first mocked wrapper run had [three setup failures](pilot-local-preflight-20261103/wrapper-pure.log)
  because the fixture used ExUnit's reserved `:file` context key. The key was
  changed to `:attempt_file`, and the [rerun passed three tests](pilot-local-preflight-20261103/wrapper-pure-v2.log).
  The [pre-correction manifest](pilot-local-preflight-20261103/source-before-fixture-sha256)
  is retained separately.
- Offline dependency compilation first [failed on the sandbox's local TCP lock](pilot-local-preflight-20261103/deps-build.log),
  then [failed because the isolated Mix home lacked Hex](pilot-local-preflight-20261103/deps-build-escalated.log).
  Copying the installed archive allowed the initial build and its
  [27-test pass](pilot-local-preflight-20261103/focused-tests.log).
- The initial copied dependency tree contained a Rebar `source.dag` cache that
  changed during compilation, as the [before](pilot-local-preflight-20261103/deps-sha256)
  and [after](pilot-local-preflight-20261103/deps-after-sha256) manifests show.
  The isolated generated build outputs and copied cache were removed before the
  final cache-free build above; source dependencies were not changed.

The one-shot local launcher reserves and conservatively charges 120 calls even
if the process stops or the run completes early. Its final receipt and native
controls do not make a historical count of actual outgoing requests from absent
or incomplete files. The pinned service's metadata remains cooperative; neither
these tests nor the model tag attest per-request weights. Candidate pairs must
remain private, and independent semantic labels are still required. The prior
uncertain ChatGPT pilot remains preserved and must not be resumed or retried.

After integrating the operator and contributor procedures, the
[documentation check](pilot-local-preflight-20261103/docs-check-summary.log)
checked 1,087 Markdown files and 8,965 local links with zero errors. The full
local run also reported permission warnings for private ledger directories;
those directories were not opened or changed. The retained summary omits their
paths. This documentation pass did not repeat the runtime tests.
After independent whole-chapter review and corrections, a separate git-backed
mirror check covered 1,088 Markdown files and 8,977 local links with zero errors;
it did not run model or runtime tests.
