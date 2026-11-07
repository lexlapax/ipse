# Anthropic signed-thinking draft withdrawal — 2026-11-06

Historical development evidence. The [plan](../../plan.md) owns P31 status;
the [operator manual](../../operator/usage.md) and [developer training](../../developer/workspace-context.md)
describe current behavior. This increment extends the earlier
[text-only carryover record](anthropic-draft-carryover-20261104.md).

For an Anthropic no-tool draft, the projection now permits exact native thinking
blocks with bounded UTF-8 thinking and a nonempty bounded UTF-8 signature. It
withholds the complete authenticated draft interval, including those fields;
earlier and later native messages remain unchanged. Redacted thinking, unsigned
or malformed blocks, unknown fields and tool exchanges still refuse withdrawal.
This does not validate a signature with the provider or rewrite native blocks.

A one-scheduler source test with the previous Draft and DraftNative BEAMs omitted
from a private SDK copy passed 11 tests with exit 0 and no warnings. Controls
cover cancelled and accepted projections, the actual Anthropic request-body
builder, retained earlier signed thinking, and absence of the draft reasoning,
signature and draft text from later request bodies. The retained log at
`/tmp/ipse-anthropic-thinking-20261106/pure-02.log` has SHA-256
`d9da835f8f0f2552ef5cfaebbe7662fffcf82435ee0d46bd3c17b1709ae3cb06`.
The tested source and projection-test SHA-256 values were respectively
`d3b29590684e7d499a554fbac42f95a5cc54fb677bcb11a351ab93bfbc180d6f` and
`3897b6418d0e9fef5ade1b822227940e5eef32c72b3530822e79fda822081766`.

The first pure attempt failed one test before projection because its invalid
UTF-8 fixture could not be encoded into a journal digest; it also emitted
redefined-module warnings. The invalid-byte assertion was moved to the direct
validator and the earlier log was retained at
`/tmp/ipse-anthropic-thinking-20261106/pure-01.log`, SHA-256
`5f665477ecdad8bffdc0dd6131cea4052fa9c80e4a3cdfe428c2799e616b8e09`.

An independent static reviewer found no concrete blocker in the scoped change
or the subsequently strengthened Session test. The latter has SHA-256
`24aa8b0975eb56c08b2cdf413415b9bc0a63e8c8a55a5b5056c5d468744e37bd`
and had not yet run at that checkpoint. It uses streamed synthetic Messages responses and checks
cancelled and synthetically accepted Session/Saved carryover; its acceptance
witness is not a native terminal proof. Run only when the shared native Input
and loopback lane is free:

```sh
ERL_FLAGS='+S 1:1 +A 1' mix test test/ipse/session/draft_vertical_test.exs --only anthropic_signed_draft_carryover
```

Installed, real terminal and live Anthropic qualification, broader provider
continuation and P31I completion remain open.

The later focused Session run passed that test with its synthetic acceptance
witness. Its retained log at
`_build/verification/p31-focused-run-20261106-04/anthropic-signed-session.log`
has SHA-256 `9517bdd395be67a1134d54a46ca523a996557728c9f017bb6dd6a55d459c695a`.
The operator observed exit 0 and an independent host check found no test process,
Input-lock holder or listener. This does not change the remaining limits above.
