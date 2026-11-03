# Synthetic Session-owner guard discriminator — 2026-11-03

This investigation is not a production acceptance adapter or a completed
same-reply journey. The isolated snapshot is
`.session-guard-discriminator-e657.s8SxJW7i` at the repository root, made from
committed `e657267fc59a48325b17fe53022f796a49c51796` with `docs/archive`
excluded and dependencies copied separately. Its only source overlays are the
two synthetic fixture files below; no production event-job authority changed.
The snapshot and its logs must be preserved for independent inspection.

The fixture pauses the real Session's admitted synthetic Host task through a
test-only, in-memory Host instrumentation hook. It uses the existing
synthetic source-sharing handoff to retain that Session's Writer control,
Session control and active **prompt** source, then exercises the committed
native guard against a synthetic root. This is a manually reproduced bridge,
not a production SessionSource acceptance adapter, assistant reply, rendered
card, consent, review permit or publication. The per-test synthetic roots and
journals were removed by the fixture; only source and logs below remain.

## First fixture and the control gap

The original fixture overlays are preserved under `first-fixture-evidence/`:

| File | SHA-256 |
| --- | --- |
| `test/ipse/session/share_host_job_test.exs` | `cc9cf1691fd38da6c5825b60bc4fa6293ead35c73a2994ddc4bda877f5f3b95c` |
| `test/support/session_transaction_bridge.exs` | `f99b5461062a9a50d3b9e9d51c722c145cf42b06b054e55ab058a319f41ed6a8` |

With `IPSE_SHARE_TTY_UNION=1`, `MIX_ENV=test`, `HEX_OFFLINE=1`, isolated
`IPSE_HOME`/`TMPDIR`, and `ERL_FLAGS='+S 2:2'`, each test was a fresh Session
run using `mix test test/ipse/session/share_host_job_test.exs --only TAG
--seed 0`:

| Tag | Result and limit | Log SHA-256 |
| --- | --- | --- |
| `session_guard_positive` | 1 passed, 85 excluded; the synthetic root switched while the genuine Session handoff was retained and cleanup completed | `session-guard-positive.log`: `10abe5d0bf1c77007f873db15595a231f29962d9253d56719b31cf3f59b156a5` |
| `session_guard_wrong_recipient` | 1 passed, 85 excluded, but **invalid as a refusal control**: the bridge ignored the configure return and then deliberately failed, so test termination and old root alone cannot establish refusal | `session-guard-recipient.log`: `fe9a7cd606c736cd9125f219866c8e48df9a768c5a1e27d958a9300b377f684c` |
| `session_guard_writer_loss` | 1 passed, 85 excluded; loss of the native Writer-control helper left the synthetic root old and cleanup unconfirmed. It did not kill the Writer GenServer or journal owner | `session-guard-writer-loss.log`: `1278fd761aeb946d4cd248590cfc9e2ffb6f8ca865489e00a8d40833d1022c9e` |

## Corrected fixture and stopped run

The corrected fixture requires the bridge to forward the actual configure
result and the test to assert `{:error, :cleanup_unconfirmed}`. Its source is
preserved under `corrected-failure-evidence/`; its
hashes are `2364c86d140a52c2bcfebc480ce917005393354263e958a827154b7f6f2dc271`
for `test/ipse/session/share_host_job_test.exs` and
`7d0004d01d4b6bb3a6bce20e885e6cfe8d418acab2ce24cb4a86987589768dd0`
for `test/support/session_transaction_bridge.exs`; `final-fixture.sha256`
retains the file manifest. The committed `native/ipse-transaction.rs` and
`lib/ipse/runner/transaction.ex` hash to
`2e4197e07f9967201196fb777d236327d525a546d1564f500e7b8257b06dddb9` and
`d6a9a8cb3935b43d7befb9ae56a31b95cd8eff3b8a1048f230899403b4993d64`;
the built helper hashes to
`ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b`.

The positive test passed again (1 passed, 85 excluded), with log
`session-guard-positive-final.log` SHA-256
`270db7b76e733ce8948999f722857112803e1366b20638ddc024fbb554eb6473`.
The corrected wrong-recipient test failed (0/1, 85 excluded): the independent
test process never received the requested return before its five-second wait.
The log `session-guard-recipient-final.log` hashes to
`4a9fa53da6816e7e6b786957957083ebbb1bb9131503a6e645ee45b92d842bf1`.
The sequence stopped there; the final-fixture Writer-control-helper loss test
was not run. No unknown synthetic effect was replayed.

Source inspection identifies a possible cause of the missing response: if the
Session takes its mismatch branch, it evaluates `poison_session_share` before
returning, and that function kills the Host task waiting on the call. The
trace does not establish which branch ran, the requested configure result, or
wrong-recipient protection.

One separately authorized fresh diagnostic installed a test-only `:sys`
observer on the real Session to correlate the incoming configure call and its
outgoing reply, without depending on the killed caller. It also failed (0/1,
85 excluded): no matching reply arrived within five seconds. Its exact test
and bridge overlays hash to
`eea39e12e1e66b71814cf6b2a6f061cd68876496a51f8558f0c02df33d165f0b` and
`ccb10f9056ec09517a93934d0bb226583913e387da5a7377b26a2315e44b3e18`;
their manifest is `observer-fixture.sha256`, SHA-256
`134cdf790e7490c23ca06de4bc3c088d23dd2fd150c8066e922f326ed840cfd4`.
The retained `session-guard-recipient-observed.log` SHA-256 is
`e470fd5e2a91015c751b41cf20c9c534296228bb13eda47891fb0db5dd4bc686`.
No further attempt was made. Both corrected failures occurred before their
root and cleanup assertions, so neither establishes those outcomes; the
fixture's teardown removed the synthetic roots. The earlier helper-loss test
did assert old root and unconfirmed cleanup, and the positive test asserted
confirmed Session closure.

Wrong-recipient behavior remains unproven. Current acceptance claims remain
limited to the positive synthetic owner handoff. Actual Session/Writer/source
semantic binding to an acceptance event, the just-completed reply/card,
consent and no-replay publication remain open.
