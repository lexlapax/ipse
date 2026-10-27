# Hook-free child-scope review candidate

Recorded 2026-10-27. At this review point the candidate was private and unapplied;
the record is historical, not evidence of inference integration or P30/P31
completion. The [plan](../../plan.md) owns current status. The earlier
[instrumented investigation](effect-scope-design.md) and
[retained-guard revision](child-scope-revision2.md) preserve defects and repairs.

The [candidate patch](child-scope-final.patch) contains changes to
`lib/ipse/session/resources.ex` and `lock.ex`, plus four tests at their intended
repository locations. It is based on commit
`dab5a458fa3a9f8425c3a5897a670ef233dc9ecd`; base source SHA-256 values are
`adc1a81af0f837daaeec1e675d9b090cd3ee67252e40ed3fe77bc566d86b1bb2` and
`e15fa70e33b71ab98bf4c4096d3b2f898714436b0a30e7f3e4db58850dc2c15d`.
Candidate source hashes are
`e7f580c9322e4b705ecd5e83de854782be1f3f850ce652bf8fdb3d2566147aed` and
`b638c5f04a03f7ba231f43bcea3dc2cb192e7717e7805e90cd7712cc75f92550`;
patch SHA-256 is
`d8981b3a6025ca9e08aec31dafbcddb7c37a2300b9de3039a82d7b4f0b4f9c9c`.
The private instrumentation hook and its hook-dependent test are absent from
the patch.

The candidate delegates a retained Session lock guard to a nonce-authorized
child scope, fences a peer on owner/scope loss, and waits for the peer, its
guard and the child's resource receipt using a shared bounded cleanup grace.
It refuses duplicate nonces, controlled reentry, and initiation from the
Session owner; ordinary nested `file_effect` calls remain inline. An unconfirmed
receipt or cleanup is unknown and must cause the eventual caller to quarantine
the affected request, not proceed as though cleanup succeeded. This is a host
primitive; the runtime must call it from a tracked owned task, outside the
Session GenServer.

The [combined private output](child-scope-final.log) reports **24 passed**,
seed 20270207 and max-cases 1, including the existing Session resources and
authority suites. It hashes to
`126c2cde662eb323015f5e2e191c0e12b79673dca9ee9462252bb0fdbae270cd`.
The four separately retained test sources are
[controlled lifecycle](child-scope-final-controlled.exs),
[child close](child-scope-final-close.exs),
[retained guard](child-scope-final-guard.exs), and
[receipt/nonce](child-scope-final-receipt.exs), with SHA-256 values
`f969214aad73b074c1747b2c7c8b3d793cb650c1b77b4e0be31807f5b8c0279e`,
`f0917583f9b32503122597dce35c8dec9ef5953454376b86f30eb9bcc425dbca`,
`e080a2bfc5141db4f3734a3ed5d4d2c08c72d7598b9e2e01cb2745ed04e0d141`, and
`38d408ab738e588211bf70221a4a795f7a8486a5a39268e005044da72c6922d3`.
The graph used Elixir 1.20.4/OTP 29, strict compilation and the private helper
identified in the earlier investigation. Native controls exercised lock
acquisition, cancellation, and nested lock ordering, not 7.2.11 protected quota
qualification. One control deliberately stops and kills its own synthetic helper;
inspect the fixture before reproducing it.

Receipt correlation relies on exact private host references and PIDs; BEAM
messages do not authenticate senders. A hostile process in the same BEAM with
those exact private terms could forge a matching message. The intended boundary
therefore requires trusted host callbacks and prevents extension VM/JSON access
to those terms. A monitor is asynchronous and cannot prove that no bytes are
sent after owner loss. Session source and policy freshness, the egress
linearization point, actual Identity/Consent use, Mint connection cleanup,
completion witness and complete repository baseline remain open.
