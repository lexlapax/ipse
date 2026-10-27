# Private child-scope prototype, retained-guard revision

Recorded 2026-10-27. The [earlier snapshot and design](effect-scope-design.md)
remain historical evidence, including their retained-guard defect. This is a
separate private candidate, not an approved change or a production API. It is
not wired to inference. The [plan](../../plan.md) owns milestone status.

Independent review found that the earlier child scope was tracked as `:peer`,
so the actual retained Session lock guard refused its nested native controller
registration. That failure was reproduced in an isolated graph. The private
candidate adds a dedicated delegated-scope registration accepted only from a
caller already tracked as a scope, and uses it after the root scope's
nonce-validated child registration. The new test also checks that an unrelated
caller cannot use this delegation. This is a candidate authority contract that
requires further independent review, not a proof that every caller and cleanup
race is covered.

Subsequent review found that this revision permits recursive controlled child
scopes with no global depth or count bound. A later private revision refuses
controlled reentry while preserving ordinary inline nested file effects. This
revision remains historical and must not be treated as the repaired candidate.

The [patch](child-scope-revision2.patch) is against source at commit
`53300f4`, with base `resources.ex` SHA-256
`adc1a81af0f837daaeec1e675d9b090cd3ee67252e40ed3fe77bc566d86b1bb2` and
base `lock.ex` SHA-256
`e15fa70e33b71ab98bf4c4096d3b2f898714436b0a30e7f3e4db58850dc2c15d`.
The patched source hashes are
`2d6954a178d3326f9806c6420dd25d8c1dca0ebd7bad091c62543552748c5c6d` and
`b638c5f04a03f7ba231f43bcea3dc2cb192e7717e7805e90cd7712cc75f92550`;
the patch SHA-256 is
`15e7c4c3c3d98e202b4ad048187b63d3eb3470d6ba80c558dbe0bc696ced35d5`.
The patch retains a **private-only diagnostic hook** and must not be applied to
production as written.

The isolated graph ran the [retained-guard control](child-scope-retained-guard.exs),
the earlier [child-scope controls](child-scope-diagnostic.exs) and
[close-path controls](child-scope-close-diagnostic.exs), and the existing Session
resources and authority suites. The [combined output](child-scope-revision2.log)
reports **22 passed**, seed 20270127, max-cases 1. The new test SHA-256 is
`2c5db42626bebb2b3f4681852fcfbb2a234a3e563f659347cdad2167bf58cac6` and the
log SHA-256 is
`66c73da07c1b218b4ed64054c461d25cf9316afbca55da9d2f395b85d23846bd`.
The graph used the private helper identified in the earlier record; its native
tests cover locks and cancellation, not protected allocation or 7.2.11 quota
qualification. One test deliberately stops and kills its own isolated native
helper; inspect it before reproducing.

The reviewer independently reproduced the retained-guard repair and the
normal-close and cast-stop controls on a separate private graph. Review of
delegated-scope authority, child/guard teardown, loss and replay of cleanup
receipts, and concurrent send/owner death remains open. In particular, BEAM
monitor delivery is asynchronous; it cannot replace a synchronous authority
check and defined linearization at inference egress.
