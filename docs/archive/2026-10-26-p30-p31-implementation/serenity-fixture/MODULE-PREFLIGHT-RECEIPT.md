# Serenity control-open preflight, 2026-10-27

The user authorized the disposable Serenity test, Docker, the existing image
and device-mapper tools. The coordinating agent independently reviewed and
executed the [control-open harness](module_preflight_harness.sh), SHA-256
`f93c8b970c51d6e325f59d0256ea4ff44709ff033548967edb5bf7074dab035e`.
It opened the exact loop-control and mapper-control character devices, but did
not issue an ioctl, open a block device, bind a backing file, create a mapper,
mount a filesystem, unload a module or remove a loop index.

[Captured before/after files and the exact module receipt](module-preflight-evidence/SOURCE-SHA256SUMS)
record kernel `7.2.11-arch1-1`, nonce `63ebcfd6bc5a4167223662f0dae3539d`,
loop and dm_mod absent before and present after, and no loop index lines in
either snapshot. The root-owned `module-load.receipt` SHA-256 is
`5a78ade1345a020ce7ddd9baa14fe23851ce5b2744376b9bc0565bcfea17518c`.
The persistent original remains at
`/home/lexlapax/projects/lexlapax/ipse/.serenity-module-receipt.6Fow8PKP`.
The opened modules are persistent host effects; this test did not restore the
previous host module state.

The coordinating agent's tool transcript recorded exact container ID
`87838ae9e589a802b8122d272190262e051fc1a91a45cc45e56bb9a00926ca55`, stopped
with exit 0; stage `/tmp/ipse-module-stage.59bvFtZV` device:inode `53:241967`
and binary inode `53:241968`, SHA-256
`687be2268a4720eebb0cc5d6671684b0275f7ff32700fd7e8d20e1a3ccf6f64f`.
After independently rechecking the exact container, stage identity, contents and
hash, the coordinating agent removed only that stopped container and staged
binary/directory. The workspace ledger was retained, and neither module was
unloaded. The executable was built from [module_preflight.rs](module_preflight.rs)
with `rustc --edition=2021 --cfg ipse_live_reviewed -D warnings` in its private
build directory; its default build is disabled.

A separate no-device runtime mount preflight used
[runtime_boundary_preflight_harness.sh](runtime_boundary_preflight_harness.sh),
SHA-256 `33de2a440a233e74edab40e24425b9195aa4e54cca39b50e3529af5663195c68`.
The coordinating agent's transcript recorded stage
`/tmp/ipse-boundary-check.n3y8oM1r` device:inode `53:238372`, probe inode
`53:238375`, host mount namespace `4026531832`, and equal container/cgroup ID
`eb618cb0bc15654c78785be28ef9f865cf237368222d5fa5b1fe8209a41c895c`.
It reported `RUNTIME_PREFLIGHT_OK`, removed the exact container and stage, and
exited 0. This is mount validation, not a runtime-graph or fault test. Its
[frozen source graph](runtime-boundary-build/SOURCE-SHA256SUMS) includes the
original absolute-path manifest for provenance; no raw output log was captured.

The coordinating agent reviewed and ran the separate [loop-index candidate](loop_index_create.rs)
and [harness](loop_index_harness.sh), SHA-256
`02de7d84edd897d993db711c0dd89f488a2daf38c0a7ac1fe1de3d576a9c8727`.
It issued one `LOOP_CTL_ADD` for index 4095 after recording intent. The index
was absent before, present afterward, and no backing was bound or block I/O
performed. The exact [index receipt](module-preflight-evidence/index-add.receipt)
has SHA-256 `7931162f92507eebb80d67045b5e1db27828cc4abe0af1234eea13c379092ecf`.
Host sysfs reported `25:601631`; fresh no-device containers reported
`84:601631`, matching the container-view receipt. The coordinating agent then rechecked and removed only stopped container
`480a5719161b8c318774c51be11a82d42a6c90c2df246d087719e000c3959c09` and
stage `/tmp/ipse-index-stage.ROL1IT29` device:inode `53:246335`, after
verifying the staged program inode `53:246336` and its recorded hash.
The workspace ledger and index remain. The index is deliberately
retained and is a persistent host effect. The later held-FD configure/fault
sequence remains unexecuted and requires review. None of this evidence
qualifies the 7.2.11 kernel for Ipse's protected storage profile.
