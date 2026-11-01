# Retained native stdin through the existing transaction owner

Dated **2026-10-31–2026-11-01**, based on `8c9bfcf` plus the inventoried increment below.
This is component evidence and an implementation handoff, not milestone or
managed SDK delivery acceptance. Current procedures belong to
[Session sources](../../developer/session-sources.md),
[verification](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols)
and the [native protocol](../../../native/README.md#direct-stdio-server-transport).
The [plan](../../plan.md) remains the acceptance ledger.

## Implementation boundary

The actual stdio supervisor lends its existing child-stdin write description to
the existing protected transaction controller. It pauses ordinary writes from
reservation through confirmed settlement. No separate output process, inherited
test destination, fabricated completion witness or terminal mode supplies delivery.
The existing authenticated descriptor transfer and C/F/G close protocol are reused.
The pipe class is checked separately from regular source/flock descriptions.

Before transfer, both peers bind the exact operation and original wall expiry.
The supervisor and importer retain fixed monotonic cutoffs without renewal.
The importer requires three held kernel locks, Writer and Session controls, and
at least one retained source. Its one-use write checks all of those owners and
the pipe supervisor before each nonblocking chunk and after completion. The
ceiling is the existing 32-KiB worker JSON allowance plus its four-byte prefix;
this does not increase the worker JSON limit. The pipe must close and settle
before other transaction operations or ordinary stdin can resume. Reused
operations and concurrent ordinary input stop the supervisor's actual group.

These are trusted-host OS primitives. Three generic locks do not establish
Identity/Consent/Collection semantics, a dependency union or effect permission.
No Session/frame ticket or public worker continuation is wired in this increment.
Existing runtime gates remain. A failed final check or partial write is unknown;
the native checks are final admission, not a kernel-atomic expiry guarantee.

## Actual component controls and earlier outcomes

The test uses real native helpers, authenticated pipe transfer and kernel locks,
with explicitly synthetic lock contents and standalone owner controls. It does
not manufacture a valid policy or original Session proof. A maximum-sized binary
frame must arrive exactly once; ordinary stdin must work again after both close
acknowledgements. Wrong operation/expiry, duplicate input, missing owners,
concurrent ordinary input, elapsed admission and pre-write owner loss have
separate controls.

The small Rust child fixes actual Linux pipe capacity to 4096 bytes, records its
first 4096-byte read and then stops reading. A coordinator invalidates the Session
control, source owner or supervisor only after that physical partial read. The
writer must return unknown, deliver no complete-frame receipt and lose its
capability. Already admitted pipe bytes are not rolled back or replayed.

Earlier logs are retained rather than replaced:

- The first cohort passed 1/7: the new native receipts were absent from the host
  parser's allowlist. The second passed 3/7: the second native frame-size check
  still rejected a maximum frame, and a direct controller call left a stale
  caller-side capability cache whose first lookup correctly returned unavailable.
  Both native size checks now use one predicate; tests retain the unavailable
  result before the subsequent invalid-capability refusal.
- The third passed 7/8: the synthetic source exporter was settled with a different
  deadline. Its existing exact-deadline rule was preserved and the fixture fixed.
  The fourth passed 8/8 at the earlier 32-KiB raw-frame ceiling.
- The later operation-bound cohort passed 11/12. Its pre-write source test killed
  a BEAM actor and asserted zero bytes without observing actual native owner exit.
  The counterexample delivered its synthetic bytes and retained an unknown result.
  That log does not identify the exact native/BEAM interleaving or prove a native
  owner check was bypassed. The corrected zero-byte control waits for native
  exit; the distinct partial-delivery cases deliberately preserve uncertainty.
  This exploratory run also overlapped the tail of a build and is not acceptance.
- A subsequent serialized cohort passed 12/12 at the earlier raw ceiling.
  The final cohort below additionally exercises the full existing prefixed-frame
  bound. Earlier passes are not silently relabelled as that later qualification.

The initial Mix attempt was refused by the socket-restricted sandbox before
tests; the permitted focused current-decision control passed one test with 139
excluded. No sandbox, TLS, approval, source, policy or deadline check was weakened.

## Final verification and limits

The final fixed-runtime Runner/Worker and genuine Session lifecycle cohort
passed **158 tests**, with **8 skipped** and **27 excluded**, in **308.0 seconds**
(max_cases 1, seed 20261031). It includes all 17 genuine lifecycle top-level
cases and the 12 pipe controls before the last test-only cleanup assertions.
The final isolated pipe cohort additionally
requires each partial-write loss result before its original expiry and passed
**12 tests in 1.7 seconds**. Separate existing Session-control checks passed
**2 tests in 0.1 seconds**; genuine managed approval passed **11 tests in
128.3 seconds**, with 12 excluded. These are distinct cohorts, not a new whole
suite aggregate.
The subsequent explicit supervisor-close and native-source-exit cleanup checks
passed **12 tests in 1.6 seconds**, using the final inventoried test source.

The native helper unit run passed **81 tests**, with
**2 ignored**, serially in **11.12 seconds**. Strict native compilation used
`rustc --edition=2021 --test -D warnings native/ipse-runner.rs`.
The complete production native entry was also compiled with `-D warnings`.
The host was Linux `7.2.11-arch1-1` x86_64, Rust 1.99.1, Elixir 1.20.4 and
Erlang/OTP 29 (ERTS 17.1). This is no installed Arch or macOS qualification.
Formatting, strict Elixir compilation, credential-free demo and CI policy passed.
The initial documentation check passed with 996 Markdown files, 8281 links and
zero errors; the final check includes **997 Markdown files and 8287 links**, with
zero errors. Private-directory
access warnings remain unrelated and were not bypassed. Relevant developer and
operator chapters were reviewed whole; operator procedures and authority remain
unchanged. Native protocol prose now also distinguishes the existing clock-only
`D` frame from retained-descriptor delivery.

The initial parser-free package build completed but began before the final host
documentation/platform adapter edits; its preserved archive is exploratory and
does not qualify the final candidate. Parser-free packaging proves no PDF parser
or parser-enabled release. No remote release is published by these checks.

After committing and pushing **`bb333b4`**, a clean tracked worktree completed
`./dev/build.sh` (182 host modules and the three inert bundles), then
`IPSE_BUILD_PDF=0 ./dev/package.sh`. The archive's documentation check reported
52 documents, zero missing local targets and source reference
`bb333b49398d021113341047b9e5efee73ab892b`.
`elixir dev/verify.exs installed package` passed for that exact archive and
`examples/memory-corpus.json`. Its receipt confirms unchanged inventories,
private homes, a precompiled harness and no system development toolchain on the
runtime PATH. The standalone CLI/help/demo, workspace, ownership/idle-resume,
bundled extension and synthetic explicit-Memory checks passed. Memory's 100
records/100 queries are exact-token fixtures, not P31 semantic quality.

The committed archive SHA256 is
`e0cf540983f7ac2d009b0f0bd066ffa814bb13e71a9983b4a8ea8d1ecb076c94`.
The rebuilt helper still matches the inventoried qualification bytes. This
generic installed proof does not exercise an installed managed Worker route;
that route is still absent. It proves no PDF parser or full notes journey.

No live inference or model download ran. Charged allowances remain ChatGPT
238/300 and local 4/1000. Dependencies and external-service selection are unchanged.
The latest completed whole-source result remains the negative `e86b1b8` run:
3538 passed, 60 failed, 109 skipped and 112 excluded, with its original caveats.
Focused passes cannot change that aggregate. Full P30/P31, actual managed Worker
adoption, installed domain journeys, independent quality/audit and reviewer
handoff remain open.

## Next actual integration

Bind a real pending Worker request to its protocol sequence, exact encoded frame,
artifact/native Port, parent/action result and complete Session-owned dependency
union. Derive current authority under the existing managed-owner scope; extend
the typed Session/Writer handoff for this purpose, including headless saved
consent without a fabricated terminal channel. Reuse `Runner.SessionSource`
orchestration for the original flock and inactive source groups. Settle the pipe
and every source/control before Writer thaw; release policy locks before waiting
for worker computation. Buffer any early worker response until that settlement.
Unknown delivery must close the worker, retain liability and never replay.

The supervisor currently retains 256 used handoff IDs. That component limit is
not a qualification of every SDK lifecycle: existing mixed-read invocations and
4-MiB paged output can require more frames. Resolve this bound against the actual
Worker sequence and existing traffic/action ceilings before opening that route;
do not silently reduce required positive coverage. Accepted-decision management
journals remain a separate additional-owner requirement.

## Source, helper and available receipt inventory

The inventory below records the actual source, helper and available logs.
The post-commit archive and receipts are included at the end.

| Path | SHA256 |
| --- | --- |
| `lib/ipse/runner.ex` | `377c2f0bcbaa035c3efe9f025431f65e16d24c5748644650b011f0b098dd93e1` |
| `lib/ipse/runner/transaction.ex` | `9dd311208344a93c2bf4da06350a84129c6a23e4bd06c2adb160953ec185c5cc` |
| `native/ipse-lease-sink.rs` | `af5b13d46dd6486f54d8c752f08a2e9e4443f279acbb7f00544213cd0df14e6a` |
| `native/ipse-lease-transfer.rs` | `c4896faa2d23f59f0be1c5d2e2ddb0c832896d308a67e85f98d1db1c615513e3` |
| `native/ipse-stdio.rs` | `276b0ad0da59fc6e47120db10a0133bc66416cf3a2943faffe7cd31386336a94` |
| `native/ipse-transaction.rs` | `5737eb4803acb27a96a0c644de558f413a9c85d09a37645116a5090716f8ad8c` |
| `test/ipse/runner/transaction_pipe_test.exs` | `ecd608316ed501ad73b47b847714789ae3b052bcac5af7a8b2abdbfb4ade38cc` |
| `test/support/stdin_backpressure.rs` | `51e7cf702ec120f55de3e340de28d3f97250c66f0ff7dc2a95567c19caf99c96` |
| `native/README.md` | `2c08e16ec723aa254c367cdc9c08cd2c14436e9b67c7b9e58e49bccdf4db86ed` |
| `docs/developer/session-sources.md` | `92f2b39a24d1beba85ee102e076c7c099bca102dbe197e8099315de90335d205` |
| `docs/developer/testing.md` | `8d360576034430db49fec6cba80469a6e8463ab2fdbfdc3a4d03ab46be110bb3` |
| `docs/operator/knowledge-permissions.md` | `b92e571d999c221422c007708a7cd3b1086a0f6b2b678d664688c5be394de984` |
| `docs/operator/recovery.md` | `8c087c2faa925f83a907f9a6dcfc45831edada0dbca924aa3a0676e4cc6f595d` |
| `mix.exs` | `bbfc4737b2332df7b946db4e084bf971c287a21f1a69dd67595c6c544b803257` |
| `mix.lock` | `c6be0ff68446834973ed443028e318f86782ee9f6061b9fd911da419184f86c0` |
| `docs/developer/dependencies.md` | `2d91c8d36991216522b06e7f2e28c802ceac32256e42a7cccc1c9ce8d6094cec` |
| `priv/ipse-runner` | `8b44d7e2017d50a7d700ef14fdb8d1cfc9f8e35838cc788a5eea31b59fb505b7` |
| `/tmp/ipse-managed-current-decision-triage-20261031.log` | `bee3aa811f64bd5e0ff083931af16ea506933a6323bf6fda228a545009b6ead0` |
| `/tmp/ipse-worker-pipe-compile-first-20261031.log` | `9ef6b07ce985b2f322f9bf76bc1f755dd88c1e7a59a7a037553028ce7138fd17` |
| `/tmp/ipse-worker-pipe-build-first-20261031.log` | `a0eff3c19d9277349a00d3eddeda5ddb40db9a4712659add05715a7d840d5e2d` |
| `/tmp/ipse-worker-pipe-build-second-20261031.log` | `4f8c7090628cb7814c8240b72328dc47324d24587891070043afba894c4348f0` |
| `/tmp/ipse-worker-pipe-build-third-20261031.log` | `20d59fb92cf46f035d11740219ede16f4c6e6daa02bfbcde9acaba970a30b262` |
| `/tmp/ipse-worker-pipe-build-final-20261031.log` | `d418fc2af650158b94ac8dd99a528de3227edcdd6b357ec4dd25117b4e3a50d9` |
| `/tmp/ipse-worker-pipe-component-first-20261031.log` | `17f7ed0e1c3bf5330a84e6c9c0192e7e6c32ff746636c8083d972156f88da6d7` |
| `/tmp/ipse-worker-pipe-component-second-20261031.log` | `c12e02f154b204c27b6f94407a20598cf2747d85c77bfb9638ac16995d6badf3` |
| `/tmp/ipse-worker-pipe-component-third-20261031.log` | `dc6399174b26d6490a8fa2c1e01f3a00e4781090439cbf4edeb90d3c213b96d6` |
| `/tmp/ipse-worker-pipe-component-fourth-20261031.log` | `654d38e2443879cf0b2ed6122b60e0c926bc5136d54d03f869610ec0ba3d3262` |
| `/tmp/ipse-worker-pipe-component-bound-20261031.log` | `c1cf2150a5760e877ce32185be6392cfe9c2d5bf418fb99f41d682581821c4e8` |
| `/tmp/ipse-worker-pipe-component-qualified-20261031.log` | `c9fca5cd34dcd19f7d0da7b4c5306a1738230eb743ece5b8535446b49e162b21` |
| `/tmp/ipse-worker-pipe-component-final-qualified-20261031.log` | `4fb6430d038a6d4989a102a616a44917f746f31df8efdbbecbd1b67177dbe771` |
| `/tmp/ipse-worker-pipe-component-owned-cleanup-qualified-20261101.log` | `c9fca5cd34dcd19f7d0da7b4c5306a1738230eb743ece5b8535446b49e162b21` |
| `/tmp/ipse-worker-pipe-native-tests-20261031.log` | `d62659097ae1d0efd6613a41aa3f7a243a4d4798509560eca5cdbd38bcb5f13a` |
| `/tmp/ipse-worker-pipe-native-strict-qualified-20261031.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-worker-pipe-format-compile-final-20261031.log` | `04ef88419ce6ce50a26912ead3ba4b6051d2641f5e68b0abcd9b8f55c85b2338` |
| `/tmp/ipse-worker-pipe-regression-qualified-20261031.log` | `636f6e5b8fd241373ba1b3426268eae17ca2a7e91ac598e1e650d1ecd14a5eaa` |
| `/tmp/ipse-worker-pipe-session-controls-qualified-20261031.log` | `7f31b81eeed12ba8bd441a87253e240f0a108e9e11cb2cab5f0961d9104c1cca` |
| `/tmp/ipse-worker-pipe-approval-qualified-20261031.log` | `885456dc6f7f56c9f1abcaa9c66dae4e708b6606b9868081f4f2fd20ce3f9dfe` |
| `/tmp/ipse-worker-pipe-demo-qualified-20261031.log` | `1572354765d026316354d3c37c8902756123fd6e2e94a11959ef7391b71f5c6f` |
| `/tmp/ipse-worker-pipe-ci-qualified-20261031.log` | `e856938f2d4ee3eb319a90056aca83ff6b7347ea57ff71bac975f84df18ae633` |
| `/tmp/ipse-worker-pipe-docs-first-20261031.log` | `50fe642a3f73452a45e5983b8b08388b2cd4a13cf117da803b2d6dd442f1b06d` |
| `/tmp/ipse-worker-pipe-package-20261031.log` | `ac22a10854e416207d03c8a2f9d1269ba8ced6a6c172deb1c6b7de49884ed952` |
| `/tmp/ipse-worker-pipe-package-first-20261031.tar.gz` | `6944ace86d84b8da65af84f984f5ad1b0cdc33745bc346931e7acdf22cac48e2` |
| `/tmp/ipse-worker-pipe-docs-final-20261101.log` | `565dfd68f2892e4082512bde8abe4e4e0ab7526719a943c902248c5ebecc60e0` |
| `/tmp/ipse-worker-pipe-committed-build-20261101.log` | `0e9bc50ef3e705cc9360df1f026b5d2cd744f282d376f73dea05b20c6e058d56` |
| `/tmp/ipse-worker-pipe-package-committed-20261101.log` | `ecb958c1ea4a40ce4c94fa3fe9ee7b1e10c07b8567aac790f93bc58a36a120ff` |
| `/tmp/ipse-worker-pipe-installed-package-20261101.log` | `248aacc92fdb6430b910ba523cc35ad2744283356829337726446b421a614e4f` |
| `/tmp/ipse-worker-pipe-bb333b4-package-20261101.tar.gz` | `e0cf540983f7ac2d009b0f0bd066ffa814bb13e71a9983b4a8ea8d1ecb076c94` |
