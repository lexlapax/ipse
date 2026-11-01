# Exercise real history expiry after native Session correction

Dated **2026-11-01**, based on `61fa928`. This is fixture maintenance and
bounded native lifecycle evidence, not C1a or P30/P31 completion. Current
procedures belong to the [operator manual](../../operator/knowledge-permissions.md#reclaim-an-expired-native-note)
and [contributor testing chapter](../../developer/testing.md). The
[plan](../../plan.md) owns remaining acceptance.

## Preserve the failures and identify their boundaries

The previously retained `save_history_expire` failure was reproduced alone on
the current source: **zero of one passed, 22 excluded, in 60.3 seconds**.
The PTY driver had reached the standalone `Type correct …` prompt but waited
for the `approval>` marker of the newer Session-owned relation flow. It never
answered that old prompt before its unchanged 60-second bound.

A diagnostic driver change allowed only this named fixture to answer the
standalone prompt. That exposed the obsolete next step: its generic Core
supersession API correctly refused with `native_review_unconfirmed`. The second
run reports **zero of one passed, 22 excluded, in 17.9 seconds**. Neither run
establishes a production history-expiry defect. Both logs remain in the
inventory. The diagnostic driver edit was reverted; its final bytes are
unchanged from `61fa928`.

## Use the existing executable contract

The fixture now opens a genuine new Session in the same protected project,
issues `/correct` for the actual saved preference, observes the exact prompt
through its native channel, stages it and obtains the separate native
statement/category and relation choices. Session performs the existing
source-owned publication and confirmed close. Saved validates that new journal;
the test requires the exact target, a settled result, the matching review and
replacement evidence from that new Session with `native_operator_assertion`
origin. It manufactures no successor proof, native permit, source lease or
publication authority and invokes no model.

The previous eight-second signed retention choice remains unchanged. Correction
must complete before it expires and preserve that exact deadline in historical
retention. The test then disables capture, waits for the actual deadline and
uses public `knowledge expire`. Its existing assertions still require intent
before staging, settled historical-expiry normalization, removal of only the
old record, the complete unchanged successor, disabled permission, zero
model/download/cost accounting, public operation inspection and an unchanged
original Session journal. This is elapsed wall-clock expiry; annual endurance
qualification remains separate.

The first repaired run passed **one case, 22 excluded, in 25.6 seconds**. The
whole operator and contributor procedures were reviewed against the actual
flow. Their ownership and command semantics remain unchanged; testing guidance
now explains how to retain the current native prerequisite instead of bypassing
it through a retired generic mutation API.

## Fixed-source verification

The fixed-source native statement/lifecycle cohort passed **twelve cases,
eleven excluded, in 145.0 seconds**, using
`mix test test/ipse/session/operator_assertion_integration_test.exs --exclude managed_approval:true --max-cases 1 --seed 20261101`.
This excludes the eleven native managed-approval controls already qualified at
the unchanged runtime candidate. Formatting and strict compilation passed.
The documentation checker passed 1002 Markdown files, 8332 local links and the
manual/archive rules with zero errors; permission-denied private directories
remain untouched. Production code, native helpers,
deadline policy, the PTY driver and inference allowances are unchanged. The
original whole-suite verdict remains 3538 passed, 60 failed, 109 skipped and
112 excluded; focused results do not revise that aggregate. Broader capacity,
installed/platform, human, quality and final audit qualification remain open.


| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `test/support/managed_history_cli.exs` | 6761 | `0c1c781d962bcd86c124c53d3c3fb72a4b6c9ea8c0e6e564312a797d24c112e9` |
| `test/support/operator_pty.rs` | 22426 | `c242e711c0c14097fc516b6c2ebded824caab553892375e3422f62c02e8448e4` |
| `priv/ipse-runner` | 969344 | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |
| `/tmp/ipse-history-expiry-driver-baseline-20261101.log` | 66097 | `2ea6a1c224a6a579d5b0c5bbdd1b363f1c183f49e9d1b93845d02fb4d51bcb93` |
| `/tmp/ipse-history-expiry-driver-first-20261101.log` | 66478 | `882c4987747fc2b0940b17b90a3e4dcc8775ab099762fc29127936893d4c510b` |
| `/tmp/ipse-history-expiry-session-first-20261101.log` | 331 | `17cccaa6d10914ceec9ea3dd3fabd457b9b0c0e2c388169d53fe3d90dbe6a560` |
| `/tmp/ipse-history-expiry-session-regression-20261101.log` | 307 | `4349d34d242b7166910e8c9e16911206f1d767d461565aba9fda38df189822d4` |
| `/tmp/ipse-history-expiry-session-format-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-history-expiry-session-compile-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-history-expiry-session-docs-first-20261101.log` | 757 | `995b8320e1f9d4c39533482e8fbd732d67b6c09b88ebe9c0eb0140b8263f4877` |
