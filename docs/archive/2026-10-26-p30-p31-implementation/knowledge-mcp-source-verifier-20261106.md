# Source knowledge MCP verifier — 2026-11-06

The focused source-mode synthetic verifier ran against a `corpus/mcp-lexical`
artifact built in `_build/verification/p31-focused-run-20261106-04` from the
separate source checkout of frozen snapshot 06. The snapshot is base
`8304dd4c5357b0786b27540713d3c868f39cb0f1` plus working patch SHA-256
`4b458b4ec0161fb51c64710a39c63676043730127edf987ebc3581fc4dcec9cc`
and allowlisted new files; it is not a clean commit build. The run checkout also
contains the reviewed test-helper retention overlay and a later test-only
completed-backup wrapper repair, neither part of the verifier's product source.
The verifier, runtime, and scenario source hashes are respectively
`8947e317828b009ce8b8a71dea9a690e75052b5e48fc6b83ad1a5290ed8869c2`,
`d7093291304018c917c7391f0a11ac92f0811f6927d0c23b14d44a0eeb16b596`, and
`101e26d63b7f2b14300d23db97abf7616893bdbf33741124b20ab1ca861d63e6`.

The artifact manifest SHA-256 is
`bf8bdb4153cc001804b354c60a9cc6d7118e445137e612cd166fa5795e1788b7` and
its Corpus BEAM SHA-256 is
`a47810c83eff3c69416a0afdbe3d6f88b1e0d15a8fb5000e43f9800bf1b86d1c`.
Artifact and SDK pre/post inventory files match respectively, with hashes
`7c1d21b55387611f32b121707d1f81b695b8523587ca8de04f7306a62876b855`
and `b06905abef6311faf5512beb3d73838119497bcacbcb75a2ddfa806b0420907d`.
The verifier reports a precompiled harness, private home and no system toolchain
on its runtime path.

The retained `mcp-source-verifier.log` SHA-256 is
`ddceea49a02c83f43fcd7a4686e285ddefd86860a626955d4f26f523e8cb5694`.
It reports nine checks: selected hydration and final validation, refusal of
malformed or stale selection, no denied dispatch, an empty-selection generation
probe without storage mutation, and preserved unknown outcome without replay on
resume. It reports no model requests or host-loaded domain modules. This is
selected-source coverage, not proof of complete namespace ranking.

The synthetic evidence root is retained at
`_build/verification/p31-focused-run-20261106-04/mcp-source-evidence/runtime/tmp/ipse-knowledge-mcp-7a01641cb509c005eac12f05bc99983c`.
Its `cleanup.json` SHA-256 is
`6f82d8457775cec5d66dc5529f3cb38a00184a8a1464f69d8aab096fbe1fccc6`;
it reports proof completion, eight confirmed Session closes, zero unconfirmed
closes and backend process exit. This receipt's scope is Session acknowledgement
and backend process exit only; it does not independently prove all descendant
or socket cleanup. The deliberate unknown journal and synthetic fixture records
remain retained. This source-mode run does not establish installed-package,
real remote-service, paid-model, full namespace, or complete P31 qualification.

The operator observed exit 0 from the bounded `elixir dev/verify.exs source`
command; no separate exit receipt file was created. A separate read-only
host-wide audit reported no `beam.smp`, `ipse-runner`, `ipse-pdf` or `timeout`
processes, and no holders of the Input lock or TCP port 39657 (`fuser` exit 1
with no output). That observation was reported in a team message, not retained
as a separate audit file, and is a point-in-time observation rather than a
proof of every possible descendant. Full artifact and SDK file-set inventories
were regenerated and matched; source inventory stability was verifier-reported.
