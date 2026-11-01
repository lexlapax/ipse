# Default literal lifecycle modes through genuine Session sources

Dated **2026-10-31**, based on `c731d1f` plus the test inventory below.
Production Elixir/native source and helper bytes are unchanged from `7b6ccd1`.
This restores integration coverage through the already implemented adapter;
it does not open the unreviewed Core supersession entry. Current contributor
procedures belong to [testing](../../developer/testing.md) and
[Session sources](../../developer/session-sources.md); the [plan](../../plan.md)
owns remaining acceptance.

## Completed default cohort

All **17 top-level tests passed in 239.8 seconds**, serially with max_cases 1
and seed 20261031. The cohort contains the 13 genuine Session scenarios, the
native test's **six default modes without an environment selection override**,
the native turnover record test, and the separate history-use and interrupted-
compaction follow-ups. The six default modes are ordinary, temporal, deadline,
split, history expiry and pin history. Code paths and scripts are absolute and
exclude the implicit current-directory entry. A prior selected five-mode/native
turnover run passed two top-level tests in 70.3 seconds; it was not the default
cohort and is retained separately.

Ordinary replacement and old history keep the original signed deadline. Temporal
history uses exactly the native review time plus 365 days; pinned history stays
persistent. The actual public pin/replacement/forget path preserves the original
journal and authenticates retained history after successor removal. All ordinary
success, cancellation, revocation, missing-source and unknown recovery controls
retain physical store, Saved and no-replay assertions.

## Explicitly controlled parts

The deadline case installs a child-only Collection pause module **before initial
permission review**, using a real, stable inventoried BEAM path. After an actual
public native duration choice and relation review, it pauses at the pending root
switch, verifies the exact signed target deadline and actual transferred Session/
Writer controls, and waits past that deadline. The actual publisher then checks
its active resource scope and live native transaction and calls the original
unchanged switch body. The required reply is exactly
`transaction_write_deadline_elapsed`. The selected root and operation index stay
unchanged; full publishing liability remains one operation, 65,536 input bytes
and 16,384 output bytes with nil actual/receipt. Session stops and reopens idle
without replay. This establishes a refusal before final native admission, not a
physical completion bound for an already admitted rename.

The split case installs a separate child-only Session pause before initial review.
It pauses **after the real new assertion and Writer proof are committed**, before
the worker selects a root. A trusted test task authenticates the two existing
records/pages and seeds explicitly synthetic full-page geometry with a same-value
CAS and a separate checked generation. Filler rows have no public records and
grant no source authority. The actual publisher independently revalidates the
real old/new proofs, current policy and seeded root, performs the genuine native
review, and publishes **eight signed sidecars** through the production transaction.
Observed values: **25 closed read units**, **1,772 normalization-receipt bytes**,
and **22,297 measured Consent input bytes**, within the 65,536-byte reservation.
The measured charge is actual ledger usage, distinct from the earlier synthetic
packet-size probe. This is selected-record protocol/geometry coverage, not an
independent populated-capacity or quality result.

The history-expiry component starts with real Session-reviewed sources and signed
history, then supplies an explicitly labelled **future as-of** timestamp to the
existing trusted Core component. It checks the before/exact expiry boundary,
native deletion, unchanged successor/anchor, refused recapture and backup floor.
Its separate component journal and virtual mapping do not establish that a year
elapsed or that the public CLI performed a future action. Turnover records use
`source_scope: native_reviewed_session_fixture`, retain `qualification: false`,
and separate actual native review time from `explicit_synthetic_as_of`.
Actual short elapsed-policy reclamation remains separately tested.

These controlled child hosts preserve native helper bytes and real source/input
provenance; their pauses are not unmodified-host fault qualification. Stable
instrumentation-source hashes are listed below. The post-switch control retains
its separate SessionSource pause and requires the physically incremented root,
unknown result, full publishing liability and idle no-replay recovery.

## First outcomes and scope limits

Earlier telemetry/trace probes are retained. One found the exact elapsed error at
Collection's boundary, but exported-wrapper traces and a later private-call trace
were not consistently observable. Their failed assertions are not diagnosed as
production failures. The final control uses a deterministic boundary pause and
requires the exact native reply rather than accepting multiple outcomes. Its
first attempt used a nonexistent child-fixture `Process.fetch!`; the corrected
accessor and stable-host setup passed. The first split seed used strict `not` on
a row/nil value and returned unconfirmed; its boolean expression was corrected,
and the fixture's separate generation is checked explicitly. No production gate,
deadline, allowance or source validation was relaxed.

Three final deadline/input-loss/post-switch-loss cases passed in 41.3 seconds;
the isolated genuine split passed in 24.2 seconds before the complete cohort.
All original negative logs remain inventoried. Source/helper bytes were fixed
during each qualifying native run; PTYs ran serially. Journals in ordinary test
roots are cleaned by their fixtures, while the diagnostic/native-mode roots retain
synthetic evidence. These are automated PTYs, not human or independent labels.

No inference, metadata-service request or download ran. Allowances remain
ChatGPT 238/300 conservatively charged and local 4/1,000. No runtime dependency,
native format or packaging change is introduced. The earlier whole-source negative
result remains 3,538 passed, 60 failed, 109 skipped and 112 excluded at `e86b1b8`,
with its original concurrency/inventory caveats; these passes do not alter it.
Formatting and documentation checks passed; the checker examined 996 Markdown
files and 8,279 local links with zero errors, retaining unrelated private-directory
access warnings. These are tests/manuals only, so no new runtime build or package
qualification is claimed. Whole-current, full capacity/annual turnover, installed/platform, semantic quality,
independent adversarial audit and the full P30/P31 handoff remain open. Affected
developer chapters were reviewed whole and reconciled with the unchanged operator
two-review/recovery procedure.

## Source, helper and available log inventory

| Path | SHA256 |
| --- | --- |
| `test/ipse/session/managed_supersession_session_test.exs` | `497ffa57fdf99a6e5096b482ea5165eddf110007c6e8632ca7561116c70ab82e` |
| `test/ipse/session/managed_supersession_native_test.exs` | `e2b89f7200cd5fc3e5eac1b78573cb506aa47fda2aa204d98aa9988ea0f69810` |
| `test/dev/knowledge/managed_v3_turnover_native_test.exs` | `3550f569e5b524ecf09284f5741842c91048855a3e7b8206ee144074ce2aea96` |
| `test/support/managed_supersession_session.exs` | `4dac3052c72c6be8df5dd2e48947ee469c4d2ec1aa60d9e1d026efdeff56359b` |
| `test/support/managed_supersession_unknown.exs` | `eef9bc53220cbc8d2ffb49dce4fa768863de1f96bc28389623f101caf1cdfa41` |
| `test/support/managed_split_session.exs` | `6ae048861ea93978cb4c6ad2c54474c250bba56dd645d1971ae53cb1eecc735e` |
| `test/support/managed_session_turnover.exs` | `44cd70920ee6817c1752eba15292b57890b2a7966deb4cb881cbf2e253cd1346` |
| `test/support/managed_history_expiry.exs` | `a4c2ee131feca632728698753b3d9b90f380874023731e6b8a030144ebaab306` |
| `test/support/operator_pty.rs` | `c242e711c0c14097fc516b6c2ebded824caab553892375e3422f62c02e8448e4` |
| `priv/ipse-runner` | `71d4125511930d6dd5694db290474e2a1640cdc27f13b0aaf8ee79bb59f87996` |
| `/tmp/ipse-supersession-deadline-telemetry-prior-20261031.exs` | `bf6d27549d5736f90e5742b971261fdf58d11236161d621ab520cc69c50148f7` |
| `/tmp/ipse-supersession-genuine-lifecycle-full-qualified-20261031.log` | `166486adbddbf82147514d52c73279b1728b31469199f76a923084b1720892c9` |
| `/tmp/ipse-supersession-genuine-split-first-20261031.log` | `7814195e57211cbe2cabc56c71f5bd45bb989366eb1b188eec0d19792f88b374` |
| `/tmp/ipse-supersession-genuine-split-second-20261031.log` | `ec8d93e4050074c8ee8db8a4c6977b3e304167583717635c2d061274db7e3f9b` |
| `/tmp/ipse-supersession-genuine-turnover-first-20261031.log` | `66b2b7d7184d59de41f7a2f42e069df4da718fc0651d6122216b726b02904480` |
| `/tmp/ipse-supersession-native-deadline-boundary-diagnostic-20261031.log` | `85bea190177e62790b9c3612b8a0ab8612093abd0bb9a1da326b9bd5ccdda2fd` |
| `/tmp/ipse-supersession-native-deadline-external-trace-20261031.log` | `ad224a8f3eab0bab7a498a902ad1a959020e35bebc1fc85148da48e336a61aa5` |
| `/tmp/ipse-supersession-native-deadline-first-20261031.log` | `2758fb433d183435fea322ca9c99c2a9dbc3e961d2c6843b5ffb197fc43b6f22` |
| `/tmp/ipse-supersession-native-deadline-loss-final-qualified-20261031.log` | `48e46dc572da2d35fa46b49e36cb212b621ae081ac3376def21a54cc5aa6a61b` |
| `/tmp/ipse-supersession-native-deadline-loss-qualified-20261031.log` | `02616ba25570782ffbf36646cf68ebf23a69c45f110b066492e1ca61dfdf01a7` |
| `/tmp/ipse-supersession-native-deadline-owned-boundary-first-20261031.log` | `55961db4548b5a79038204fd515e937d7a16328ed971832beffdae3568eb5e7a` |
| `/tmp/ipse-supersession-native-deadline-owned-boundary-second-20261031.log` | `a90f8b4caf51547c18387d440bf52016cf1c8d5cf3556644db2dc2466bd804c8` |
| `/tmp/ipse-supersession-native-deadline-switch-20261031.log` | `ce1aa2781cc3e71d1ced886fcc6656a700e189ab595100d7d9c3544812f41b56` |
| `/tmp/ipse-supersession-turnover-pure-qualified-20261031.log` | `e444f8efdcc2145b2e36a2f0755731f0cc37292be2c4451700c58f216bcc2573` |

Controlled child source digests (all installed before initial permission review):

- Collection deadline: `189e6b4708fe516fc8851d0860b455ab3f97f7f972d7fb57301a5f547b961f66`.
- Session split: `db45a8230a76a30e5ff4960bf79bbf2074e11b0ef9870be5547dd05b95c3989c`; recomputed from the exact unique source replacement in the inventoried fixture.
- SessionSource post-switch: `2b383f84ea8b3da48b3662213ac1319b45953843dc6f75fcd7b834045781fa88`.
