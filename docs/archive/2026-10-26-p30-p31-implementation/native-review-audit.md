# Independent native-review audit and closure

Dated **2026-10-27**. This independent review follows the
[NativeReview component](native-review-component.md). The reviewer did not author
or repair its product code. During execution they changed no public runtime,
test or helper and staged no Git paths. The [source chapter](../../developer/session-sources.md#bind-a-new-terminal-choice-to-revalidated-facts)
owns current API guidance; the [plan](../../plan.md) owns acceptance.

The two reproduced P2 findings are **closed for the exact repaired runtime below**.
No additional actionable product defect was identified in this scoped review.
This is neither a shipped management workflow nor whole P30/P31 acceptance.

## Findings and observed repairs

| Finding | Trigger and original result | Required result and repair |
| --- | --- | --- |
| P2: liveness checks became stale during blocking activity calls | Original `review.ex:140–143` checked deadline/upstream before `Resources.active?`. A real suspended scope delayed its reply until exclusive expiry or upstream death; consumption still returned a receipt, and final completion could still succeed. Original `enter` also created its deadline after post-input validation, extending the observation lifetime. | Capture the fixed observation deadline immediately after native return, bound resource calls by remaining lease, and recheck deadline/upstream/scope after the RPC. Expired consumption refuses; final success is withheld; delayed validation cannot renew a lease. |
| P2: a consumed callback's returned error appeared known | Original `review.ex:115–116` forwarded `{:error, :synthetic_after_effect}` after consumption, although an effect could already have happened. | After consumption only `:ok` or `{:ok, value}` may succeed. Other returns, errors, exceptions or observed loss remain unknown. Explicit errors before consumption grant nothing. |

The probes replace only native IO and monotonic time in a renamed copy of exact
production source. Scope ownership, suspension, call queueing and owner death use
real `Resources` processes. These state-machine probes supply no terminal-origin
evidence. Separate actual-native controls verify the protected v2 channel.

## Exact source and runtime

The original owner graph was frozen before independent copying into
`/tmp/ipse-independent-native-review-20261027-01`. Its **2,344** regular admitted
source/runtime inputs stayed unchanged. The repaired owner graph was separately
frozen before copying into independent graph `02`; all **2,344** inputs remained
exact before and after both native scopes. The declared Mix test-failure cache
is excluded. Symlink aliases are not independent regular manifest rows.

| Input | SHA-256 |
| --- | --- |
| Original Review source | `af0beb86aac52ee3df6e339ff6f613ce15ce5352bad1fc8f306c827b5439844b` |
| Original Resources source | `99c810953a45e03b1d1f163bb307c20c255745f4d8fa4ec0f40e79c071e2a73d` |
| Original 2,344-row manifest | `94cc8096180a623ed35cc8175646d64f621a2723cd1ebc15f782259d1ea35ee8` |
| Repaired Review source | `c53e1aa81801b8988affd1d31faa1e93ddd1585b9f12ab6f9ff3fb17d58801fc` |
| Repaired Resources source | `adc1a81af0f837daaeec1e675d9b090cd3ee67252e40ed3fe77bc566d86b1bb2` |
| Executed repaired Review BEAM | `3f956b7ac72f3ec384d209e697d2ed8474cffa01d65f4a7b042f796e14c45909` |
| Executed repaired Resources BEAM | `a3a7cf2a45d752914006dfefb2b33abd3610fe7460b1337fc1742ac0dc6c73a5` |
| Repaired 2,344-row manifest | `abc8c2cd6735c36fbc7ffb9857ef7bf87512b911e77fa7e75cec00f74d472707` |
| Actual private helper | `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b` |

The executed BEAMs retain their compilation origins in the owner's private repair
graph. They were copied without rebuilding, not represented as compiled from the
independent copy. No shared helper was executed or rebuilt by this audit.

## Independent execution

| Scope | Before | After |
| --- | --- | --- |
| Maintained simulated review plus actual Resources authority | 13/13; seed `20261126`, 0.2s | 14/14; seed `20261130`, 0.2s: thirteen Review tests plus one authority test |
| Exact strict seven-case driver | 2/7, five reproduced failures | 7/7; seed `20261127` |
| Stronger display companion | 2/7, same five failures | 7/7, additionally asserting escaped bidi, ordinary Unicode and complete numeric field bytes |
| Observation-epoch probe | Callback entered and consumed at its expected exclusive expiry | Refused before callback entry |
| Maintained actual-native test forms | Not independently run before repair | 4/4; seed `20261201`, 2.8s |
| Stronger actual-native closed-scope companion | Not needed to reproduce the original findings | Passed with a valid `:ok` callback marker |

The strict driver isolates consumption and final completion for both expiry and
upstream death, a returned error after consumption, ordinary valid success and
exact numeric facts refusing silent rebase. Its SHA-256 is
`fcc950696fa6c2460cb8971da0f6b4faf3b6f10de7f85cbd6935f91eb7ae3ead`;
the stronger display companion is
`e7d0946395446961d42294dc08cc279a38bf3cee27554d04c3afbd80c87c6196`.
Both exact drivers are retained before and after. The valid callback result is
`:ok`, so the new success whitelist cannot mask their liveness checks.

The actual-native tests cover five command verbs, cancelled/stale challenge,
changed facts, raised callback error, cross-task/forged/replayed permits and pipe
refusal. The terminal window was explicitly acquired and released. These are
actual protected native-v2 observations and restoration/cleanup checks, without
Collection publication, provider calls or human-attribution claims.

The original maintained `closed_scope` callback returned `:ignored`. The new
whitelist alone would make that unknown even without checking the closed scope.
The independent companion changes **only** that marker to `:ok`, outside the
admitted graph, and requires unknown after actual `Resources.finish`.
Original fixture SHA-256:
`53652c6116bcecf400a45768ea3e08c266fae2714bff78bf6bc673845ac1bbdb`;
stronger fixture SHA-256:
`e9c5b55a293022ccb29b51d0657af8a6a61f6de06044689d7bedf0a905ebb8b8`.
The owner's final maintained fixture matches that stronger companion exactly.
The original fixture, one-literal companion, driver and pass log are all retained.

Independent ExUnit execution used **Elixir 1.20.4 / OTP 29**. The owner separately
verified actual Elixir 1.18.5 source compatibility; this audit does not relabel
that as an independent 1.18 ExUnit run or an OTP-27/macOS check. Transient native
case receipts were removed by fixture cleanup; the preserved source/runtime and
pass logs support reproduction, not reopening those deleted per-case files.

## Preserve harness failures without masking findings

The first upstream probe used a relative `Code.eval_string` filename, which made
its source lookup fail. The corrected companion changes only that filename to an
absolute path. Both versions and logs remain. Renamed source-derived Permit
fixtures emit an Inspect-consolidation warning after application startup; no
provenance assertion depends on that fixture implementation. Product strict
compilation evidence is separate.

The unchanged earlier diagnostic returned an arbitrary `:callback_success` atom.
After repair it correctly demonstrates refused expired consumption, then never
queues the final scope RPC because that atom is outside the new success whitelist.
Its old helper records `release missing`. This is retained as diagnostic-marker
incompatibility, not a passing unchanged diagnostic or a product failure. The
exact strict `:ok` driver independently closes all five before-failure cases.

## Durable independent evidence

The common protected base is
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification`.

| Evidence directory | Regular files | Payload manifest / provenance / receipt SHA-256 |
| --- | --- | --- |
| `independent-native-review-before` | 2,365 | `88a5b1ef5617f0a61c962086b85039b5d5c60f32365738851a13b147eeb346da` / `9a3686e5c50b7b29b2003078cc6e113671583de04499046a52852bf1a8909aef` / `a2c70f2ae3879176817e0b742c7f2aaccd2cb2e3be9258a73c7ec5cf60a67827` |
| `independent-native-review-closure` | 2,377 | `578b79cd9ea6909b84714d76d653eee168c46f65a62d468780d94617b0fb3ff9` / `ad687164bda40491f0316d409a2f11ecac52e579eea649a16f1fee0a4af4fbe3` / `80e0095cf80ef6f02cbda5eac2ad310a120f0b836e22052e797535167e520dae` |

The full independent closure report is `working-copy/REPORT.md` in the second
directory, SHA-256
`a82a4972edd070c8d1c4aea8b6cb7c01197b67c76057a398337516dcf4e9c42a`.
Every copied source/destination length/hash and all admitted runtime rows were
checked. Directories are 0700, data files 0600; files and directories were synced.
Symlink aliases and Git metadata were explicitly omitted; regular targets and
actual helper identity remain preserved. Reproduce only in a new private working
copy, restoring executable modes and safe private aliases there. Never execute or
modify the preserved evidence in place.

## Owner component history and final evidence

The separate `native-review-owner-graphs` directory preserves **all eight** owner
roots below, including failed fixture/source variants and exact manual drivers:

| Original root under `/tmp/` | Retained purpose |
| --- | --- |
| `ipse-native-review-dfaffc6ead7983e0` | Initial Inspect fixture failure, 8/9 |
| `ipse-native-review-1abf43b0afb861d9` | Escaped-control hex expectation failure, 8/9 |
| `ipse-native-review-40fecbe9b73c59fb` | Existing single-string bound failure, 11/12 |
| `ipse-native-review-final-ea8d2735fd9f76ae` | Earlier maintained 25/25 |
| `ipse-native-review-live-a89238c549715ed6` | Original runtime, accepted P2 before state; Rust edition/format diagnostics |
| `ipse-native-review-repair-7fecc21a78041bc2` | Repaired `c53e…` / `adc1…`, strict 131 source files, 25 focused plus four native; 1.18 compatibility |
| `ipse-native-review-final-20261027-01` | Stronger maintained closed-scope fixture, four native passes; all manual extraction attempts |
| `ipse-native-review-final-20261027-02` | Final observation-epoch maintained regression, 30 combined passes |

Complete per-graph path/length/original-mode inventories represent **19,003**
regular graph rows through **3,085 full-byte blobs**. Identical bytes share a blob
only after full equality verification; no failed source variant was discarded.
All original source rows and stored blobs were rechecked after all copies.
Aliases were not followed; Git metadata/special entries are explicitly recorded
as omissions. Earlier snapshots without a historical admitted manifest are not
retroactively claimed to have been immutable at test time.

Owner-history `files.sha256`:
`c265faa87fe8a00c56d478e1d58e845eb1e70917a909b403c965f799bb96648f`;
provenance:
`a82b2f242403c68db57e746576e4747945d8f3370ce764699f74152c87dca8da`;
receipt:
`65c41a44b8c7f533fe81caf731a41aebb3c73c654f2a7ed78057a2c9b5c31e55`.
`REPRODUCTION.txt` explains verified reconstruction into a fresh private working
directory. Originals were neither changed nor chmodded.

The owner's final **30/30**, seed `20261203`, 5.7s, comprise fourteen Review,
nine Resources, one authority, two protocol and four native tests. Its 2,344-row
manifest is `06e15e3aadee010e6875625c182b4c8f3dd38ba4f1b334e93274b9963d191c06`.
Production code remains the exact repaired `c53e…` / `adc1…`. This is owner evidence,
distinct from the independently executed fourteen-test scope above.
The owner also ran all three complete developer examples unchanged. Both failed
extraction wrappers, the corrected external driver, raw logs and successful
native/Session/SDK-proof exercise remain preserved; no provider call was involved.

## Scope of closure

The whole reviewed chapter keeps fresh choice, historical source attribution,
effect permission and current storage authority separate. Trusted callers still
must release locks before terminal IO, rederive complete facts/current permission
under effect locks, consume once before an attempt, journal where required and
retain uncertain outcomes. The primitive is not hostile-BEAM containment, saved
semantic consent, a SourceIndex proof, current managed eligibility, an import or
recovery grant, a human-identity certificate or final milestone acceptance.
