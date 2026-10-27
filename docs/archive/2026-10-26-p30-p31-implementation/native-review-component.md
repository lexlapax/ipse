# Fresh native review and one-use host permits

Recorded 2026-10-27. This is a host-primitives component, not a shipped knowledge
management command or whole P30/P31 acceptance. The
[source-reading chapter](../../developer/session-sources.md#bind-a-new-terminal-choice-to-revalidated-facts)
teaches the current API. Stored management choices, Session effect integration,
current eligibility and operator lifecycle procedures remain separate work.

## Effect boundary

`Runner.Review.with_review/3` displays complete, escaped JSON facts and a fresh
eight-byte challenge through actual native-v2 terminal input. Only exact
`command SPACE lowercase_challenge` enters its trusted callback. Bare yes,
whitespace, stale challenges, EOF, pipe input, malformed receipts and mismatched
input/display hashes refuse. The complete facts retain existing JSON limits,
plus a 16-KiB total and 64-KiB escaped-display ceiling. There is no truncation.

The callback receives a redacted, same-process opaque permit. The trusted adapter
must reacquire its effect locks and revalidate target, policy, recipe and full
facts before calling `consume/3`. The first genuine-owner attempt spends the
permit, even when facts changed. Foreign processes and forged references cannot
spend the genuine permit. Callback exit deletes it. No SDK endpoint or serialized
observation constructor exists.

The 30-second monotonic lifetime starts immediately after native input returns.
Resource queries use a bounded remaining timeout; deadline, upstream owner and
current scope are checked again after blocking IO. `Resources.active?/0,1`
accepts only the actual scope owner, attached worker or tracked task/effect while
the scope remains open and its owner is alive. A standalone review has no bound
scope. After consumption, only `:ok` or `{:ok, value}` can succeed. Errors, other
returns, exceptions or observed loss remain unconfirmed. A new effect attempt
requires inspection and fresh review, never automatic replay.

The resulting internal `native_review` receipt binds command, event, display,
challenge, input, observation time and facts digest. It supplies neither source
truth, current storage authority, an effect permission nor human identity. An
automated PTY uses the same native channel. It is not a SourceIndex proof or the
stored `native_management` capsule. Trusted Core/cooperative storage remains the
boundary; hostile BEAM code is outside this primitive's claim. A Session adapter
must still journal intent before effects.

## Independent findings and repair

The first candidate passed its maintained tests but the independent auditor
found two actionable P2 defects:

1. A real suspended Resources server demonstrated that checking time and owner
   only before its blocking activity RPC allowed consumption or final success
   after deadline/upstream loss. The post-input RPC also preceded creation of
   the lease, permitting an expired observation to start a new lifetime.
2. A returned error after consumption was forwarded as a known error, even
   though the primitive could not prove that the callback had made no effect.

The repair fixes the lease epoch before the post-input query, bounds each query
by the remaining lease, repeats liveness checks afterward and withholds every
consumed result outside the success whitelist. The original independent strict
controls passed **2/7** before repair and **7/7** after; a stronger companion also
passed **7/7** afterward. The original failure inputs/logs remain preserved.

Maintained controls now include actual suspended-Resources races at consumption
and completion for both owner loss and exact expiry, and a post-input observation
epoch regression. Native scope-loss uses a positive `:ok` callback marker so
the success whitelist cannot independently mask that liveness assertion.

## Executed verification

The final focused graph is `/tmp/ipse-native-review-final-20261027-02`.
Seed `20261203`, maximum cases one: **30 tests passed in 5.7 seconds**:

- Fourteen source-derived simulated-native-IO/clock permit tests with actual
  Resources processes. These establish state behavior, not terminal provenance.
- Nine existing Resources, one resource-authority and two native-protocol tests.
- Four actual-native tests using separately compiled Rust PTY drivers and the
  private native helper: five command verbs, cancellation/stale challenge,
  changed facts, callback failure, scope loss, cross-task/forged/replayed permits
  and pipe refusal. No Collection publication or model inference occurs.

All **2,344** regular project/build inputs remain exact before/after the combined
run. The manifest excludes Git metadata and the declared Mix execution cache.
SHA-256: `06e15e3aadee010e6875625c182b4c8f3dd38ba4f1b334e93274b9963d191c06`.
The final graph copies unchanged runtime BEAMs compiled in
`/tmp/ipse-native-review-repair-7fecc21a78041bc2`; compiler origins remain there.
That repaired graph force-compiled **131 source files** with warnings as errors,
bound five runtime modules to its exact private sources/BEAMs, and selected helper
`d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.
The shared checkout helper was never rebuilt or executed for these checks.

Final Runtime source hashes:

| Source | SHA-256 |
| --- | --- |
| `runner/review.ex` | `c53e1aa81801b8988affd1d31faa1e93ddd1585b9f12ab6f9ff3fb17d58801fc` |
| `session/resources.ex` | `adc1a81af0f837daaeec1e675d9b090cd3ee67252e40ed3fe77bc566d86b1bb2` |

Actual Elixir **1.18.5**, host OTP **29**, compiled the same two production
sources/four modules with empty diagnostics. All five final Elixir source/test
files passed formatting under both 1.18.5 and 1.20.4. ExUnit ran on 1.20.4;
there is no 1.18 ExUnit or OTP-27 execution claim. Rust fixture compilation used
explicit edition 2021 with warnings denied. Host evidence is Linux only.

The whole developer source chapter and operator knowledge-permissions/memory
chapters were reviewed. The three complete developer Elixir examples ran
unchanged: actual native review, an account-free synthetic Session's attributed
source read/quote, and the dependent SDK proof example. The chapter integrates
review before reading and separates historical source attribution from fresh
effect-specific authority. No operator management workflow is advertised.

## Retained diagnostics

Earlier owner graphs retain three test-fixture corrections: a source-derived
Inspect assertion could not install a new implementation after protocol
consolidation; JSON escaped-control hex case differed; and a single maximum-size
string violated the existing eight-KiB string limit. Final tests check the actual
production Inspect implementation, case-insensitive escaped hex and two strings
whose complete object is exactly 16 KiB. No production guard was weakened.

The live graph retains an initial Rust default-edition warning failure and an
initial extra-EOF-newline formatter failure, with original files/logs. Explicit
edition 2021 and the actual Mix formatter corrected the harness. The manual
extraction harness first expected two snippets instead of three, then incorrectly
matched `File.rm_rf!` as a tuple; both failed drivers/logs remain, followed by
the successful unchanged three-example run. The independent original diagnostic
using an arbitrary success atom is separately retained; its final RPC wait no
longer applies under the repaired whitelist. Strict `:ok` controls isolate the
actual liveness repair.

These component passes do not replace the final current-tree full build/test,
package/install, platform, model quality, sustainable managed-store or whole
post-implementation audit gates.
