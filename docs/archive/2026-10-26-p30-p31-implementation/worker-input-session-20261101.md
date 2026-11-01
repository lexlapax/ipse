# Bind actual managed export inputs to Session and native owners

Dated **2026-11-01**, based on `28faa71` plus the source inventory below.
This is historical engineering evidence for the Session adoption of the
[sealed Worker frame](worker-input-frame-20261101.md), not P30/P31 acceptance.
Current contracts belong to [Session sources](../../developer/session-sources.md#deliver-a-managed-export-input-under-its-original-owners),
[invocations](../../developer/extension-invocations.md) and
[testing](../../developer/testing.md#exercise-actual-os-policy-and-native-protocols).
The [plan](../../plan.md) owns remaining scope.

The later [accepted-input increment](accepted-worker-input-20261101.md) supersedes
this record's then-unavailable version-6 Worker route and retains the earlier
source/package results and limits below.

## Actual delivery and recovery boundary

Host's protected export route now calls `Session.WorkerInput` for initial export
requests, committed host-action continuations and output-page requests. Session
independently reconstructs the actual request, active parent and complete
inherited-plus-explicit dependency union. The actual tracked publisher prepares
the existing immutable Worker frame under its original callback timer; Session
queries that binding and journals an input intent before native delivery.

The current source/policy scope transfers consuming Session flock, Session and
Writer controls and every inactive original source group into the same native
transaction that receives actual Worker stdin. Active proofs bind to the drained
Writer snapshot. Every scope must settle before Session records delivery and
the original publisher awaits buffered compute outside policy locks. The Rust
transport and helper are unchanged from `5ecb411`; there is no second writer,
synthetic terminal, automatic approval or new dependency.

The existing narrow own-write metadata transition is shared with model lineage.
It requires the complete authenticated v3 root-only causal write union, a known
successful own capture and the exact adjacent successor inspection. A typed
input transition binds the original intent and unchanged deadline. Original
payloads, dependency objects and historical records remain intact; only their
authenticated root mapping changes the fresh guard view. Record-bearing,
mixed, scan and unclassified dependencies cannot use that transition.

Saved reconstructs the exact parent/action/page relation and hashes using the
ordinary encoders. Tampered bindings refuse. An interrupted input becomes unknown
with unavailable lineage, without reconstructing a handle or repeating bytes.
Actual confirmed close and idle resume leave the worker callback trace unchanged.

## Failures retained and concrete repairs

Initial paged delivery failed before preparation because Worker called the
Session-owner-only resource query. The repair adds a narrow peer query available
only to the actual registered extension resource, for its exact task and live
tracked effect; foreign callers remain denied. The subsequent successful physical
output exposed replay's rejection of the new record family. Explicit closed
record admission and chronological causal validation fixed that failure.

Genuine capture then failed on its own advanced root. Reusing the authenticated
own-write transition restored that allowed path without dropping old dependencies.
One transient run with a temporary tag-only observer passed; the observer was
removed, and no causal explanation is inferred from that pass. A concrete timing
defect was separately fixed: the native wall cutoff is clamped to the original
journaled intent deadline as well as Worker and policy cutoffs.

The first broad integration run passed 165 of 166 tests, with one failure,
8 skipped and 27 excluded in 349.0 seconds. Its publication interposer had begun
intercepting earlier shared Worker-source acquisition before its publication
watcher existed. It also exposed a nullable operand in production poisoning;
that predicate now defaults to literal false. The fixture hooks the actual
supersession callback under its held owners. Its original storage/unknown/no-replay
assertions remain. The repaired isolated case passed in 16.8 seconds.

The expanded qualified run passed 246 of 247 tests, with one failure, 8 skipped
and 27 excluded in 378.0 seconds. Only the pipe test's cleanup observer failed
on an unspecified procfs read error after its zero-byte ownership-loss assertions.
The shared observer now retries read errors within the same original deadline;
only a later absent process or observed exited state proves exit. A persistent
error fails with its reason. No particular original errno or race cause is claimed.
The repaired 13-test pipe cohort passed in 1.5 seconds.

The genuine record-content fixture required three further observer corrections:
it selects the exact committed note/proof rather than assuming the first note's
category; it distinguishes the native stdio supervisor from the importing
transaction; and it collects the inspection task result after the terminal loop
instead of losing that result to the loop's message handling. All intermediate
failed logs are retained. The fourth run passed in 17.3 seconds.

## Evidence scope

The genuine approval journey uses actual native reviewed sources, committed
record content and an original inactive Session, with registered synthetic
loopback-model adapters. A disclosed one-use BEAM controller pause inspects the
actual importer before its unchanged native write. Its descriptor set includes
three policy locks, consuming and original Session flocks, Session/Writer controls
and actual Worker stdin in that same kernel process; the original flock remains
busy. This is source-level Linux evidence with instrumented observation, not an
independent human, live-model, installed-domain or macOS result.

The paged positive reads root metadata, not record contents. A separate
permission-withdrawal control changes permission after a committed snapshot and
before the next Worker frame: the VM callback canary does not run again, Saved
retains uncertainty, and idle resume sends nothing. Pure replay tamper controls
cover parent, action, payload, frame, dependency and root-transition bindings.

Before the final combined run, invocation compatibility passed 63 tests in
32.5 seconds; genuine managed approval passed 11 tests, with 12 excluded, in
158.6 seconds; input-boundary controls passed 2 tests, with 139 excluded, in
9.6 seconds. These are separate cohorts, not a whole-suite aggregate.

The original full-suite `e86b1b8` result remains 3538 passed, 60 failed, 109 skipped
and 112 excluded in 5751 seconds. Focused passes do not revise that verdict.
No inference, model download or account use occurred in this increment. Finite
allowances remain ChatGPT 238/300 charged and local inference 4/1000 charged.

## Remaining authority and qualification

Dependency versions 3–5 are supported by this export adapter. Accepted-decision
v6 inputs refuse until their original management-journal owners reach the same
native sink with original sources and consuming Session controls. Transform,
event and nested-service Worker entry points remain outside this adapter.
Managed nested tool/MCP result delivery retains its separate refusal gate.
Complete inherited stale-A/fresh-B frame cases, tight result-journal reservation
accounting, integrated capacity/turnover, document producer qualification, P30
consumers, independent frozen quality, installed domain journeys, adversarial
audit and full reviewer handoff remain open. This increment closes no milestone.

## Fixed-source verification and inventory

The fixed-source serial regression passed **247 tests**, with **8 skipped and
27 excluded**, in **369.2 seconds** (max_cases 1, seed 20261101). Separate native
Session controls passed **2 tests in 0.1 seconds**. The serialized Rust program
passed **81 tests, with 2 ignored and zero failed**. Formatting, strict compilation,
CI policy and the isolated-home credential-free demo passed. The documentation
checker examined **999 Markdown files and 8303 local links, zero errors** before
this inventory; private-directory permission warnings were retained without
inspecting those directories. Relevant whole manuals and their entry points were
reviewed and reconciled with current behavior, including accepted-decision refusal.

Source/helper bytes:

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `lib/ipse/extension/actions.ex` | 53945 | `a0672919e5385e90e0a43ba4b5e0d1a0457f7d3a93fcef619dc0b75458ae159c` |
| `lib/ipse/extension/host.ex` | 32834 | `044844d33a471446dde6e17ac12a5e7ddb49d4ca4ab53349cba439e4baac889e` |
| `lib/ipse/extension/invocation.ex` | 28673 | `94e9407ebb96bebfc35e4e9fc80bc435331e71d7857a7caa4f45c58c9ee93fb8` |
| `lib/ipse/extension/result_source.ex` | 32409 | `1f4c4b7f24c20d4a1a4b33f3de2ef9f659a9fa9ac374a24ad3bbafd9900a13f9` |
| `lib/ipse/extension/worker.ex` | 27257 | `a2f0e58eb0d8b6734532dc6894e3b30f4b1ab022e35da36629f473ee2405d514` |
| `lib/ipse/runner/session_source.ex` | 7622 | `6e09ad530049dfdea3e210026286866fd150b38a0489d2250ed5bda26bd4317e` |
| `lib/ipse/session.ex` | 270967 | `d972d00968f332e9e62cc2e54c7ec44db35403e948a2d0bcf21dd5bdb34f5944` |
| `lib/ipse/session/invocation.ex` | 66406 | `8daa40f2f8cf46297883d508d8d6deab81d5806b54238f809f719a6312341ccf` |
| `lib/ipse/session/managed_lineage.ex` | 57865 | `3f0be46e86a9d3687528c1d691ff8d702ad23b6ef3687b89e59abe10fd47a5d8` |
| `lib/ipse/session/managed_output.ex` | 20221 | `2cdbf0d06584a41a8e4b4e2b991707c6f36f190d7f41f3588eaa429794d29793` |
| `lib/ipse/session/managed_reference.ex` | 42623 | `5b43b5224124c7f694c30606581276ea355c6c6b64a17b4301a2a0e7979decab` |
| `lib/ipse/session/managed_tool_use.ex` | 49470 | `774166aabc1e9231d9f381df42141d0fcb5343065b9b9b56cf6ae4b090115f2a` |
| `lib/ipse/session/resources.ex` | 39970 | `34c3091ec422ae69544140b528c4942844bcfe6f078df661a3c9115e8753e252` |
| `lib/ipse/session/saved.ex` | 40413 | `5562c384ea9ea78f88a99021c75f8921a38095fca697625e2b63e9c680c4b13c` |
| `test/ipse/extension/managed_collection_call_session_test.exs` | 279176 | `f011590cacd8823221f26015f69dda5af2e293c1e42f22aca4adf4382469f371` |
| `test/ipse/extension/worker_test.exs` | 22424 | `7c78eea21a6418bcf7dc5f68d01f6386f7385d19bbf56c85bda24b19566c3bed` |
| `test/ipse/runner/transaction_pipe_test.exs` | 10708 | `4065c608d1c2f292ae72c718bd18daa8e49d0a23b8d413a29e23bcba1e5cd9b8` |
| `test/support/managed_approval_session.exs` | 15786 | `2d81fc0d99cc96790c82d1b0bf0c93bad3d5a0e1348d403589a30eea8957292a` |
| `test/support/managed_supersession_session.exs` | 32665 | `f176789f7a049c8007f937ef490b5d5b2234fdf04501fe96a4a2de27d74cb086` |
| `test/support/managed_supersession_unknown.exs` | 11377 | `b5e25d8557a80ab9426af9a6f8b6b9cc519773aadba888c747ea8aca520017f8` |
| `test/support/native_pipe_scope.exs` | 6677 | `1d91f39b8fd3e1b4a33415db7f7ce1d118fe9c534ec4f878b2892b4314be71be` |
| `lib/ipse/session/worker_input.ex` | 19522 | `8f5253e99825244824d3fdf0a528a35043a001600b67ddfb858d2eca26e2b848` |
| `priv/ipse-runner` | 969344 | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |

Successful and failed evidence remain separate at these exact local paths:

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `/tmp/ipse-worker-input-session-paged-first-20261101.log` | 1363 | `0758a7a3bfcd95d126565944112988cc1a1129f77d0113e3d2750cc383a02d68` |
| `/tmp/ipse-worker-input-session-paged-diagnostic-20261101.log` | 1514 | `a990545066dc53e48cb31a395b48899047826d9884fd8d58d66f5afe7d21252d` |
| `/tmp/ipse-worker-input-resource-component-first-20261101.log` | 292 | `2af6cbdcda138886395412de32fd33e9ebf882d93f7b386fb9b7585d99ae33c8` |
| `/tmp/ipse-worker-input-session-paged-resource-fixed-20261101.log` | 778 | `21a9ac4f4f83c2e3f8a5d8267a33d6be48591ae93d457329493fae25b9dc066b` |
| `/tmp/ipse-worker-input-session-replay-compile-20261101.log` | 551 | `d5da7cdedb4dd9626c7c8480b85471aea35970dc1cb1a51b8931959d05a83715` |
| `/tmp/ipse-worker-input-session-paged-replay-first-20261101.log` | 363 | `6652663466438bc259c1f880965f666833cb83927b5783b80f4f03e30a192f5b` |
| `/tmp/ipse-worker-input-genuine-current-first-20261101.log` | 36286 | `4f5ca370565b9a0a690385e162fe19d3b83165f76e67c59f7d76ae3600f757d5` |
| `/tmp/ipse-worker-input-genuine-current-root-transition-20261101.log` | 426 | `ce1f72179f2b1b4998a23dfa635e21aebc5b93c26c7be85cda6f9eff55111d06` |
| `/tmp/ipse-worker-input-genuine-current-root-bound-20261101.log` | 36305 | `6be93569e3304a33490a285493a6a7a4fc80ebc73894af8ef3f260f00b4ae652` |
| `/tmp/ipse-worker-input-session-regression-first-20261101.log` | 37229 | `d4dec7a280bbc471988b5a507592cd367f15d023c69fbcebe1400363d7baff29` |
| `/tmp/ipse-worker-input-genuine-effect-loss-repaired-20261101.log` | 521 | `f4825606f8b17d38bb1277460c63c36b0ecd2fc6e3acdfd497f49a9a486b1b2f` |
| `/tmp/ipse-worker-input-genuine-source-owners-first-20261101.log` | 55996 | `505484b4883b6d89f469de642f228a774c651c945a2417c2a5a5a661dd415b9d` |
| `/tmp/ipse-worker-input-genuine-source-owners-second-20261101.log` | 52053 | `a6cc5d40b87b5f3ed17826edc84546d95190402d06211d18e163b10d887ce192` |
| `/tmp/ipse-worker-input-genuine-source-owners-third-20261101.log` | 51704 | `844c7b3248490cc7548af04ce30abe4f4a032dafaceba077b849ccf56ed89ea5` |
| `/tmp/ipse-worker-input-genuine-source-owners-fourth-20261101.log` | 333 | `e15e03af7db742795a1b09080607e9c89a558eec62e95426733e584e5bb2d5ce` |
| `/tmp/ipse-worker-input-session-build-qualified-20261101.log` | 845 | `86badcf2cdf1a613b2f612b23d6588ab3a4ec59cfc966b6076a6a60e110edb53` |
| `/tmp/ipse-worker-input-session-regression-qualified-20261101.log` | 4958 | `9d9ec6bded1173b9451cca2eb6589e6945cdfecf189b31af42de1ccbb7b62169` |
| `/tmp/ipse-worker-input-native-cleanup-observer-20261101.log` | 262 | `c474168f508f663186cc4e5cc3bef8e27332e777ec2d15ea7650d478d3a6af74` |
| `/tmp/ipse-worker-input-invocation-compatibility-20261101.log` | 1389 | `e3eb4d64c9bd8c0d2258d7b661aef3c10fdb4fae62eb89b8dc335c3e9d13ce12` |
| `/tmp/ipse-worker-input-session-approval-qualified-20261101.log` | 327 | `f618558c0e37377c4feac20ccddb7fd688dfb4722ee7d3740e4f169fde13b5b8` |
| `/tmp/ipse-worker-input-session-boundary-qualified-20261101.log` | 312 | `e57753fd2a70c7d3de36c7f6481f3a6b024c24cc9e6babb733ecd9e45f767100` |
| `/tmp/ipse-worker-input-session-regression-final-20261101.log` | 4553 | `52796989620458cbd4597d8fb8454f8a5a1da5b585b6b09d5c9f2ec175c95091` |
| `/tmp/ipse-worker-input-session-controls-final-20261101.log` | 267 | `639cdcf5fd257dc9ae205f737d82ffa489c974f274bb9f28d575b902f0ba9c75` |
| `/tmp/ipse-worker-input-native-final-20261101.log` | 8602 | `d4d6060d425ed8e557c000d5e21505765f57d743f0097b46328f11cfcf0ea83f` |
| `/tmp/ipse-worker-input-format-final-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-worker-input-compile-final-20261101.log` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `/tmp/ipse-worker-input-ci-final-20261101.log` | 32 | `e856938f2d4ee3eb319a90056aca83ff6b7347ea57ff71bac975f84df18ae633` |
| `/tmp/ipse-worker-input-session-docs-first-20261101.log` | 756 | `ac32a32b6f5b308daf0873f9aa66a29d248a4c5623d9b045462101663d77fea0` |
| `/tmp/ipse-worker-input-session-demo-final-20261101.log` | 2720 | `e6cd4bffc2e4a3d6ae7dc39c6223ba197572d902f2fe25a9c598c56579f23718` |

Earlier component package receipts describe their original source; they do not
qualify this changed Session runtime. No moving-source package is represented as
committed qualification.

## Committed package

After committing and pushing **`3f4d9db`**, its clean tracked source completed
`./dev/build.sh` and the deliberately parser-free `IPSE_BUILD_PDF=0 ./dev/package.sh`.
The package records source `3f4d9db99e6ca4c55e9d222df75f3a6dd7c7f656`, with
52 documents and zero missing local targets. Its rebuilt native helper exactly
matches the fixed-source inventory above.

The first verifier attempt refused before startup because the retained archive
copy omitted its checksum sidecar. After generating that sidecar, the second
attempt refused the custom archive basename because it did not match the
application version. The third attempt retained the original generated basename
and matching original checksum in a dedicated directory. Its archive bytes are
identical to the first retained copy; there was no rebuild between attempts.

`elixir dev/verify.exs installed package` then passed against that exact archive
and `examples/memory-corpus.json`. It verified unchanged extracted inventories,
private homes, precompiled harness and no system development toolchain on runtime
PATH. CLI/help/demo/setup/doctor, native ownership/helpers, idle resume, ordinary
bundled behavior and Memory's synthetic 100-record/100-query, six-Session/two-project
workload passed without model dispatch. This is the generic installed baseline;
it does not exercise installed managed export-input, accepted-decision delivery,
PDF, semantic quality, independent human, macOS or publication workflows.

The two additional developer-manual descriptions of accepted reads were also
reconciled with their separate unavailable worker-delivery boundary; the artifact
above retains its exact committed documentation rather than claiming those later
editorial changes were packaged.

| Path | Bytes | SHA256 |
| --- | ---: | --- |
| `/tmp/ipse-worker-input-session-3f4d9db-package-20261101/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` | 15010939 | `ae3f16b19b85ba9d7c4f479e2c80de8abf5e1e7b52a1361da8a516b9775599da` |
| `/tmp/ipse-worker-input-session-3f4d9db-package-20261101/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz.sha256` | 108 | `22b8b31d7728d5b25ab47bbff8e0f8b63e6980a6499177088a1325d2f167316f` |
| `/tmp/ipse-worker-input-session-committed-build-20261101.log` | 845 | `405c58d85aa993d274a348d68b45dfca2d93a6b18ea486a354c5401405669061` |
| `/tmp/ipse-worker-input-session-package-committed-20261101.log` | 1476 | `17dc587d51985ffc47fe630f421271ae732183b58f149ffb1a85c7e3101f3ce2` |
| `/tmp/ipse-worker-input-session-installed-package-20261101.log` | 307 | `571c64a55f12a541d6c73e83c336cbbe664a1a90c54adc4cae35681396a85385` |
| `/tmp/ipse-worker-input-session-installed-package-second-20261101.log` | 751 | `b0400fb45bcc1f88c7976c60b909b85b12c29b3ec8b07298eb335591c15906bc` |
| `/tmp/ipse-worker-input-session-installed-package-third-20261101.log` | 2879 | `afba86c8f86ff487504a38fd6ad483afdb80a1c0e49b224f2f8e79fec39be718` |
