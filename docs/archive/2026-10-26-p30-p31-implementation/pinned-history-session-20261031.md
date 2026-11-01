# Persistent history through a genuine Session replacement

Dated **2026-10-31**, based on `440c67d` plus the three test sources inventoried
below. Runtime/helper behavior is unchanged from `7b6ccd1`; this adds actual
coverage of an existing path. The [plan](../../plan.md) owns acceptance and the
[operator procedure](../../operator/knowledge-permissions.md#correct-or-supersede-a-native-note)
owns current use.

The isolated native `pin_history` control creates actual ordinary/current
statement receipts under public knowledge setup, pins the current note through
public native management, and performs actual ordinary correction and temporal
replacement through the Session-owned two-review adapter. It verifies physical
generations and receipts, then authenticates the old pinned history and its
matching successor. Public native forgetting removes the successor; the old
signed history remains byte-identical with `successor_storage: unavailable` and
no stored expiry. The original Session journal remains byte-identical and still
passes Saved reconstruction. No model dispatch occurs.

A separate **pure explicit as-of** calculation checks that persistent metadata
remains eligible at a timestamp 1,000 years ahead and cannot prepare an elapsed
history policy. No runtime clock is changed, no future effect is published and
this is not annual native turnover qualification or current-use permission.
Later use still needs current consent and original sources. There is no
instrumented production module or fabricated review/source receipt in this case.

The first case passed in 7.7 seconds. The completion-marker check then passed
in 8.7 seconds. The final source/journal-preservation case's completed summary is
retained below. Each is one selected genuine case; the other eleven scenarios
are excluded, not new passes. These automated PTYs establish neither human
authorship nor semantic quality. No inference, metadata service request or
download ran; allowances remain ChatGPT 238/300 conservatively charged and
local 4/1,000. The earlier whole-source negative result is unchanged.

This supplies a genuine counterpart to the old synthetic-source pin-history
component. It does not open that legacy Core mutation entry or close the remaining
split/deadline/turnover fixtures, full capacity/lifecycle, installed/platform,
quality or independent-audit gates. Operator knowledge and developer Session-source
chapters were reviewed against the actual pin/replacement/recovery flow, keeping
historical persistence distinct from live authority.

## Inventory

| Source or evidence | SHA256 |
| --- | --- |
| `test/ipse/session/managed_supersession_session_test.exs` | `d4cf7138fb27690b01128d8facb518d46acaa2368dbc4f85b357e459eac9f265` |
| `test/support/managed_supersession_session.exs` | `8cb1133145cf5a67ca624d8ea40aa04e6f92874b8222746a1ecda9e408b1d77c` |
| `test/support/managed_pinned_history_session.exs` | `7894411ed3a5d16a2de2317e35dbdf87941da8ffd6b4ea9c355aeb0d73cb6ce8` |
| `priv/ipse-runner` | `71d4125511930d6dd5694db290474e2a1640cdc27f13b0aaf8ee79bb59f87996` |
| `/tmp/ipse-pinned-history-session-final-qualified-20261031.log` | `226063657fd56d780cb484b99cd0f7a50ffdbca3c89cc61b14e40ff4b8dee5b6` |
| `/tmp/ipse-pinned-history-session-first-20261031.log` | `1e568fce4bbc3739ae86b7a4ab1795903ae635ac4c94922e53468ad2503091f8` |
| `/tmp/ipse-pinned-history-session-qualified-20261031.log` | `09f11cda63d53935b810118b4c288aafbbcf9f1f31bbb290e5d0849c33c47ba2` |

Final selected case, seed 20261031, terminal exit 0:

```text
Finished in 8.0 seconds (0.00s async, 8.0s sync)
Result: 1 passed, 11 excluded
```
