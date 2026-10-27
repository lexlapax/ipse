# Hook-free private child-scope candidate

Recorded 2026-10-27. This [patch](child-scope-clean.patch) is a private candidate
for review, not an applied production change or an inference integration. It is
based on commit `53300f49caa111312ee1057cb80fbff00bb9c176` with the two base
source hashes recorded in the [retained-guard revision](child-scope-revision2.md).
Its resource and lock source SHA-256 values are
`1b5cf1fa7a11e313735675fb86ca516de7af8be3645c4e38a6adb2f8267f7de2` and
`b638c5f04a03f7ba231f43bcea3dc2cb192e7717e7805e90cd7712cc75f92550`;
the patch SHA-256 is
`24c034d546bd1642cbf64769e487fa15e8746f86c334c6861e55acbb805f9c9a`.
The private diagnostic hook has been removed from this candidate.

It refuses recursive controlled scopes while keeping ordinary nested
`file_effect` callbacks inline; tracks and awaits the exact guard's termination;
and shares one four-second cleanup grace across peer, root, guard and child
receipt checks. Its retained-guard control acquires and releases two nested
native locks in the same peer. The test is a local synthetic lock exercise,
not an actual Identity/Consent Session journey or 7.2.11 quota qualification.

The strict-compiled private graph reported **23 passed, 1 excluded** using seed
20270204 and max-cases 1, including existing Session resources and authority
suites. The [output](child-scope-clean.log) SHA-256 is
`c030121053a5b9ccd4c881b29d7ee8aecd3ea1e81a44516921a0333e68d3056c`.
The [main controls](child-scope-clean-controlled.exs),
[close controls](child-scope-clean-close.exs),
[retained-guard control](child-scope-clean-guard.exs), and
[receipt-replay control](child-scope-clean-replay.exs) hash respectively to
`7eeb1782bf354f765af3e8ee74cc935206f5ba6dae236d8a5955407df23beb2c`,
`f0917583f9b32503122597dce35c8dec9ef5953454376b86f30eb9bcc425dbca`,
`e080a2bfc5141db4f3734a3ed5d4d2c08c72d7598b9e2e01cb2745ed04e0d141`, and
`1f7aae7d8d0c91fcceeccdce99f1bfe47daab4ba03c88bb15d2bc52fc9c07da3`.
The excluded control requires the prior private hook; its separate recorded
evidence is in the [earlier investigation](effect-scope-design.md). One included
fault test stops and kills its own isolated helper; inspect it before running.

Wrong-token and wrong-child receipts, and replay of a previous child receipt,
cannot confirm a later withheld resource receipt in these tests. BEAM messages
do not authenticate their sender: a hostile process in the same BEAM with the
exact private nonce and PID could forge a matching message. The candidate relies
on those terms and host callbacks staying within the trusted host boundary;
isolated extension workers and JSON do not receive them. Independent review and
the exact runtime ownership boundary must be resolved before promotion.

This preserved snapshot also lacks an explicit duplicate-nonce refusal in
root child registration. Ordinary calls generate fresh references, but the
reviewer identified duplicate registration as an additional hardening and test
case; a later private revision is under investigation. This snapshot is not
the final audited implementation.

The full repository baseline is not established on the current unqualified
storage profile. Connection ownership, Session source/policy freshness,
completion-witness cleanup and actual inference egress linearization remain
separate open work. The [plan](../../plan.md) owns current status.
