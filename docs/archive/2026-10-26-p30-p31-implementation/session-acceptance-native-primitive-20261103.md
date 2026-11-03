# Session-acceptance native primitive — 2026-11-03

This records an isolated primitive checkpoint, not a completed acceptance
journey. The tested candidate is in the disposable snapshot
`.native-acceptance-guard-8d1f.EkMnfkXu` at the repository root. It was made
from committed `8d1f5d7dcfc55efdab07389a8f35a626b159ad25` with
`docs/archive` excluded and repository dependencies copied separately; it
does not include the quarantined chat draft or private user data. The four
exact reviewed overlays were later copied into the worktree for this checkpoint;
the complete integrated suite remains open.

| Snapshot overlay | SHA-256 |
| --- | --- |
| `native/ipse-transaction.rs` | `2e4197e07f9967201196fb777d236327d525a546d1564f500e7b8257b06dddb9` |
| `lib/ipse/runner/transaction.ex` | `d6a9a8cb3935b43d7befb9ae56a31b95cd8eff3b8a1048f230899403b4993d64` |
| `test/ipse/session/stored_sources_test.exs` | `d1a4e8a97ac970b6df4b5496f5de0df644bdf0057514a02db56d5707e08a2ffa` |
| `native/README.md` | `c0cf2afbaeec08e1ff31168a35d539f5f2f694b538a2f020e7235a6651e21a4d` |

The README was clarified after the test runs to state the cutoff bounds and
state-dependent cleanup rules. The tested runtime and test sources did not
change; this documentation-only revision was not followed by another run.

The candidate keeps opcode `j` unchanged and adds a distinct explicit
Session-acceptance purpose and one-shot guard. It refuses purpose entry after
prior mutation/staging, unarmed switching, rearming, deadline widening and
second switch attempts. It derives a monotonic cutoff from an earlier monotonic
sample, tightens the uncapped guard cutoff before applying the transaction
lifetime, and checks live retained owners at the native decision. Descriptor
identity is not proof of the Session/Writer/source semantic relationship.
Generic transactions remain available: the future trusted host must enter the
purpose before its acceptance mutation and must not fall back to another path.

## Checks and retained logs

All paths below are relative to the snapshot. The uninstrumented helper was
built with `sh dev/build-native.sh`; its SHA-256 after restoration was
`ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b`.
Checks used isolated `IPSE_HOME` and `TMPDIR`, `MIX_ENV=test`, `ERL_FLAGS='+S
2:2'`, local socket access, and seed `0`. The following commands are shown
without their output redirections; the named log holds each result.

| Command | Result | Log SHA-256 |
| --- | --- | --- |
| `mix test test/ipse/session/stored_sources_test.exs --only chat_acceptance_guard --seed 0` | 7 passed, 30 excluded | `guard-test-reviewed.log`: `b5e3e5f55b76b01bf221b95bd3e0e6aec506d3db9b7aee4f5a7dc3a3cb50c6b3` |
| `IPSE_TEST_SOURCE_SWITCH=1 mix test test/ipse/session/stored_sources_test.exs --only chat_acceptance_guard_hook --seed 0` | 1 passed, 39 excluded; six owner-loss scenarios | `guard-hook-reviewed.log`: `448e6a9a538d0a54b193f7454f530e25bc29c871ebc6798a22c7f0f9900933a3` |
| `mix test test/ipse/session/stored_sources_test.exs:932 test/ipse/session/stored_sources_test.exs:1572 --seed 0` | 2 passed, 35 excluded; existing `j` controls | `guard-existing-j-reviewed.log`: `b0ee719e171411c5944bb7a3e64e2bf0ec24b58a47cbbef3fba1c7c88dbb16bc` |
| `task-tmp/guard-native-unit-reviewed session_acceptance_clock_cutoff_never_extends_after_wall_changes` | 1 passed, 83 filtered out | `native-clock-reviewed.log`: `39dd2ec5075af9791bf9ca965fc831d60f2d299300a82dcc15da2a3a99b27281` |

The unit binary was compiled from the final overlay with `rustc
--edition=2021 --test native/ipse-runner.rs -o
task-tmp/guard-native-unit-reviewed`. The separate boundary helper was built
with `rustc --edition=2021 -C opt-level=z -C strip=symbols -C panic=abort
--cfg ipse_source_switch_test_hook native/ipse-runner.rs -o priv/ipse-runner`;
it was used only for the hook test, then the uninstrumented helper was restored
before the `j` regressions. In the six hook scenarios, loss of each synthetic
Writer, Session-control or source owner before the decision left the old root
and an unknown result; loss after the decision left the new root and an unknown
result. This is evidence of the checked decision boundary and uncertainty, not
kernel-atomic cancellation. The clock control simulates supplied wall and
monotonic values; it does not change the host clock.

The first test batch failed 0/3 because the Elixir response parser did not
allow the two new tags; `guard-test-first-failure.log` SHA-256
`861d5524066b28a4895aa437799463871ad0f7b10df541e96204299db0c80a1d`.
After correcting that parser, a second batch passed 1/3 and failed the other
two before transfer because the pending state blocked the existing recipient
identity lookup; `guard-test-second.log` SHA-256
`6cc5c9888820df919851a91c3f37b265e3420047e292262f38d077519bb240f3`.
The final source permits that lookup. Both failure logs remain in the snapshot.
An initial `/tmp` archive extraction also hit quota; its incomplete temporary
directory was removed before the project-filesystem snapshot was created.

After the focused tests, the same source overlays and uninstrumented helper
hashes were checked again. The isolated `./dev/build.sh` passed with
`HEX_OFFLINE=1` and `IPSE_BUILD_COMMIT=8d1f5d7dcfc55efdab07389a8f35a626b159ad25`;
`full-build-offline.log` SHA-256 is
`d1716ac65511e136efad15c5eaf89432988ea6c8d78e25a6797bf9dae2ab83d8`.
The changed Elixir files passed `mix format --check-formatted`, and
`MIX_ENV=test mix compile --warnings-as-errors` passed incrementally. Their
empty logs `changed-format-check.log` and `test-compile-warnings.log` both hash
to `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
These checks used the same isolated paths, offline dependency setting and
local Mix socket access as the focused tests; they did not override `HOME`.

## Independent review and remaining gates

Independent source review of the corrected frozen candidate found no further
concrete blocker for this isolated primitive. The review confirmed that the
two earlier cutoff issues and pre-purpose mutation issue were addressed, while
explicitly leaving these boundaries open:

- The positive tests use independent synthetic owner helpers and an inactive
  source lease. They do not prove actual Session ↔ Writer ↔ source ownership
  or host binding of a same-reply proposal.
- The substituted source-inode control does not cover every wrong owner, role,
  peer or secret. A missing Writer with a present Session control is not
  constructible through the existing Writer-first import protocol.
- Real SessionSource integration, the actual native card and code, consent and
  reservation accounting, interruption recovery, later authenticated use,
  ordinary approval controls and the full same-reply journey remain untested.
  The primitive is not wired into that journey.
- The complete test suite has not been run for an integrated change. The
  successful build and compile checks above apply to the isolated snapshot, not
  later integrated source. Independent review covered the native protocol guide;
  a sanitized git-backed documentation check passed 1,103 Markdown files and
  9,073 links with zero errors.

The logs and helper named above remain in the snapshot, which is not a durable
archive by itself. Preserve the snapshot or copy its synthetic evidence before
removing it. The [design](chat-acceptance-session-guard-design-20261103.md) and
[architecture reassessment](chat-acceptance-reassessment-20261103.md) remain
proposals and do not claim this investigation completes the frozen contract.
