# Synthetic provider draft carryover

Recorded 2026-11-07 as a scoped implementation and verification record. The
[plan](../../plan.md) owns current milestone status; the
[operator procedure](../../operator/usage.md#refine-a-request-before-submitting-it)
describes current use. This record does not establish P31I completion.

OpenRouter and explicitly selected loopback OpenAI-compatible routes use Chat
Completions continuation, while xAI API and registered-client subscription use
the `xai` Responses replay namespace. The draft projection now checks the
selected adapter's native shape and complete tool groups before withholding an
entire cancelled draft interval. Saved reconstruction selects the policy from
the recorded provider. This does not switch provider or billing mode.

The working-tree change was checked with eight adapter-shaped pure projection
controls, strict compilation of the three changed host modules, Elixir 1.18
format comparisons and independent static review. The focused native candidate
used local source commit `2337e1bae486157d30096ab39c85b0e07de4ece7` plus the
selected working-tree draft modules and tests. Its isolated test build compiled
201 files with warnings treated as errors. A corrected Chat Completions Session
group passed two tests, and an xAI group passed three; both used fresh synthetic
fixtures, the normal provider wrapper and loopback endpoints. They exercised
cancelled draft tool calls, ordinary continuation, same-ID Saved reconstruction
and route-specific synthetic authorization. The subscription credential was a
test fixture, not an account or entitlement check. A separate corrected
malformed-native case also passed.

The first Chat Completions group exited with one pass and one failure: its
malformed-data case could not start because its synthetic OpenRouter profile
was missing. That original result and fixture remain retained; a later fresh
fixture supplied the profile and passed. An earlier direct-check invocation
loaded zero tests and is not counted. The first sandboxed Mix compile failed
because its loopback filesystem lock was denied; a separate local-socket-enabled
compile passed. Scoped process, listener and open-file checks and source
comparisons passed after the focused runs. An independent audit checked their
recorded process groups and byte-compared the selected successful-run journals
and release receipts; the successful temporary roots were then removed, while
the failed root remains retained. These checks do not prove every detached
descendant or validate receipt signatures.

At the time of this record, private artifacts are under
`_build/verification/p31i-carryover-native-candidate-20261107-01`; they are not
part of a release and may contain synthetic private prompts. Their SHA-256
values identify the recorded bytes, not a complete environment seal:

| Artifact | SHA-256 |
| --- | --- |
| `build-evidence/compile-loopback.log` | `c5cc738323937ea3b6113c579c570eb1c90a82d3113b6a7f46c71bfc6081cea0` |
| `chat-session-01/private.log` (failed run) | `2cea5c1c160a7911c16ca70cec5f3c1a64067248e56ca2cb7780fe47479332b9` |
| `malformed-session-01/private.log` | `efde494cf1255d9a7ba284bfc5a18b16a56a14161aaa01df3aa6090047ca8131` |
| `xai-session-01/private.log` | `25fc1827dc7d8ecd70138508e146e3d528824f5d0df1c7aa173f0b307e3acdd2` |
| `chat-session-corrected-01/private.log` | `9c5855398a64a586238bfbaf2400457c310818beb92d03e16f9c1e43add275f9` |
| `source-input-corrected.sha256` | `680681ae952d709cf0dcee31bf045231f580044ba665f2d847c058bd9142c511` |
| `success-evidence-01.sha256` | `f3171c3d1134f452c9edd14a231b43c48a9559b4392ae1ca8090e9363732d52e` |

The focused tests do not establish installed behavior, live provider behavior,
model quality, all mixed-provider histories or the final integrated baseline.
The broader P30/P31 regression was still active with failures when this record
was made. Keep its results and the remaining P31I acceptance gates separate.
