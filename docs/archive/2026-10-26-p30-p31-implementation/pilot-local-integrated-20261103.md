# Committed local pilot synthetic gate — 2026-11-03

This is an offline synthetic verification of the local capture-pilot launcher on
committed source after planning integration. It follows the earlier
[isolated preflight](pilot-local-preflight-20261103.md); current procedures are
in the [capture-pilot chapter](../../developer/capture-pilot.md), and the
[plan](../../plan.md) owns milestone acceptance. No live model call, model
download, or access to the real user's authorization ledger occurred.

## Exact source and build

The isolated snapshot was `git archive` of commit
`c8aa3cd6734b11365de52bc74f4b211ab62d1bff`, with `docs/archive` excluded and
no source overlays. Its [source fingerprint](pilot-local-integrated-20261103/source-sha256)
has SHA-256 `293e030065b553f7072cad42b0934deed85b038928e5baab7ee80ad6ee1b7b2f`;
all recorded source files matched before and after the batch. The six committed
pilot source/test files match the hashes in the earlier preflight. The retained
single source manifest checks the snapshot, but does not independently establish
the timing of the reported before/after checks.

The 743-file copied [dependency-source fingerprint](pilot-local-integrated-20261103/deps-sha256),
excluding `_build` trees, is byte-identical to the
[post-build fingerprint](pilot-local-integrated-20261103/deps-after-sha256);
both hash to `843a8bffba4b4e070bd25b4bc54da54c6e4e9a1404bbe085c3676da5a911bcee`.
They also match the earlier clean preflight. The isolated Mix home contained a
copy of Hex 2.5.1 from that earlier isolated snapshot; its
[manifest](pilot-local-integrated-20261103/hex-sha256) hashes to
`1359cb45bc344884ceb7e54f4dcec501d59c07db46a3c6514ea23ae7bafdbe2f` and
matched after the batch. Mix and Hex used isolated homes and `HEX_OFFLINE=1`;
the sandbox escalation allowed Mix's local lock socket. The prior preflight
records the original lock, missing-Hex and copied-cache failures.

The [native helper](pilot-local-integrated-20261103/native.log),
[offline dependency compile](pilot-local-integrated-20261103/deps.log),
[strict application compile](pilot-local-integrated-20261103/compile.log) and
[bundled extension build](pilot-local-integrated-20261103/bundles.log) passed.
The dependency compile emitted third-party warnings; application compilation
used `--warnings-as-errors`. This clean build is evidence for these on-disk
files in the recorded environment, not cryptographic attestation of executing
memory in a future process.

The built native runner SHA-256 was
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
The Provider, Usage, Ollama Models and Jason BEAMs respectively hashed to
`afd89d5ec90c87287290a4bd916e2a5dbe3a00d2e45318185778cd90f348f9b1`,
`7124158025b67851ed503ef238349cd9e9fda93ecdb070120e6a9e23cda277a6`,
`3113c0992f7408d628755470bfd7c411d2c4c01801a9e598572c247f0538fd41`, and
`fdf2d74677ddafd307c1a56d238303429661a3f58f0ba9b82ae4f19f2fd7ef64`.
The broader [runtime file manifest](pilot-local-integrated-20261103/runtime-sha256)
hashes to `e0cdba5a0604864394aff0719cb5a93eb78e397599c681c915651338b08918c7`.

## Focused synthetic checks

The following command passed **27 tests** in the isolated test environment:

```sh
mix test test/dev/knowledge/pilot_test.exs test/dev/knowledge/local_pilot_test.exs test/dev/knowledge/pilot_reservation_test.exs --seed 311033
```

The [test log](pilot-local-integrated-20261103/tests.log) includes the pure
fake-provider loop, mocked wrapper, owner-only reservation, protected native
lock contention and killing the reservation-owning Erlang process within the
same BEAM VM. It does not
simulate a whole-machine power loss or second-VM crash. With the confirmation
and audit variables absent, the [launcher refused with exit 1](pilot-local-integrated-20261103/refusal.log)
before resolving the production account or ledger. The refusal log contains the
message but not a shell exit-status record or invocation environment; these are
reported observations. Scoped
`mix format --check-formatted` on the six pilot files passed; its
[log](pilot-local-integrated-20261103/format.log) is empty.

This gate does not establish a successful live pilot, per-request model-weight
attestation, protected capture, independent semantic labels or representative
daily intake. The local pilot's fixed 120-call reservation has no refund path;
the incomplete earlier ChatGPT run remains separate and must not be replayed.
The documentation checker also passed in a git-backed mirror: 1,090 Markdown
files, 8,996 local links and zero errors.
