# Verification and local handoff

See the [documentation map](../index.md) for ownership, [usage](../operator/usage.md)
for operation, and [troubleshooting](../operator/troubleshooting.md) for recovery.

## Documentation completion check

Before declaring any sub-goal or milestone done, edit affected developer/operator
guides as coherent documents. Rework structure and flow around their audience,
integrate new behavior into existing explanations and reconcile overlapping
guidance. Remove repetition and stale claims; separate current procedures,
proposals and dated evidence. Validate commands, examples and limitations against
implementation and actual results. Check relative file links, heading anchors
and terminology across entry points; fixture coverage is distinct from live checks.
When adding or moving a guide, update the map and all old references. Keep
operator procedures in `docs/operator/`, developer guidance in `docs/developer/`,
and superseded material in the [archive](../archive/index.md).

Documentation-only changes need relevant CLI/example and link checks, not
invented runtime tests. Report blocked external link checks accurately; an HTTP
success alone does not establish that a source supports the associated claim.
See the [completion rule](../../AGENTS.md#finish-a-change).

## Checks that require no account

```sh
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
IPSE_HOME=$(mktemp -d) ./bin/ipse demo
```

Use focused tests during changes, then run the suite for a runtime handoff.
The suite exercises real filesystem and process behavior, local HTTP streaming,
OAuth validation with generated test keys, refresh serialization, skills,
journal recovery, approvals, and cancellation. HTTP fixtures bind to loopback;
Mix can also need local sockets. Initial dependency fetching needs network.
No real API keys or subscription are required. Auth transport injection and
subscription loopback endpoint overrides are compiled only for the test
environment. OAuth recovery and session-level subscription error fixtures are
separate from live account checks.

Ordinary `mix test` excludes `:native_sandbox`, `:macos_sandbox` and
`:macos_filesystem` enforcement checks. On a supported Linux host, run
`mix test --include native_sandbox`;
included checks fail when unavailable. On macOS, run
`mix test test/macos_sandbox_test.exs test/stdio_runner_test.exs test/macos_filesystem_test.exs --include macos_sandbox --include macos_filesystem`
to cover policy, process/stdio enforcement and actual filesystem aliases, as the
hosted macOS job does. The filesystem fixture requires a real case-insensitive,
normalization-insensitive volume and verifies inode identity before testing the
metadata guard; it fails rather than treating an unsuitable volume as proof.
Linux's remaining macOS exclusions are platform skips, not known test failures;
hosted macOS must verify each new runtime revision. A local Mac repair session is
needed only for a reproducible failure requiring that environment. Report the
exclusion count, hosted revision and actual OS enforcement separately; the stronger
detached-process cleanup limitation below remains a distinct accepted boundary.
Stdio fixtures create an isolated owner-only `IPSE_HOME`; they do not use or
change the operator's signed cache or its permissions.

The demo is deterministic and does not call a model. It checks that the CLI,
session loop, skill loading, file tools, and native command helper work together.
Use its printed ID with `./bin/ipse chat --resume SESSION_ID` under the
same `IPSE_HOME`; `/session` should show the session without replaying tools.

### macOS App Sandbox diagnostics

After building on macOS, use a disposable workspace outside the probe's own
temporary directory:

```sh
IPSE_MACOS_WORKSPACE=$(mktemp -d)
elixir scripts/verify-macos-sandbox.exs priv/ipse-runner "$IPSE_MACOS_WORKSPACE"
elixir scripts/verify-macos-sandbox.exs priv/ipse-runner "$IPSE_MACOS_WORKSPACE" --process-boundary
rm -rf "$IPSE_MACOS_WORKSPACE"
```

The default probe checks signed file/network enforcement and ordinary child
inheritance. The extra flag also runs twelve process cases through the same
signed helper. Four controls keep the descendant in the original group. Eight
cases use `setsid` or `setpgid`, each followed by normal exit, timeout, explicit
Port closure, or Port-owner death. Readiness follows the group change and an
actual inherited outside-read denial. The probe confirms helper-process exit,
then releases a scratch-file gate and checks for a descendant's write and exit.
Children stop after five seconds even if the probe crashes. No process flood,
provider account, or credential file is involved.

Currently the extra flag prints eight `GAP` lines and exits nonzero. This is a
failure of the stronger descendant-lifetime contract, not a passing containment
result. The developer subsequently accepted best-effort cleanup for macOS native
mode. CI includes production macOS enforcement, the default experimental probe,
and both source/package platforms. The stronger process diagnostic remains opt-in.
The script removes its scratch files and bundle, but macOS retains each generated
`org.ipse.sandbox.<random-id>` app container under `~/Library/Containers`.
See [production gates and container lifecycle](sandbox.md#signing-and-integration-gates).

### Stdio cleanup load diagnostic

Two diagnostics address different boundaries. For the selected synthetic MCP/feed
Session cases that have shown intermittent Mac failures, capture host worker-call
and cleanup timing:

```sh
IPSE_TEST_STDIO_PROBE=1 mix test test/stdio_probe_test.exs test/extensions_feeds_test.exs test/mcp/session_test.exs
```

CI enables this test-only switch for its ordinary suite. The probe uses an
isolated OTP trace session, arities instead of arguments, monotonic elapsed times
and classified return outcomes. It retains no argument or response payloads;
privacy and owner-cleanup fixtures verify that boundary. Enrollment uses OTP's
synchronous process handshake. Capture ends at owner loss, twenty seconds or
64 returned/pending calls; its report is explicitly incomplete. This is not a
production tracing option or a reason to enable return tracing on real sessions.
The diagnostic preserves operation deadlines and success assertions. Staged MCP
checks distinguish dispatch, the observed effect and final completion instead of
assuming the entire turn fits inside a shorter receive timeout. A green run does
not identify the cause of an earlier failure.

For the native helper's frame/drain boundary, use the separate Elixir load diagnostic:

```sh
mix run scripts/diagnose-stdio-cleanup.exs --iterations 1000 --concurrency 16 > /tmp/ipse-stdio-cleanup.jsonl
mix run scripts/diagnose-stdio-cleanup.exs --iterations 100 --concurrency 4 --sandbox native > /tmp/ipse-stdio-native.jsonl
```

The script alternates the original initial-exit fixture, 64 KiB on each output
stream, and the same burst with collection delayed by 100 ms. It records every
decoded frame, helper exit status, elapsed time, and incomplete frame bytes.
The summary separates output-read errors, drain deadlines, other helper errors,
transport failures, and missing completion. Any unexpected status, output,
error frame, missing completion, or delayed child write makes the run fail.
Bounds are 1,000 trials, sixteen concurrent owners, 256 KiB captured per trial,
a five-second helper lifetime, and a seven-second collection deadline.

Native setup is serialized because signed-cache preparation uses a nonblocking
cross-process lock; launched servers and cleanup still overlap. Setup failures
remain failures and are never retried in trusted mode. State and workspaces are
temporary, and the previous `IPSE_HOME` is restored. Native Mac runs can leave
OS-managed app containers, as described above. Logs contain only synthetic
fixture output and can be large. No MCP or provider service is contacted.
The collector's delayed receive does not guarantee backpressure on the OS pipe.
See [local investigation evidence](#macos-stdio-cleanup-load-2026-10-15).

## Release check

```sh
./scripts/package.sh
```

From the source checkout, verify the printed archive automatically:

```sh
elixir scripts/verify-package.exs dist/ipse-*.tar.gz
```

The glob must select exactly one archive; otherwise pass the exact printed path.
This creates an isolated fresh HOME/IPSE_HOME and utility-only PATH, checks
default/explicit working directories (including spaces), and runs bundled helper
lifecycle checks. It uses the existing account and needs a bounded outer job
timeout. CI runs it on Linux and macOS; no archive is published automatically.

Extract the printed archive into an empty directory. Run `./ipse --help`
and `IPSE_HOME=$(mktemp -d) ./ipse demo` there. Do not rely on a source
checkout's `priv/` directory or build artifacts. Record OS, architecture, libc,
Elixir/OTP, and Rust versions with results. A release includes ERTS and the
native helper, but needs compatible system libraries.

From that extracted directory, also run the bundled helper checks:

```sh
./bin/ipse eval 'Code.require_file("verify-release.exs")'
```

On macOS it also checks native workspace writes, outside-file denial, and ordinary
child timeout cleanup using built-in codesign without a development toolchain.
This Elixir script verifies that runtime and application paths belong to the
extraction, exercises timeout and owner-death cleanup, and checks lock exclusion,
release on owner death, and inode preservation. The cleanup commands emit readiness
only after spawning their descendants, so the checks establish that work started
before cancellation or timeout. `./bin/ipse eval` is the bundled OTP launcher;
the root `./ipse` wrapper accepts Ipse CLI commands instead.
To prove independence from development tools, repeat help, demo, and helper
checks with Elixir, Erlang, Mix, and Rust executables absent from `PATH` while
retaining ordinary host shell utilities, including `sleep` for the helper check.

The packaging script copies the documentation tree recursively. When distributing
a release, set `IPSE_NOTICES_DIR` to a directory containing the bundled toolchain's
license notices; the packager copies these into `licenses/`. Building on one Linux
distribution does not establish compatibility with another distribution.
Inspect that directory in the extracted archive and record the supplied notice
sources and versions. Repackaging recreates the entire generated release staging
directory, including runtime, applications, docs and licenses. The archive
verifier requires exactly one ERTS directory; obsolete files from a prior
toolchain or application set must not survive a rebuild.

## Live provider acceptance

These checks are manual and use the account owner's authorization. Use a scratch
workspace and a small prompt. Record success/failure without credentials,
authorization URLs, tokens, private prompts, or full transcripts.

1. ChatGPT: browser login, status, streamed answer, tool-call round trip, resume,
   token refresh after expiry, and logout. Confirm account/model eligibility and
   that no API billing fallback occurs. Expiry/refresh must be tested with the
   live service before claiming the complete subscription lifecycle works.
2. OpenAI API: set the key securely; test streamed text and a tool round trip
   with `--provider openai`. This uses separate API billing.
3. Ollama: start the service and a tool-capable model; test text and a tool round
   trip with `--provider ollama`. Record the model/version and relevant hardware.
4. Anthropic API: test text, tool use, continuation, and a surfaced provider error
   with `--provider anthropic` and a key supplied securely.

### Provider verification status

Milestone completion is scoped to its recorded evidence; fixture coverage is
not live-service acceptance. Current recorded status:

| Provider | Live evidence | Outstanding |
| --- | --- | --- |
| ChatGPT subscription | Browser sign-in, streamed coding/tools, resume, natural-expiry rotating refresh, logout, compaction, local MCP, and serial delegation on Arch | Broader eligibility/allowance cases and other hosts remain bounded by the individual records below |
| Ollama | Installed `qwen3.5:9b`: basic acceptance, compaction, native local/HTTP MCP, serial/parallel delegation and idle resume on Arch | Other models/hosts and feature-specific negative paths |
| Anthropic API | Explicit API billing with `claude-haiku-4-5`: basic acceptance, compaction, native local/HTTP MCP, serial/parallel delegation and idle resume on Arch | Other models/hosts and feature-specific negative paths |
| OpenAI API | Explicit API billing with `gpt-4.1-mini`: basic acceptance, compaction, native local/HTTP MCP, serial/parallel delegation and idle resume on Arch | Other models/hosts and feature-specific negative paths |

The developer authorized live API calls using the ignored repository `.env` on
2026-10-15. Keys were loaded privately for the check; they were not printed,
committed, journaled, or supplied to the MCP server. No model was downloaded,
no credential fallback occurred, and each provider was explicitly selected.
These results do not establish arbitrary model/host coverage. See
[the live acceptance record](#live-provider-acceptance-follow-up-2026-10-15).
Earlier Ollama evidence
is in [Arch local provider checks](#arch-release-and-local-provider-checks-2026-10-14)
and [runtime identity](#p1-runtime-identity-2026-10-15).

## Current evidence and next checks

The [plan](../plan.md#current-priorities-and-status) owns current milestone scopes.
Older dated records retain their contemporary numbering: P24 media is now deferred
P28, and old P25 production-knowledge references predate the P25 comparison and
P26/P27 deferral. P24 now owns external adversarial architecture validation and
baseline security; P25 requires final architecture/security review after repairs.
The operator returned partial static reviews of `21e59fe` and `b570ef8`, then a
fresh cloud review of `b5297be` using documentation at `b08cd76`;
the [disposition register](architecture-review-dispositions.md) separates its
unrun proposals from supervisor reproductions and actual repairs. The follow-up
accepted prior scoped repairs; the fresh report adds PA findings and confirms
fresh-session provenance while withholding acceptance for defects, policies and
remaining coverage. A1–A5 repairs passed local and hosted handoffs at `b5297be`, with controlled pre-fix failures for
approval interleaving, writer acknowledgment and oversized question-ID admission.
The PA-5/PA-6 egress repair at `42d9f1f` also passed its local and hosted
Linux/macOS handoffs. The role/text/catalog/login batch and fixture follow-up
passed local and hosted gates through `091b2bd`; the failed first matrix remains
recorded below rather than being overwritten. P25's subsequent research/comparison
and supervised authoring are recorded separately in the [trial record](p25-evaluation.md).
The OpenAI security-service baseline completed with five static findings. Four
repairs passed local and hosted checks at `bfce156`; final composition follow-up
verification passed at `375e607`, as recorded below.
Security-service access checks are not scan evidence. A private cloud environment
was explicitly created and published, but Security Cloud requires its own setup.
The 2026-10-18 focused subscription report was interrupted by its safeguard;
successful CLI exit does not establish review completion. The operator approved
scanning first while architectural acceptance stays open, without another
architecture-review round. The one-time scan completed at `8b4f706`; the
[register](architecture-review-dispositions.md#baseline-security-scan-at-8b4f706)
distinguishes applicable repairs from the accepted private-journal trust limit.

### Focused review and cloud setup, 2026-10-18

The focused pass used the committed `86d4d69` export and repair delta; runtime/tests
match `e8f7ad5`. Observed metadata reports Opus 5.5, high effort, no API key source
and only Read/Glob/Grep. It ran about 15 minutes and made 54 Read calls plus
searches. The safeguard cut off the report and its final response acknowledges
missing findings and coverage. Raw output and observed read ranges remain private.
The [register](architecture-review-dispositions.md#focused-completion-at-86d4d69)
retains sanitized concerns without inventing a complete verdict. A supervisor
optional-callback recovery probe passed one selected synthetic test (12 excluded);
it does not establish the separately mentioned pressure failure.

General cloud onboarding installed Elixir 1.18.3/OTP 27/Rust 1.85.1, retaining
toolchains outside the unchanged checkout. Setup reported passing build, strict
compile, format, credential-free demo and repeated dependency refresh. The plain
suite completed with 880 tests, two cleanup failures and 32 exclusions. It
attributes them to orphan zombies under the container's PID 1. Both complete
affected modules passed 63 tests using an external Rust subreaper; the full suite
under that launcher remains unrun. The launcher adopts/reaps orphans and preserves
the command's exit status; source, assertions and deadlines were unchanged.
These are observed onboarding results, separate from the prior inspected hosted
CI receipts. Landlock ABI 6 is unavailable, so this host supplies no native
enforcement evidence. Environment publication is not a fresh-restoration proof.

The published general environment has Only me visibility, package-manager network
access and no added variables/secrets. Security Cloud list/search does not discover
it. Its UI loaded after one retry and offers a separate automatic scan environment.
The one-time repository scan is prepared for `lexlapax/ipse`, GPT-5.6 Sol/high,
continuous monitoring off. The operator explicitly approved its automatic
environment creation and launch. The service confirms active run
`wfr_a67044bec66103c57f7c55f9a2555183d2426db134312b7d2afa5f30990823ea`, target
`8b4f706953bd491c08c1926bbf6c111e898a1eb3`, environment
`6ad4c44338748191a3da3afa4d2ac91b`, created at 13:06:15 UTC and running at 13:06:32.
The [operator record](../operator/architecture-review.md#baseline-scan) links the run.
The run completed at 13:33:24 UTC, with no output-validation warning. The report
claims complete static coverage of 399 paths, no exclusions, five findings (one
High, one Medium, three Low) and no runtime/test/native-enforcement execution.
All four UTF-8 artifacts were read to their final page and their exact digests
matched: report `dd0e788e…`, manifest `e18a4f59…`, findings `3b490d69…` and coverage
`0b0c4382…`. Raw artifacts remain private outside Git. Service usage is $41.79,
fully allowance-covered, with no pending billing or error.
No local security CLI, new runtime package, billing-mode change or P25 execution
is claimed. The [security context](../../SECURITY.md) supplies the
review threat model, including check/use and shared-grant/temporary-secret seams.

The repair candidate's synthetic native-helper test failed before the fix by
creating an outside-workspace marker; no credential or real exploit target was
used. Post-repair runner/native tests passed 44 cases (22 exclusions). Tool/auth
checks passed 35 cases, then 31 including real multi-response attempt exhaustion
and traced pre-crypto rejection. The native-initialization/CI/Session set exposed
a linked failed-start test-fixture issue, corrected to the supervised start path;
both boundary cases then passed. The final native-inclusive suite passed 875 tests
with zero failures and 15 Mac exclusions in 237.8 seconds. Build, actual Elixir
1.18.4/1.20.4 formatter checks, strict compilation, CI pin policy and the isolated
demo passed. The strengthened JWT trace includes a passing-signature positive
control, and its selected test also passed. An intermediate compile caught the
new guard before its `cwd` binding;
it now follows canonicalization and precedes journal/lock setup.

The rebuilt archive SHA-256 is
`9b1c78692e1507cb7942f0347acb5c104f52910b0aae3d88def5453de725f496`.
Extracted-package verification passed, including the root `SECURITY.md`, native
helper/application separation and aggregate call quotas. Independent installed
proofs passed all 41 extension and nine model-call assertions with unchanged
archive/host bytes and no system development toolchain on runtime PATH. The
deliberate service-crash cleanup remains unconfirmed/`safe_to_continue: false`.
Hosted Linux/macOS verification subsequently passed at `bfce156`, recorded below.
Documentation checks cover 112 root/docs
Markdown files and 1,577 local links/anchors with zero errors.

The follow-up independently reproduced next-turn refusal after real optional
worker pressure (pre-fix failure, post-fix selected regression pass). It removes
macOS selected-environment staging from shared data in favor of an exact private
stdin prefix. Four Rust policy/framing tests pass on Linux; this is not macOS
enforcement. The strengthened 120 KiB selected-environment fixture first exposed
immediate Port backpressure (44 passes, one failure, five exclusions in the
focused delivery/stdio run). Bounded launch flushing fixes that path; the stdio
set then passed 21 cases, with five Mac exclusions. Final native-inclusive source
verification passed 877 tests, zero failures, 15 Mac exclusions in 247.0 seconds.
Both Elixir formatter floors, build, strict compile and the isolated demo pass.
The final archive SHA-256 is
`0b4997bd2ea77db55d8c739431ba1ce0e458074e4c7351bfe96d349e081d4715`.
Extracted-package verification and both previously compiled independent artifacts
pass: 41 extension/nine model checks, unchanged archive/host, no system development
toolchain on runtime PATH. Deliberate service-crash cleanup remains unconfirmed.
The final source change after the full suite only clarifies the Runner API's
environment wording; strict compile and installed proofs cover that host identity.
Hosted verification passed at `375e607`; `bfce156` alone does not cover these
follow-ups. The exact final matrix and receipts are recorded below.

The fresh report at source `091b2bd`/evidence `20b377c` found two applicable
interaction defects despite that passing matrix. The subsequent internal audit
and candidate `7810925` passed their recorded matrix, but the returned package R
review at evidence `a46cc66` found a false pre-spawn cleanup failure and an
incomplete all-status response bound. It also challenged idle required-delivery
loss and the widened MCP cleanup test. Those findings reopen the affected claims;
the earlier matrix certifies its exercised fixtures, not these missing cases.

The [full internal audit](architecture-self-audit.md) now inspects ownership,
SDK/delivery, context/egress and OS/persistence/accounting, including the complete
Session state machine and meaningful actual test bodies. Its additional
composition repairs cover terminal stdio receipt races, required callback loss,
feed task-death cleanup, prompt admission/queue bounds, auth reception/proxy
bypass, compacted uncertainty, research preview identity and endpoint resume
binding. The consolidated review of `a5912ab`/evidence `a21469e` has now returned
without acceptance. It confirms prior repairs in inspected scope but finds
required-extension cancellation and abnormal-death lock gaps. Those repairs, the
explicit conservative pool-loss policy and additional HTTP-child cleanup probe
passed their own frozen checks at `99bbbdf`. A later real blocked-write probe
exposed that process exit does not fence filesystem IO. The additional completion-owner
repair passed a new frozen baseline and hosted matrix at `e8f7ad5`; that evidence
is separate from the first repair's green run.
The completed baseline adds claimed whole-tree independent static security
coverage; it does not retroactively expand earlier reviewer reads or establish
runtime enforcement. Security-repair/follow-up platform verification has passed
at `375e607`. The supervisor's
[scoped P24 readiness decision](architecture-review-dispositions.md#p24-scoped-readiness-decision)
assesses that evidence and accepted limits for supervised P25. It supplies no
new independent post-fix verdict. P25's
[record](p25-evaluation.md) retains the initial failure and assistance; its authored
repair, two fresh reports and assisted held-out/live controls now pass their scoped
checks. Final security review and trial acceptance remain open; no further P24
architecture-review sequence is scheduled.

During P23E2 iteration, a full run overlapped a focused recompile and produced
eight artifact-admission failures; that run was discarded. Final verification
froze runtime bytes and ran serially. No trust assertion or runtime deadline was
weakened to obtain the passing result below.

| Checkpoint | Evidence | Scope and remaining limits |
| --- | --- | --- |
| License matrix `27bc9d4` and model-proof readiness correction, 2026-10-18 | [Run 39159684772](https://github.com/lexlapax/ipse/actions/runs/39159684772) passes Linux completely. Mac passes 929 tests/zero failures/32 exclusions, enabled 36/0/6, four Rust checks, package verification and all 41 extension assertions; its model-proof fixture times out in `gen_tcp.accept` and the later signed probe is skipped | Failed matrix retained. The fixture started its five-second accept timer before import, Session startup and approval. A controlled 5.5-second preparation delay reproduces the old failure; starting the accept task only at approval readiness passes all nine assertions with the same delay, both formatter floors and the same installed archive/artifact. Accept/read/model/assertion deadlines remain five seconds; no production code, assertion or accepted outcome changes. Actual prior Mac preparation time is unmeasured. Corrected-source hosted verification subsequently passes at `7bb642b`, recorded above |
| Apache-2.0 and proof-fixture source `7bb642b`, hosted 2026-10-18 | [Complete Linux/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39160752791) passes every applicable step: 929 tests/zero failures/32 exclusions per host, enabled Mac 36/0/6, four Rust checks, signed App Sandbox, package verification and all four parsed installed receipts (41 legacy/nine model assertions per host) | Full logs, exact revision/job/step conclusions and both committed license copies checked against locally verified bytes. License/data/docs and proof-readiness changes; runtime, ExUnit and build source remain the P25 candidate. Earlier failed model fixture and unmeasured preparation timing are retained. Third-party and historical licenses keep provenance; P25 acceptance and earlier scan/review limits are unchanged |
| Apache-2.0 transition, Linux Serenity, 2026-10-18 | Root and bundled extension licenses preserve the original copyright and canonical Apache text. Build, actual Elixir 1.18.4/1.20.4 formatters, strict compile, 914 native-inclusive tests/15 exclusions, isolated demo and package verification pass. Archive `a94d421d0c2bf70d129c0e5bc24cf3ba9f4088fd81cb7cf12a20e96e65e8a334` passes all 41 legacy/nine model assertions with the unchanged precompiled artifacts | Both packaged license copies checked byte-for-byte; upstream MIT notice unchanged. All six built-in identities change; old entries refuse preflight and refreshed entries refuse the old pinned synthetic session, with unchanged/restorable journal and zero model requests. Runtime/test/build source is unchanged from P25. Exact-source hosted verification subsequently passes at `7bb642b`, recorded above; deliberate service-crash cleanup retains its unconfirmed/unsafe-to-continue outcome |
| P25 final provider source `3307563`, hosted 2026-10-18 | [Complete Linux/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39158172263) passes every applicable step: 929 tests/zero failures/32 exclusions per host, enabled Mac 36/0/6, four Rust checks, signed App Sandbox, packages and all four parsed installed receipts (41 legacy/nine model assertions per host) | Full logs, exact source, all terminal job/step conclusions and runtime/test hashes checked. Closes the corrected provider platform gate and supports scoped P25 supervisor acceptance; partial scans and prior failed matrices retain their original scope, and no whole-design certification is claimed |
| P25 provider composition corrections, Linux Serenity, 2026-10-18 | Four regressions fail at `0196689`; incremental event folding, final deadline checks and EOF charging pass all 67 provider cases, including real Session/budget failed-usage recovery. Build, actual Elixir 1.18.4/1.20.4 formatting, strict compile, 914 native-inclusive tests/15 exclusions, isolated demo and six unchanged trial-journal restores pass. Package verification and unchanged precompiled 41+9 assertions pass; archive `42ba975adf5de9a2fd9ca511c78d11daade56f97fddbc2bddc5a5af3f4f28fc5` | Fresh affected-boundary source review plus a same-reviewer corrective-patch check use 40 cumulative requests/940.2 seconds under original limits, without runtime execution or whole-design acceptance. No new actionable patch defect. Exact-source hosted verification subsequently passes at `3307563`, recorded above. Initial integration fixture run 66/67 omitted cache partitions while expecting a known total; explicit zero partitions repair staging, normalization/assertions unchanged. Deliberate service-crash cleanup stays unconfirmed/unsafe to continue |
| P25 provider candidate `0196689`, hosted 2026-10-18 | [Run 39155854298](https://github.com/lexlapax/ipse/actions/runs/39155854298) passes every Mac gate: ordinary suite 924/0/32, enabled Mac 36/0/6, four Rust checks, signed App Sandbox and parsed installed 41+9 assertions. Linux reports 924 tests/one failure/32 exclusions: the strict diagnostic-question recovery test receives `cleanup_unconfirmed` at final close; subsequent package steps are skipped | Full logs, exact source and job/step conclusions checked; both Mac proof receipts parsed. Failed matrix, cause unconfirmed. The later local full suite passes the unchanged assertion; no accepted outcome, production timeout or assertion deadline is widened, and a green result does not prove the earlier cause |
| P25 verification scan and initial provider-stream correction, 2026-10-18 | GPT-5.6 Sol/high scan completes at `f467de9`, with one Medium finding/no High or Critical findings, partial static coverage of 417 paths and no runtime execution. Four original artifacts match service digests. The resource probe and three regressions reproduce the issue; initial corrected provider suite passes all 62 checks | Approval/journal dispositions receive refreshed coverage. Initial correction passes 909 native-inclusive tests/15 exclusions, both formatter floors, strict build/demo/recovery/package and old compiled 41+9 proofs. Later review/composition corrections have their own rows above; no clean-scan or whole-design acceptance claim. First expanded provider run: 59/60 because the new fixture wrote after deliberate client abort; staging corrected, existing split-byte assertions unchanged. Local 4 MiB probe: approximately 13 seconds before, 5 milliseconds after, exact retained bytes |
| P25 final follow-up `f467de9`, hosted 2026-10-18 | [Complete Linux/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39152616173): every applicable step passes, 911 tests/zero failures/32 exclusions per host; enabled Mac 36/0/6, four Rust checks and signed App Sandbox enforcement. Packages and all four parsed installed receipts pass 41 legacy/nine model assertions per host | Full logs, exact revision and all job/step conclusions checked. Runtime matches the final locally verified follow-up. The approved verification scan completed at this source with partial coverage and a separate Medium provider-stream finding; its correction is recorded above. No independent whole-design acceptance or clean-scan claim |
| P25 architecture-delta follow-up, Linux Serenity, 2026-10-18 | Both new regressions fail before repair. A controlled old-writer probe demonstrates a late append under the next acquired real lock. The corrected focused set passes 32 cases, then both delayed-append/caller-death cases pass after the extra guardian check. Frozen full suite: 896 native-inclusive passes/15 exclusions. Strict fail-fast build, actual 1.18.4/1.20.4 formatter checks, compile, isolated demo, CLI configuration and unchanged recovery of six trial journals pass. Package verifier and old compiled 41+9 proofs pass; archive `c74a494de94196fa25809d12880d22736aca6f71ac9ed87c59b42ae081474187` | Synchronous tracked inactive IO replaces temporary timed-out writers; CLI resolves limits after bounded header discovery and before complete history. No production deadline changes. Exact-source hosted verification now passes as recorded above; affected security verification remains open. Independent review scope/assistance and both Medium dispositions are in the [register](architecture-review-dispositions.md#independent-repair-delta-review) |
| P25 confirmation/journal repairs `81b67f5`, hosted 2026-10-18 | [Completed matrix](https://github.com/lexlapax/ipse/actions/runs/39150357202): both hosts pass every applicable step, 908 tests/zero failures/32 exclusions each; Mac enabled 36/0/6, four Rust checks, signed enforcement, packages and all four parsed installed receipts (41+9 assertions per host) | Runtime matches `e021a8f`; only real-timer fixture serialization/docs differ. Both full logs and exact source/job/step conclusions were inspected. The original failed matrix remains below. This passing source precedes the independently found inactive-writer/resume corrections and does not validate them |
| P25 security repair `e021a8f`, first hosted matrix | [Run 39149573897](https://github.com/lexlapax/ipse/actions/runs/39149573897): Linux passes all stages, including 908 tests/zero failures/32 exclusions and both parsed installed proofs. Mac reports one failure among 908 tests/32 exclusions: the expected optional-consumer backpressure closure was found after the fixture's 6,000 ms receive deadline; later Mac enforcement/package steps did not run | Actual late delivery is observed; its scheduling cause is not established. The real-timer text-stream fixture now runs serially rather than competing with asynchronous modules; all 12 cases and both formatter-floor checks pass locally. Production's five-second timer, the six-second assertion, expected closure fields and cleanup assertions remain unchanged. The next full matrix must verify that test-only change; this failed attempt remains evidence |
| P25 final-scan repair candidate, Linux Serenity, 2026-10-18 | Build, both actual Elixir 1.18.4/1.20.4 formatter checks, strict compile, isolated demo and documented configuration example pass. Frozen native-inclusive suite: 893 passed, 15 exclusions. Package verifier and old compiled artifacts pass all 41 legacy/nine model assertions; archive `d5d6636355bbc498ac058b72a0c42c1c1f738fdeae73cdc21aa8feb0795f7bd7`. Six retained live-trial journals restore unchanged; five multibyte/escaped-JSON chunk-boundary probes preserve values/source offsets | Fresh approval/question codes and finite per-journal admission/streamed decoding. First full run: 891 passed, 15 exclusions, one inactive-append permission compatibility failure; correction restores prior behavior and adds strict hardlink protection. Hosted platforms and refreshed affected security review remain open. The scan at `b5ddd02` predates these changes; no independent whole-design acceptance or clean-scan claim |
| P25 authored repair `1fc50b5`, source/installed and hosted 2026-10-18 | Corrected new regressions fail twice against the unchanged baseline and pass all 18 workspace cases with the Ipse-authored patch. Full candidate suite: 862 passed/32 exclusions; both formatter floors, strict compile/demo, 12 enabled Linux and 21 stdio checks (five Mac exclusions) pass. Archive `cdd37e0dab3f2f4d2258b764061ada2e19c8de8e012cd201efe37e80cc8d066b` passes package verification and 41+9 installed assertions. Documentation-only `2c32d97` [hosted run](https://github.com/lexlapax/ipse/actions/runs/39142415316) verifies the identical runtime/tests on both hosts: 894/0/32 each, enabled Mac 36/0/6, four Rust checks, signed enforcement and all four installed receipts | Independent source review and installed probe verify specific preflight refusal, distinct queued result, no execution and inert recovery. Earlier failed matrices and unconfirmed causes remain in the execution record. No extension/authority/egress contract changes; deliberate service-crash cleanup stays unconfirmed |
| P25 supervisor test diagnostics `a021d0e`, hosted 2026-10-18 | [Complete matrix](https://github.com/lexlapax/ipse/actions/runs/39143843693): 896/0/32 per host, enabled Mac 36/0/6, four Rust checks, signed enforcement, packages and all four parsed installed receipts (41+9 assertions per host). Local focused set: 38 passed | Two bounded synthetic trace privacy/owner tests and staged MCP readiness; no product runtime change, timing-policy increase or widened accepted outcome. Passing instrumentation does not establish earlier intermittent causes. Documentation-only `e20dd29` separately failed Ubuntu's prompt-annotation 100 ms completion assertion, retained without a runtime-cause claim |
| P25 live research/self-development reruns, 2026-10-18 | Two fresh repaired-runner reports score 14/21 each, with every criterion at least two, matching the checked reference. Six held-out cases pass after one shorter-output continuation (8,982 characters; nine cumulative requests/28 proposals). Live controls total ten requests: answered question across pending restart, two actual compactions, cancellation before effect, absent file and unchanged idle resume | Own ChatGPT subscription, explicit `gpt-6.1-sol`/high; frozen inputs and installed runner. Original source-fit, over-length and supervisor fixture failures remain recorded. No word-matching, unassisted-success, equal-native-budget, engine-performance or unattended-development claim. [Execution record](p25-evaluation.md) owns actual hashes/counts/interventions and the final scoped acceptance decision |
| P24 final security/composition source `375e607`, hosted 2026-10-18 | [Completed Linux/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39134788296) passed every applicable step: build, format, strict compile, CI pin policy, ordinary suites (892 tests, zero failures, 32 exclusions per host), demo, package verification and both installed proofs. Enabled Mac subset: 36 tests, zero failures, six exclusions; four Rust policy/framing tests and signed App Sandbox enforcement pass | Exact source, both terminal jobs/all steps and full logs inspected. All four JSON receipts parsed: 41 extension/nine model assertions true per host, unchanged archive/host and no runtime system development toolchain. Includes actual Mac 120 KiB environment/raw-stdin delivery and optional pressure/next-turn regression. Signed enforcement checks code/entitlements, allowed workspace/private-tmp writes, denied outside fake-credential/symlink reads/write/chmod and loopback. Hosted archives: Linux `92499599751c03e8d3825f41f9df11788340d6b386e1dc3b120e8e32be5410b8`, Mac `79beacc3c790c1fdbb94f8b71830a942963714f76169410862e7ad72c76db7b6`. The local frozen runtime passed 877 native-inclusive tests (15 Mac exclusions), both formatter floors, build/strict compile/demo and installed proofs; archive `0b4997bd2ea77db55d8c739431ba1ce0e458074e4c7351bfe96d349e081d4715`. Deliberate service-crash cleanup remains unconfirmed/unsafe to continue; earlier intermittent causes remain unconfirmed. Supports the scoped supervisor readiness decision, not independent post-fix acceptance or a second scan |
| P25 unscored access preparation, 2026-10-18 | Ipse's own ChatGPT subscription returned the exact readiness response using requested/reported `gpt-6.1-sol`, high reasoning, no tools, and confirmed cleanup. A separate fresh Codex CLI 0.163.0 subscription session returned the exact response with tools unused and requested `gpt-6.1-sol`/high; no served-model identity was exposed. Keyless configured Exa MCP discovery returned exactly the allowed search/fetch tool schemas and closed cleanly | Separate auth stores; no borrowed credentials, API fallback, source research or scored run. Ipse used the development runtime, not yet the frozen installed trial runner. Codex apps/plugins/memories/hooks/subagents were disabled. Only metadata discovery went to Exa; no search queries, repository content or credentials were sent. Private preflight artifacts stay outside Git. These checks establish access only, not research quality or matching backend identities |
| P24 baseline-security repairs `bfce156`, hosted 2026-10-18 | [Completed Linux/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39133201684) passed every applicable step. Ordinary suites: 890 tests, zero failures, 32 exclusions per host. Enabled Mac subset: 35 tests, zero failures, six exclusions; one Rust policy test and signed App Sandbox probe pass. Build/format/strict compile/CI pin policy, demo, packaging and both installed proofs passed | Exact source/all job and step conclusions/full logs inspected. All four JSON proof receipts parsed: 41 extension and nine model assertions true per host, unchanged archive/host and no system development toolchain on runtime PATH. Signed enforcement confirms allowed workspace/private-tmp writes and denied outside fake-credential/symlink read/write/chmod and loopback. Source is the four scan repairs, before the subsequent pipe/pressure/startup follow-ups. The scan remains pinned to `8b4f706`; static coverage is not runtime evidence. Deliberate service-crash cleanup remains unconfirmed |
| P24 final consolidated repairs `e8f7ad5`, hosted 2026-10-18 | [Completed Ubuntu/macOS run](https://github.com/lexlapax/ipse/actions/runs/39108388987) passed build/format/strict compile, ordinary suites (880 tests, zero failures, 32 exclusions per host), demo, package verification and both installed proofs. Enabled Mac subset: 35 tests, zero failures, six exclusions; one Rust policy test and signed App Sandbox enforcement pass | Exact SHA, both terminal jobs/all steps and full logs inspected. All four proof receipts parsed: 41 legacy/nine model assertions true per host, unchanged archive/host and no system development toolchain. Signed enforcement verifies code/entitlements, allowed workspace/private-tmp access and denied outside credential/symlink reads, write/chmod and loopback. Includes blocked-write and budget-lock regressions, staged MCP readiness, verified-effect disconnects and synchronous trace-owner setup; runtime code is unchanged from the locally packaged `74686f1`. Documentation links/anchors: 122 documents, 1,554 links, zero errors. Completes this repair delta's platform checks; independent SDK/sandbox source omissions, baseline scan and P25 remain open. Deliberate service-crash cleanup stays unconfirmed and historical intermittent causes are not retroactively established |
| P24 instrumented MCP matrix `b0cedc6`, 2026-10-18 | [Run 39107695962](https://github.com/lexlapax/ipse/actions/runs/39107695962): Linux passed all stages and both installed proofs. Mac passed the MCP cases but had one failure among 880 tests (32 exclusions): the trace owner-death test received no startup PID within ExUnit's implicit 100 ms; revocation had not been exercised. Later Mac enforcement/package steps were skipped | Owner setup now uses synchronous Agent initialization around the same tracer start, replacing the unrelated scheduling assertion. The 5,000 ms capture policy and existing cleanup polling/assertions stay unchanged. Both formatter floors, strict compile and the tracing/diagnostics/lifecycle/Client/Session set pass all 49 cases locally. No runtime change or claimed failure of the actual revocation mechanism; exact Mac scheduling delay remains unmeasured |
| P24 repeated matrix `f838327`, 2026-10-18 | [Run 39106751148](https://github.com/lexlapax/ipse/actions/runs/39106751148): Linux passed every stage and both installed proofs; Mac had one failure among 880 tests (32 exclusions), in the direct Client disconnect case. The corrected Session readiness cases passed; later Mac enforcement/package checks were skipped | The direct test returned a pre-dispatch transport error before its post-effect assertions ran, so the actual dispatch/effect phase is unconfirmed. It now gates connection loss on an atomic ready marker and already-verified call log/file, keeps the strict unknown result and one-effect assertions, and records fixture-only boot/initialize/list/call/effect stages on failed preconditions. The separate immediate-exit Session regression remains strict. All 23 Client/Session cases pass locally. Runtime code remains unchanged; a later green matrix cannot retroactively establish this failure's root cause |
| P24 filesystem first hosted matrix `74686f1`, 2026-10-18 | [Run 39106021352](https://github.com/lexlapax/ipse/actions/runs/39106021352): Linux passed all 879 ordinary tests (32 exclusions), packaging/verifier and both installed proofs. macOS had one failure among 879 tests (32 exclusions): the abrupt-stdio-supervisor test never reached its ready-file precondition; later Mac enforcement/package steps were skipped | The fixture started a three-second ready-file poll before discovery/model work. A controlled 3.2-second model gate reproduces that mismatch with the old helper. The corrected helper waits for the existing tool-start event before its unchanged three-second poll; protocol and cleanup deadlines/assertions stay intact. Focused MCP session suite passes all 12 tests. This identifies a test-stage timing defect, not the exact phase or runtime cause of that earlier Mac occurrence. Runtime code is unchanged from `74686f1`; the corrected matrix is recorded above |
| P24 filesystem-completion follow-up, frozen Linux source, 2026-10-17 | Build, actual Elixir 1.18.4/1.20.4 formatter checks, strict compile and isolated demo pass. Full native-inclusive suite: 864 passed, 15 Mac-only exclusions, 233.9 seconds. Focused filesystem/writer/budget/state/task suite: 56 passed; broader composition suite: 155 passed | A real blocked FIFO write allowed unsafe resume with the previous tool implementation and refuses resume after repair until the reader drains. A real budget lock remains unavailable after caller death until its completion owner finishes. Raw mode alone was probed and is not a fix. No compilation overlapped final tests. Exact-source hosted verification is recorded above at `e8f7ad5` |
| P24 filesystem-completion bundled runtime | Package verifier and both previously compiled independent extension proofs pass; all 41 legacy/nine model checks parsed true, unchanged archive/host and no system development toolchain on runtime PATH. Archive SHA-256 `ef38dba04701b842dd55b7773a21c66a1046bbb3d59752464010130d4e24ef0e` | Deliberate service-crash cleanup remains unconfirmed and `safe_to_continue: false`. Documentation links/anchors: 122 documents, 1,553 links, zero errors. The final runtime's hosted evidence is recorded above at `e8f7ad5`. No independent acceptance, security scan or P25 run |
| P24 first consolidated repair `99bbbdf`, hosted 2026-10-17 | [Linux/macOS run](https://github.com/lexlapax/ipse/actions/runs/39104588885) passed build/format/strict compile, 877 ordinary tests with zero failures and 32 exclusions per host, demo/package/verifier and both installed proofs per host. Enabled Mac subset: 35 tests, zero failures, six exclusions, one Rust policy test and signed App Sandbox probes | Terminal jobs/full logs inspected; all four receipts parsed with 41 legacy/nine model checks true, unchanged archives/hosts and no host development toolchain. This predates the additional filesystem-completion repair: a real blocked write subsequently showed that BEAM caller death, including raw mode, does not prove IO completion. The final follow-up evidence is recorded separately above. No architecture acceptance or security scan |
| P24 consolidated follow-through, frozen Linux source, 2026-10-17 | Build, actual Elixir 1.18.4/1.20.4 formatter checks, warnings-as-errors compile, isolated credential-free demo and native-inclusive suite pass: 862 passed, 15 Mac-only exclusions, 231.5 seconds. The affected invocation/model/MCP/text/writer/task/delegation suite passes all 119 tests | Required cancellation and abnormal-death lock exposure reproduced before repair. A corrected actual-pool fixture pins conservative Session stop/manual inert resume; early fixture PID selection mistakes are not counted as reproductions. A suspended named Finch child reproduces premature slot release. The initial nested-drain ordering failed the existing confirmed workflow-shell cancellation check; resource receipts now precede normal nested termination and the unchanged strict assertion passes. No compile/build overlapped final tests; exact-source hosted verification is recorded above at `99bbbdf` |
| P24 consolidated follow-through, extracted runtime and old compiled artifacts | Package verifier and both previously compiled independent extension proofs pass. All 41 legacy/nine model assertions parsed true, unchanged archive/host and no system development toolchain on runtime PATH. Archive SHA-256 `4eb19967dcaa6f28362df06898b3a88baad5a5dc885825dbdacd3348cfa59282` | Deliberate service-crash cleanup remains unconfirmed with `safe_to_continue: false`. Documentation links/anchors: 122 documents, 1,553 links, zero errors. No raw private review committed, live account, independent acceptance, security scan or P25 claim. Hosted evidence for this source is recorded above at `99bbbdf`; later filesystem changes require their own verification |
| P24 full internal audit hosted `a5912ab` | [Run 39100702633](https://github.com/lexlapax/ipse/actions/runs/39100702633) completed successfully on Ubuntu and macOS: build, format, strict compile, ordinary suites (871 tests, zero failures, 32 exclusions per host), demo, package verification and both installed proofs. Mac enabled subset: 35 tests, zero failures, six exclusions; one Rust policy test and signed App Sandbox enforcement pass | Exact SHA, every terminal step and full logs inspected. All four proof receipts parsed: 41 legacy/nine model assertions true per host, unchanged archive/host and no runtime system development toolchain. Signed enforcement confirms code/entitlements, allowed workspace/private-tmp access and denied outside credential/symlink reads, write/chmod and loopback. Archives: Mac `3a3c0d79c8e3cc6954b81da2edf1beece8791fb93fe8996841789dc46a408be8`, Linux `9fce9c44b018e560e8380bc236e1c93316f27ad6ebd40c8bbb5cb0db71440d43`. Completes this full internal audit's platform gate; one consolidated handoff is ready. Deliberate service-crash cleanup and historical intermittent causes remain unconfirmed. No independent acceptance, security scan or P25 claim |
| P24 full internal audit, frozen Linux source, 2026-10-17 | Build, actual Elixir 1.18.4/1.20.4 formatter checks, warnings-as-errors compile, isolated credential-free demo and full native-inclusive suite pass: 856 passed, 15 Mac-only exclusions, 226.6 seconds. Documentation links/anchors: 120 documents, 1,535 links, zero errors | Full internal boundary inspection and all new regression bodies, including actual pre-fix failures, are in the audit. Auth/egress/CLI focused 67, SDK 122, delivery/research 90, lifecycle/recovery 51 and endpoint/config/profile/CLI/budget 80 checks passed during iteration. No compile/build overlapped final tests. Hosted results for the same source are recorded above; local Linux does not establish Mac enforcement or independent acceptance |
| P24 full-audit extracted runtime and frozen artifact compatibility | Package verifier and both previously compiled independent artifact proofs pass. All 41 legacy/nine model assertions parsed true, archive and host unchanged, no system development toolchain on runtime PATH. Archive SHA-256 `b1eb2c9721e7a5511a6838b3b5b20b27c0e07f08eb39ab2200ce1441a33aaec0` | Deliberate service-crash cleanup remains unconfirmed and `safe_to_continue: false`. The artifacts were not rebuilt with the candidate SDK. No live provider/account, stronger containment, security scan, independent acceptance or P25 claim |
| P24 R repair hosted `f64fa0a` | [Run 39097766348](https://github.com/lexlapax/ipse/actions/runs/39097766348) passed Ubuntu source/demo/package and both proofs; macOS failed the strict controlled MCP disconnect assertion for actual helper exit zero, so its later gates were skipped | Trace showed unconfirmed stdio cleanup, not a proven forced helper exit. This is a failed matrix, not an accepted alternate outcome. The later controlled closed-stdin regression reproduces one loss mechanism; it does not prove the historical cause |
| P24 fixture-only follow-up `596b166` | [Run 39097986313](https://github.com/lexlapax/ipse/actions/runs/39097986313) passed both hosts: ordinary suites 858 tests, zero failures, 32 exclusions each; Mac enabled subset 34 tests, zero failures, six exclusions, one Rust policy test and signed App Sandbox enforcement | Full jobs/logs inspected. All four installed receipts parsed with 41 legacy/nine model assertions true, unchanged archive/host and no runtime system toolchain. Same runtime as f64fa0a; a green rerun does not establish the earlier failure's cause. Does not certify the subsequent full-audit delta |
| P24 earlier documentation-only `a46cc66` matrix, inspected during R repair | [Run 39092277048](https://github.com/lexlapax/ipse/actions/runs/39092277048) failed Ubuntu: 834 tests, two failures, 32 exclusions. Subscription cancellation read an empty PID readiness file; diagnostic/question recovery got `cleanup_unconfirmed` on final close. Mac passed its ordinary 834-test suite, enabled 34-test subset (six exclusions), Rust policy, package/proofs and signed enforcement | Full logs and exact jobs inspected; Mac receipts parsed with all 41/nine assertions true and unchanged archive/host/no runtime toolchain. Ubuntu later gates were skipped. Both exact fixtures passed 21 unchanged local runs; that does not establish the cleanup failure's cause. The empty-file race is addressed by atomic PID publication, with every liveness/cleanup assertion retained; both affected modules pass 66 tests and both formatter checks. Runtime/package bytes are unchanged by that fixture follow-up |
| P24 package R final source, Linux Serenity, 2026-10-17 | Build, actual Elixir 1.18.4/1.20.4 formatter checks, warnings-as-errors compile and isolated credential-free demo pass. The native-inclusive suite passed before final whitespace normalization (843 passed, 15 Mac exclusions, 222.7 seconds) and again on frozen formatted source (843 passed, 15 Mac exclusions, 223.3 seconds) | No build/compile overlapped either suite. Documentation links/anchors pass (120 documents, 1,532 links). Hosted verification remains pending. No Mac-device, live-account, architecture-acceptance, security-scan or P25 claim |
| P24 package R extracted package and precompiled artifacts | Ordinary verifier and both independently precompiled installed proofs pass. All 41 legacy/nine model assertions parsed true, unchanged archive/host bytes and no system development toolchain on runtime PATH. Archive SHA-256 `06cb4e184dc7bbf66bd1f29647b2acc232b28605416b068cd939e71ddc2ad280` | Uses existing artifacts rather than rebuilding them with the candidate SDK. Deliberate service-crash cleanup remains unconfirmed/`safe_to_continue: false`. This verifies compatibility and the extracted runtime, not independent R acceptance or macOS enforcement; hosted checks are pending |
| P24 package R repair probes, Linux Serenity | Scoped launch refusal reproduced false cleanup failure; real Session startup additionally reproduced SDK link loss. A negative scope-death regression rejected trapping exits in the outer worker. A held-open HTTP socket reproduced successful scope close with a live borrower/pool. Required consumer/broker loss and compaction reproduced silent policy loss. Embedded NUL reproduced an actual truncated shell effect | Corrected ownership, explicit release and pre-launch admission fixtures pass. The SDK runs in an owned nested task with caller guardian; main delivery survives summary preparation. Strict MCP clean/immediate/forced cases pin distinct outcomes. No deadline extension or acceptance of both cleanup statuses in one scenario. Final local checks passed as recorded above; hosted verification pending |
| P24 R-2 all-status response and memory probes, Linux Serenity | Ten open-ended oversized length/chunked cases across 200/201/302/429/500 pass; the eight nonstreamed cases failed against the previous adapter. Trusted TLS succeeds, wrong hostname/untrusted root refuse; existing proxy/error/helper checks pass. Separate isolated VMs received a synthetic 64 MiB chunked 500: old adapter consumed 67,108,864 bytes with sampled global binary-memory increase 77,769,248 bytes; candidate stopped after 8,519,680 bytes sent, with sampled increase 3,120,984 bytes | Existing locked Finch replaces inference `httpc`; no dependency added. Request ceiling is 8 MiB, distinct from server bytes sent, socket buffers and sampled VM memory. Samples are not OS/per-process peak guarantees. No real provider/account or credential used; final source/package/platform checks pending |
| P24 internal-audit corrected hosted matrix `7810925` | [Completed Ubuntu/macOS run](https://github.com/lexlapax/ipse/actions/runs/39091648455) passed source build/format/strict compile, ordinary suites (834 tests, zero failures, 32 exclusions per host), demo, package verification and both installed proofs per host. Enabled Mac subset: 34 tests, zero failures, six exclusions; one Rust policy test and signed App Sandbox probe passed | Exact revision, terminal jobs/steps and logs inspected. All four receipts parsed: 41 legacy/nine model assertions true per host, unchanged archives/hosts and no system development toolchain at runtime. Signed probe checked code/entitlements, allowed workspace/private-tmp access and denied outside credential/symlink reads, write/chmod and loopback. The local native-inclusive repeat also passed (819 passed, 15 Mac exclusions, 218.6 seconds) and both formatter floors pass. Only the MCP test changed after `c774557`: runtime/native/SDK/package bytes and the verified local archive are unchanged. Closes the internal repair-platform gate; independent coverage/acceptance, scan and P25 remain open. Deliberate service-crash cleanup and the earlier discovery flake's root cause remain unconfirmed |
| P24 internal-audit first hosted matrix `c774557` | [Run 39091156765](https://github.com/lexlapax/ipse/actions/runs/39091156765) passed Ubuntu source/demo/package and both installed proofs: 834 tests, zero failures, 32 exclusions; 41 legacy/nine model assertions true with unchanged archive/host and no system development toolchain. Mac ordinary suite reported 834 tests, one failure, 32 exclusions; enforcement/package/proof steps were skipped | The older MCP post-dispatch-loss test fetched Session info after `done: error`, but unconfirmed cleanup may already have stopped it normally. The log shows `GenServer.call(:info)` exiting `normal`, not a failed unknown/no-replay assertion. Test-only follow-up `7810925` captures identity before dispatch, quiesces either lifetime path before history reads, asserts normal DOWN and validates restored context. Runtime/native/package code is unchanged; both formatter floors and all eight MCP Session fixtures pass locally. This failed matrix is not a Mac pass; the follow-up must exercise all skipped gates |
| P24 internal adversarial audit `c774557`, Linux Serenity, 2026-10-17 | Reproduced N-A1/N-A2, display/Unicode faults and IA1–IA5. Final build, both Elixir formatter floors, strict compile, isolated credential-free demo and native-inclusive suite pass: 819 passed, 15 macOS-only exclusions. Package verification and both independently precompiled installed proofs pass; archive SHA-256 `82146e7ffd6ca6201f0ccba7052760c1f06e8ef4085231e64bae1517070f6bbe`. All 41 legacy/nine model checks are true, archive/host unchanged and no system development toolchain on runtime PATH. Subsequent hosted results and the test-only follow-up are recorded above | [Internal report](architecture-self-audit.md) records eight reviewed boundaries, actual selected test-body inspection, controlled pre-fix failures and explicit omissions. Covers diagnostic/question recovery, source corruption, stream transport/admission, default 8 MiB response bound, nested/MCP cleanup and pre-attachment owner loss. Deliberate service-crash cleanup remains unconfirmed (`safe_to_continue: false`); no live account, independent acceptance, scan or P25 execution |
| P24 corrected hosted matrix `091b2bd` | [Completed Ubuntu/macOS run](https://github.com/lexlapax/ipse/actions/runs/39086249225) passed build/format/strict compile, ordinary suites (822 tests, zero failures, 32 exclusions on each host), demo, package verification and both installed proofs per host. Enabled Mac subset: 34 tests, zero failures, six exclusions, plus one Rust policy test and signed App Sandbox enforcement | Exact source, terminal jobs/steps and logs inspected. All four proof receipts parsed: 41 legacy/nine model assertions true per host, unchanged archives/hosts and no system development toolchain. Mac signed probe verifies code/entitlements, workspace/private-tmp access and denial of outside credential/symlink reads, write/chmod and loopback. Confirms fixture scheduling/readiness and current repair-platform scope; the earlier discovery flake's root cause remains unconfirmed. Deliberate service-crash cleanup remains unconfirmed. No live account, architecture acceptance, scan or P25 claim |
| P24 fixture readiness/scheduling follow-up, Linux Serenity, 2026-10-17 | All 23 stream/catalog tests and the full native-inclusive suite passed again (807 passed, 15 Mac exclusions); both formatter floors pass. The mixed-peer case waits for the healthy required consumer to drain before blocking on the optional peer and bounds test observation separately from the five-second runtime deadline. The two real-VM catalog cases retain every assertion and their five-second protocol setting in `catalog_stdio_test.exs` | Runtime/native/package/proof code is byte-unchanged from `db7af4e`; the existing local archive and installed receipts still describe those bytes. Hosted macOS must exercise the fixture correction and previously skipped gates. Serialization addresses fixture contention exposure, not proof of the older discovery flake's root cause |
| P24 role/text hosted `db7af4e`, first matrix | [Run 39085307497](https://github.com/lexlapax/ipse/actions/runs/39085307497) completed Ubuntu successfully: 822 tests, zero failures, 32 exclusions, demo/package/verifier and both installed proofs. Parsed Linux receipts have all 41 legacy/nine model assertions true, unchanged archive/host and no system development toolchain. macOS ordinary suite reported 822 tests, two failures, 32 exclusions; later enforcement/package steps were skipped | New mixed-peer closure was delivered just after its 6.5-second observation deadline; it now establishes required-client readiness before pressure and allows scheduler grace without changing the five-second delivery policy. Existing MCP catalog discovery failed before dispatch, with a late initialization response logged nearby; the precise cause remains unconfirmed. Real-VM catalog tests move to a synchronous module with all assertions and the configured five-second protocol deadline intact. This matrix is not a macOS pass or architectural acceptance |
| P24 role/text/catalog/login repair local handoff, Linux Serenity, 2026-10-17 | Controlled fixtures reproduced optional pressure failure, skill shadow drift, login-lock contention/stale callback and approval redraw amplification. Final 66 streaming/question/CLI/conformance checks passed. Build, Elixir 1.18.4/1.20.4 formatting, strict compile, full native-inclusive suite (807 passed, 15 Mac exclusions), isolated demo, package verifier and both precompiled installed proofs passed. Archive SHA-256 `099eb006c372786c57cef3f4f36142ce4715bbd57c1df48d42952612d6a75b09` | Optional detachment, required completion/loss with retained paid usage, lower-role references/helper input, pinned skill catalogs, refresh/logout races (including empty logout), inert torn-ledger handoff and preserved native history use synthetic/local fixtures only. Three full-suite assertions and one bundled demo still assumed the old header shape; corrected fixtures pass without weakening authority/recovery checks. All 41 legacy/nine model proof assertions are true, archive/host unchanged, no system development toolchain; deliberate service-crash cleanup remains unconfirmed. Documentation: 113 documents/1,469 links, zero errors. Hosted checks are next. PA-13 latency and D6 refusal remain explicit; no new live provider, scan or architectural acceptance |
| P24 PA-3/PA-9–PA-11 hosted `451f97c` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39082545732) passed source, demo, package verification and both installed proofs. Ordinary suites: 805 tests, zero failures, 32 exclusions per host; enabled Mac subset: 34 tests, zero failures, six exclusions, plus Rust policy and signed App Sandbox checks | Exact terminal jobs/steps and logs inspected; four receipts parsed, 41 legacy/nine model assertions all true per host, unchanged archives/hosts, no system development toolchain. Deliberate legacy service-crash cleanup remains unconfirmed. Confirms this increment, not the next role/stream/catalog batch or architectural acceptance |
| P24 startup measurements, Linux Serenity, 2026-10-17 | `MIX_ENV=test mix run scripts/measure-session-startup.exs` opens synthetic legacy histories without inference/effects. Before/after one sample per size: 8 MiB/50 questions 714.6/706.6 ms; 32 MiB/100 questions 5,006.5/4,919.0 ms; 64 MiB/200 questions 20,463.7/20,117.4 ms | No material latency improvement. Ordinary message/action accumulation and repeated full question-prefix validation are reduced; canonical prefix JSON encoding/hashing, full startup passes and unbounded history remain. These are measurements, not medians, universal latency bounds or actual self-development-tree evidence |
| P24 PA-3/PA-9–PA-11 local handoff, Linux Serenity, 2026-10-17 | Approval, duplicate-receipt and framing defects reproduced before repair. Eighty validation/delegation tests and 67 cleanup-focused tests passed; the integration follow-up passed 55 native-inclusive tests. Build, both formatter floors, strict compilation, full native-inclusive suite (790 passed, 15 Mac exclusions), isolated demo, package verifier and both precompiled installed proofs passed. The final portable cleanup fixture passed all four tests. Archive SHA-256 `2684474a5f1d84e914c506c2516e6f86367cf4f1b167bf4215257699d92f932c` | Real shell/extension helpers deliberately stopped with SIGSTOP refuse confirmed cleanup; ordinary closure and task-owned lock release require helper receipts. Forced watchdog exit remains distinct from returned-error cleanup. Installed proofs: all 41 legacy/nine model assertions true, unchanged archive/host, no system development toolchain; deliberate service-crash cleanup remains unconfirmed. Documentation: 113 documents/1,466 links, zero errors. Hosted Linux/macOS checks are pending; these fixtures do not prove detached containment or uninterruptible-IO termination |
| P24 PA-5/PA-6 hosted `42d9f1f` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39080827277) passed source, demo, packaging and both installed proofs on both hosts. Ordinary suites: 796 tests, zero failures, 32 exclusions each; enabled Mac subset: 34 tests, zero failures, six exclusions, plus Rust policy and signed App Sandbox checks | Terminal jobs/steps and exact logs inspected. All four installed receipts parsed: 41 legacy/nine model assertions per host, all true; archive/host unchanged and no system development toolchain. Deliberate legacy service-crash cleanup stays unconfirmed. This verifies the egress increment, not later cleanup changes or architectural acceptance |
| P24 PA-5/PA-6 local egress handoff, Linux Serenity, 2026-10-17 | Shared URI/proxy policy uses existing OTP and Finch/Mint clients. Forty focused tests and the full native-inclusive suite passed (781 passed, 15 Mac exclusions), as did build, Elixir 1.18.4/1.20.4 formatting, strict compilation, isolated demo, package verifier and both prebuilt installed proofs. Archive SHA-256 `13392ce91ada3c5491ac43e9ed9dfa3bd1934ee2ac803e612242f0e237874d0e`; all 41 legacy/nine model assertions true, unchanged archive/host, no system development toolchain | Actual local CONNECT proxies observed auth, inference and MCP destinations; proxy rejection never falls back to direct egress. MCP proxy authorization is distinct from origin bearer headers; unsupported proxy schemes refuse, and CLI remote-cleartext endpoints fail before credential acquisition. No live auth/provider/MCP account or remote origin was contacted. Hosted Linux/macOS verification is pending. Deliberate legacy service-crash cleanup remains unconfirmed; remaining PA findings, policy decisions and coverage stay open |
| P24 follow-up A1–A5 hosted `b5297be` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39077065133) passed source, demo, package verifier and both independent installed proofs on both hosts. Ordinary suites each reported 792 tests, zero failures, 32 exclusions; enabled Mac subset: 34 tests, zero failures, six exclusions, plus one Rust policy test and the signed App Sandbox probe | Exact source hash, terminal jobs/steps and logs inspected. Four actual proof receipts parsed: 41 legacy/nine model assertions on each host, all true, archive/host unchanged and no system development toolchain. The signed Mac probe verified codesigning/entitlements and workspace/private-tmp access with outside reads/write/chmod and loopback denied. Deliberate legacy service-crash cleanup remains unconfirmed/`safe_to_continue: false`. Closes scoped repair platform verification; fresh independent architectural coverage, the earlier unconfirmed MCP discovery flake's root cause and the baseline scan remain open. Fresh-session handoff pins this source; only documentation changed afterward |
| P24 follow-up A1–A5 local handoff, Linux Serenity, 2026-10-17 | Before-fix fixtures reproduced displaced approval text, raw writer-call timeout and oversized question-ID admission. Repaired focused suite: 109 passing tests, plus the subsequent real two-child CLI/HTTP regression. Final build, both Elixir 1.18.4/1.20.4 formatters, strict compile, full native-inclusive suite (777 passed, 15 Mac exclusions), isolated demo, package verifier and both independently prebuilt installed proofs passed. Archive SHA-256 `cdfb72e897b56f236bce362d5db47bc8c57b019866c1535b9ee3bd6da3a750d7`; 41 legacy/nine model assertions, unchanged archive/host and no system development toolchain | Real sibling read versus shell approval; controlled writer stalls beyond five seconds, provider cleanup and an actual completed shell effect restored unknown without replay; valid 256-byte ASCII/multibyte/opaque questions resume and answer while oversized IDs refuse before admission. Package checks exercise the shipped validator/source binding and definite missing-parent refusal. Stalls suspend the writer callback, not kernel fsync; no power-loss proof or stronger latency/retention boundary. Hosted Ubuntu/macOS checks remain pending. Deliberate legacy service-crash cleanup remains unconfirmed/`safe_to_continue: false`. Documentation links/anchors: 111 documents, 1,449 links, zero errors |
| P24 S2/design hosted `b570ef8` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39073948838) passed all applicable source/package/installed checks and both Mac enforcement steps. Ordinary suites each reported 786 tests, zero failures, 32 exclusions; the enabled Mac subset reported 34 tests, zero failures, six exclusions plus Rust and signed App Sandbox probes | Exact source revision, terminal jobs/steps and logs inspected. Actual Mac checks cover retained group ownership, inherited ignored-SIGCHLD handling, signature verification and native enforcement. Both independent installed proofs pass with unchanged archive/host; deliberate service-crash cleanup remains unconfirmed. Closes S2's platform scope. The follow-up brief targets this source, and the original prompt is archived; independent omitted-surface coverage and the baseline scan remain open |
| P24 S2/design local handoff, Linux Serenity, 2026-10-17 | Source confirms post-reap numeric group references in shell/stdio/signature checks; isolated Rust and integrated process probes verify retained ownership, inherited ignored-SIGCHLD handling, late signal refusal and EOF-confirmed child exit after abrupt helper loss. Build, actual Elixir 1.18.4/1.20.4 formatters, strict compile, 49 process/native and 43 design/accounting/extension checks, 771 full native-inclusive tests (15 Mac exclusions), isolated demo, package verification and both prebuilt installed proofs passed. Archive SHA-256 `744790c8a6eaa508dbac4a6bd898df13f2f6066cb4f0fae00388c5278287ca2e`; 41 legacy/nine model assertions, unchanged archive/host and no system development toolchain | No forced PID reuse or stronger detached-descendant claim. One extra inert group owner per invocation; no dependency. Design fixtures verify real lease expiry with inert diagnosis/handoff and current shared-overdraw refusal/accounting, not live providers or full child scheduling. Hosted Mac/native signature validation remains open; deliberate terminal service-crash cleanup remains unconfirmed/`safe_to_continue: false` |
| P24 S1/S3 hosted `fe54206` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39073011423) passed all applicable source/package/installed checks and both Mac enforcement steps. Ordinary suites each reported 783 tests, zero failures, 32 exclusions; the Mac subset reported 34 tests, zero failures, six exclusions plus Rust and signed App Sandbox probes | Exact revision, terminal jobs/steps and logs inspected. Both installed large-Unicode-delta probes passed, as did the unchanged-runtime independent artifacts. Closes the caller/owner and oversized-visible-delta platform scopes; the later group-identity candidate and independent omitted-surface review remain separate |
| P24 S1/S3 local handoff, Linux Serenity, 2026-10-17 | Controlled approval/cancel timeouts and killed CLI ownership failed before repair; a gated 138 KB Unicode delta separately reproduced `invalid_chunk` closure. Build, actual Elixir 1.18.4/1.20.4 formatters, strict compile, 50 related tests, 768 native-inclusive tests (15 Mac exclusions), isolated demo, package verification and both prebuilt installed proofs passed. Archive SHA-256 `15f68dd18a81f296eccedbe031b2cc591e11cb5f99eb7908ddc7934d9ab92ca0`; unchanged archive/host, 41 legacy/nine model assertions, no system development toolchain | CLI now owns its root Session, reports unconfirmed request exits without retry and closes its reader; bounded cleanup can still remain unconfirmed. Large visible deltas preserve exact Unicode, original UI/native response and contiguous v2 ranges while direct push/pressure bounds remain strict; new installed large-delta probe passed. Hosted validation and the separate process-group concern remain open. Deliberate terminal service-crash cleanup remains unconfirmed/`safe_to_continue: false` |
| P24 F7 hosted `be11890` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39072420144) passed all applicable source/package/installed checks and both Mac enforcement steps. Ordinary suites each reported 778 tests, zero failures, 32 exclusions; the Mac subset reported 34 tests, zero failures, six exclusions plus the Rust and signed App Sandbox probes | Exact revision, terminal steps and logs inspected. Mac filesystem checks established case/normalization alias inode identity before metadata denial, alongside portable parallel-child alias cases and installed metadata probes. Closes F7's platform scope; S1/S2/S3 and independent coverage remain separate |
| P24 F7 local handoff, Linux Serenity, 2026-10-17 | Both metadata and parallel case-alias regressions failed before repair. Build, actual Elixir 1.18.4/1.20.4 formatters, strict compile, 18 focused tests, a clean serial 763-test native-inclusive run (15 Mac exclusions), isolated demo, package verification and both prebuilt installed proofs (41 legacy/nine model assertions) passed. Archive SHA-256 `fca624924d8b9256e562b4dd2a78f08ac0bc486ed6c09b6de3f18531f10e4103`; archive/host unchanged, no system development toolchain in installed proofs | Conservative case/normalization/format-control denial and original execution paths; actual Mac alias enforcement awaits hosted CI. One new installed assertion initially used Unicode directly in a C-locale eval argument; the fixture now constructs explicit UTF-8 bytes and passes without runtime changes. An earlier full pass overlapped a helper rebuild and was discarded; the reported baseline ran serially. Existing deliberate service-crash cleanup remains unconfirmed/`safe_to_continue: false` |
| P24 F4 hosted `200640e` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39071506109) passed source/package/installed checks and both Mac enforcement steps. Each ordinary suite reported 775 tests, zero failures, 31 exclusions; the Mac subset reported 33 tests, zero failures, six exclusions plus the Rust and signed App Sandbox probes | Exact revision, terminal jobs/steps and logs inspected, including both independent installed proofs and unchanged archive/host assertions. Closes F4's platform gate within the documented persistence contract. Alias changes and the remaining architecture concerns/omissions need separate verification |
| P24 F4 final local handoff, Linux Serenity, 2026-10-17 | Build, actual Elixir 1.18.4/1.20.4 formatters, warnings-as-errors compile, 761 native-inclusive tests (14 Mac exclusions), isolated demo, ordinary package verification and both prebuilt independent artifacts (41 legacy and nine model assertions) passed. Archive SHA-256 `4cd88cb2b06b09d48df64a26397864fa1718c2dc8440ba7882019614492fe0cd`; archive/host bytes unchanged and no system development toolchain in installed proofs. Documentation check: 109 documents, 1,426 relative links, no errors | Writer ownership/loss, source offsets, corruption and file-change refusal, steady CPU/memory, valid external ledger tails, same-size prefix rewrite/invalid suffix refusal, chronological reads and duplicate-attempt integrity. Existing rollback, historical peaks, child/model/history/feed recovery and installed compatibility remain passing. Two development fixture/startup issues were corrected before this baseline: invalid usage test sessions and premature writer linking on rejected initialization. Hosted gate remains open; persistence/growth limits are explicit in the journal contract |
| P24 recovery/floor hosted `324bff1` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39069878607) passed all applicable source/package/installed proofs and both Mac enforcement steps. Both ordinary suites reported 766 tests, zero failures, 31 exclusions; the Mac subset reported 33 tests, zero failures, six exclusions plus the Rust and signed App Sandbox probes | Exact revision, terminal job/step conclusions and logs inspected. Both hosts passed the new installed shell-uncertainty, one-use historical-result and project sandbox-floor assertions. Closes F2/F5/F6 platform scope; the later persistence candidate and F7/omitted coverage remain open |
| P24 F4 development probes, Linux Serenity | On Btrfs, five-append median latency at 2/16/64 MiB changed from the unchanged stateless path's 6.726/41.943/164.200 ms to the owned path's 1.398/1.422/1.527 ms. Actual Session denial/approval handling measured 3.576 ms at 2 MiB and 3.386 ms at 64 MiB. Usage restore at 8,000 admissions changed from 2,777 ms to about 117–120 ms. A 10,512,683-byte ledger took about 605 ms for initial validation, then 17.8/19.5 ms for warm protected reads; the old uncached reads were about 696–731 ms | Synthetic records, actual native locks, local temporary and Btrfs probes. The initial journal/uncached accounting probe used tmpfs; the paired Btrfs journal probe and actual Session check distinguish filesystem effects. No universal latency/power-loss guarantee. Live ledger reads still verify full prefixes; journal startup/growth and same-size rewrite limits remain explicit. One hundred related integrity/history/feed/model/accounting tests passed during iteration; full/platform checks pending |
| P24 tool recovery and sandbox floor, Linux Serenity, 2026-10-17 | Real helper loss after a scratch-file effect and a failing output consumer reproduced definite-error misclassification. Live duplicate/invalid identities reproduced approval/execution; a corrected historical fixture separately reproduced result reuse. Both approved sandbox-floor assertions failed before repair. Final build, actual Elixir 1.18.4/1.20.4 formatters, warnings-as-errors compile, 108 focused checks, 752 native-inclusive tests (14 Mac exclusions) and isolated demo passed | Unknown effects stop without replay; known validation/setup errors remain definite. Covers incomplete/oversized/invalid/contradictory frames, one-use historical results, durable original/native refusal evidence outside effective context, inert resume and project-only sandbox tightening with operator environment/CLI authority. One initial historical fixture omitted its required header; it was corrected before the old-code reproduction and final checks. Hosted gate remains open |
| P24 recovery/floor extracted runtime | Ordinary verifier passed the new installed shell-uncertainty, one-use historical-result and project sandbox-floor assertions. Both prebuilt independent artifacts passed all 41 legacy and nine model assertions with unchanged archive/host bytes and no system development toolchain. Archive SHA-256 `154ceaaf1c5eafc5678dc767ed0a8dacf1b74f9e11703cce63a171573a7caa98` | Real owned helper loss in the extracted package, synthetic history/configuration, no model account. Deliberate service-crash cleanup still remains unconfirmed/`safe_to_continue: false`. No stronger OS, external account or F4/F7 completion claim |
| P24 F3 hosted `3bd99af` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39068946286) passed all applicable source/package/installed proofs and both Mac enforcement steps. Both ordinary suites reported 757 tests, zero failures, 31 exclusions; the enabled Mac subset reported 33 tests, zero failures, six exclusions plus the Rust and signed App Sandbox probes | Exact revision, terminal jobs/steps and logs inspected, including both packaged terminal/JSON assertions. Closes F3's platform gate; does not certify the later recovery/floor candidate or close F4/F7/P24 |
| P24 F3 source/package, Linux Serenity, 2026-10-17 | Real native-lock reproduction left canonical input 60 versus ledger booking 40 and refused resume before tail repair. Three new assertions failed against the old implementation. After repair: build, both actual formatters, warnings-as-errors compile, 41 focused usage/budget checks, 743 native-inclusive tests (14 Mac exclusions), isolated demo, ordinary package verification and both installed proofs (41 legacy and nine model assertions) passed. Archive SHA-256 `cfcb5565120296200fca94ee610a5e6148988d1978e5bcc2f7671a7ef587f018` | Covers write-ahead publication, real observation-lock refusal with unchanged idle resume, worker death between commit/publication, preserved committed overdraw, uncovered final settlement refusal and existing forged/rollback/peak checks. Failed writes leave unavailable counters and unknown liability, not exact consumption. No validation relaxation or historical-state repair. Hosted gate subsequently passed as recorded above |
| P24 F4 journal scaling probe, Linux Serenity | Five appends at each prepared journal size gave median 5,279 µs at 2 MiB, 36,365 µs at 16 MiB and 144,202 µs at 64 MiB, with 2 KB synthetic records | Confirms increasing append cost in the current repeated-read/decode path. Does not measure a complete Session approval timeout, ledger contention or another OS; F4 remains open |
| P24 F2 source, Linux Serenity, 2026-10-17 | Both endpoint-authority regressions failed before repair; the real CLI loopback fixture observed the synthetic Authorization credential. The real helper approval test separately failed for absent destination facts. After repair: build, actual Elixir 1.18.4/1.20.4 formatters, warnings-as-errors compile, 740 native-inclusive tests (14 Mac exclusions), isolated demo and 78 focused authority/provider/helper/delegation checks passed. Four source artifact/destination checks and both published JSON examples through the actual local config CLI also passed | Project endpoints and operator-ID replacement refuse before session creation/HTTP dispatch. Operator custom roots, project default-endpoint profiles/roles, URI/port bounds, private-path exclusion, origin/target binding and parallel/nested model approvals retain their contracts. Synthetic credentials/loopback only; no new live inference or billing claim. The sandbox-precedence decision remains pending |
| P24 F2 extracted package and independent artifacts | Ordinary verifier passed archive SHA-256 `130fd539bf2ffea4f1f96dc45b3aa2b8800f9ffdf6c90bc7d31c4ee62e62b38a`. Previously built artifacts passed all 41 legacy-lab assertions and the nine-assertion model proof, now also checking real destination disclosure, with unchanged archive/host bytes and no system development toolchain at runtime | Existing ABI exercised on this new host; no new production memory/backend claim. The deliberate terminal service crash retains unconfirmed cleanup and `safe_to_continue: false`. Hosted platform gates subsequently passed as recorded below; these results do not close F3–F7 or omitted architecture coverage |
| P24 F2 hosted `e7a5458` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39067819404) passed every applicable source/package/installed proof and both Mac enforcement steps. Both ordinary suites reported 754 tests, zero failures, 31 exclusions; the Mac enforcement subset separately reported 33 tests, zero failures, six exclusions, plus the Rust and signed App Sandbox probes | Exact revision, terminal job/step conclusions and logs inspected. Both packaged terminal/JSON checks passed, as did the strengthened model proof. Closes endpoint/profile/disclosure platform scope; the separate sandbox-precedence choice and F3–F7 remain open |
| P24 F1 hosted `0420e7a` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39065988548) passed all applicable build/format/compile/test/demo/package steps, both installed proofs and both Mac enforcement steps. Both ordinary suites reported 748 tests, zero failures, 31 default exclusions; the separately enabled Mac subset reported 33 tests, zero failures, six exclusions plus the Rust and signed App Sandbox probes | Exact revision and terminal job/step conclusions inspected; logs confirm the new packaged CLI terminal/JSON assertion passed on both hosts. F1's platform gate is closed. No live paid provider, personal Mac/device or completion of F2–F7/P24 is claimed |
| Earlier documentation-only `3dd7110` hosted | [Failed matrix](https://github.com/lexlapax/ipse/actions/runs/39063011931): Ubuntu passed; Mac reported 743 tests, two failures, 31 excluded. Both failures were MCP catalog stdio discovery before dispatch (`test/mcp/catalog_test.exs:340` and `:371`); later Mac checks were skipped | Failed log inspected. The F1 matrix above passed afterward without an MCP runtime change. This is recurring unconfirmed transport/startup behavior, not a fixed defect or a reason to increase deadlines/weaken assertions without evidence |
| P24 first critique, 2026-10-17 | Operator returned the independent source-only report: seven findings, three unverified concerns and nine design/limit items, with explicit omissions and no executed tests | Original report remains in the private operator conversation. The sanitized disposition register separates checked source paths, supervisor reproductions and unresolved coverage; a partial static review is not architectural acceptance |
| P24 F1 source, Linux Serenity, 2026-10-17 | Real CLI regression failed before repair. Final actual Elixir 1.18.4/1.20.4 formatters, warnings-as-errors compilation, 734 native-inclusive tests (14 macOS exclusions), isolated demo and 29 focused terminal/CLI/session-listing tests passed | Synthetic controls/formats across live provider text, presentation, tool views/results, errors and a real write approval; full arguments remain visible, EOF denies the write, journal/provider content stays original. Malformed/split output is inert, JSON round-trips supplementary characters and Unicode/latin1 IO devices/aliases preserve UTF-8. No new dependency, actual terminal UI visual check or live provider claim |
| P24 F1 extracted package and compatibility | Ordinary verifier passed archive SHA-256 `8e94981c8ea260fd6b5ba06fbaa7ab9a5ee2c437035e9773effa5c52d7be89d5`, including new actual CLI human/JSON checks under its restricted C locale and unchanged listing journal. Previously built independent artifacts passed all 41 legacy-lab and nine model-lab assertions with unchanged archive/host bytes and no system development toolchain | The installed probe initially caught Unicode IO rewriting JSON under latin1, then alias-aware device handling fixed the unchanged assertion. JSON stdout is checked separately from VM diagnostics. Deliberate terminal service-crash cleanup remains unconfirmed/`safe_to_continue: false`. Hosted Linux/macOS subsequently passed as recorded above; other findings and incomplete review coverage keep P24 open |
| P24 preparation, 2026-10-17 | Operator selected their Claude subscription. Prepared 325 committed files from `21e59fe` plus brief/revision/exclusions/manifest; all archive entries and source hashes verified. Read-only connected Security Cloud checks found access, the exact repository and available credits; the environment search returned none | No external critique, scan, environment creation, API charge, billing change or recurring monitoring. Raw review findings remain private. The operator must return the initial independent critique before triage and the baseline security audit |
| P23F hosted `21e59fe` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39061878457) passed every applicable build/format/compile/test/demo/package step, both independent installed proofs and both macOS enforcement steps. Both ordinary suites reported 743 tests, zero failures, 31 default exclusions; the Mac enforcement subset separately reported 33 tests, zero failures, six exclusions, plus a passing Rust policy test and signed App Sandbox probe | Exact SHA and terminal job/step conclusions and logs inspected. Both model-artifact proofs passed all nine assertions with unchanged archive/host bytes and no system development toolchain. Hosted archives: Mac `a73a322f81234ecb1dca3137e1c38ea986bbe1ecdf504d18a30d1a6db1694130`; Linux `e6d74c7f49a25ce733f41993e2c06af6f9d40c52edf67eb788e59a1f868db7d7`. Closes P23's scoped platform gates; no live paid/helper account, local Mac device, stronger detached cleanup or P24/P25 review claim |
| P23F source, Linux Serenity, 2026-10-17 | Final build, actual Elixir 1.18.4/1.20.4 formatting, warnings-as-errors compilation, 729 native-inclusive tests and isolated CLI demo passed (14 macOS-only exclusions). During development, 147 model/delegation/budget/profile/report checks passed; the strengthened combined model/cost recovery regression and related cached-page/child set passed 25 checks before the final full suite | Actual separate-profile loopback inference, full approvals/denial, two simultaneously open child HTTP requests under one quota, nested egress approval retaining the enclosing mutation lease, overdraw, byte/deadline limits, cancellation/worker/session death, strict source/cached-result validation and unchanged resume. The combined artifact proof exposed skipped model action sources during usage-read recovery; recovery now folds all canonical events before validating cached snapshots. Fixture credentials/counters/rates only; no new live provider/account claim. Hosted verification passed as recorded above |
| P23F extracted package and model artifact | Ordinary verifier passed archive SHA-256 `3a3103d665bb4af256105d7ae9916523e8ab0df3fd709e28362ff75970c7cc72`. The independently built model artifact passed all nine source/installed assertions, including actual helper-cost aggregation and cached recovery, with unchanged archive/host files and no system development toolchain on the runtime path. Previously built seven-artifact compatibility fixtures also passed all 41 installed assertions against this archive, retaining unchanged archive/host bytes | Explicit synthetic Ollama profile, private native response and bounded text, canonical usage, configured local estimate, shared main/helper refusals and byte-unchanged journal/budget resume. The compatibility lab's deliberate terminal service crash retains unconfirmed cleanup and `safe_to_continue: false`. Hosted Linux/macOS subsequently passed as recorded above |
| P23E2 hosted `a815d06` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39052820111) passed every applicable build/format/compile/test/demo/package/installed-lab step, plus both macOS enforcement steps | Exact commit and terminal job/step conclusions inspected: eight required shared steps on Ubuntu and ten on macOS. Confirms this budget/auth candidate on hosted systems, not live paid billing, local Mac device use or P25 self-development. Accounted extension model operations remain open; reviews and deferred media are not exercised |
| P23E2 shared admission, Linux Serenity, 2026-10-17 | Final frozen build, actual Elixir 1.18.4/1.20.4 formatters, warnings-as-errors compilation and 709 native-inclusive tests passed (14 macOS exclusions). Final budget/config/profile/child-SDK set: 50 passed. The earlier 19-case concurrency set passed 31 consecutive runs. Published operator JSON and actual CLI budget inspection/saved-policy resume passed with zero model requests; isolated demo passed | Atomic parallel booking, main/compaction/child quotas, known release, uncertain holds, observed/final-only overdraw, final counters despite unconfirmed settlement, money basis/currency/overflow, profile inheritance, live/resumed rollback and pre-repair refusal. New parent/child historical-peak cases failed before the validator repair and passed afterward. Refusals cannot conceal canonical usage. No paid inference, operator-wide quota or invoice-ceiling claim; accounted extension model operations remain open |
| P23E2 extracted package and installed compatibility | Ordinary verifier passed archive SHA-256 `5835224ef54a31ae3c3c1b93a3fc14e1a7972f7f27a1486d251237b773c6410c`, including the shared source/release budget fixture. Previously built independent artifacts passed all 41 installed-lab assertions against this archive; archive/host bytes stayed unchanged, temporary CLI selection ran and no system development toolchain was available | Real synthetic parallel parent/child requests share three admissions and the parent follow-up refuses; separate last-slot fixtures retain bookings under fail-fast sibling cancellation. Default-off and direct idle resume preserve state. The lab's deliberate terminal service crash still has unconfirmed cleanup and `safe_to_continue: false`. Hosted Linux/macOS follow-up passed as recorded above |
| P23E1 provider output ceilings, Linux Serenity, 2026-10-17 | Build, actual Elixir 1.18.4/1.20.4 formatters, warnings-as-errors compilation and final 685-test native baseline passed (14 macOS exclusions). Final provider/config/profile/report compatibility set: 54 passed. Actual CLI help/demo, both published JSON examples, output-cap inspection and saved-policy resume passed in isolated state with zero model requests | Supported wire caps, lower summary/child bounds, explicit subscription refusal, Ollama length termination retaining usage without tools, strict numeric/removed/changed policy refusal before tail repair and absent legacy cap recovery. No paid inference or live provider enforcement claim; shared reservations and accounted extension model operations remain open |
| P23E1 extracted package and installed compatibility | Ordinary verifier passed archive SHA-256 `7f473adf6a5292f699b85df6f59da34f5f3582f745cb7d0bd632619f340b6c05`, including capped-policy fixtures and inert resume. Independent installed lab passed all 41 assertions with unchanged archive/host bytes, actual temporary CLI selection and no system development toolchain | Compatibility on this candidate, not a new claim about P22's frozen core. Deliberate terminal service crash keeps unconfirmed cleanup and `safe_to_continue: false`. Hosted results are recorded separately below |
| P23E1 hosted `1fe5514` and auth cleanup repair | [Completed matrix](https://github.com/lexlapax/ipse/actions/runs/39047576717): macOS passed; Ubuntu failed `rotating refresh is serialized and atomically replaces the entire token set` at `test/auth_test.exs:191`. Ubuntu reported 699 tests, one failure, 31 excluded; subsequent steps were skipped. An unmodified local repeat reproduced the failure within 30 runs. In-memory diagnostics then caught `port_close` raising after the helper's error response; the outer rescue replaced native contention with `argument error` | Failed-lock cleanup now reuses idempotent `Runner.unlock/1`. The unchanged refresh fixture passed 301 consecutive local runs; 23 focused auth/runner tests passed, including 128 contending helpers with exact retryable-response checks, stable inode and subsequent acquisition. The final P23E2 baseline above also passes. Synthetic credentials only; no retry/deadline change, weakened assertion or live-account claim. The hosted P23E2 matrix above also passed; later runtime changes need their own baseline before freezing P25's runner |
| P23D hosted follow-up `84597b4` | [Completed Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39046213259) passed every applicable build/format/compile/test/demo/package/installed-lab step, plus both Mac enforcement steps | Actual job/step conclusions inspected. Eleven focused catalog tests also passed on Linux. No runtime fix, deadline increase or automatic retry was introduced; the preceding Mac failure remains unreproduced with cause unconfirmed. Output-cap changes need their own hosted result |
| P23D hosted `03d4187` | [Completed matrix](https://github.com/lexlapax/ipse/actions/runs/39044897250): Ubuntu passed; macOS failed `stdio integration supports resource-only and prompt-only capability sets` at `test/mcp/catalog_test.exs:324`, with `MCP transport failed before tool dispatch` | Actual job/step conclusions and failed log inspected. Mac reported 690 tests, one failure, 31 excluded; later native/demo/package/installed-lab checks were skipped. Cause is unconfirmed; no passing replacement run is claimed |
| P23D child-accounting SDK/report, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, actual Elixir 1.18.4/1.20.4 formatters and final 675-test Linux native baseline passed (14 macOS exclusions). Seven final child fixtures passed, including the additional legacy case; the earlier report/summary/registry set passed 22 tests. Exact documented tree configuration passed three real CLI command checks with zero model requests; help/demo passed | Actual serial/parallel children, final cumulative replacement, failed-child partial usage, caller/child scope, frozen prefixes, accounting-only fingerprints, missing/busy/unsafe/oversized/legacy gaps, cached-counter forgery refusal, pre-repair validation and inert resume. Index exhaustion refuses new discovery while preserving admitted ranges. Atomic budgets and accounted extension model requests remain open |
| P23D extracted package and installed compatibility | Final archive SHA-256 `492b4264cbd08dd34f46ccc91ef5fe8accceae2e3136412aac0cf67e54018afb` passed the ordinary release verifier, including real parallel-child reports and inert recovery. Independent installed lab passed all 41 assertions with temporary CLI selection; archive/host bytes stayed unchanged and no system development toolchain was available | Synthetic rates/providers only; no live billing or globally atomic cross-session balance claim. The lab's deliberate terminal service failure retains unconfirmed cleanup and `safe_to_continue: false`. Hosted `03d4187` failed Mac; the follow-up `84597b4` above passed both platforms without a runtime change |
| P23C hosted baseline `d81af65` | [Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39042723717) passed every applicable step: build, format, compile, tests, demo, ordinary packages, independent installed extension lab and both macOS enforcement steps | Actual job/step conclusions inspected. Confirms the summary baseline and the two corrected observation waits; the new child SDK/report requires its own hosted result |
| P23C own-session summaries, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, actual Elixir 1.18.4/1.20.4 formatters and 669 native-suite tests passed (14 macOS exclusions). Final summary fixtures: 7 passed; summary/action/job compatibility: 21 passed. Exact operator JSON passed the real CLI check with zero model requests; help/demo and extracted-package verification passed | Captured full-session enumeration across 18 pages/70 requests, cumulative replacement, admission identity, separated billing bases, partial/legacy unknowns, independent cost/counter overflow, explicit disabled parity, 10,000-read versus 16-mutation-step bounds and byte-identical idle resume. Child accounting, budgets and generic accounted model requests remain open |
| P23C installed-artifact compatibility | Existing independent lab passed all 41 assertions against archive SHA-256 `6bfc77fd173ef647399a003159220e18059dbab31abe8745ddebd77de04f0fc2`; archive and host BEAM bytes stayed unchanged within the run, with real temporary CLI selection and no system development toolchain | Compatibility on the new SDK, not a new frozen-core claim. The deliberate terminal service-crash case retains unconfirmed cleanup and `safe_to_continue: false`. New hosted Linux/macOS results must be checked separately |
| P23B hosted `f7babc0` | [Completed matrix](https://github.com/lexlapax/ipse/actions/runs/39041048982): Ubuntu passed; macOS failed two tests whose three-second observation windows preceded existing five-second worker startup/initialization bounds | Ring-refusal closure and extension-tool question waits now cover the worker budgets; both focused fixtures passed locally. Runtime deadlines/assertions are unchanged. This records the failed run, not a macOS verification claim for the fix |
| P23B granted report pages, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, both actual formatters, 26 focused reader/report/history fixtures and 662 native-suite tests passed (14 macOS exclusions). Source SDK, exact documented operator JSON/CLI check (zero model requests), help/demo and extracted-package cost fixture passed | Own-session canonical pages, source/caller binding, private exclusion, frozen prefixes beyond sixteen requests, known failures, page/source forgery refusal, snapshot ceiling, cancellation and inert resume; report basis separation, group overflow and unknowns. Whole-session/child aggregation and budgets remain open |
| P23B installed-artifact compatibility | Existing independent lab passed all 41 assertions and temporary CLI selection against new Linux archive SHA-256 `c017c6673499e4ee84103f5165c8fe5b7acd02d7133b0fdbe2cedb5e8433f4d1`, unchanged during verification | This is compatibility on the new SDK, not a claim that P23 core edits occurred inside P22's historical freeze. Host BEAM bytes stayed unchanged within the run; the deliberate terminal service-crash case still ends with unconfirmed cleanup and `safe_to_continue: false` |
| P23A hosted baseline `0008dbe` | [Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39038766880) passed every applicable step; actual job/step conclusions inspected | Calculator baseline only; later read/report/summary increments require their own hosted results |
| P23A configured estimator, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, both actual Elixir 1.18.4/1.20.4 formatters, 15 focused fixtures and 647 native-suite tests passed (14 macOS exclusions); CLI help and isolated credential-free demo passed | [Pure rate-card estimates](costs.md): exact configured identity/units/rounding, cache partitions, explicit unknowns, provenance and overflow. No rate lookup, paid call, installed report extension, accounting-read grant or budget enforcement is claimed |
| P22 hosted completion `de073ba` | [Ubuntu/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/39037702166) passed every applicable step: build, format, compile, tests, demo, ordinary packages and independent installed extension lab; macOS native and default experimental sandbox enforcement passed | Actual job/step conclusions inspected. Includes canonical bundle-path correction and 41-assertion lab; the stronger macOS escaped-descendant lifetime diagnostic remains an acknowledged limit |
| Supervised extension-only change, Linux Serenity, 2026-10-17 | Frozen installed release authored operator-only stats in two files under three exact edit approvals; a fresh read-only review found no actionable issue in scope; 41 source/installed assertions, focused integration and all 632 native-suite tests passed (14 macOS exclusions), including symlinked temporary-root verification | Actual ChatGPT subscription `gpt-6.1-sol`/high, eight author and five reviewer requests; both shipped hooks and inert idle resume verified. Runtime assertions use synthetic data/model, not live graph quality |
| Independent extension lab, Linux Serenity, 2026-10-17 | Seven artifacts compiled separately; 33 source and installed-release assertions passed, including real temporary CLI selection; eight focused tests and 632 native-suite tests passed with 14 macOS exclusions | Candidate core `3b0ef78` unchanged under `lib/`/`native/`; host BEAM bytes unchanged and domain modules never loaded in host. Synthetic extraction/corpus/model only; terminal expected service crash leaves cleanup unconfirmed and `safe_to_continue: false` |
| Ephemeral text sources, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, both actual Elixir 1.18.4/1.20.4 formatters, 25 focused fixtures and 631 native-suite tests with 14 macOS exclusions passed; real dual-version source SDK fixture, CLI help and isolated demo passed | Negotiated embedded/independent-worker delivery, unchanged v1, shared range identity with unequal chunking, UTF-8/cancelled-pending positions, idle closure, malformed bindings, no-effect replies and inert resume; synthetic provider only |
| Child outcomes, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, both actual Elixir 1.18.4/1.20.4 formatters, 55 focused fixtures and 623 native-suite tests with 14 macOS exclusions passed; serial/parallel source demos, CLI help and isolated demo passed | Authenticated parent-side result/cleanup receipts, correlation/privacy, timeout/cancellation, forged reports/source positions, exited queued-child approval refusal and inert incomplete resume; synthetic providers only |
| Admitted-tool views, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, both actual Elixir 1.18.4/1.20.4 formatters and 615 native-suite tests with 14 macOS exclusions passed; source SDK primitive, CLI help and isolated demo passed | Private input/result and metadata parity, independent live/history grants, separate write approval, reused provider IDs, unavailable views, cancellation, extension-question restart and physical-source refusal before repair; synthetic providers only |
| Live metadata feeds, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, both actual Elixir 1.18.4/1.20.4 formatters, thirteen focused feed fixtures and 602 native-suite tests with 14 macOS exclusions passed; source primitive, CLI help and isolated demo passed | Independent compiled consumers, exact metadata/acknowledgments, finite queues/receipts, pressure/timeout cleanup, question recovery and physical-source refusal; synthetic providers only |
| Runtime epochs/waits, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, both actual Elixir 1.18.4/1.20.4 formatters, 31 focused causal/recovery fixtures and 589 native-suite tests with 14 macOS exclusions passed; source fixture and isolated CLI demo passed | Recorded session/approval/question boundaries, private-source validation, disabled parity, explicit extension recording with capture off and child-loss interruption; synthetic providers only |
| Explicit history, Linux Serenity, 2026-10-17 | Build, warnings-as-errors compilation, both actual Elixir 1.18.4/1.20.4 formatters, eleven focused history fixtures and 578 native-suite tests with 14 macOS exclusions passed | Own-session fixed ranges, separate private grants, budget gaps, source/contiguous-span validation, approval/question boundaries and inert resume; synthetic provider only |
| Hosted child-outcome baseline `6b234c6` | [Ubuntu/macOS matrix, attempt 2](https://github.com/lexlapax/ipse/actions/runs/39031441379/attempts/2) passed all applicable steps: build, format, compile, tests, demo and extracted packages; macOS native/default experimental sandbox steps passed | Actual job/step conclusions inspected. Initial macOS concurrent-ring drain wait failed; unchanged failed-job retry passed. This baseline precedes v2 text sources and does not prove stronger containment or drain latency |
| Hosted v2-text candidate `3b0ef78` | [Matrix run](https://github.com/lexlapax/ipse/actions/runs/39032443735) ended with Ubuntu success and macOS test failure | The older serial MCP batch test waited five seconds despite discovery and two connections each allowing ten seconds. Its aggregate assertion now allows 35 seconds, retaining call-order/result/cleanup checks; macOS tests passed at the next baseline below |
| Hosted lab baseline `2874da0` | [Matrix run](https://github.com/lexlapax/ipse/actions/runs/39036899179) passed Ubuntu including the installed lab; macOS passed tests, native enforcement, demo and ordinary package verification, then failed the new installed-lab path assertion | macOS resolved `/var/.../release/erts-.../bin/erl` through `/private/var`; the verifier incorrectly compared lexical prefixes. Canonical bundled executable comparison passed Linux symlink-root and hosted macOS verification at `de073ba` |
| Source/extracted compatibility | Credential-free demo, bundled extension/accounting/dual-version-text/lifecycle/local-ring/conformance/history/feed/tool-view fixtures, traced conformance CLI and serial/parallel child demos passed in Linux glibc-2.44 package verification with matching OTP 29.1.1 notices and utility-only PATH | APIs work without a system toolchain; source-debugger modules/debug information are absent. Primitive tool-view positions are synthetic. The separate lab adds installed private tool/text delivery and domain catch-up without changing archive SHA-256 `93f88a3ded9666e0b2c083699932b972ad36d538614c5ed54420b253b140196d` |
| Provider acceptance | [Explicit live provider checks](#live-provider-acceptance-follow-up-2026-10-15) | Recorded account/model/platform combinations only; fixtures do not establish billing, hardware or arbitrary-model support |

Conformance fixtures exercise independently compiled tools/commands/services and
compiled built-in hooks through real Sessions with a synthetic provider. Coverage
includes trust refusal, bounded input, headless denial before code loading, approved
scratch-state recall into later request context, effective-user-text assertions,
explicit questions without write approval, cancellation, journal validation,
failure-stop behavior, private-value exclusion and CLI refusal of live/replay flags.
The documented shipped CLI fixture passes without credentials. Source/extracted
fixtures additionally check the built-in pair through the runner. Reports describe
declared assertions and Session close acknowledgments, not a separate native
containment proof or production extension quality certificate. See the
[author contract](extension-conformance.md).

Developer-trace fixtures additionally verify fixed arities and target isolation,
VM-side one-in-flight admission during a 10,000-call burst with the collector
suspended, independent deadline cleanup, owner/collector/watchdog death, explicit
stop, target exit and coexistence with another OTP trace session. Conformance
fixtures cover traced cancellation, private-value exclusion and refusal of trace
controls outside synthetic checks. These establish bounded dispatcher samples,
not a complete timeline, source-debugger integration or production tracing safety.
The extracted verifier invokes the same trace CLI with only bundled runtime and
utility executables available.

The [hosted deadline-reason failure](https://github.com/lexlapax/ipse/actions/runs/39019657244)
exposed a race between watchdog destruction
and notification of the collector. The repair claims one closing reason in a
shared atomic latch before either participant destroys settings. Report collection
can therefore perform its own cleanup without relabeling a deadline or mistaking
the watchdog's normal exit for failure. Capture bounds and wire fields are unchanged;
all nine cleanup fixtures passed 51 consecutive executions locally. The subsequent
[Ubuntu/macOS repair run](https://github.com/lexlapax/ipse/actions/runs/39020626883)
passed all applicable steps, including
extracted packages; the earlier failed run remains recorded rather than relabeled.

The answer and child-outcome baselines each had a first macOS attempt fail the
existing concurrent-ring drain wait, outside their feature assertions. Each
failed-job retry passed all steps without a code change. This is evidence of an
intermittent wait; it is not a ring runtime repair or guaranteed drain latency.

Diagnostic fixtures cover default-off parity, private/hash exclusion, shared source
identity, operator/export scope, immediate stop, bounded overload, rotation and
sampling. They exercise real blocked-worker owner-death cleanup, invalid replies
without action admission, fresh leases on idle resume without historical delivery,
corrupt receipts and optional source overflow without losing recovery records.
The independent export-capability fixture writes only local synthetic files; it
does not establish remote transfer/TLS behavior. A shutdown race found by the full
suite was repaired with one shared worker cleanup result; its focused regression
passed 31 successive executions before the full suite passed. The CLI now uses
orderly close, with an idle capture grace of at most 500 ms and explicit cleanup
failure reporting. Documented config/temporary-selection/demo commands passed
with an isolated operator home, no account and no collector.

Ring fixtures add repeated-session aggregate file/byte bounds, preservation of
mandatory journals, full-ring refusal without active-writer eviction, unchanged
lock inode identity, owner-death slot release, mismatched-limit refusal, bounded
duplicate-key/oversized catalog rejection, symlink refusal and preservation of
legacy root files. The source/extracted fixture additionally reuses a one-slot
ring across two fresh sessions through the native helper. The managed namespace
has a derived quota; unrelated/legacy files remain outside it. This is backend
retention without a new event/action API or dependency, not a lossless trace archive.

Job fixtures exercise source-bound approved writes, headless refusal, required
before-request recall, after-turn answer isolation and later context visibility.
They cover host-derived failure despite a callback's false success claim,
explicit question resume in both schedules, committed-write interruption without
idle replay, and a delayed write's captured revision conflicting with concurrent
forget. Metadata-only jobs receive neither prompt text nor private source hashes.
See the [job contract](extension-event-jobs.md). These are generic SDK fixtures,
not a production extraction algorithm or independent installed-package proof.

Answer fixtures add original/presented views sharing one occurrence, request and
effective-prompt binding, rejection of a forged presentation, metadata/disabled
parity and oversized private refusal without changing native history. They cover
after-answer storage approval, invalid notification effects, actual blocked-worker
cancel/owner-death cleanup and question recovery with an answer source and no
second inference. A native clarification regression first reproduced lost
after-turn delivery after resume; source checkpoints now preserve mixed prompt/
answer context without replaying prompt notifications. A coherently forged
checkpoint source still fails physical validation. The source/extracted projection fixture checks the new compiled
view and diagnostic wrapper APIs only; it is not installed answer-subscriber
execution in an extracted package. That stronger proof remains part of the
independent frozen-core package gate.

History fixtures use real independent SDK commands for bounded catch-up, separate
write denial, a saved-range question continuation and cancel/owner-death cleanup.
Primitive cases cover metadata/native exclusion, distinct recorded views, missing
or changed anchors, fixed-boundary reads past later oversized/torn data, page splits
without truncation and explicit gaps. Coherently altered text or omitted source
spans fail physical validation; a genuine budget gap survives resume. Validation
checks cached references without rerunning reads or callbacks. The primitive
source/extracted fixture is not an installed release-worker or complete domain
deduplication/forget proof. The separate [installed lab](extension-proof.md) now
exercises those domain cases. See [history limits and evidence](extension-history.md).

Committed-fact metadata fixtures cover model, tool, context, question, child,
extension and turn boundaries with fixed dimensions and stable source IDs.
Admission fixtures retain actual parent request/session IDs. Child fixtures check
registered-worker completion, actual start-source binding, distinct result/cleanup
status and refusal of forged reports, duplicate receipts and wrong physical offsets
before tail repair. Serial/parallel cases cover timeout, cancellation, child loss
and incomplete abrupt-death recovery without replay. Real sessions establish
request and source-to-delivery-to-invocation links and private/native/hash exclusion.
Idle resume remains byte-identical when optional recording/capture is off. Arbitrary
extension business values cannot relabel host action outcomes. The bundled
source/extracted fixture checks model boundary correlation alongside private
prompt projections. These are projection checks, not a broader delivery service,
complete journal authentication or an active diagnostic exporter.

Runtime fixtures exercise recorded process epochs, native approval/questions,
fresh waits after abrupt restart, cancellation and observed owner loss. Pure
checks cover strict source schemas, mismatched/duplicate finish refusal, absent
legacy links and the 10,000-fact recording limit plus its stop marker. A plausible
question reference pointing at the wrong physical position refuses before tail
repair. Independent event-job fixtures enable `lifecycle.record` with diagnostics
off, retain separate write approval and restore extension-question source links;
delegation fixtures bind distinct child approvals and interrupt a lost child's
wait without accepting its stale decision. Capture resume emits one new epoch
fact without replaying historical samples. The bundled idle start/close/resume
fixture checks compiled Session/source/metadata compatibility; it is not a domain
graph extension or a guarantee that a final close fact reaches a closing sink.

Live-feed fixtures exercise compiled independent workers and source-bound
admission/acknowledgment with diagnostic capture off, metadata secret exclusion,
separately granted tool input/results and correlated child start/completion,
normal write approval, notifications alongside feeds, pressure and invalid replies,
deadline cleanup uncertainty, explicit stop, cancellation and owner death.
Question checkpoint adjacency and explicit-answer enrollment survive abrupt
restart without historical callback replay. Receipt bounds span leases; coherent
payload tampering refuses physical validation before repair. The bundled feed
fixture checks declaration/envelope/ack primitives, not installed release-worker
execution or a complete ingestion audit. See [feed scope and limits](extension-feeds.md).

Notification fixtures exercise separately granted original/final-effective views,
metadata secret exclusion, final transformed text, synced ordered receipts,
disabled behavior and no action bypass. Bounds cover private payloads, source
input and selected declaration count. Required/optional failures, timeout, actual
worker VM shutdown, byte-identical original-session idle resume and fresh identical
prompts are tested. A self-consistent forged source/payload chain passes pure
projection checks but is refused by physical-source validation in resume/saved
diagnostics before tail repair. Missing receipts are also refused. See the
[notification contract](extension-events.md).

Timeout evidence distinguishes actual VM exit from complete cleanup confirmation:
when the terminating worker cannot acknowledge close, its receipt stays unknown
with unconfirmed cleanup and Session close reports that uncertainty. No retry or
inference is manufactured. The nine [source/view fixtures](lifecycle-events.md#internal-journal-source-and-prompt-views)
and existing worker-text/context/service tests remain in the full suite. Source
and extracted baselines, independent artifacts and hosted results are separate
claims; no new live provider, audio device, exporter or remote service was used.
The [independent lab](extension-proof.md) supplies the separate installed-worker
proof: prompt capture, deterministic entities/edges, awaited service/state recall,
frozen request context, approved file workflow, explicit question recovery,
bounded catch-up/deduplication, scope/version isolation and stale-write conflict
after forget. It also verifies private tool-feed and v2 text acknowledgments.
The compiler and host verifier use separate VMs; the unchanged archive runs with
utility-only parent PATH and its own bundled Erlang runtime, without system
Elixir/Mix/Rust. The last deliberate service crash is a terminal negative case:
inference stays unstarted, cleanup remains unconfirmed and no later domain
scenario runs. Passing its assertions does not permit continued effects.
Build, warnings-as-errors compilation, both actual Elixir 1.18.4/1.20.4
formatters, CLI help and isolated credential-free demo passed for this increment.
Documentation review checked 97 Markdown documents and 1195 local file/heading
links with no errors.

The [lifecycle audit](lifecycle-events.md#supported-lifecycle-coverage), supervised
trial below and hosted verification of the current lab complete P22's gates.
Synthetic dispatcher tracing and documented source-debugging boundaries are
implemented; no live GUI/editor debugger trial is claimed. The full
[event/graph coverage gate](lifecycle-events.md#knowledge-graph-acceptance-proof)
combines primitive failures, independent domain evidence and reviewed live use.
Remaining accounting/media work, the larger self-development evaluation, deferred
production knowledge packages and the final license transition are tracked in the
[current plan](../plan.md), which owns acceptance/status.

### Supervised extension-only trial (2026-10-17)

The supervisor extracted the unchanged Linux archive at core `3b0ef78` and created
a separate candidate worktree at `2874da0`. Its explicit ChatGPT subscription
`gpt-6.1-sol`/high author session loaded the bundled self-development skill and
evidence checklist, read the two relevant files and made three individually
reviewed edits. Only `examples/extension-lab/spec.exs` and `src/memory.ex` changed:
an empty-arguments, operator-only stats command uses the existing state-read
continuation and returns counts/revision/deletion metadata. No core/native edit,
dependency, shell command, candidate script, commit or push occurred in that session.

A fresh session using the same frozen release/model loaded the review skill and
checklist, read each target file once and returned no actionable finding within
the specified read-only/no-disclosure/no-revival question. The reviewer noted the
ordinary result schema is generic and did not claim runtime verification. The
supervisor inspected the actual diff and added independent missing/populated/
deleted-state assertions: exact returned fields, operator-only catalog, one
`state.get`, no model request and an unchanged tombstone. The lab now passes 41
assertions in source and the unchanged installed archive, including temporary CLI
selection and a symlinked temporary root. These checks establish SDK behavior,
not production extraction quality or a general correctness review of the whole memory example.

Private journal inspection found eight author and five reviewer requests, all
explicit subscription/model admissions; each session ran one prompt and one
presentation transform. The effective prompt contained the configured annotation,
the displayed answer contained the configured wrapper, and original assistant
text remained unchanged. Both sessions closed successfully; separate idle resumes
preserved journal bytes and candidate-file digests without prompting or executing
work. Raw transcripts/authentication remain outside Git. Hosted results and native
suite evidence are recorded above; Linux checks are not local macOS execution.

## Historical verification records

### Extension CI compatibility follow-up (2026-10-16)

The earlier [service run](https://github.com/lexlapax/ipse/actions/runs/38999961420)
stopped at formatting. The [context run](https://github.com/lexlapax/ipse/actions/runs/39000762785)
repaired formatting and passed Ubuntu, but macOS stopped at a five-second MCP
fixture wait while still discovering the catalog; native/demo/package steps were
skipped. `51513e8` adds an explicit catalog-ready barrier, retaining the configured
server/RPC and resource-outcome limits and no-replay assertions. Fourteen focused
catalog/session tests and the subsequent full hosted matrix passed. This is
fixture coordination evidence, not a production timeout or permission change.

The dated records below preserve what ran at each checkpoint, including failures,
interventions and superseded limitations. A claim that work was pending describes
that record's state, not the latest implementation. Counts and successful jobs
apply to the recorded revision/scope; skipped jobs are not verification evidence.
Use the current summary above and linked topic contracts before reproducing old
commands or treating a historical result as current completion.

### Documentation restructure, 2026-10-14

Operator and developer guides now have separate directories, with a central
documentation map, dependency inventory, and historical archive. Verified 139
local file links and heading anchors across 24 Markdown documents, including
the archived snapshot. Checked active CLI commands against `./bin/ipse --help`
and the implementation. The 21 distinct public external links in active
documentation were reachable through HTTP checks or direct source retrieval;
reachability does not guarantee future availability. `git diff --check` passed.
These documentation-only changes introduced no runtime dependency; no runtime
suite or packaging rerun was required. The runtime evidence below is retained
from its actual checks.

### Initial Debian handoff

Initial handoff checks passed on Debian 13 Linux x86_64 (glibc 2.41),
Elixir 1.18.3 / OTP 27, Rust 1.85.1:

- Source build and compilation with warnings as errors.
- Elixir formatting and **49 tests, 0 failures**.
- Source CLI demo and interactive session resume without tool replay.
- Bundled release build; extracted CLI help and demo from a separate directory,
  without the development toolchain's library-path setting.
- No occurrences of the old project spelling in repository source or filenames.

### Arch source check, 2026-10-14

On Arch Linux x86_64, glibc 2.44, Elixir 1.20.4 / OTP 29 (ERTS 17.0.6),
Rust 1.99.0:

- Fixed Elixir 1.20 bitstring-size pin warnings in the native frame parser,
  SSE parser, and SSE fixture helper.
- Source build, formatting check, warnings-as-errors compilation, and all
  **51 tests passed** after the live fixes below. Tests use fixtures, not live
  model services.
- Source demo passed with isolated state under `/tmp`; interactive resume
  restored the idle session without replaying tools.
- The first sandboxed build failed because Mix's TCP lock returned `:eperm`.
  Build and checks passed with the required socket access outside that sandbox.
- Reviewed the implementation against official OpenAI
  [registration](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
  [session lifecycle](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
  and [inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
  documentation. This is a source review, not live protocol verification.
- An initial browser callback connection refusal involved a stale callback
  port; a running login listened on a different port. A fresh matching attempt
  reached the listener. The precise cause of the initial stale URL is unknown.
- Fixed the real auth transport's strict `not uri.userinfo` check: normal URLs
  have `nil` userinfo, which raised before HTTP exchange. Public OpenID discovery
  then succeeded with TLS verification enabled. Added a real-transport URL
  credential rejection test; OAuth protocol fixtures still inject transport.
- Fixed the Responses adapter discarding streamed output items when the live
  `response.completed` event contained `output: []`. A regression fixture now
  covers text, tool calls, and opaque continuation retention in this case.

### Live ChatGPT subscription check, 2026-10-14

Verified with the account owner authorizing in Chrome on the same Arch machine:

- Fresh browser authorization, loopback callback, token exchange and signed
  identity validation completed. Status confirmed plan-usage permission; the
  credential file mode was `0600`.
- Explicit `chatgpt` provider with `gpt-6.1-sol` returned streamed text using the
  public Responses API with `store: false` and `stream: true`. No API provider
  or API key was selected.
- In a scratch workspace, individually approved `write`, `edit`, and `shell`
  calls created a small file, changed its contents, and read it through a shell
  command with exit code 0. Full proposed arguments appeared before approval.
- After closing and resuming the live session, the model recalled the file,
  final contents, and command result without tools. Journal tool-start counts
  remained three, confirming no replay.
- Logout returned success (remote revocation confirmed by the auth transport).
  Status then reported no session. Checked that access, refresh, and ID token
  fields were removed while client registration and host ID remained.

### Arch release and local provider checks, 2026-10-14

Built `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` on the Arch toolchain recorded
above. Fresh extraction under `/tmp` passed CLI help, credential-free demo, and
the bundled `verify-release.exs` checks. These ran with a utility-only `PATH`
containing no Elixir, Erlang, Mix, or Rust executables. The runtime and helper
resolved inside the extraction. This validates this host, not another Linux ABI.

An initial archive had only the generic Apache and Jason license texts. Rebuilt
with `IPSE_NOTICES_DIR` containing official upstream Elixir v1.20.4 and OTP
29.0.6 license trees, OTP/app authors, ERTS vendor license texts, and source
header/provenance inventories. Sources were tag commits
`759443e724f55bf58e71c0603644e99058918d52` (Elixir) and
`e07fd07837e5aa845657f5fa340637121e451d47` (OTP). Verified those files inside the
extracted archive. The header inventory includes upstream tests/examples;
it records provenance rather than certifying exactly which source files were
linked. No new build dependency was added.

Rebuilding initially retained stale documentation and notice files. After fixing
the packager to replace those generated directories, both sentinel checks passed.
Formatting, warnings-as-errors compilation, and all 51 fixture tests passed.

The installed Ollama-compatible service/client reported 0.40.1. A live
`qwen3.5:9b` read-tool round trip read the scratch file and returned its contents.
No model was downloaded. `ollama ps` reported the `llamacpp` runner, 4096 context,
and mixed CPU/GPU execution (28%/72%) on this host (Intel Core i7-12700K; NVIDIA
PCI vendor/device `10de:2486`). This is evidence for that local configuration,
not all models or hardware.

An intentionally unavailable ChatGPT model returned HTTP 400 under explicit
`chatgpt` selection; the failure surfaced without API provider fallback.

Natural-expiry refresh subsequently passed (see below). The later
[P0 closure check](#p0-closure-on-serenity-2026-10-15) observed a live usage-limit
error with Ipse's permission disabled. Broader plan eligibility, exhausted
allowance, live revoked-session recovery, paid API calls, and live provider use
on macOS remain unverified. Successful fixtures do not establish live-service compatibility.

### HTTP lifecycle regression checks, 2026-10-14

Controlled CLI fixtures exposed a transport lifetime defect: standalone profiles
reused fixed names, and asynchronous shutdown could leave the old profile alive
or collide with the next request. Replaced the duplicate auth/provider lifecycle
code with guardian-owned leases from a fixed 64-name pool. Each guardian starts
its own linked profile, monitors the borrower, and waits for profile exit before
releasing the name. This adds no package dependency.

Four behavior tests verify completed-request cleanup, borrower-death cleanup,
overlapping requests with isolated options, and repeated active cancellation
closing both linked processes and actual loopback sockets before immediate reuse.
All **55 fixture tests passed**. The isolated five-test P1 CLI draft also passed
against this transport; that is preparation, not a claim that P1 UI work is done.

Priorities and completion criteria are in [plan.md](../plan.md). When reporting a
failure, include the command, toolchain, sanitized error, and whether it ran in
a sandbox. Avoid calling permission failures application regressions until
the same command has been checked with the required access.

### Live natural-expiry renewal, 2026-10-15

Waited for the original access-token expiry without changing its timestamp or
re-authorizing. After expiry, `Ipse.Auth.token/1` renewed the session: both access
and refresh tokens changed and expiry advanced. Registration, host, identity,
and plan permission were preserved; credential mode remained `600`.
A subsequent explicit ChatGPT `gpt-6.1-sol` request returned the expected text
in four streamed chunks. Logout succeeded and access/refresh/ID token fields
were cleared. The check used the normal protected account registration, kept
all secrets in memory/protected storage, and retained only sanitized booleans
and timestamps as evidence. This is live renewal evidence, separate from fixtures.
No API-billing fallback was enabled. The later
[P0 closure check](#p0-closure-on-serenity-2026-10-15) adds one live usage-limit
error response. Broader eligibility, exhausted allowance, live revoked-session
recovery, paid API calls, and other platforms remain unverified.

### P1 CLI behavior, 2026-10-15

Six controlled CLI integration tests exercise the real CLI, session, HTTP
transport, and isolated journal homes with a loopback Ollama-protocol fixture.
They cover idle EOF, visible provider failure, running/finished states and
queued input at EOF, approval denial after EOF, resume preserving completed
write history without replay, and cancellation races. The cancellation check
forces repeated cancel and input arrival while cancellation is pending, proves
queued/discarded input is not sent, then completes a fresh turn in the same CLI.
No live model or account is used by these tests.

Build, formatting, warnings-as-errors compilation, all **61 tests**, and the
credential-free source demo passed. These checks do not establish live provider
compatibility beyond the separately recorded P0 account checks.

The rebuilt Arch bundle also passed help, credential-free demo, native timeout,
owner-death and lock checks, and HTTP-profile acquisition/cleanup from a fresh
extraction using a utility-only `PATH` without the development toolchain. A
source `chat --provider demo --yes` smoke check accepted two piped tasks and
finished both before exiting on EOF in an isolated scratch workspace. This is
scripted CLI evidence, not additional live model connectivity evidence.

### P1 runtime identity, 2026-10-15

Build, formatting, warnings-as-errors compilation, all **66 fixture tests**, and
the credential-free source demo passed. Added checks cover application version,
provider/model overrides, bounded invalid identifiers, missing/differing reported
models, secret exclusion, repeated-turn context, historical versus current-run
metadata after resume, and `/info` without inference while a request is pending.
Existing HTTP fixtures now assert runtime context survives serialization for
ChatGPT/OpenAI, Ollama, and Anthropic, and optional response metadata preserves
existing tool/continuation formats.

A separate live request to the already installed local Ollama `qwen3.5:9b`
returned application version `0.1.0`, configured provider `ollama`, and requested
model `qwen3.5:9b` from the supplied host facts. Resuming that scratch session
showed the saved provider-reported model in `/info`, with the current-run field
unavailable before inference. A plain “What version are you?” follow-up returned
`0.1.0`. No model was downloaded and no paid credentials were used. The new
identity behavior was not rechecked live with ChatGPT, OpenAI API, or Anthropic;
the earlier subscription lifecycle evidence remains separate.

The rebuilt Arch archive passed help, `/info` followed by EOF without inference,
credential-free demo, native timeout/owner-death/lock checks, and HTTP-profile
cleanup from a fresh extraction with a utility-only `PATH` containing no
development toolchain. `/info` showed bundled application version `0.1.0` and
explicit demo/scripted configuration. All 144 local documentation links/anchors
across 24 Markdown documents passed validation; developer/operator guidance was
reviewed against the implementation.

### Subsequent live ChatGPT identity, 2026-10-15

Reauthorized the same Ipse registration through the documented browser consent
flow. An explicit ChatGPT `gpt-6.1-sol` scratch session returned application
version `0.1.0`, provider `chatgpt`, requested model `gpt-6.1-sol`, and appropriately
unknown backend revision. `/info` after resume showed saved reported model
`gpt-6.1-sol` separately from unavailable current-run metadata, without inference.
No API provider or billing fallback was enabled.

### P2 context compaction, 2026-10-15

Build, formatting, warnings-as-errors compilation, all **78 tests**, and source
demo passed. Six helper tests cover safe boundaries, repeated compaction,
verbatim intent/action provenance, native recent continuation, old reasoning
exclusion from summary input, bounded/schema/tool-call rejection, stable JSON
digests, and disabled compaction. Five session integration tests cover durable
commit plus continuation, original journal retention and resume without replay,
cancellation before commit, owner death after commit, malformed summary recovery,
and rejection of corrupted committed checkpoints. Existing approval tests now
verify host-written decision/outcome metadata rather than inferring it from text.
A cancellation regression distinguishes approval-pending calls that never started
from executing calls whose effects may already have occurred.

A separate live ChatGPT scratch transcript with synthetic project facts compacted
from **29,490 to 3,358 bytes**. The resulting streamed reply (16 text chunks)
retained the project name `acorn` and MIT constraint. Exactly one checkpoint was
saved, all original messages remained, and no tools started. Resume retained
those facts without another compaction or tool execution. This is live evidence
for that account/model, separate from deterministic fixtures. Summary fidelity
is not proven generally; native OpenAI compaction and other providers' live
compaction behavior remain unverified. See [the contract](context-compaction.md).

The final compaction archive passed help, `/info`, `--context-bytes 8192` and
`--no-compact` parsing, credential-free demo, bundled compaction-module loading,
and native timeout/owner-death/lock checks from a fresh extraction with no
development toolchain on `PATH`. Developer/operator docs were reviewed and all
153 local links/anchors across 25 Markdown documents passed validation.

### Minimum-version formatter compatibility, 2026-10-15

GitHub CI for the identity and first compaction commits stopped at formatting
before behavior tests. Elixir 1.18 formatted two multiline tuple assertions
differently from Arch's 1.20. Rewrote those assertions to avoid that layout
ambiguity without changing their coverage. Formatting passes with both Arch
Elixir 1.20.4 and the official checksum-verified Elixir 1.18.4 OTP-27 build.
The latter was used for formatting only on the local OTP 29 host, not as proof
of the minimum runtime combination. All 11 affected provider fixtures passed
locally. The follow-up [GitHub Checks run](https://github.com/lexlapax/ipse/actions/runs/38703884589)
passed on the configured OTP 27 / Elixir 1.18 combination, including formatting,
all 78 tests, build, and demo.

## P3 workspace context (2026-10-15)

On Arch, the source build, Elixir 1.20 and 1.18 formatter checks,
warnings-as-errors compilation, all **95 tests**, and credential-free demo
passed. Workspace fixtures cover global/ancestor/nested scope, referenced
resources, non-repositories, source bounds/UTF-8/symlinks, snapshot validation,
saved-content resume with drift, explicit async refresh, and canonical cwd
aliases. A two-call pending write batch is recorded as not started when new
nested instructions appear; neither write executes before a revised proposal
reaches approval. `/context` and refresh are local, and refresh is refused while
model work is active. Independent review reproduced and fixed nonregular-source
crashes and disagreement between resource discovery and snapshot validation for
sensitive absolute paths; regression fixtures passed.

Separate **live ChatGPT subscription** scratch checks used explicit
`chatgpt/gpt-6.1-sol`: a coding task created `nested/hello.exs` with the comment
required by nested guidance and ran it with Elixir (56 streamed text chunks,
three approved mutations). After resume and a changed ancestor instruction file,
a non-coding notes-file task retained the saved project marker and README purpose
(29 streamed text chunks, one approved write). Two context snapshots were journaled;
changed instructions produced drift diagnostics. Full proposed mutation arguments
were displayed before approval. These checks do not establish semantic instruction
compliance for every model or arbitrary shell target.

Source and fresh bundled launchers passed from an arbitrary Git subdirectory
and with explicit `--cwd`, using isolated `IPSE_HOME` directories. Fixture journal
metadata and manifests confirmed the chosen cwd and ancestor provenance.
The isolated P3 archive used the previously committed native helper (pending
sandbox changes were excluded). The extracted release ran without Elixir, Mix,
Rust, or Erlang on `PATH` and passed bundled timeout, owner-death, and lock checks.
This is same-host Arch release evidence, not a new OS account or cross-machine
portability check. The original journal is retained; resume never replays tools.

## P2 native Linux sandbox (2026-10-15)

On Arch x86_64, kernel `7.2.9-arch1-1`, the source build, both Elixir formatter
versions, warnings-as-errors compile, **97 ordinary tests (7 enforcement tests
explicitly excluded)**, and demo passed. Running `mix test --include native_sandbox`
against the rebuilt helper passed **all 104 tests**. These are actual OS checks,
not simulated permission errors: outside fake credentials and symlink targets
could not be read/written/chmodded; system metadata remained read-only; workspace
chmod, Rust threads, and Elixir compilation worked; inherited test secrets and
`/proc` were absent. A reachable loopback control endpoint became inaccessible
inside the sandbox. Host signals, IPC, pidfds, process-group escape, scheduling,
page/process-memory mutations, and cross-PID resource changes were denied.
A disposable host process's file-descriptor limit stayed unchanged, while
current-process limit queries worked. Synchronized timeout and owner-death tests
proved started descendants did not leave delayed effects.

Independent review found host-process resource-control calls still needed
restriction. The fixed profile now allows `prlimit64` only for current-process
PID zero and denies scheduling/priority/page mutation APIs; compiler and thread
checks passed afterward. Native mount-source replacement was also checked
against retained inode/device identities and failed closed.

Separate **live ChatGPT subscription** evidence: `chatgpt/gpt-6.1-sol` streamed
42 text chunks while creating a scratch Elixir file and executing precisely
`elixir hello.exs` under the native profile. Both effects were individually
approved with full arguments; the native shell returned exit zero and expected
output. Provider inference remained outside shell enforcement. No fallback to
API billing or trusted execution occurred.

A fresh bundled extraction passed native outside-file denial, workspace write,
protected-workspace refusal, demo, and existing timeout/owner-death/lock checks
with no development toolchain on `PATH`. Linux aarch64 and other kernel policies
remain unverified. macOS enforcement and Windows remain separate work; selecting
native on unsupported platforms fails closed. See [scope and limits](sandbox.md).

## P4 release verification and protocol proposal (2026-10-15)

The local Arch source baseline and all **104 tests with native enforcement
included** passed again after the cross-platform fixture setup change. Both
Elixir formatter versions passed. Rebuilding the archive with version-matched
runtime notices and running
`elixir scripts/verify-package.exs dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`
passed: fresh extraction, empty isolated HOME/IPSE_HOME, no development toolchain
on `PATH`, help, default launch cwd containing spaces, explicit `--cwd`, exact
demo output file, and bundled OTP/helper lifecycle checks. This is a fresh-home
check on the existing account, not a newly created OS account or another host.

The CI matrix now schedules these source/package checks on Linux and macOS.
The experimental macOS script uses the approved built-in `codesign`, an ad-hoc
helper app, and Rust standard-library TCP probe. It requires successful execution
and a reachable network control before claiming network denial; it checks outside
file/symlink/metadata denial and allowed workspace/private-temp writes. Syntax
and the Rust probe were checked locally; the hosted probe result is recorded
below. The supported CLI still fails closed
for native mode on macOS; this probe alone does not implement resource/process
containment for a production backend.

The [protocol proposal](protocol-proposal.md) defines schemas, explicit trust and
configuration, approvals, cancellation/ownership, durable intent/results, and
unknown-outcome recovery. It does not implement MCP, delegated agents, or remote
execution. Those require their own focused implementation and tests.

The [first cross-platform CI run](https://github.com/lexlapax/ipse/actions/runs/38709598986)
passed Linux checks and macOS source build, formatting, warnings-as-errors
compilation, ordinary tests, demo, packaging, and fresh-home bundled verification.
The experimental macOS step failed before enforcement because the hidden Rust
source filename produced an invalid inferred crate name. An explicit crate name
fixes this reproduced build issue. Review also tightened network checks to accept
only a connect permission denial, rejecting refusal, timeout, and successful
connections. The revised Rust probe passed those controls under Linux native
enforcement before the successful macOS run below.

The [second hosted run](https://github.com/lexlapax/ipse/actions/runs/38710166415)
again passed both platforms' core/package checks, then stopped at code signing:
the auxiliary entitlement input had been placed in `Contents`, a nested-code
location. It now stays outside the app bundle, following Apple's documented
[bundle structure](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle).
This is a signing-layout fix, not a passing enforcement result.

The [corrected hosted run](https://github.com/lexlapax/ipse/actions/runs/38710566686)
passed on both platforms, configured with Elixir 1.18/OTP 27. Each passed build,
format, warnings-as-errors compile, ordinary tests, demo, packaging, and fresh-home
bundle verification. Archives were `ipse-0.1.0-linux-x86_64-glibc-2.39.tar.gz` and
`ipse-0.1.0-darwin-arm64.tar.gz` (macOS 14 runner). This establishes those hosted
source/bundle paths, not that the Arch/glibc-2.44 archive runs on Ubuntu.

The actual macOS signed-helper probe also passed: strict code-signature and
entitlement checks; denied outside fake-credential/symlink reads, outside writes
and chmod; permitted workspace chmod/write and private-temp write; same Rust
binary successfully executed inside the sandbox; reachable loopback connection
became a connect permission denial; nested shell inherited the restrictions.
Resource ceilings, adversarial process escape/cleanup, runtime signing/cache
lifecycle, and a production CLI backend remain unimplemented/unverified on macOS.
No Windows execution or paid API checks were performed. Final live-test logout
completed successfully; local subscription tokens were cleared while retaining
the app registration for the next sign-in.

## macOS process boundary (2026-10-15)

Historical research milestone before the native-backend decision below. Statements
about unavailable native mode describe this earlier state. See the
[current backend and verification](#macos-native-backend-2026-10-15).

Continued from `d7d2118` on macOS **26.7.2**, build `25G325`, Darwin `25.6.0`,
arm64. The installed toolchain was Elixir **1.20.3**, Erlang/OTP **29.0.5** with
ERTS **17.0.5**, and Rust **1.97.1**. Source build, formatting,
warnings-as-errors compilation, **97 tests with 7 Linux enforcement tests
excluded**, and the credential-free demo passed. The initial build was blocked
by Mix's loopback TCP lock under the execution sandbox; the build and tests
passed with the required socket access. TLS and tests were unchanged.

The default signed App Sandbox probe passed. Two subsequent invocations with
`--process-boundary`, including one refined to confirm actual helper-process
exit, reproduced these results:

| Descendant | Normal exit | Timeout | Port closure | Port-owner death |
| --- | --- | --- | --- | --- |
| Original process group | Stopped | Stopped | Stopped | Stopped |
| New session using `setsid` | Survived | Survived | Survived | Survived |
| New group using `setpgid` | Survived | Survived | Survived | Survived |

Each surviving descendant retained outside-file denial and wrote its workspace
marker only after the signed helper had exited. The bounded fixtures then
terminated; liveness checks confirmed their exit. Both diagnostic runs exited
nonzero with eight named containment failures. The three initial probe runs
also left three generated macOS app containers; scratch bundles and workspace
fixtures were removed. This is actual host OS evidence, separate from provider
fixtures and the earlier macOS 14 CI evidence.

The local `ipse-0.1.0-darwin-arm64.tar.gz` archive built and passed
`verify-package.exs`: fresh isolated HOME/IPSE_HOME, help, default and explicit
workspaces containing spaces, exact demo output, bundled timeout/owner-death
and lock checks, and no development toolchain on PATH. This verifies the
existing trusted runner, not bundled native-mode enforcement. No additional
version-matched toolchain notice directory was supplied, and no release was
published. Final formatting, warnings-as-errors compilation, and the ordinary
97-test suite passed again. All 189 local inline documentation links and heading
anchors across 29 Markdown files passed validation.

Public-interface research is recorded in
[the macOS boundary](sandbox.md#public-interfaces-and-remaining-limits).
`--sandbox native` remains unavailable on macOS. Resource ceilings, signal
isolation, adversarial reparenting, signing/cache recovery and container cleanup,
and bundled native-mode enforcement remain open. Linux enforcement was not run
on this macOS host. No live provider or Windows check was performed.

The [CI run for `e4ce266`](https://github.com/lexlapax/ipse/actions/runs/38714558457)
passed both Ubuntu Linux and macOS 14 jobs: source build, formatting,
warnings-as-errors compilation, ordinary tests, demo, packaging, and fresh-home
bundled verification. The macOS file/network probe also passed. The new
process-boundary flag was not included in that passing CI run; its eight local
failures remain open production acceptance checks.

Following the developer's decision to keep native mode unavailable and continue
public-native investigation, reviewed Foundation termination through Context7,
Apple's XPC/spawn/ptrace contracts, XNU libproc and coalition sources, and
Endpoint Security documentation and installed SDK headers. The SDK was **27.0**.
No compatible process-tree boundary was verified. These are documentation/source
findings, not live tests of the candidate APIs. No private API, service,
entitlement, or package was adopted. See the
[candidate comparison](sandbox.md#additional-native-controls-reviewed).
The follow-up documentation check validated 192 local inline links and heading
anchors across 29 Markdown files. CLI help still documents opt-in native mode
and fail-closed unavailability. No additional runtime behavior was changed.

## macOS native backend (2026-10-15)

After the research above, the developer requested native execution on the Mac,
accepting best-effort detached-descendant cleanup. On the same macOS 26.7.2 arm64
host, the production Runner path passed actual workspace writes, outside-file
read/write/chmod and symlink denial, protected signed-worker mutation denial,
environment scrubbing, temporary-home writes, and installed Elixir compilation.
A reachable loopback TCP positive control connected; the sandboxed Rust probe
received `EPERM`. Host and supervisor signal probes were denied. Resource probes
verified inherited ceilings, descriptor exhaustion, regular-file write denial,
and inability to raise a hard limit.

Ordinary process-group children stopped on timeout and owner death. A synchronized
detached child retained an output pipe after its parent exited; Runner completed
within the bound, then the surviving child proved outside-file denial before its
bounded exit. This explicitly verifies the accepted lifetime limitation rather
than claiming complete descendant cleanup. Changed signed-worker contents and
workspaces containing the active application failed before command effects.

The full suite with macOS enforcement included passed **121 tests with 7 Linux
enforcement tests excluded**. Sixteen portable cache tests use a fake helper;
they cover reuse, corruption, unsafe links/modes, abandoned stages, generation
capacity, malformed or broadened entitlement schemas, and competing locks.
Those fixtures are distinct from the real codesign and OS enforcement checks.
A Rust policy-parser test also passed, including boolean/array type confusion,
exact roots, duplicates, and trailing-data rejection.

Source build, formatting, warnings-as-errors compilation, and the credential-free
demo passed. The actual CLI demo also completed with `--sandbox native` in an
isolated scratch workspace and state home. The Mac archive built and
`verify-package.exs` passed using a fresh isolated HOME/IPSE_HOME and utility-only
PATH. Its bundled native checks exercised allowed workspace writes, outside-file
read/write denial, and ordinary child timeout cleanup without Elixir/Mix/Rust on
PATH. Earlier trusted helper/lock checks also passed.

Linux enforcement and live provider inference were not run on this Mac.
OS-managed test app containers persist. No package was published.

The first CI run for `2ffcad2` stopped at formatting on both platforms before
tests. Elixir 1.18 wraps a long pinned-pattern expression differently from 1.20.
Extracting the entitlement path keeps the expression short and both formatter
versions agree. Formatting passed locally with Elixir 1.18.5/OTP 27.3.4 and
1.20.3/OTP 29.0.5; all 16 cache tests passed after this behavior-preserving change.
Operator guidance was reviewed and remains valid. The
[replacement CI run for `f07d3f2`](https://github.com/lexlapax/ipse/actions/runs/38757410934)
passed the complete Linux job and Mac source/ordinary tests. Seven Mac enforcement
tests passed; the compiler check returned 127 because CI installs Elixir outside
the native profile's fixed tool roots and minimal PATH.

The corrected suite separates workspace/environment checks from compiler access.
An unsandboxed compilation first proves the installed toolchain works. Native
execution must compile when that toolchain is under the fixed readable roots;
otherwise it must report permission denial and leave no compiled artifact.
All nine corrected Mac enforcement tests passed locally with Homebrew Elixir.
Formatting passed with both supported Elixir versions. A local attempt to use
the isolated older toolchain could not start tests because its fresh Mix home
lacked Hex; no dependency was installed and that attempt is not a test pass.
The [final CI run for `3c349f5`](https://github.com/lexlapax/ipse/actions/runs/38758452442)
passed both Linux x86_64 and macOS 14 arm64 jobs, including source checks, demo,
packaging, and fresh-home verification. The Mac passed all nine corrected native
enforcement tests, the Rust policy-parser test, and the experimental file/network
probe. Its installed compiler positive control succeeded and native execution
outside the readable tool roots was denied without a compiled artifact.
The final local full suite passed **122 tests with 7 Linux enforcement tests
excluded**. Developer/operator docs were reviewed for the transfer back to
Serenity. The subsequent [Linux return checks](#p0-closure-on-serenity-2026-10-15)
ran native enforcement on Serenity rather than inferring it from ordinary CI.

## P0 closure on Serenity, 2026-10-15

Pulled clean `main` from `origin` through `ec5fb85`, preserving the Mac native
backend and its accepted detached-descendant lifetime limit. This closes P0 for
the available Arch host and account; unavailable live branches stay explicitly
unverified below. It does not claim every subscription plan or platform works.

### Recovery and protocol fixtures

Reviewed current official OpenAI [errors and recovery](https://developers.openai.com/siwc/token-sharing-open-source/errors-and-recovery),
[profiles and sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
[preview limitations](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations),
and [models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).
The subscription request uses developer messages and `additional_tools` input
items instead of top-level function tools; OpenAI API requests keep their
separate format. Subscription URLs are pinned to the public OpenAI endpoint,
with test-only loopback overrides.

Fixtures cover terminal refresh errors clearing only unusable tokens, retained
registration/account identity, invalid-client and transient failures preserving
credentials, and rotated tokens with reduced scopes being saved before denial.
A discovered post-rotation discovery outage could previously lose the new refresh
token. Renewal now saves protected pending rotation before fetching identity keys.
Tests verify retry and owner-death recovery without a second token exchange,
original expiry retention and consistency checks, malformed/mismatched/expired identity rejection,
fresh-login replacement, and logout revoking the newest pending refresh token.
Unverified identity is never activated. Loss before durable storage still
requires fresh login; expired unvalidated identity requires fresh login too.

Structured HTTP and SSE failure fixtures preserve bounded status, body shape,
code, parameter, and request ID without provider prose or credentials. Real
session/loopback fixtures simulate ineligible-account and usage-limit failures,
prove one request with no retry or API-key fallback, retain credentials, and
resume without replay. CLI fixtures verify queued input is discarded visibly
after errors and only fresh input starts another turn.

### Live account checks

The normal protected ChatGPT registration passed the updated request shape with
`gpt-6.1-sol`: **43 streamed chunks and two individually approved effects** in a
scratch workspace. It wrote `hello.exs`, then ran exactly `elixir hello.exs` under
the actual Linux native profile, with the expected output and exit code zero.
No API billing path was selected. Earlier browser sign-in, approved edit,
session resume, natural-expiry rotating refresh, and logout evidence above
remains valid; those lifecycle actions were not repeated for this patch.

With the owner's specific approval, temporarily disabled only “Allow Ipse to use
plan limits,” saved it, and made one tiny request. The live SSE stream returned
`subscription_sharing_usage_limit_exceeded`; Ipse stopped and surfaced recovery
guidance. Restored the saved permission to enabled at its original 100% app limit;
credit use remained disabled. This proves handling of the live code, **not actual
allowance exhaustion**. Automatic approval review rejected an extra post-restore
request as outside that permission-test scope; restoration was verified in the UI.

No already ineligible or exhausted account was available. Broader plan/workspace
eligibility, genuine allowance exhaustion/reset behavior, live revocation
recovery, and the pending-renewal outage path remain unverified against OpenAI.
Those negative branches have fixture coverage only. No allowance was deliberately
exhausted, no credits were enabled, and no API billing fallback was used.

### Local and release checks

Serenity: Arch Linux x86_64, kernel `7.2.9-arch1-1`, glibc 2.44,
Elixir 1.20.4 / OTP 29 (ERTS 17.0.6), Rust 1.99.0. Source build, both Elixir 1.20
and 1.18 formatter checks, warnings-as-errors compilation, and isolated
credential-free demo passed. Ordinary tests: **142 passed, 16 enforcement tests
excluded**. With actual Linux native enforcement included: **149 passed,
9 Mac enforcement tests excluded**. Historical Mac evidence remains separate.

Rebuilt `ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` with the same version-matched
official runtime notices described above. `scripts/verify-package.exs` passed:
fresh isolated HOME/IPSE_HOME, utility-only PATH without Elixir/Erlang/Mix/Rust,
help, demo, default/explicit workspaces with spaces, and bundled helper lifecycle
and lock checks. This is a local archive check, not publication or another Linux ABI.

Developer/operator commands and content were reviewed; the fulfilled Serenity
handoff is preserved in the documentation archive. All 221 local links and
heading anchors across 30 Markdown documents passed validation. No new
dependency was added.

## P5 local MCP, 2026-10-15

Implemented the explicitly configured local stdio client described in the
[MCP contract](mcp.md). Reused MCP Elixir SDK 1.1.0 and JSONSchex 0.10.0 after
comparing published package contracts and actual source. The SDK's advertised
optional Req/Plug modules were necessary for compilation on Elixir 1.20; their
locked dependency chain is documented. Req 0.7.5 replaced the older release
flagged during resolution, and `mix hex.audit` passed with no current advisories
or retired packages. The developer explicitly approved Telemetry and Rebar3.
Rebar3 was already installed here (3.27.0); no new system package was installed.

### Protocol, effect, and ownership evidence

Local fixtures use real subprocess stdin/stdout, not an in-memory MCP transport.
They verify explicit config/allowlists, collisions including normalized dotted
names, strict schema subsets and bounds, pagination, duplicate/changed discovery,
unsupported sampling, safe protocol errors, text redaction, and invalid/oversized
messages. Mixed request/response envelopes are rejected before SDK decoding, and
private values containing JSON escapes are checked before encoding. Persistent
configuration fingerprints exclude private values.

Real session fixtures verify exact approval arguments, intent before dispatch,
headless denial, serial calls, confirmed cancellation, owner-death cleanup,
configuration-bound resume, completed-call preservation, and unknown-outcome
batch stopping/resume without replay. The OS supervisor tests cover independent
stdout/stderr, environment clearing, lossless bounded binary relaying, output and
input backpressure, timeout/owner death, ordinary child cleanup, and cancellation
while writes are queued. Only an unsent cancellation control can retry; tool
input is never replayed. Cleanup confirmation requires actual exit status,
including after a linked Port error. Detached process-group escape remains an
explicit trusted-execution limitation on both platforms.

`mix run scripts/demo-mcp.exs` passed with the existing SDK as **both client and
example server**, a scripted model, one displayed exact approval, and a verified
scratch `mcp-note.txt` write. No model service was contacted. The documented
`--mcp-config` CLI option also passed a credential-free scratch smoke check;
`--help` and operator examples were reviewed against the implementation.

### Source and package baseline

On Serenity's Arch x86_64 toolchain recorded in P0, source build, warnings-as-errors
Ipse compilation, both Elixir 1.20/1.18 formatter checks, and the original
credential-free demo passed. Ordinary suite: **182 passed, 16 enforcement checks
excluded**. Including actual Linux native enforcement: **189 passed, 9 Mac
checks excluded**. All 244 local documentation links and heading anchors across
32 Markdown files passed validation. Mac enforcement was not run on this host.
Fresh upstream dependency compilation emits existing UUID/JSONSchex deprecation
and type-analysis warnings on Elixir 1.20; these were not suppressed, vendored,
or patched. Ipse's own warnings-as-errors compilation passes.

The Arch archive rebuilt with every resolved package's upstream license notices,
including NimblePool's README notice. Corrected the old Jason MIT label to match
its pinned Apache-2.0 notice. Fresh-package verification passed the existing
help/demo/workspace/helper/lock checks and a **real bundled MCP SDK round trip**:
both peers used the extracted runtime without Elixir/Erlang/Mix/Rust on PATH.
The matching Elixir/OTP notice set from P0 was supplied. No archive was published.

The checks above are fixture and local SDK interoperability checks. The live
ChatGPT follow-up below is separate. Live Ollama/API use with MCP, arbitrary
third-party servers, persistent server sessions,
network transports, resources/prompts, sampling/elicitation/tasks, delegation,
remote execution, and Windows remain unverified or unimplemented. The P0 live
subscription evidence is separate; no account setting or billing path changed
in this milestone.

The first P5 hosted run failed because the source fixtures launched Elixir with
the deliberately cleared environment but did not select the CI installation's
Erlang path. Arch's system Erlang masked that test setup error. Source fixtures
and the SDK demo now explicitly select the running OTP installation's `bin`
directory; the runtime environment isolation policy is unchanged.

The corrected implementation at `b7522dd` passed
[Linux x86_64 and macOS 14 arm64 CI](https://github.com/lexlapax/ipse/actions/runs/38773218000):
source checks, ordinary tests, credential-free demo, packaging, and fresh-home
bundled MCP verification. Mac native enforcement and the signed App Sandbox
probe also passed. These hosted checks are separate from the local Arch results.

### Live ChatGPT MCP follow-up

On 2026-10-15, the source CLI at `6b324b1` passed a live MCP session on Serenity's
Arch toolchain recorded above. Reused Ipse's existing protected sign-in and
explicitly selected `chatgpt/gpt-6.1-sol`; there was no API-provider fallback,
account-permission change, or new dependency. Reviewed the current official
[subscription inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
and [preview limits](https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations).
Local MCP functions went through the existing `additional_tools` subscription
route, rather than hosted MCP/connectors.

Configured only `priv/mcp-notes.exs`, using the existing SDK server, a fresh `/tmp`
workspace, separate scratch journals, an explicitly selected OTP path, and
`--max-steps 4`. The live model requested `mcp__live_notes__write_note` exactly
once. Reviewed the full arguments and individually approved the proposed content
`Live ChatGPT MCP verified.` followed by one newline. The server returned success;
exact file bytes matched, the streamed assistant reply completed with
`MCP_WRITE_OK`, and the journal retained one approved intent and one tool result.

Exited and resumed with the same explicit MCP configuration. Before any new
prompt, all ten journal events and the file's modification/change timestamps
were unchanged: startup did not replay the tool. A second live prompt requested
recall without tools; its streamed reply recalled the saved text and completed
with `RESUME_OK`. Final assertions found two finished turns, still one MCP
intent/result, unchanged file timestamps, and the same exact bytes. Scratch
transcripts and account details are not committed.

This is live-model evidence for one local SDK example server on Arch, separate
from scripted demos and protocol fixtures. Arbitrary third-party servers and
other live providers remain unverified. This follow-up did not independently
test refresh, logout, cancellation, or unknown-outcome recovery. Refresh/logout
retain their earlier P0 live evidence; MCP cancellation and unknown-outcome
recovery retain their P5 fixture evidence.

Reviewed developer/operator guidance against the live result. All 245 local
documentation links and heading anchors across 32 Markdown files passed.

## Linux Rust subprocess compatibility, 2026-10-15

During independent MCP investigation, an approved offline Cargo build inside
the native Linux sandbox failed to start Rust compiler subprocesses. Rust 1.99
uses a private connected Unix sequence-packet pair for its fork/exec error
channel; the profile previously permitted only stream pairs. Permitted
`AF_UNIX/SOCK_SEQPACKET` pairs while retaining datagram-pair and all external
socket/connection denials. Namespace, Landlock, filesystem, and resource policy
are unchanged.

Source build, formatting, warnings-as-errors compilation, and the full ordinary
suite passed in the development worktree. All nine focused Linux enforcement
tests passed, including actual Rust compilation/linker spawning and forced
`Command::pre_exec` child spawning. The probe also checked that private stream
and sequence-packet pairs work, while datagram/non-Unix pairs and standalone
Unix/IPv4/IPv6 sockets return permission denial. The previously failing locked
Cargo build then passed with networking disabled and writes confined to its
temporary native workspace. This is local Arch enforcement evidence, not a
new protocol-compatibility or macOS claim.

## P6 local delegation, 2026-10-15

Implemented opt-in serial local children using the existing OTP session, task,
approval, and journal boundaries; no new package was added. The child gets the
same provider/model/workspace, saved instructions, and selected task/context,
with a separate journal and no parent transcript, MCP, or recursive delegation.
See the [contract](delegation.md) and [operator guide](../operator/subagents.md).

Fifteen focused policy/session fixtures passed. They cover explicit enablement,
headless denial, exact parent/child approval references, individual child denial,
intent ordering and separate journals, context minimization and saved-instruction
drift, normal close, completed/unknown resume without replay, standalone child
resume refusal, abrupt parent death, real child-shell cancellation, timeout,
recursion rejection, two-child budgets, and oversized results. Human approval
waiting pauses the active child budget. Completed child closure records no
spurious cancellation. The real shell fixture stopped the child session before
parent cancellation returned, and its delayed file effect did not occur.

### Source and bundled checks

On Serenity's Arch toolchain recorded above, source build, both Elixir 1.20/1.18
formatters, warnings-as-errors compilation, and the original credential-free
demo passed. Ordinary suite: **197 passed, 17 enforcement checks excluded**.
With actual Linux enforcement included: **205 passed, 9 Mac checks excluded**.
`mix run scripts/demo-subagents.exs` passed two exact scripted approvals and
verified the file and both journals, without contacting a model service.

The extracted Arch package also passed the bundled delegation demo under a
utility-only PATH without a development toolchain, alongside its original
help/demo/workspace/helper/lock and MCP round-trip checks. The final runtime
notice-complete rebuild and fresh-package verification passed. Hosted Linux/macOS
[CI passed Linux x86_64 and macOS 14 arm64](https://github.com/lexlapax/ipse/actions/runs/38795554992), including source,
bundled MCP/delegation checks, and actual Mac native enforcement. Local Arch
checks alone do not establish Mac behavior.

### Live subscription check

A separate interactive source CLI check explicitly selected
`chatgpt/gpt-6.1-sol`, `--subagents`, `--sandbox native`, and `--max-steps 4`,
with a fresh scratch workspace and separate journals. Reviewed and approved one
exact delegation task. The child then requested two distinct parent approvals:
write `hello.exs` with `IO.puts("LIVE_CHILD_OK")` plus one newline, then run
`elixir --erl '+S 2:2' hello.exs` with a ten-second timeout. Approved each exact
proposal through the parent UI.

Verified exact file bytes, one approved parent delegation intent, two approved
child effects, and the child journal's native shell result: exit 0 and
`LIVE_CHILD_OK`. The parent consumed the bounded child result and completed its
stream with `DELEGATION_OK`. Idle CLI resume restored the saved delegation flag
and native policy without explicit flags. Parent/child journal event counts and
file modification/change timestamps remained unchanged; no child or effect was
replayed. No API provider, billing fallback, account-permission change, or
independent refresh/logout test was involved. Private transcripts are not committed.

Live evidence covers one successful child path on Arch. Cancellation, owner
death, denial, timeout, and unknown recovery remain fixture evidence. Parallel,
recursive, cross-provider/model, remote, and child-MCP execution remain outside
P6. Documentation was reconciled with the implementation and actual results.

## P7 expanded local MCP, 2026-10-15

Implemented exact configured resource URIs and prompt names through the existing
SDK, host approval, descriptor binding, intent journal, and unknown-outcome
boundary. Discovery fetches metadata only. Resource text and prompt messages
remain bounded untrusted tool data, with no automatic prompt execution or linked
resource loading. Added optional per-server native enforcement, independently
of the shell setting. Reused existing packages; no new runtime dependency.
See the [developer contract](mcp.md) and [operator guide](../operator/mcp.md).

### Fixtures and source baseline

Focused fixtures cover resource-only/prompt-only capability negotiation, no
automatic content fetch, exact approval targets/arguments, headless denial,
durable provenance, descriptor drift, duplicate/missing metadata, malformed
prompt arguments, cursor/page ceilings, URI mismatch, binary/embedded content,
oversized results, and unknown recovery without replay. Generic protocol errors
after dispatch now stop as unknown, since an effect may have happened before
the server reported an RPC failure. Valid ordinary tool error results remain
reported errors. Schema fixtures cover the exact built-in Draft 2020-12 marker,
narrow nullable pairs, bounded inert defaults, and continued rejection of
references/combinators/remote loaders. Config fixtures cover default fingerprint
compatibility and rejection of selected secrets in public fields across every
configured server. Child environments remain server-specific; known private
values are checked/redacted across the host catalog, arguments, identity, and
retained text.

Arch source build, both Elixir 1.20/1.18 formatters, warnings-as-errors compilation,
and the original credential-free demo passed. Ordinary suite: **222 passed,
26 enforcement checks excluded**. Actual Linux enforcement included: **235 passed,
13 Mac checks excluded**. Native stdio fixtures prove workspace writes, denied
outside/symlink/network access and process-group escape, child-only loader
environment with a positive control, setup cancellation, owner death, and
confirmed ordinary-descendant cleanup. Hosted macOS CI also passed the four new
stdio enforcement cases: direct args/environment with outside-file denial,
loader injection with a positive control, setup cancellation, and owner death
with ordinary-descendant cleanup.

`mix run scripts/demo-mcp.exs` passed three exact approved SDK-to-SDK calls:
scratch write, fixed resource read, and prompt retrieval. This uses a scripted
model and contacts no model service. The notice-complete Arch archive and final
fresh-extraction verifier passed, including bundled tool/resource/prompt calls,
delegation, fresh-home workspace behavior, and helper/lock checks with a utility-only
PATH. [Supported-host CI passed Linux x86_64 and macOS 14 arm64](https://github.com/lexlapax/ipse/actions/runs/38799753085),
including source, native Mac enforcement, bundled tool/resource/prompt and
delegation round trips, and the independent Mac sandbox probe.

The [first P7 CI run](https://github.com/lexlapax/ipse/actions/runs/38798892424)
passed Linux source/package checks and the Mac ordinary suite. The Mac enforcement
step passed the new native cases but failed its repeated ordinary initial-server-
exit cleanup fixture: stdout was retained, yet the helper's final `X` record was
missing. Its log did not reveal which fixed error frame was sent. Added twenty
bounded real cleanup iterations with exact status/frame diagnostics and explicit
error-frame rejection, preserving the cleanup and completion requirements. All
twenty iterations passed locally on Linux. The replacement CI passed both Mac
invocations of this stricter fixture (forty helper runs), alongside all other
checks. The original missing completion record was not reproduced and its cause
remained unknown at P7 closure; no runtime policy was relaxed or root-cause fix
claimed. The later [local load investigation](#macos-stdio-cleanup-load-2026-10-15)
reproduced the symptom with a decoded drain error. The original CI log still
does not establish whether it failed through that same path.

### Pinned independent interoperability

The separately reviewed MIT `rust-mcp-filesystem` 0.2.0 at
[commit df98dc38](https://github.com/13thx-mcp/filesystem/tree/df98dc38c969c92f25c778d37691e7a3f1914367)
uses rmcp 3.4.0. Its locked dependencies were downloaded, then built offline
inside the Linux native sandbox under the developer's explicit approval.
An initial SDK-only diagnostic exposed the canonical `$schema` marker and
negotiated revision 2025-11-25. Nesting Ipse's process-group supervisor inside
an outer sandbox failed by design; the group-escape denial was retained.

The full Ipse adapter subsequently passed with the client outside and only the
server inside the native profile. The optional
`mix run scripts/verify-independent-mcp.exs /path/to/reviewed/filesystem-server`
copied the reviewed executable into a fresh scratch workspace, discovered three
allowlisted tools, approved exact read/list/write calls separately, verified
synthetic file/result bytes and journal intents, and resumed idle without journal
changes. The actual generated schemas exercised the canonical dialect, nullable
`Option<String>` path and inert false overwrite default. This is real independent
protocol interoperability with a scripted model, not live model evidence. The
server is not installed, bundled, added to default tests, or required by CI.

### Live ChatGPT subscription check

A separate interactive source session explicitly selected
`chatgpt/gpt-6.1-sol` and two configured servers. The independent Rust server
ran read-only inside its per-server native profile; the bundled SDK catalog
example ran in the explicitly displayed trusted mode. Individually approved
`read_text_file` with `path: fixture.txt`, the fixed `notes://guide` resource,
and `summarize` with `topic: scratch verification`. Verified the exact synthetic
independent marker `LIVE_INDEPENDENT_MCP_OK`, guide text, role-delimited prompt
text, three approved durable intents/results, and streamed `LIVE_MCP_P7_OK`.
No retrieved prompt was executed. Idle CLI resume followed by EOF preserved
journal event count and fixture timestamps; no model request or MCP call replayed.
Explicit `/exit` records cancellation separately; it is not a replay event.

This live check used the existing Ipse subscription sign-in, with no API billing,
provider fallback, permission change, or new refresh/logout check. Private
transcripts and credentials are not committed. The final approval target-display
addition was verified by fixtures; the live run used the preceding display.
At P7 closure, other independent servers, live providers, Mac independent/live MCP,
network transports, templates/subscriptions, and persistent connections remained unverified
or unimplemented. The existing macOS detached-descendant limitation remains.
Subsequent independent memory-server evidence is recorded
[below](#second-independent-local-mcp-server-2026-10-15).

## macOS stdio cleanup load, 2026-10-15

Local host: macOS 26.7.2 arm64, Elixir 1.20.3, OTP 29 / ERTS 17.0.5,
Rust 1.97.1. The checkout started clean at `8a97b3a`; origin fetch succeeded
after an initial connection timeout and confirmed it was current.

The original helper passed 300 synthetic trials at concurrency eight. At
concurrency sixteen, one of 1,000 trials returned stdout `done`, helper status
zero, and `E: stdio output did not drain`, without `X`, after 519 ms. No delayed
write occurred. A second 1,000-trial run with temporary process-group tracing
reproduced this once. At the deadline, `/bin/ps` showed a live `sleep` in the
original group, reparented to PID 1, after the first group-wide SIGKILL.
Tracing inspected only that fixture group and was removed from the helper.

This supports a fork during group-signal delivery as the cause of the local
reproduction. Apple's published [group iteration](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_proc.c)
collects member PIDs before signaling them through the
[group-kill callback](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sig.c).
That source review is supporting evidence, not a trace of the host kernel's
exact fork timing. The earlier CI failure's error frame remains unavailable;
its cause is still unconfirmed.

The stdio supervisor now repeats group SIGKILL on idle five-millisecond drain
polls, stopping after a failed signal or pipe EOF. The original 500 ms drain
deadline, output/error frames, watchdog, and sandbox policy remain in force.
An ordinary descendant left by the first signal can therefore release its pipe
before the drain expires. This is best-effort group cleanup, not a new process
containment boundary.

The diagnostic passed two 1,000-trial trusted-mode runs at concurrency sixteen
and 100 actual native trials at concurrency four after this change. Each required
exact output, one successful completion, no error frame, and no delayed write.
A new 200-run concurrent regression preserves those strict completion checks.
A separate native test deliberately detaches a pipe holder: it must still emit
the drain error without completion within two seconds. After release, the
surviving child proves outside-file denial, preserving the documented lifetime
limitation.

Initial macOS stdio enforcement failed before launch because fixtures used the
host's `0755` state home. The suite now uses isolated `0700` homes without
changing host permissions or weakening cache checks. All eighteen focused
stdio tests then passed with five Linux tests excluded. An initial concurrent
native diagnostic also exposed expected cache-lock contention; the diagnostic
serializes preparation rather than changing runtime locking or retry policy.

Final source build, formatting, warnings-as-errors compilation, and isolated
credential-free demo passed. Ordinary tests: **223 passed, 27 excluded**.
The full suite with actual macOS enforcement included: **237 passed,
13 Linux enforcement tests excluded**. The focused stdio suite above includes
the new concurrent regression and detached-pipe negative control.

Built `dist/ipse-0.1.0-darwin-arm64.tar.gz` and verified that exact archive with
`elixir scripts/verify-package.exs dist/ipse-0.1.0-darwin-arm64.tar.gz`.
Fresh isolated HOME/IPSE_HOME and a utility-only PATH passed help, demo,
default and explicit workspaces with spaces, bundled MCP tool/resource/prompt
and delegation checks, and OTP/helper lifecycle and lock checks. Bundled Mac
native file denials and ordinary-child timeout cleanup passed. No archive was
published. The documentation check passed all 295 local links and heading
anchors across 36 tracked Markdown files.

Hosted [Checks run 38822941399](https://github.com/lexlapax/ipse/actions/runs/38822941399)
subsequently passed for fix commit `b3db345` on Ubuntu and macOS 14. Both jobs
passed source build, formatting, warnings-as-errors compilation, ordinary tests,
demo, packaging, and fresh-package verification. The Mac job also passed native
enforcement and the experimental App Sandbox probe.

These are synthetic lifecycle and actual Mac file-enforcement checks. No live
provider, independent MCP server, or Linux enforcement rerun is implied.
Detached descendants can still survive with workspace access, and OS-managed
sandbox containers persist. The original CI failure's cause remains unconfirmed.

## Linux return after macOS cleanup, 2026-10-15

Serenity returned with a clean `main` fast-forwarded to `39bdc8e`, including the
cleanup fix `b3db345`. Fetch confirmed no further origin changes. Host: Arch
Linux x86_64, kernel `7.2.9-arch1-1`, glibc 2.44, Elixir 1.20.4,
OTP 29 / ERTS 17.0.6, Rust 1.99.0.

The source build, formatter check, warnings-as-errors compilation, and
`mix test --include native_sandbox` passed: **236 passed, 14 macOS tests
excluded**. This includes actual Linux native enforcement and the new 200-run
concurrent stdio cleanup regression with exact output/completion, no error
frames, and no delayed child writes. The credential-free source demo passed
under a fresh temporary `IPSE_HOME`. Initial sandboxed Mix invocations could
not acquire their loopback TCP lock (`:eperm`); checks passed through the tool's
permission flow without changing tests, TLS, or sandbox policy.

Built `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` with
`IPSE_NOTICES_DIR=/tmp/ipse-toolchain-notices`, reusing the version-matched
Elixir 1.20.4 and OTP 29.0.6 upstream notice collection recorded above. Checked
the archive for those notices, provenance/header inventory, Telemetry's NOTICE,
and NimblePool's README notice. Ran:

```sh
elixir scripts/verify-package.exs dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz
```

Fresh isolated HOME/IPSE_HOME and utility-only PATH passed help, demo, default
and explicit workspaces with spaces, bundled MCP tool/resource/prompt and
delegation checks, and OTP/helper timeout, owner-death, and lock checks.
No archive was published. Developer/operator guidance and source CLI help were
reviewed; all 298 local file links and heading anchors across 36 tracked
Markdown documents passed validation, as did `git diff --check`.

No regression required a runtime fix. No live provider, fresh authentication,
independent server, macOS enforcement, or extra stdio load diagnostic was run
in this return check. Earlier Mac evidence remains separate; the original CI
failure's cause is still unconfirmed, and detached-descendant cleanup remains
best effort. P0–P7 remain complete within their documented scope; broader
independent local-server interoperability was proposed next. The following
section records the subsequent second-server check.

## Second independent local MCP server, 2026-10-15

Started from clean `main` at `f44bc8d` on the Serenity Arch x86_64 host recorded
above. Selected the separately implemented Apache-2.0 `mcp-memory` 2.0.0
published crate, pinned by its verified registry SHA-256 and included Cargo.lock;
see [source, dependencies, and exact patch](dependencies.md#second-independent-mcp-investigation-memory).
This version implements MCP itself rather than using the first server's rmcp
SDK. An earlier SQLite candidate was rejected during source review because it
hard-codes protocol revision 2024-11-05; Ipse's pinned revision was retained.

The unmodified memory crate failed to build on Rust 1.99/x86_64 at an incorrectly
typed prefetch pointer. Applied only the documented pointer cast in temporary
upstream source, then built successfully offline inside the Linux native
sandbox. No protocol source or Ipse runtime policy changed. This evidence covers
that patched 2.0.0 build, not an unmodified or current upstream release.

The optional verifier passed:

```sh
mix run scripts/verify-independent-memory-mcp.exs /path/to/reviewed/mcp-memory
```

It copied the reviewed executable into a fresh workspace, used an isolated
owner-only `IPSE_HOME`, selected per-server native enforcement and stdio, and
allowlisted only `create_entities`, `get_entity`, and `search_nodes`. It set the
server's existing synchronous durability option. Startup/discovery creates an
empty scratch binary log; it does not create the synthetic entity.

The first proposed write was explicitly denied: the log bytes remained identical
and the journal contained no dispatch intent. Four subsequent calls received
separate approvals with exact nested arguments: create one synthetic entity,
retrieve it, search for it with a one-result limit, and retrieve a deliberately
missing name. Exact create/get/search content passed across fresh server
processes. The last call returned a valid `isError` tool result, journaled as
`error`, rather than an unknown transport outcome. The verifier checks approved
intent arguments, server fingerprint, requested native policy, all five outcome
records including denial, and unchanged journal events/log bytes on idle resume.
Its initial search assertion expected a graph object; inspection confirmed the
upstream array format and the checker was corrected to require the exact entity
array. No runtime compatibility fix was needed.

Source build, formatting, warnings-as-errors compilation, and the isolated
credential-free demo passed. `mix test --include native_sandbox` passed
**236 tests, with 14 macOS tests excluded**. All 304 local links and heading
anchors across 36 tracked Markdown documents passed; `git diff --check` passed.
Reviewed operator/developer guidance and kept the optional check separate from
normal server configuration and the bundled SDK demo. No packaging or runtime
code changed, so packaging was not rerun; the preceding Linux return record
retains the separate fresh-package evidence.

No live model/provider, authentication, Mac independent-server run, resources,
prompts, network transport, concurrent memory writers, cancellation, interrupted
write recovery, or power-loss durability was exercised here. The script removes
its scratch state and restores the previous `IPSE_HOME`; the reviewed source,
Cargo cache, and executable remain in `/tmp` only. No server was installed,
bundled, enabled in normal sessions, or added as a default/CI dependency.

## P8 skill resources, 2026-10-15

Added explicit skill-relative text reads through the existing bounded source
reader, without a new dependency. The bundled review skill/checklist and source
demo exercise the feature. Focused fixtures passed precedence, inert script/link
content, path/symlink/credential rejection, invalid UTF-8 and size/depth bounds,
current-byte hashes, outside-workspace user skill resources, and saved-content
resume after a file change. No automatic reload or effect replay occurred.

Arch source build, formatting, warnings-as-errors compilation, and the isolated
resource-enabled demo passed. Full Linux enforcement suite: **239 passed,
14 macOS tests excluded**. Hosted
[Linux/macOS source/package CI passed](https://github.com/lexlapax/ipse/actions/runs/38844821382)
at `4a19bb3`, including Mac native enforcement and resource-enabled bundled demo.
See [skill contract](architecture.md#skill-resources) and
[operator usage](../operator/usage.md#skills). Provider validation is recorded
separately; these fixtures/demo require no service or credentials.

## Live provider acceptance follow-up, 2026-10-15

On the recorded Serenity Arch host, the developer explicitly authorized reading
provider keys privately from the Git-ignored repository `.env` and paid API
validation. Ollama 0.40.1 used the installed `qwen3.5:9b`; Anthropic used
`claude-haiku-4-5`; OpenAI API used `gpt-4.1-mini`. All three passed streamed
visible output, one exact individually approved synthetic write, native
continuation, idle resume with unchanged journal events, a further model turn
without tool replay, and a surfaced unavailable-model error. No provider/billing
fallback or model download was used. Scratch transcripts were removed afterward.

Each provider separately passed a live summary/checkpoint request over seeded
synthetic history, subsequent inference retaining its marker/license, and idle
resume without recompression or tools. Anthropic initially returned exactly one
JSON Markdown fence; Ollama initially returned empty visible content. Both failed
closed and retained history. The repair accepts one exact JSON fence while
retaining the strict schema/tool/byte checks, and supplies Ollama's documented
structured-output schema, disabled thinking, zero temperature, and a 4096-token
summary cap only for compaction. Ordinary turn requests are unchanged. Focused
fixtures verify both repairs and continued rejection of prose, multiple JSON
documents, invalid keys, and tool calls. No hidden reasoning was displayed.

All three also passed two separately approved native MCP calls against the
previously reviewed independent Rust filesystem executable: exact synthetic
write and read, followed by idle resume without replay. A safe explicit
`overwrite: false`/`expected_revision: null` proposal from OpenAI was initially
denied by the harness's omitted-argument expectation; the next request used that
exact fully specified proposal and passed. Serial delegation passed with one
exact approved task/context, a real same-provider child reply, parent completion,
and idle resume without starting another child. Initial natural-language task
wording varied the proposed arguments; explicit JSON proposals resolved this
without broad approval or changed host policy.

These are actual provider requests with synthetic data, distinct from fixture
tests and the original ChatGPT subscription evidence. Compaction history was
seeded, not a claim about an extended natural conversation. No live allowance
exhaustion, paid-account eligibility, token revocation, concurrent external
writers, or Mac provider check was performed. Provider keys and private
configuration remain outside Git; only sanitized outcomes are recorded here.

## P9 parallel local delegation, 2026-10-15

Added explicitly enabled two-child groups with serial defaults, exact group/child
approvals, separate journals, and the same provider/model. Nine focused fixtures
pass overlapping tasks, deterministic result order, recursion/MCP exclusion,
mutation serialization, exact approval routing, file and shell wildcard conflicts,
hardlink rejection, complete parent death/cancellation cleanup, sibling shutdown
after failure, headless/default denial, budgets, and concurrency-bound idle resume.
Owner-death checks wait for the coordinator, child sessions, and provider tasks
to stop; readiness is emitted only once per child in the test provider.

Live checks passed on installed Ollama `qwen3.5:9b`, Anthropic `claude-haiku-4-5`,
and OpenAI API `gpt-4.1-mini`: one exact approved group, two real child responses,
parent completion, separate child relationships, and idle resume without starting
children again. OpenAI initially proposed serial calls; those were denied with
no child start. A clearer exact parallel-tool request passed on the same model
without changing approval policy or billing. These are synthetic-data checks,
not arbitrary shared-workspace stress coverage.

Credential-free source and bundled parallel demos verify the approved group,
two child relationships, and idle resume. Source build, formatting,
warnings-as-errors compilation, isolated demo, and **249 tests with Linux native
enforcement included (14 Mac tests excluded)** passed. The exact rebuilt
`dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`, with version-matched runtime
notices, passed fresh-home/utility-only-PATH verification including bundled
serial and parallel delegation. Hosted [Linux/macOS source/package CI passed](https://github.com/lexlapax/ipse/actions/runs/38846368587)
at `4e5f922`. No dependency was added. Reads are not isolated from
writes; unrelated processes and detached descendants retain the documented
limits. Remote/recursive agents and child MCP remain unavailable.

## P10 Streamable HTTP MCP, 2026-10-15

Implemented explicit MCP 2025-11-25 Streamable HTTP POST with JSON/finite SSE
responses, verified HTTPS, optional server-specific static bearer authentication,
and session headers/best-effort DELETE. Reuses the existing SDK, SSE parser,
strict admission/catalog/schema checks, approvals, and synced intent journal.
Existing Req/Finch/Mint provide streaming HTTP/1 with private guarded pools;
no dependency or external runtime was added. See the
[transport contract](mcp.md#streamable-http-boundary) and
[operator setup](../operator/mcp.md#configure-a-network-endpoint).

Twelve network fixtures plus five HTTP profile tests passed: explicit endpoint
and token identity/rotation, JSON/SSE handshake and private session lifecycle,
exact resources/prompts, full approvals/headless denial, authentication errors,
redirect rejection without another request, body/header bounds, incomplete or
mixed malformed streams, wrong IDs, unmatched ping, changed sessions, descriptor
drift, post-dispatch disconnect with unknown/not-started outcomes, idle resume
without replay, cancellation, and owner death closing the client socket. Private
Finch root/children/guardian exit is separately confirmed on borrower death and
normal return. Final review found abrupt request-worker death discarded the
worker identity before waiting for the pool guardian. The regression holds that
guardian open: the old path incorrectly confirms cleanup and fails the assertion;
the repair retains the identity until confirmed shutdown and passes. HTTPS fixtures passed trusted matching-host discovery/tool calls,
untrusted-CA rejection, and trusted-certificate hostname mismatch without HTTP
dispatch. Trust was changed/restored only inside the isolated test VM. An initial
fixture asserted the wrong TLS alert name; the actual hostname rejection was
retained and the fixture now accepts the supported OTP alert names. A later
redirect fixture used the wrong OTP socket-info module; correcting that fixture
restored the full focused pass without changing production policy.

The optional independent verifier passed against the previously reviewed,
checksum-pinned and explicitly patched Apache-2.0 `mcp-memory` 2.0.0 executable.
Its authenticated literal-loopback HTTP endpoint returned finite SSE responses.
A disposable graph check denied one create without dispatch/intent, approved
exact synthetic create/get/search/missing-record calls, checked persisted bytes
and ordinary tool errors, and resumed idle with unchanged events and no replay.
The daemon received only a synthetic server token and selected durability flag,
then its ordinary process group was closed. This was not an arbitrary public
HTTPS service, OAuth server, current upstream release, or remote-isolation test.
See [the exact upstream source/build record](dependencies.md#second-independent-mcp-investigation-memory).

Actual live Ollama `qwen3.5:9b`, Anthropic `claude-haiku-4-5`, and OpenAI API
`gpt-4.1-mini` each passed two exact individually approved create/get calls through
that authenticated HTTP server, parent completion with the synthetic marker,
network-origin intent records, and idle resume without replay. Provider keys
were loaded privately from the ignored `.env` and were never supplied to the
server. These are synthetic-data checks on Arch, separate from fixture and
original ChatGPT subscription evidence. No ChatGPT HTTP MCP check, live remote
cancellation guarantee, OAuth flow, long-lived GET stream, reconnection/event
resumption, other model/host acceptance, or general server compatibility is claimed.

Source build, formatting, warnings-as-errors compilation, isolated demo, and
**262 tests with Linux native enforcement included (14 Mac tests excluded)**
passed. Rebuilt the exact `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` with
version-matched runtime notices and passed fresh-home/utility-only-PATH verification,
including the new bundled HTTP MCP round trip and serial/parallel delegation.
The HTTP demo uses only OTP sockets and the extracted runtime. Hosted
[Linux/macOS source/package CI passed at f5fe717](https://github.com/lexlapax/ipse/actions/runs/38849973400),
including the final worker-death ownership regression and macOS native enforcement.
Serenity ran the local Linux checks; GitHub Actions ran the separate
`ubuntu-latest` and `macos-14` jobs. No macOS suite or Mac live-provider request
ran locally on Serenity. The initial transport's
[hosted run also passed](https://github.com/lexlapax/ipse/actions/runs/38849383383).

## P11 live project assessment, 2026-10-15

The developer selected a read-only assessment of the live dotsetup checkout:
ask what the project does and what its next steps are, independently read it,
then compare the answers and identify needed Ipse changes. Ran the actual
interactive source CLI with explicit ChatGPT subscription selection, requested
`gpt-6.1-sol`, `--cwd` pointing to that checkout, `--sandbox native`, and an
isolated temporary state directory. Project-content transfer to OpenAI received
explicit developer approval after automatic review required it. There was no
provider/billing fallback. Private journals and visible answer copies remained
owner-only outside Git; no transcript, account data, or repository secret values
are recorded here.

The first answer used file reads only. It correctly identified the project's
purpose, implemented command surface, file-link versus system-copy behavior,
completed core work, staged deployment pilot, and explicitly deferred work.
It distinguished repository records from fresh live verification and named the
operator approval/credential gates. Independent code/document review agreed.
It did not inspect current Git state or run checks and said so, but recommended
operator provisioning before doing the available repository preflight.

A neutral follow-up requested current Git state and documented safe checks
before provisioning. The same session performed 27 file reads and nine exact
individually approved shell calls across both turns. No write/edit, Git sync,
installation, real credential provisioning, live system change, delegation, or
MCP call occurred. The follow-up found the existing unrelated lockfile edit,
reported local remote-tracking parity without claiming a fresh fetch, and revised
its recommendation to validation first. The existing worktree and diff hashes
were unchanged afterward. No private project content was added to Ipse docs.

| Check | Inside Ipse's Linux native shell | Independent Serenity check |
| --- | --- | --- |
| Git state and whitespace | Existing change preserved; checks passed; no fetch | Same status and unchanged diff hash |
| Standalone ShellCheck | 52 scripts passed | 52 scripts passed through the normal hygiene command |
| Core sandboxed project suite | Stopped at the first Bash process-substitution failure | 134 passed, 0 failed |
| Full repository hygiene | Stopped before checks at `/dev/fd/63` | Secret scan passed; failed on the pre-existing change's missing changelog entry |
| Repository consistency check | Passed | Passed |
| Integration suite | Five passed, one source-comparison test skipped | All six passed |
| Pinned source verification | Sibling checkout not visible; failed | Existing sibling clone found; all six pinned artifacts matched |

A separate synthetic `mapfile -t lines < <(...)` probe through `Ipse.Runner`
returned exit 0 in explicitly chosen trusted mode and exit 1 with
`/dev/fd/63: No such file or directory` in native mode. The native profile
intentionally has no `/proc` or descriptor-path view. This is a reproduced
compatibility gap, not a reason to expose host processes or silently weaken
confinement. The project's own temporary-fixture tests passed independently;
Ipse correctly reported their native failures rather than claiming success.

The follow-up also called a sandbox-hidden sibling source checkout "absent"
without qualifying host visibility. It exists on Serenity, and independent
pin/integration checks passed. This shows a need for explicit, platform-specific
sandbox visibility facts in model/operator context. Optional extra read-only
roots would require a separate trusted configuration and boundary review; the
trial did not expand roots or retry project commands in trusted mode.

Recommended next work: repair/retest ordinary Bash compatibility while retaining
adversarial enforcement; supply precise sandbox visibility guidance; then add
reusable project-orientation/Git workflow instructions that gather repository
health before operator-only steps. Existing tools handled the workflow after
prompting. There is no evidence here requiring a project registry, workflow
framework, or GitHub adapter; GitHub was not exercised. Substantive editing,
commit/push inside dotsetup, deployment, and other provider/host project trials
remain unverified. This completes the selected read-only assessment, not general
coding acceptance in that live repository. See [remaining P11 work](../plan.md#p11-live-dotsetup-trial).

## Native Bash and visibility repair, 2026-10-15

The developer selected the first two P11 follow-ups: repair ordinary Bash
compatibility and share precise platform-specific visibility facts. The initial
P11 record above describes the pre-repair behavior. Extra dependency roots and
project-orientation/Git workflow guidance remain separate proposals.

On Serenity (Linux x86_64, kernel 7.2.9-arch1-1, installed Bash 5.3.20), the native
profile now supports nested Bash read/write process substitutions, `mapfile`,
`cmp` with two substitutions, child Bash, workspace file descriptors, and standard
input. A fresh read-only procfs belongs to the job's private PID namespace;
host `/proc`, procfs data/enumeration, outside files, and network remain denied.
A live host anonymous-pipe probe confirms the command cannot reopen the host
pipe through private procfs. The outside-PID signal probe now requires ESRCH
because that PID is outside the namespace; other syscall denial assertions
remain strict. Ordinary SIGTERM/exit-37 results, missing executable/interpreter
errors, timeout, and owner-death cleanup all passed. The trusted group leader
and namespace PID 1 reap children; user commands run as ordinary children.
See the [descriptor design](sandbox.md#observed-bash-and-dependency-visibility-limits).

Build, formatting, warnings-as-errors compilation, native demo, and **270 tests
with Linux native enforcement included passed (14 macOS tests excluded)**.
The focused native/stdio suite passed 31 tests (five excluded). These are actual
local Linux checks; no macOS suite ran locally on Serenity.

The real dotsetup temporary-fixture suite passed **134 tests, zero failures**
through the native runner with explicit `USER=ipse-fixture`. Native mode
intentionally does not inherit USER; without that fixture value the project
script stops with `USER: unbound variable`. This is separate from the repaired
Bash descriptor issue. Repository hygiene now reaches its checks: 52 ShellCheck
scripts and the secret scan passed, then the unchanged existing lockfile edit
failed its missing-changelog-entry check, matching the independent result.
No project edits or system operations were made.

CLI startup, `/session`, and model context now derive fixed platform-specific
facts from the same `Ipse.Sandbox` functions. Tests cover Linux, macOS, unsupported
platforms, trusted mode, and consistent session/model/CLI exposure without
reading environment values. A live ChatGPT-subscription check used an isolated,
entirely synthetic workspace, explicit native policy, and one exact approved
shell call. Bash substitution counted three rows; a real sibling was hidden.
The model correctly reported that the path was not visible/inaccessible in the
sandbox and that this did not prove host absence. There was no provider fallback.
Automatic approval review rejected repeating external dotsetup analysis under
the earlier approval; the local project checks and synthetic model check
completed verification without sending additional project content.

Rebuilt the exact `dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz` with
version-matched runtime notices. Fresh-home/utility-only-PATH package verification
passed, including bundled MCP and serial/parallel delegation. An additional
probe through that extracted archive passed native Bash substitution and
confirmed host `/proc` remains absent. Hosted
[Linux/macOS source/package checks passed at 9ee5c3f](https://github.com/lexlapax/ipse/actions/runs/38854953735),
including the separate macOS native enforcement checks. Serenity ran the Linux
native suite; GitHub Actions ran `ubuntu-latest` and `macos-14`. No macOS suite
ran locally on Serenity. The Linux descriptor repair does not establish macOS
Bash compatibility, Linux aarch64 execution, extra dependency-root access, or
general live-project coding acceptance.

## Project orientation skill, 2026-10-15

Continuing the P11 follow-ups added a bundled `project-orientation` skill and a
conditional, explicitly loaded Git assessment resource. They use the existing
skill loader, file reads, and approved shell tools; there is no new runtime
logic, dependency, project registry, GitHub adapter, or expanded file root.
The guidance gathers implementation, existing changes, and available validation
before operator provisioning, distinguishes saved tracking refs from fresh
external state, and preserves read-only scope when requested.

Ipse's parser validated discovery, explicit invocation, source/hash provenance,
and bounded resource loading. Existing skill/resource tests passed (six tests),
as did formatting, warnings-as-errors compilation and the isolated source demo.
The exact Linux archive rebuilt with runtime notices and passed the full
fresh-home/utility-only-PATH verifier. Bundled-skill discovery and explicit resource loading also passed
separately against that extraction.

A real ChatGPT-subscription session (`gpt-6.1-sol`, explicit native policy) used
only a disposable synthetic Git project. It explicitly loaded the Git resource
and ran three individually reviewed shell calls. From a neutral read-only
purpose/next-steps request, it found the pre-existing unstaged inventory change,
identified its mismatch with implementation, reported a real failing fixture
check separately from passing shell syntax, and prioritized repository
validation before operator enrollment. Final status, diff, and file hashes were
unchanged. It did not claim fresh remote state or deployment. Five journaled
tool calls completed. The first harness post-check incorrectly expected local
tool arguments in intent metadata; a corrected harness passed without an Ipse
runtime change. Private journals and synthetic answers remain outside Git.
Hosted [Linux/macOS source/package checks passed at 680b6f3](https://github.com/lexlapax/ipse/actions/runs/38857048801),
including the separate macOS native checks. This is scoped live skill evidence,
not proof that every model will select or follow the skill automatically, and it
sent no additional dotsetup content.

The developer then selected a new forms/SQLite task-tracker app for the coding
trial, replacing the proposed dotsetup coding trial. Dotsetup's read-only
comparison remains complete; its existing edits are preserved. See
[the separate coding trial](../plan.md#p12-task-tracker-coding-trial).

## P12 task tracker coding trial, 2026-10-15

The developer selected a new forms/SQLite task tracker instead of modifying
dotsetup. Ipse built it in the separate local project
`~/projects/lexlapax/ipse-task-tracker`. This used the real embedded
`Ipse.Session` OTP API, not the terminal CLI, with explicit ChatGPT subscription
selection, requested `gpt-6.1-sol`, and trusted shell mode `off`. Trusted execution
was selected openly for public package fetching and local HTTP tests; it was not
a fallback from native mode. Each mutation/shell call was individually reviewed
and approved. There was no provider/billing fallback, delegation, MCP call,
private existing-project transfer, deployment, or new GitHub publication.
State/auth ownership stayed separate; private journals remained outside Git.

The test operator explicitly imposed Elixir/OTP and no Node/Python for this
first app. The developer clarified that Ipse is a general-purpose AI harness
written in Elixir, while its workloads may use other languages or tools, then
selected finishing this app. Repository instructions, entry points, architecture,
and operator guidance now distinguish harness implementation constraints from
workload choices. This specified-stack trial does not verify autonomous stack
selection or broad non-coding coverage. Current host instructions and bundled
tools were coding/project-oriented at this point; P13 later neutralizes the host
role and records separate broader trials.

Ipse implemented server-rendered create/edit/complete/reopen/delete forms using
Bandit, Plug, Ecto SQL/SQLite and Phoenix HTML escaping, with a locked dependency
inventory, explicit migration/setup commands, loopback/Host restrictions, CSRF,
inline validation, and responsive CSS. Initial failures in test fixtures, pool
setup, unsupported SQLite constraint DDL, and blank-title validation were
reported and repaired. Independent review reproduced null-value crashes in the
domain API; Ipse's subsequent trim guards addressed them and seven added domain
regressions prove invalid changesets, normalization, and no partial writes.

Both Ipse and independent Serenity checks passed formatting, warnings-as-errors
compilation, and **16 tests**. Ipse's real Bandit HTTP smoke passed CRUD,
validation, escaping, CSRF/Host checks, GET mutation denial, process restart
persistence, and fresh versus stale forms. A separate independent HTTP client
also verified these key effects against an isolated database across an actual
server stop/restart. Installed Chromium 153.0.8010.52 rendered a 1280 × 900 task
list and a 390 × 844 new-task form; both captures were inspected for layout and
clipping. Screenshots and test state stayed outside Git. No full browser
interaction, screen-reader, load/fault-injection, macOS app, or SSH-forwarding
check is claimed. SSH local forwarding is documented, not configured or tested.

The first implementation turn completed successfully. The review turn stopped
at the compaction trigger after successful tests and Git staging: the transcript
had only two user turns, so there was no older complete prefix outside the two
retained turns. The embedding harness initially discarded the error notification;
metadata-only diagnosis reproduced the planner's "not enough complete user
history" result. A short third user turn successfully compacted **348,382 to
270,175 bytes**, covering 52 earlier messages, then inspected staged state and
committed without replaying implementation/setup/tests. The original journal
remained intact. All 37 tool intents had recorded outcomes: 31 individually
approved mutations/shell calls and six read/skill calls requiring no approval.
This exposes a long-turn usability limit and a need for clearer recovery causes;
no compaction-policy change is claimed. See the
[current contract](context-compaction.md#bounds-and-failure-behavior).

The app source was committed locally at `5d1ebb0`; independent verification docs
were committed at `b55c478`. Its worktree is clean and no remote is configured.
A normal development instance was started on Serenity at `127.0.0.1:4100` with
`var/tasks.db`, separate from the cleaned-up synthetic verification database,
and returned HTTP 200. First creation logged one transient pooled SQLite
connection-lock error before migration/startup succeeded; no request failure
was observed. The source app README owns its operating procedures and limitations.
Dotsetup's original status/diff/lockfile hashes remained unchanged.

This completes the selected local coding trial. The developer selected safe
long-turn compaction, specific diagnostics, neutral stack selection, and separate
non-coding work as [P13](../plan.md#p13-long-turn-compaction-and-general-purpose-trials). This evidence does not require a project registry,
new language-specific runtime dependency in Ipse, or a new GitHub adapter.

## P13 long-turn compaction, 2026-10-16

On Linux Serenity, source build, formatting, warnings-as-errors compilation,
**277 tests passed** with native sandbox tests included (14 macOS tests excluded),
and the native credential-free demo passed. The focused compaction suites passed
**19 tests**, covering deterministic single-turn reductions, parallel batch
protection, unknown outcomes, original provenance across repeated reductions and
later summaries, durable resume, owner death, corrupt checkpoints, existing
summary cancellation, and failure with no partial projection or replay.

A read-only replay of the original P12 failed context reduced **351,956 to
304,892 bytes** by excerpting three older known results, without another user
message. All user text, native fields, exact calls and host provenance were
unchanged; original journal bytes were unchanged and checkpoint restore matched.
This is a planner replay, not new inference over the private transcript.

A separate live embedded `Ipse.Session` used explicit ChatGPT subscription
`gpt-6.1-sol`, native policy, and eight sequential reads of synthetic 25 KiB files
in one user turn. One output checkpoint reduced **185,114 to 66,434 bytes** under
a test trigger of 160,000 (ceiling 400,000). Ipse correctly reported all eight
marker pairs and acknowledged incomplete older excerpts. No extra user turn,
summary request, tool retry, mutation, provider switch, or API billing was used.
All original provider continuation fields matched the effective projection.
Private session state and metadata-only evidence remained outside Git.

The Linux archive passed extracted help/demo, MCP/delegation, helper/OTP, and
long-turn checkpoint verification using a utility-only PATH. Archive SHA-256:
`394d6166751a35ec3d337b2cb1fee968efc94dfc76d5c27299612fb82a3f8b93`.
Hosted Ubuntu/macOS-14 source tests, native macOS enforcement, demo, packaging,
and extracted-package/checkpoint verification passed in
[CI run 38867833020](https://github.com/lexlapax/ipse/actions/runs/38867833020)
for `57c9b67`. macOS checks ran on the hosted Mac runner, not Linux Serenity; the
experimental App Sandbox step remains a separately scoped CI check.

Neutral coding and non-coding evidence is recorded below. The
[compaction contract](context-compaction.md) describes output fidelity limits and
remaining cases that cannot fit. This is host-side projection, not a native
provider compaction endpoint or proof of unrestricted context capacity. The new
within-turn output fallback has live evidence for ChatGPT only; earlier provider
acceptance records cover the older summary path, not new fallback live tests.

P13's final CLI wording also identifies Ipse as a general-purpose local AI agent
and explains `--no-compact` as disabling automatic reduction. After this wording
change, the source baseline again passed **277 Linux tests** (14 macOS excluded),
formatting, warnings-as-errors compilation, build and native demo. The rebuilt
Linux archive passed the same extracted verification; final SHA-256:
`f8dbc34554124b6e7a0fead819ecd7499e7673c85dd58890815d8f8d721d8a67`.
This supersedes the earlier local archive artifact, not its recorded check result.

Hosted Linux/macOS source and extracted-package checks for final CLI wording
`5759bea` passed in [run 38868964874](https://github.com/lexlapax/ipse/actions/runs/38868964874).
Both production macOS enforcement and the separate experimental probe passed;
these ran on macOS-14, while local checks ran on Linux Serenity.

## P13 non-coding document trial, 2026-10-16

An embedded Ipse session used explicit ChatGPT subscription `gpt-6.1-sol`, native
policy, isolated state and four wholly synthetic workshop documents. The request
was a concise cited event plan, reconciling superseded brainstorms with approved
scope/current venue information, without code, external research, messages or
purchases. The initial prompt omitted filenames while forbidding shell discovery;
Ipse's two directory-style reads failed and it requested explicit file paths.
The same session continued after the operator supplied those paths. This is an
honest setup clarification, not first-prompt autonomous directory discovery.

Ipse read all four files, proposed one `event-plan.md` write, and read it back
following individual approval. Independent source review verified November 21,
2026 is Saturday; consecutive program durations total 210 minutes; setup/program/
cleanup fit 09:00–13:30 with no buffer; 22 people fit capacity 24; $180 + 22 × $6 +
$20 = **$332**, leaving **$28** under the $360 cap. Source citations, November 6/13
owner deadlines, unspecified Theo deadline, unconfirmed keys/adapter/snack supplier,
unplaced printing order, and assignment gaps were all correct. Hashes of all four
sources were unchanged. Host records show seven read attempts (including the two
initial failures) and one approved write, with no shell, dependency, MCP,
delegation, external action or provider/billing switch. The artifact and private
journal remain under `/tmp/ipse-p13-notes`, outside Git.

This verifies one bounded file-based planning task, not open-ended research,
calendar integration, messaging, or all non-coding work. No new harness tool or
skill was needed; explicit source paths removed the setup ambiguity. Operator
[guidance](../operator/usage.md#runtime-and-limits) now explains this file-discovery
boundary. The host role is neutral; approvals remain independent of instructions.

## P13 neutral-stack coding trial, 2026-10-16

Ipse's embedded Session API used explicit ChatGPT subscription
`gpt-6.1-sol`, trusted mode selected openly, isolated state and individually
reviewed tools. Requirements specify forms/SQLite behavior and loopback port 4200,
with no language/framework constraint. Ipse inspected installed runtimes and
selected **Python 3.14.7 / Flask 3.1.3 / Flask-WTF 1.3.0 / Waitress 3.0.2 /
SQLite 3.53.4** for maintained HTTP, form/CSRF and escaping facilities without an
asset build or separate database service. Its separate workspace is
`~/projects/lexlapax/ipse-task-tracker-open`; no private pre-existing project data
was sent. The Elixir app on port 4100 is separate and preserved.

Initial implementation was committed locally at `7473a00`. Ipse repaired an
omitted-optional-notes NULL bug found by its tests. Its 25 tests, real Waitress HTTP
CRUD/restart smoke, pip consistency, compilation, CLI default-port check and
staged whitespace checks passed. Independent HTTP review also passed blank-title
inline errors with retained notes, CSRF/Host denials, escaping/CSP, completion,
GET mutation denial and huge-ID handling, but reproduced a **NUL-only title HTTP
500** missed by those tests. The same session reproduced the failure with a
regression before adding a shared WTForms NUL validator, without weakening schema
constraints or hiding database exceptions. Its expanded **44-test** suite passed,
as did independent execution of those tests, real HTTP smoke/restart, dependency
consistency and compilation checks. Independent real HTTP after an actual restart
verified the existing task/status, retained signed session, edit/reopen/delete,
and the formerly failing NUL title now returning **422**. Installed Chromium 153.0.8010.52 desktop
1280 × 900 task-list and narrow 390 × 844 new-form renders were visually inspected
without clipping. No full browser interaction or screen-reader audit is claimed.

The app's exact lock, runtime prerequisites, dependency inventory/license notices,
setup/run/test commands, database/secret location and local single-user limits are
owned by its README. These are separate workload dependencies, not Ipse's graph.
No OS package, provider/billing switch, delegation, MCP, remote publication or
existing private-project transfer was required. App servers used for verification
were stopped. Screenshots, synthetic database and private session journals remain
outside Git. The repair was committed at `5d3d103`; independent verification
docs and the corrected README at `3d27fca`. The app worktree is clean with no
remote configured. All 22 Ipse tool intents had recorded outcomes (20 individually
approved mutations/shell calls and two approval-free skill/resource calls); no
context checkpoint was needed in this trial. Dotsetup status/diff/lockfile hashes
and the original Elixir app source worktree were unchanged.

P13 is complete for the selected context-recovery and two bounded task trials.
The remaining proposed next step is supervised self-development in an isolated
checkout, using a stable harness and independent diff/test review; see the
[first trial](../plan.md#first-supervised-self-development-trial).
No major new Git/GitHub subsystem was demonstrated necessary by these trials.

## Research planning and operator-question audit, 2026-10-16

Documentation-only update: the developer requested adding bounded deep research
to the plan. P14 now specifies a research skill, explicitly configured retrieval,
durable source/claim evidence, optional parent-gathered parallel analysis, and
fixture/live acceptance. No research server, dependency, credential or runtime
feature was added, and no open-web research trial is claimed.

Audited `Ipse.Tools.definitions/1`, session tool assembly/public prompt/approval
interfaces and the CLI input loop. Current native tools contain no structured
question tool; CLI approval input accepts y/yes, while ordinary operator replies
are user prompt text. MCP elicitation remains documented as unsupported.
Operator/developer guidance now distinguishes free-text clarification, typed
choice feedback (absent), and action approval. The related structured-question
proposal is a candidate, not an implementation milestone selected by this audit.
Documentation links/anchors and CLI help/examples are the relevant checks;
no runtime tests or paid inference are required for this planning-only change.

## Scoped configuration, shared skills and routing plan, 2026-10-16

Documentation-only planning update requested by the developer. P15 records
operator/project/directory configuration and required shared operator
`~/.agents/skills/` discovery with explicit precedence/provenance; P16 records
named model profiles, reasoning settings and bounded mixed-provider delegation.
No config parser, skill root, profile setting, adapter or dependency changed.

Rechecked current skill discovery, CLI provider/model configuration, child policy
inheritance and OpenAI request construction. Current code does not automatically
scan shared operator skills or project `.ipse/config.*`, route task roles to
other models, or forward a configurable reasoning-effort field. Operator and
developer guidance distinguish these gaps from the planned contracts. Relevant
verification is CLI help, documentation file/anchor checks and diff whitespace;
no new runtime tests, live inference or access to installed personal skills are
needed for this documentation-only update.

## P15 shared operator skills, 2026-10-16

Stable extracted Ipse code `5759bea` implemented this change in an isolated
worktree, using explicitly approved ChatGPT subscription analysis/edits and
individual tool approvals. The running stable harness stayed separate from
edited source. It added shared operator discovery, canonical-file deduplication,
selected/shadowed provenance and isolated discovery/resource/resume fixtures.
An independent reviewer inspected the source, completed documentation and reran
the checks; no private transcripts, auth or installed personal skills are committed.

A deliberate VM interruption occurred before a build command was approved.
Resuming the same journal stayed idle with identical journal bytes and workspace
diff, with no inference or tool replay. Only an explicit continuation requested
missing work. A later operator pause likewise preserved the trial; independent
review completed the handoff from existing edits rather than repeating effects.

The build exposed inherited bundled Erlang environment interfering with system
Mix tools. The trial explicitly selected system PATH/ERL_ROOTDIR and unset runtime
launcher variables for those checks; this was an announced trusted-toolchain
workaround, not sandbox enforcement. Fresh-HOME source demo also needed the
existing Mix archive cache explicitly selected. Follow-up release-environment
cleanup remains recorded; packaged operation itself passed the extracted verifier.
The isolation fixture initially used a nonexistent convenience API and omitted a
required model; tests exposed both and the fixture was corrected.

Independent source build, formatting, warnings-as-errors compilation, native Linux
suite (284 passed, 14 macOS excluded) and native credential-free demo passed.
All 39 Markdown documents/392 local links passed. The shared-skills bundled archive
built and passed extraction, isolated HOME/IPSE_HOME, utility-only PATH, MCP,
delegation, helper and lifecycle checks. macOS is not claimed from these Linux
commands; hosted checks are tracked separately. Simple one-line metadata, symlink
limitations and source drift behavior remain explicit in developer/operator guides.

## P17 structured operator questions, 2026-10-16

Isolated feature worktree verification on Linux Serenity: the focused question,
session and CLI suites passed **25 tests**. The full native Linux suite passed
**293 tests** (14 macOS tests excluded), including monitored-owner and repeated
checkpoint recovery. Source build, formatting,
warnings-as-errors compilation and native credential-free demo passed. The Linux
archive passed extracted help/demo, MCP/delegation/helper/context checks and a new
credential-free bundled question/explicit-answer check with no toolchain on PATH.

Fixtures verify single/multiple/text validation, no submitted recommendation,
waiting without a model worker, unchanged action approvals, pending and committed
answer recovery, owner death, cancellation/EOF, repeated questions, corrupt
checkpoints, headless failure/refusal and settlement of other proposed batch calls
without effects. Children fail required input explicitly; parent question routing
is not claimed.

A live embedded ChatGPT subscription session requested `gpt-6.1-sol` over a wholly
synthetic prompt with mutations denied. It used one question call for three kinds,
received explicit non-recommended single choice plus multiple/text answers, and
reported all exact values. The first attempt failed safely when the model supplied
dummy choices for a text question under optional-field normalization. Nullable
optional fields, explicit `strict: false` and field guidance repaired this; the
separate repeat passed. No provider/billing switch or private project transfer was
used for this live check. Private journals/evidence stay under `/tmp/ipse-question-live`.
Hosted macOS/new combined-source checks remain pending integration; local Linux
results are not macOS evidence. This stage reuses current JSONSchex/OTP/Jason and
adds no dependency. Operator/developer docs and their map were reviewed together.

The verified operator-question Linux archive SHA-256 is
`26a6444dc0f7491cd85c6052535b98ac1c87a7b729e373d67906c803acaab294`.
All 40 documentation files and 393 local links/heading anchors passed the local
checker. The native question fixture is part of extracted-package verification.

## P15 scoped configuration, 2026-10-16

The isolated configuration branch passed seven loader fixtures and two CLI/session
fixtures, together with 24 existing CLI/session checks (33 focused tests). The full
native Linux suite passed 302 tests with 14 macOS-only tests excluded. These are
credential-free fixture results, not live inference or macOS execution. Configuration
inspection used a provider without credentials and made no request; unchanged idle
resume kept journal bytes/effects unchanged, while source drift refused startup.
Source build, formatting, warnings-as-errors compilation, native credential-free
demo and all 42 Markdown documents/398 local links passed. Integration, packaged
runtime verification and hosted checks remain pending.

## P16 explicit model profiles, 2026-10-16

The model-profile branch passed 309 native Linux tests, with 14 macOS tests
excluded, plus source build, format, warnings-as-errors compilation and the native
credential-free demo. Fixtures cover main/profile selection, supported Responses
effort, invalid provider/model/credential/endpoint combinations, routine/review
routes, every adapter's model mapping, private parent payload/credential exclusion,
forged-route rejection, child journals and idle resume. An initial Anthropic fixture
omitted its required terminal stop reason; correcting the fixture restored the
full suite. This was not a live Anthropic failure.

A synthetic live subscription `gpt-6.1-sol` main profile with `high` effort delegated
exactly once to installed local Ollama `qwen3.5:9b`, with only two arithmetic
expressions selected for child context. Both values (391 and 43) were independently
checked. Parent/child journals verify provider/model/profile/role and preserved
separate conversations; the parent prompt was absent from the child transcript.
Idle resume changed no journal bytes and performed no inference or replay. No
model download, API billing switch, file/shell effect or MCP call occurred.
The initial result lacked host child-identity facts, so these now accompany
successful delegated results instead of depending on child self-description.

Private staging artifacts live under `/tmp/ipse-profile-live/` and are not
committed. This validates this account/model/host, not every reasoning model,
remote Ollama deployment or paid-provider profile. Source package and main/hosted
integration checks follow the first supervised self-development increment.

## Shared skills, questions, configuration and profiles integration, 2026-10-16

The first four authorized stages are integrated into main. The combined source
suite passed 316 native Linux tests with 14 macOS exclusions. Feature hosted
configuration and question checks passed on Linux/macOS. Initial profile CI
stopped at Elixir 1.18 formatting (local toolchain is 1.20); explicit block syntax
repairs that difference. Initial shared-skills macOS CI exposed isolated HOME
hiding rustup's installed toolchain; fixtures now preserve RUSTUP_HOME before
isolating operator discovery, without reading real skills/auth. Those initial
failures were not successful macOS validation. The repaired combined
Linux/macOS checks subsequently [passed](https://github.com/lexlapax/ipse/actions/runs/38924648494).

The stable self-development trial also exposed bundled release launcher variables
selecting its ERTS during system Mix builds. Trusted shell launch now removes only
the active bundle's ERTS PATH entry and launcher variables; source-mode environment
is unchanged. A bundled fixture checks this boundary without a development
toolchain. Configuration/provider selection and native sandbox policy are unchanged.

The integrated Linux archive also passed its extracted verifier, including the
new trusted-shell launcher-variable/ERTS PATH check, question lifecycle, native
helpers, MCP and delegation. Execution used isolated HOME/IPSE_HOME and a utility-
only PATH. All 44 Markdown documents and 414 local links/anchors passed. Hosted
checks are rerun on the integrated commits rather than treating earlier failures
as passes.

Independent final review found and repaired a selected-profile child dropping the
parallel-child file-policy marker. A behavior regression routes through a named
profile and verifies a hardlinked alias write is denied with both files unchanged.
The fixed allowlist retains P9's file boundary across provider/model changes.

## P14 bounded research, 2026-10-16

Credential-free fixtures verify literal source/result provenance, unavailable or
fabricated evidence, ambiguous/failed/oversized calls, stale unverified metadata,
source/claim limits, conflicts/inference/open gaps, inert retrieved instructions,
idempotence, corrupt-record refusal, native journal ordering, actual compaction,
local export and unchanged idle resume without inference/replay. A regression
requires successful ledger recovery from mixed native/MCP tool history; a live
failure exposed a boolean filter error which now has explicit session coverage.
New result timestamps are bound to host MCP completion; legacy capture-time
records remain valid. The default suite requires no external search service.

An explicit ChatGPT subscription `gpt-6.1-sol`/high session used an operator-selected
anonymous Exa HTTP MCP search/fetch configuration. The public question concerned
SQLite WAL concurrency, busy conditions, sidecars and same-host constraints for
a local tracker. Two searches and three single-page fetches stayed within the
announced limits. Three official SQLite pages were captured with literal excerpts
and source/result digests. Four corrected source-supported claims, one application
inference and one residual open note explain resolution of five historical open
notes; none of those old notes was silently deleted.

The first capture could not find host call IDs and safely stayed open. The host
now exposes bounded call attribution plus recent recorded-result references.
The first recovery implementation failed on non-MCP results in mixed history;
a targeted fix/regression allowed recovery using the same five original results.
No search/fetch was repeated to repair capture. Earlier report proposals were
denied until provenance was repaired. The reviewed final report was written,
read back and tightened within 600 words. Unknown/pending actions were never
replayed automatically after an operator pause or VM restart.

Independent review read the captured excerpts and actual primary pages:
[WAL](https://www.sqlite.org/wal.html), [isolation](https://www.sqlite.org/isolation.html)
and [temporary files](https://sqlite.org/tempfiles.html). It checked claim links,
source digests, the report's distinctions between support/inference and uncaptured
residuals, and completeness against the bounded question. URL availability alone
was not the check. WAL's later sections were outside the truncated fetch and their
search-only warnings remain qualified/open. There is no claim of exhaustive SQLite
research, performance testing, application correctness, full-page freshness or
backup validation. Trial ledger timestamps predate completion-time metadata and
represent host source-capture time; publication/author data remain unverified.

Idle resume retained identical journal bytes and the same reconstructed ledger,
without inference, retrieval or writes. Private staging artifacts are under
`/tmp/ipse-research-live/` and are not committed. Linux source/package/main and
hosted results are recorded separately as they finish. A serial research trial
satisfies this milestone; parallel research analysis is not claimed. External
services remain configurable and optional, with no new local runtime dependency.

Final routing review also found that a selected child profile dropped the existing
parallel-child file-policy marker. Preserving it keeps P9 hardlink mutation denial
active across provider/model changes. A regression routes a parallel child through
a named profile, attempts a write to a hardlinked alias and verifies both files
remain unchanged; existing parallel ownership/conflict fixtures still apply.

Final research feature verification passed 317 native Linux tests (14 macOS
excluded), source build, formatting, warnings-as-errors compilation, native
credential-free demo and extracted-package checks. The package now explicitly
verifies scoped configuration, model profiles and durable research bookkeeping
without authentication, inference or external retrieval. All 47 Markdown files
and 421 local links/anchors passed. The independently inspected live report is
485 words and all 14 referenced source/claim IDs exist. Final main integration and
hosted verification are recorded [below](#five-stage-integrated-verification-2026-10-16).

## Five-stage integrated verification, 2026-10-16

Main integrates supervised shared-skills self-development, native structured
questions, scoped JSON configuration, explicit model profiles and bounded research.
The final combined source baseline passed 324 native Linux tests with 14 macOS
exclusions, build, formatting, warnings-as-errors compilation and credential-free
demo. Local `ipse config` inspection and `ipse research --resume` export were
verified without inference or retrieval. Mix's local lock sockets require execution
outside the restricted shell sandbox on this host; TLS/tests were not weakened.
All 47 Markdown files and 427 local links/anchors passed after documentation review.

The research [feature Linux/macOS run](https://github.com/lexlapax/ipse/actions/runs/38928027763)
and [profile-policy repair run](https://github.com/lexlapax/ipse/actions/runs/38927721580)
passed. The final integrated runtime at `320b40f` also passed
[hosted Linux/macOS checks](https://github.com/lexlapax/ipse/actions/runs/38928807090),
including macOS native/experimental enforcement and extracted-package verification.
macOS ran on hosted macOS runners, not on the Linux development host. The local
Linux glibc-2.44 archive passed extraction with fresh isolated HOME/IPSE_HOME and
a utility-only PATH. Its fixtures cover trusted-shell launcher cleanup, scoped
configuration/profiles, durable research, questions, MCP, delegation and lifecycle
without authentication, inference or external retrieval.
The local live report contains three primary sources, eleven immutable claims
(including historical open notes), 485 words and fourteen valid ledger references.
Independent content review and unchanged idle resume passed; no exhaustive research
or unattended self-development claim is made. Retrieval remains an optional,
operator-selected MCP service; no external endpoint/tool name is embedded in runtime
code and no new local dependency is introduced.

## P18 macOS supervised self-development evidence

Local execution, independent review, publication and hosted CI passed on
2026-10-16. Ipse stopped before committing on `codex/trial-macos-self-development`.
After receiving the results, the operator delegated final review and publication
to the supervisor. PR #1 merged after Linux/macOS CI passed for the exact
candidate. P18 is complete within this supervised trial's documented scope.
Follow the [operator procedure](../operator/self-development.md).

During the local trial, the original `main` checkout was clean and unchanged. Fetch confirmed
`origin/main` at `ee50392e87b9f9958b81066707fa777e61c0ac72`. The detached
`ipse-stable-macos` runner and separate `ipse-selfdev-macos` candidate both began
at that commit. The stable checkout stayed clean. Host versions were macOS 26.7.2
build 25G325 arm64, Elixir 1.20.3, OTP 29 / ERTS 17.0.5, Rust 1.97.1 and
Apple clang 21.0.0. The frozen source build, formatting, warnings-as-errors
compilation and isolated demo passed; baseline tests passed 307 with 31 excluded.

The explicit main profile used ChatGPT subscription `gpt-6.1-sol`, high reasoning,
and `ipse-auth`. The operator completed Ipse's own browser sign-in and authorized
plan usage. The saved response and successful review reported `gpt-6.1-sol`;
that identifier does not establish an exact backend revision. The `review` role
selected the same profile. No routine profile, Ollama inference, MCP service or
API-billing fallback was used. Private configuration, journals, snapshots and
authorization details stayed outside Git. Trusted shell execution was explicitly
selected with `--sandbox off`; parent and child effects received individual
approvals, without a `--yes` trial launch.

Ipse loaded project orientation and its Git resource, proposed the bounded plan,
and asked a native single-choice scope question. `invalid-option` was rejected
while the question remained pending; explicit `confirm` was accepted. No
recommendation was submitted automatically, and the answer granted no effect
permission. The first CLI edit required a separate approval.

After that settled edit, the initial pre-exit journal checksum failed: idle
`/exit` appended exactly one `cancelled` event. A cryptographic prefix comparison
proved that all previous bytes were unchanged. Diff, status and all tracked and
untracked file digests matched. The supervisor exited again, snapshotted the
journal after exit, and resumed with the same runner and configuration. The
post-exit journal hash and workspace comparisons passed before continuation.
Resume restarted no inference or tools. The runbook now uses that timing;
runtime cancellation behavior was not changed.

Ipse authored the implementation, help, tests, usage guidance and runbook fix.
The runtime diff is confined to `lib/ipse/cli.ex`: the existing `Journal.list/1`
result passes through an explicit four-key allowlist and Jason. Default text
output is unchanged. Listing has no authentication, inference, network call,
journal repair or mutation, and adds no dependency. Eight isolated fixtures cover
ordering, exact keys, escaping, nulls, empty/missing stores, invalid journals,
truncated tails, explicit stores, private-data exclusion and unchanged bytes.

The authoring session's focused run passed 24 tests. The supervisor inspected
the source and tests before independently running the following checks:

| Check | Local Mac result |
| --- | --- |
| `./scripts/build.sh` | Passed |
| `mix format --check-formatted` | Passed |
| `mix compile --warnings-as-errors` | Passed |
| `mix test test/cli_sessions_test.exs test/ipse/journal_test.exs test/cli_test.exs` | 24 passed |
| `mix test` | 315 passed, 31 excluded |
| `mix test test/macos_sandbox_test.exs test/stdio_runner_test.exs --include macos_sandbox` | 27 passed, six Linux-native tests excluded |
| `IPSE_HOME=<isolated directory> ./bin/ipse demo` | Passed without a model |
| `IPSE_NOTICES_DIR=<local notices> ./scripts/package.sh` | Built `ipse-0.1.0-darwin-arm64.tar.gz` |
| `elixir scripts/verify-package.exs dist/ipse-0.1.0-darwin-arm64.tar.gz` | Passed under a 300-second `Ipse.Runner` timeout; no timeout |

The package verifier used an extracted runtime, fresh isolated HOME/IPSE_HOME
and a utility-only PATH without Elixir, Erlang, Mix or Rust. It checked help,
demos, default and explicit cwd, helper cleanup/locks, Mac native enforcement,
and bundled MCP, delegation, questions, configuration and research fixtures.
Separate actual CLI-process checks exercised both source and extracted
`sessions --json`, compared text output with the frozen baseline, and verified
allowlisting, nulls, escaping, private-data exclusion, unchanged journal bytes
and missing-store noncreation. These used synthetic journals without credentials.
Packaging included existing dependency notices and the installed Elixir/OTP
top-level notices with provenance. This is local package verification, not a
complete toolchain-component notice audit or a published release. Existing
`elixir_uuid` and JSONSchex dependency warnings appeared during fresh builds;
the project warnings-as-errors check passed.

The first configured review exhausted six model steps and returned an unknown
outcome without a final review. The private child journal and workspace were
inspected before an explicit narrower request; no child was replayed. The second
review loaded the review checklist, made one approved read-only shell call and
completed after four responses with no actionable findings. Routing independently
matched `review`/`main`, ChatGPT `gpt-6.1-sol`, high reasoning. The parent reread
the CLI, tests and `Journal.list/1`; the supervisor independently reviewed the
diff, coverage and actual results. No source or test repair was needed.

One subscription stream ended before `response.completed` and executed no tools;
the supervisor inspected state and explicitly continued with the same profile.
Later, context compaction stopped twice because retained context could not fit
safely. The original journal remained intact and no tools replayed. The supervisor
closed Ipse and finished only evidence/status documentation. The verified source
and tests stayed unchanged. This trial does not establish unattended operation,
an unlimited context, or the complete live refresh/logout lifecycle on this Mac.

Documentation review covered operator and developer guidance and retained the
existing map/ownership. Local file and heading checks passed for 48 Markdown
files and 442 links; all eight edited runbook shell blocks parsed with `sh -n`.
Private transcripts and auth remain excluded. At the initial local handoff, no
commit, push, PR, new hosted CI run or merge had occurred. Publication evidence
appears below. No local Linux execution or stronger detached-process
diagnostic is claimed.

### P18 publication and CI, 2026-10-16

The supervisor committed the seven reviewed source/test/documentation files as
`d8a7fd8bde675d7fa409b5aeb1fb24ef2b326641` and published
[PR #1](https://github.com/lexlapax/ipse/pull/1). Both the
[push workflow](https://github.com/lexlapax/ipse/actions/runs/38944044532) and
[pull-request workflow](https://github.com/lexlapax/ipse/actions/runs/38944101262)
completed successfully for that exact candidate, with Linux and macOS jobs in
each run. The jobs included source formatting/compilation/tests, demos and
extracted-package verification. The Mac jobs also ran native policy unit tests,
native/stdio enforcement fixtures and the default experimental enforcement probe.
Those hosted checks supplement the local Mac evidence above.

PR #1 merged as `d14e78195b76f5df768fd581d19299bdbc5c1e9c`. The original checkout
advanced by fast-forward after its clean state was confirmed. The frozen runner
remained at `ee50392`.
The completion update changes documentation only; the implementation and tests
retain the hashes verified during the local trial. No credentials or private
journals were committed, no archive was released, and no local Linux or stronger
detached-descendant diagnostic is claimed.

## P22 extension research and planning, 2026-10-16

Research/design only: [extension comparison](extensions.md) and
[diagnostics/tracing proposal](observability.md) review primary OpenCode (main and
separate V2 docs), official Codex, Pi declarations/guide, Claude Code, Elixir/OTP,
Telemetry and OpenTelemetry documentation. Upstream references were opened on
2026-10-16. No upstream runtime/plugin was installed, no live model or extension
interoperability trial ran, and no callback API, trace flag, memory store or new
dependency was implemented by the research increment. P19–P21 were subsequently
authorized for implementation, with their evidence below; P22 has researched
acceptance criteria rather than an implementation-complete claim. Operator and
developer entry points distinguish current facilities from proposed behavior.

## P19 diagnosis and explicit recovery

Implementation verification completed within the scope below. Synthetic fixtures reproduce a long
single turn whose required native continuation alone exceeds the context ceiling;
compaction refuses without altering it and exact byte categories explain why.
The original P18 private Mac transcript is unavailable here, so that live failure's
dominant category/root cause is not claimed. Context accounting, secret exclusion,
saved inspection, unknown outcomes, explicit handoff, cancelled requests,
corruption refusal and unchanged idle resume passed focused local fixtures.
Final local verification passed 340 native Linux tests (14 macOS exclusions),
build, formatting, warnings-as-errors compilation, the credential-free demo and
the extracted glibc-2.44 package. Eight diagnostics/recovery tests include the
actual Session refusal path, exact escaped JSON byte accounting, native/content
secret exclusion, unknown-effect references, complete printed artifact bounds,
no tail repair, corrupted checkpoint refusal, cancellation and unchanged idle
resume. The new package fixture checks saved diagnostics and explicit handoff
export without inference or replay. Hosted Linux/Mac results are recorded below;
no local Mac run is claimed.

The first P19 hosted run passed Linux but failed the existing Mac lost-resource
fixture's five-second end-to-end receive budget after tool dispatch. It did not
report a false successful result. The fixture now observes dispatch readiness
separately and allows the configured five-second call lifetime plus bounded
helper/transport cleanup before asserting error, unknown/not-started outcomes and
no-replay resume. Protocol timeouts, cleanup and those assertions are unchanged.
This is a fixture timing repair; the hosted rerun below verifies it.

The repaired baseline subsequently [passed Linux and macOS](https://github.com/lexlapax/ipse/actions/runs/38953064513)
at `8c0a34b`, including native Mac, experimental enforcement and extracted-package
checks. The prior [P20 source/package matrix](https://github.com/lexlapax/ipse/actions/runs/38952257791)
also passed both platforms. These are hosted Mac results; Serenity ran Linux only.

## P20 reusable self-development skill

The bundled skill covers frozen-runner separation, explicit scope, independent
review, real child budgets, content-free diagnostics, reviewed handoff and honest
source/package/platform evidence. Its two resources remain inert. The scripted
source fixture passed: the real Session loaded the skill and both resources,
recorded source SHA-256 provenance, and issued no tools beyond those three reads.
Effect policy was denied, state/HOME were isolated and no model inference/auth
or external service was used. The extracted glibc-2.44 package ran the same
fixture successfully under isolated HOME and a utility-only PATH, and the full
native Linux suite passed 340 tests (14 macOS excluded). The live P21 evidence
below records supervised use and its limitations; the fixture does not prove a
model followed every instruction.

## Release staging cleanup after a toolchain upgrade

On 2026-10-16, inspection found that `mix release --overwrite` retained both
ERTS 17.0.6 and 17.1 after Serenity upgraded OTP. The active launcher selected
17.1 and functional checks passed, but the old directory remained in the archive
and the supplied OTP notice collection still described 29.0.6. No archive was
published. The frozen P21 trial runner was preserved unchanged.

Packaging now recreates only its fixed generated staging directory before release
assembly. The strengthened verifier rejected the old two-runtime archive. A
fresh build contained one ERTS runtime and passed all extracted-package fixtures
under isolated HOME and utility-only PATH. This local build used Elixir 1.20.4,
OTP 29.1.1/ERTS 17.1 and glibc 2.44. Its external notice collection was refreshed
from official OTP tag `OTP-29.1.1` (`ad05823719d77c8faee87348ea39513d4e2f99c5`),
retaining the matched Elixir 1.20.4 collection. It includes upstream license trees,
authors, ERTS vendor licenses and a header inventory, with explicit source
provenance. This is notice collection evidence, not legal certification or proof
of portability to another libc. Hosted packaging verification is recorded with
the final P21 checks.

## P21 fresh-chat handoff authoring checks

Candidate authoring completed from `b7c0ed6` with a frozen P20 runner outside the
candidate. The operator-selected fresh-session handoff did not replay the retained
private journal. The focused export-compatibility fixture now models the real
source user/assistant tool-call messages plus `tool_started` intent; its restored
unknown-outcome assertion is unchanged.

Local authoring checks passed `mix format`, `mix compile --warnings-as-errors` and
`mix test test/handoff_test.exs test/cli_test.exs test/diagnostics_test.exs` (31 tests;
`:native_sandbox` and `:macos_sandbox` tags excluded by the default helper). These
are schema/API and local HTTP/terminal fixtures, not live inference. New CLI cases
cover idle import, exact saved bytes, a fresh operator prompt before any provider
request, current Ollama fixture routing, independent mutation denial, invalid
artifacts before auth/session creation, and conflicting modes without changing
source state. The tests exposed a strict-boolean CLI guard crash for absent flags;
explicit boolean checks repaired it before the passing run.

These focused checks preceded the supervisor's independent review, full suite,
native/platform and extracted-package checks, hosted checks and publication,
recorded below. No original private journal, provider/billing
selection or dependency was changed; no commit/push/merge was performed by this
authoring session. See [import contract](context-compaction.md#diagnostics-and-explicit-handoff)
and [operator recovery](../operator/recovery.md).

## P21 supervised Serenity trial and independent checks

The live author used Ipse's own ChatGPT subscription authentication, explicitly
selected `gpt-6.1-sol`/high and a frozen extracted P20 runner. The candidate was
isolated in a Git worktree. The supervisor reviewed each proposed effect rather
than enabling blanket approval. The original archive SHA-256 was
`d45211c3325567f62a949ddd0dc492ddb61c7f2f3cb04fab5e0833d72080feba`.
Its active ERTS was 17.1; the later staging cleanup left that frozen runner intact.
An initial staging configuration used a provider string instead of the embedding
API's atom and refused before inference; the harness was corrected explicitly.
There was no silent provider/billing switch or borrowed Codex authentication.

The model loaded the self-development resources, but repeated orientation and
small edit cycles required supervisor phase narrowing. Two deliberate stops
exercised idle resume, with journal and source-file bytes unchanged before a
fresh continuation prompt. At one stop an edit proposal had not started; its
source and intent were inspected before continuation, and it was not replayed.
The original parent later stopped safely at 326694 retained request bytes,
above its 320000 soft target but below its 400000 hard ceiling. Its content-free
breakdown included 141053 instruction bytes, 66963 checkpoint bytes and 57388
native-continuation bytes. This is P21 evidence, not the unavailable P18 Mac
transcript's root cause. Journals/native continuation were preserved.

The supervisor exported and reviewed a P19 handoff note, then manually supplied
the note and remaining contract to a fresh author session: the frozen runner
predated the new import feature. The new session completed in 21 steps. Existing
deterministic output compaction reduced one request from 342182 to 259508 bytes.
Its final retained context was 308493 bytes, below the 320000 target. A subsequent
idle resume of this actual live session again proved byte-identical journal and
workspace without inference or tool replay. These are supervised recovery and
authoring results, not unattended development or automatic self-upgrade evidence.

Independent candidate verification passed build, formatting, warnings-as-errors,
351 native Linux tests (14 Mac-only tests excluded), and the credential-free demo.
The integrated glibc-2.44 package passed all extracted fixtures with isolated HOME
and utility-only PATH. A new package fixture validates exported-artifact import,
fresh idle state, exact durable projection, rejection of an approval field and
byte-identical idle resume, without inference or effects. API/CLI fixtures also
cover changed/deleted artifact files and corrupt/duplicate/misplaced records.
The supervisor audited closed-schema validation, current configuration, no source
session lookup, no source call dispatch and validation before tail repair.

Automatic approval review initially rejected the child-review terminal approval,
mistaking the independent demo's scripted effects for review actions. Journal
inspection confirmed that the distinct review parent had executed zero tools and
created no child. Following explicit operator approval, that exact delegate call
ran successfully; no denial was bypassed or old effect replayed.

A scripted parent selected the single review task and supplied 3568 bytes of
contract/Session diff. The separate live child used the configured `review` role,
explicit ChatGPT `gpt-6.1-sol`/high and its normal six-step/two-minute ceiling.
It made two targeted reads (`handoff.ex` and `cli.ex`) and three completed model
requests, with recorded request durations 3069, 3141 and 9703 ms. It performed no
mutations, shell calls, tests, MCP calls or further delegation. The child reported
no findings within the permission-transfer, saved-call replay and immutable-resume
scope. The supervisor checked its source claims and existing behavioral fixtures.
This is a bounded code review, not a whole-repository security certification;
saved-record consistency does not authenticate coordinated journal tampering.
The parent and child finished and closed; private review journals remain outside Git.

The full
[hosted Linux/macOS matrix](https://github.com/lexlapax/ipse/actions/runs/38961827683)
passed at `6324b6b`, including native Mac, experimental enforcement and both
extracted packages. The earlier [packaging repair matrix](https://github.com/lexlapax/ipse/actions/runs/38960841130)
also passed. Serenity ran Linux; these are independent hosted Mac checks, not a
local Mac live-account trial. P21 is complete within the supervised trial scope;
the intervention and context-limit evidence above remain part of that result.
Private transcripts, auth,
environment values and handoff notes are retained outside Git.

The final P22 design refinement adds a feature/SDK coverage matrix, typed return
contracts, context/state/effect boundaries, installation and compatibility policy,
four delivery gates and a separate memory/workflow package proof requiring no
core/native edits. Operator/developer entry points and the plan agree that this
is planning, with no extension implementation or dependency added. Markdown file
and anchor validation passed across 54 tracked documents and 487 local links.

## P22 extension adoption scenario review

The operator's bundled default-off, independently installed, assisted setup and
generated permanent/temporary feature cases were exercised as architectural
walkthroughs in [extension adoption](extension-scenarios.md). The earlier
rebuild-only loading route and single enablement concept did not cover those
cases. The revised design separates artifact, installed/trusted record and scoped
activation instance; makes SDK values backend-independent; requires a standalone
Elixir worker/local import proof; and specifies configuration, leases, retention,
promotion and versioned future idle activation. The matrix also covers versions,
interrupted installs, missing artifacts, revocation and project discovery.

Current Config/CLI, Session/journal, Runner and MCP transport ownership were
reviewed. Official OTP code-loading/port and Elixir compilation documentation
informed the process boundary; no upstream code/tooling was installed. This is a
design gap analysis and future fixture specification, not executed extension
tests, a working installer or proof that every future feature needs no core
enhancement. P22 implementation remains unstarted. Network catalogs, managed
builders and live catalog replacement are explicit follow-ons; the foundational
contracts must refuse unsupported operations without silently executing code.
Operator/developer guidance, dependency policy and navigation were updated;
document links/anchors and current CLI help are checked for this planning change.

## P22 runtime and knowledge capability review

Primary-source comparisons and current Config/CLI, Session/progress/usage,
provider streaming and journal inspection inform the
[runtime boundary](runtime-capabilities.md) and [knowledge family](knowledge-extensions.md).
P22 now specifies observability on/off/local/export control, local developer
diagnosis, durable usage facts, bounded private text subscriptions and service/
evidence/job composition. P23 plans reports/budgets, P24 voice/realtime and P25
independent default-off memory/research/graph/RAG packages. These entries are not
implementation authorization or live integration evidence.

The documented `mix test test/handoff_test.exs --trace` source-debugging example
passed all eight existing synthetic handoff fixtures. No new runtime code,
dependency, raw BEAM trace, source debugger, external
exporter, cost service, audio device/provider, graph or RAG engine was installed
or exercised. Future acceptance cases explicitly cover disabled parity, capture/
egress control, unknown accounting, stream pressure/cancellation and retrieval
scope/provenance. Operator/developer entry points, plan and dependency inventory
are reviewed together, with file/anchor checking before publication.

Zero-Mem's paper, paper-linked repository and an independent Rust implementation
were opened as distinct research sources. No code was installed/copied and no
reported benchmark was reproduced. The knowledge plan now requires per-capability
research/selection gates and a tool/skill/MCP/extension/core decision before any
production implementation. Zero-Mem is an inspiration candidate, not a selected
dependency, and token-free maintenance does not imply zero total compute/cost.

## Extension artifact foundation (2026-10-16)

P22A1 adds the inert manifest/store API, not executable extension activation.
On Serenity (Linux, Elixir 1.20.4 / OTP 29.1.1), `./scripts/build.sh`,
`mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix test --include native_sandbox` and `./bin/ipse demo` passed. The full suite
reported **358 passed / 14 macOS tests excluded**. Afterward, one additional
interrupted-stage/symlinked-lock fixture was added; the complete focused
`mix test test/extensions_store_test.exs --trace` run reported **8 passed**.
No runtime code changed after the full run. Expected negative TLS and killed
transport fixtures emitted diagnostics; no test failed.

The focused fixtures cover nested duplicate keys, closed/bounded descriptors,
path/hash/runtime declarations, inert copying/idempotence, source changes,
symlinks, corruption/extra files, persistent advisory-lock inode identity and
abandoned staging. See [developer contract](extension-artifacts.md) and
[operator limitations](../operator/extensions.md). No live model, extension worker,
macOS execution, extracted-package execution or release publication was verified
by this increment. Those remain later P22 acceptance checks.

## Independent extension worker bridge (2026-10-16)

P22A2 adds the explicit developer worker API and `Ipse.Extension` behaviour.
On Serenity, the full build, format, warnings-as-errors compile and credential-free
demo passed. After protocol integer/duplicate-key tightening, the final
`mix test --include native_sandbox` reported **365 passed / 14 macOS tests excluded**;
focused store/worker fixtures reported **14 passed**. The external fixture is
compiled with the existing Elixir compiler in a separate VM; runtime callbacks
use the current ERTS through the native stdio helper. A uniquely named module
runs without creating its module atom in the host. Explicit trust/options,
initialization/capability bounds, credential exclusion, wrong IDs, nested duplicate
response keys, non-JSON returns, unframed stdout, callback crash/timeout, contention
and idle/active owner death are covered. Tests use synthetic local code/data only.

Initial fixtures exposed the effect of Erlang `-noinput` and standard-I/O encoding;
the bridge now uses binary Latin-1 I/O without `-noinput`. The passing final runs
include that correction. See the [worker contract](extension-artifacts.md#independent-worker-sdk)
and [operator status](../operator/extensions.md). This increment does not yet
verify session activation/configuration, durable projections/resume, an OS sandbox,
extracted-release worker startup or live providers. Hosted macOS results must be
recorded separately once available.

## Scoped extension selection and inert CLI (2026-10-16)

P22A3 implements `extension import PATH`, `extension inspect DIGEST`, data-only
scoped instances/operator-only trust ceilings, temporary `--extension INSTANCE`,
`--no-extensions`, deterministic ordering and option-digest inspection. Enabled
selections explicitly refuse chat/run while session activation is pending.
Discovery never starts extension code. Tests verify project self-trust refusal,
whole-instance precedence, typed bounds, unknown/duplicate selectors, temporary
lifetimes, disabled parity, secret option exclusion, inert CLI verification and
unchanged pre-extension fingerprints for configurations without extension data.

On Serenity, `./scripts/build.sh`, format checking, warnings-as-errors compilation,
`mix test --include native_sandbox` and the credential-free demo passed. The final
full run reported **373 passed / 14 macOS tests excluded**; the focused selection,
existing configuration and artifact tests reported **23 passed**. Runtime code
was not changed after that full run. No paid provider, macOS or extracted-package
extension execution was verified by this increment. See
[selection procedures and current limits](../operator/extensions.md) and
[configuration contract](configuration.md#extension-selection-data).

## Session extension hooks (2026-10-16)

P22A4 implements explicit registry/session admission and two default-off built-ins:
`builtin:prompt-annotation:1` and `builtin:answer-format:1`. Independent local
artifacts use the same worker SDK without loading their modules or creating
module-name atoms in the host. Intent precedes executable initialization;
validated projections preserve raw operator input, original messages and native
continuation. Resume restores cached projections without callbacks or inference.
See [developer contract](extension-hooks.md) and [operator procedures](../operator/extensions.md).

On Serenity (Linux, Elixir 1.20.4 / OTP 29.1.1), the final build, format checking,
warnings-as-errors compilation, `mix test --include native_sandbox` and
credential-free demo passed: **387 passed / 14 macOS tests excluded**. Focused
worker/session fixtures reported **16 passed**, registry fixtures **4 passed**,
and the actual MCP schema plus worker files **14 passed**. Tests cover ordered
hooks, plain JSON before encoding and after decoding, callback errors/timeouts,
credential exclusion, redacted actual status queries, original/native integrity,
mutation denial, expiry/child ceilings, missing/tampered artifacts, deleted/
mistyped/duplicate/orphan projections and corruption refusal before tail repair.
An interrupted-tool regression verifies generated unknown-outcome placeholders
remain consistent in subsequent callback context hashes and are never replayed.
The cancellation/owner-death fixture checks its actual callback VM exits using the
existing shell `kill -0` builtin. Unfinished callback intents remain inert on
byte-identical idle resume.

The source `priv/extension-demo.exs` fixture passed with both examples and idle
resume. An initial extracted-package check also passed without system development
tools. Final archive verification is recorded separately after rebuilding the
current code/documentation snapshot. Worker boot uses installed OTP's profile-free
`no_dot_erlang.boot` or the bundled Mix `start_clean.boot`; their boot instructions
were checked to exclude `c:erlangrc` startup. The worker fixture confirms Ipse's
application tree is not automatically started. No paid model, live account,
macOS local run, remote installer, full SDK, supervised extension-only trial or
published release is claimed by this increment. P22 remains in progress.

The final archive was reassembled from the current code/documentation snapshot
with `IPSE_NOTICES_DIR=/tmp/ipse-toolchain-notices-29.1.1 ./scripts/package.sh`;
`elixir scripts/verify-package.exs dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz`
passed. It exercised both hook examples, preserved native fixture data and
unchanged idle resume alongside the existing complete package verifier, using
fresh isolated homes and a utility-only development PATH. The archive is a local
verification artifact, not a published release. Hosted platform evidence follows
the commit's CI run separately.

## Extension formatter compatibility (2026-10-16)

The first P22 worker/config/hook hosted runs stopped at the Elixir 1.18 formatter
gate, including [the hook run](https://github.com/lexlapax/ipse/actions/runs/38984098657).
Both Linux and macOS builds completed; their test/package steps were skipped.
Do not count those skipped steps as hosted runtime verification. Serenity's
Elixir 1.20 formatter had accepted two multiline guarded short clauses that 1.18
rewrapped. Their explicit `do`/`end` equivalents preserve behavior and formatting
across the supported versions. Local formatting, warnings-as-errors compilation
and **16 focused worker/session tests** passed after the repair. The next hosted
run must independently establish floor-toolchain and macOS runtime/package evidence.
See [operator troubleshooting](../operator/troubleshooting.md#build-and-sockets).

[The repaired hosted run](https://github.com/lexlapax/ipse/actions/runs/38984630310)
for `efbc862` passed both `ubuntu-latest` and `macos-14` on the existing
Elixir 1.18 / OTP 27 matrix. Formatting, compilation, default tests, demo,
packaging and extracted-package verification passed on both; the macOS native
enforcement step also passed. This establishes hosted macOS hook/package
verification, not a local macOS run on Serenity. The matrix used credential-free
fixtures and did not validate a paid account or publish a release.

## P22 request accounting (2026-10-16)

On Linux Serenity, source build, formatting and warnings-as-errors compilation
passed. `mix test --include native_sandbox` passed **406 tests, 14 macOS excluded**.
After tightening malformed-data recovery, **37 focused normalization/accounting/
session/question/delegation tests** passed. Tests use synthetic provider output and
local HTTP; no paid inference, audio device or subscription billing check ran.

Fixtures establish intent before dispatch, cumulative snapshot deduplication,
inclusive cache/reasoning semantics, omitted Ollama counters remaining unknown,
partial failed/cancelled usage, unknown crash outcomes, unchanged idle resume,
pre-tail-repair corruption refusal, retained usage after rejected summaries,
parent attribution across parallel children and original native-data integrity.
The source extension fixture also checks content-free usage and unchanged
accounting on idle resume. Pricing and budget enforcement remain unimplemented.
See the [developer contract](usage-accounting.md) and
[operator inspection](../operator/usage-accounting.md).

The Linux glibc-2.44 archive rebuilt with the current OTP 29.1.1 notices and
passed `scripts/verify-package.exs` in extracted runtime isolation, including the
extended hook/accounting fixture. The archive remains a local artifact; this
increment has no new hosted macOS or live-account evidence yet. Documentation
review checked **62 Markdown files / 590 local file and heading links**.

[Hosted verification](https://github.com/lexlapax/ipse/actions/runs/38987855108)
for accounting commit `a9c1f02` subsequently passed the existing Ubuntu/macOS-14
Elixir 1.18 / OTP 27 jobs, including formatting, tests, demo and extracted-package
verification on both, plus macOS native checks. This is hosted evidence for
accounting, not a local macOS run on Serenity or proof of later text-channel edits.

## P22 private visible-text channel (2026-10-16)

On Linux Serenity, the source build, format check and warnings-as-errors compile
passed. The full `mix test --include native_sandbox` run passed **419 tests, 14
macOS excluded**. An early focused run exposed an on-exit fixture cleanup race
against the broker's already-correct owner monitor; removing redundant stop
eliminated it. The final native suite includes the repaired fixture.

Private-channel fixtures cover exact Unicode concatenation, bounded escaped
JSON frames, caller-bound acknowledgment, cumulative sequence checks, producer
backpressure/deadline, control overload, invalid/stale chunks, consumer/owner death,
responsive cancellation, native/summary exclusion and ephemeral no-replay resume.
The source extension fixture consumes raw visible text while completed formatting
and accounting remain intact. After adding schema/usage/text modules to the pinned
host digest, **22 focused registry/session/schema tests** and the source fixture
passed. Installed-worker subscription handles and audio are not implemented by
this increment. See the [embedded contract](text-streams.md) and
[operator limits](../operator/extensions.md#visible-text-clients).

The current Linux archive rebuilt and passed extracted-package verification with
the private-stream fixture on a utility-only PATH and fresh isolated homes.
An additional **9 focused channel tests** passed after strengthening the escaped
text fixture to include a full 2048-byte NUL frame. No paid provider, audio device,
release publication or new hosted macOS text-channel verification ran locally.
Documentation review checked **63 Markdown files / 597 local file and heading links**.

[Hosted verification](https://github.com/lexlapax/ipse/actions/runs/38989190974)
for text-channel commit `347e4b9` subsequently passed Ubuntu and macOS-14 on
Elixir 1.18 / OTP 27, including default tests, demo and extracted-package checks
on both and macOS native enforcement. This is hosted evidence for that commit,
not local macOS execution on Serenity or verification of later SDK edits.

## P22 typed catalogs and invocation receipts (2026-10-16)

On Linux Serenity, source build, format check and warnings-as-errors compile
passed. The full `mix test --include native_sandbox` run passed **435 tests, 14
macOS excluded**. The first full run exposed inconsistent injected/current clocks
in the final registry lease check; preparation now uses one admission clock,
while Session admission still rechecks actual current time. After the fix,
**23 focused registry/invocation/session tests** and the full suite passed.
Earlier, **31 catalog/invocation/actual CLI tests** passed. No paid inference ran.

Independent artifacts compile in a separate Elixir VM and execute only after
journaled admission. Fixtures cover inert import/catalog discovery, names and
schema bounds, full tool denial/approval, duplicate native call IDs, source/scope/
catalog pins, separate command/service values without model requests, unknown
failed callbacks, actual worker exit after cancellation/owner death, cached
receipt recovery across an omitted ordinary tool-message record, and corrupt/
deleted/replayed result refusal before journal tail repair. Idle resume performs
no callback initialization. JSON fields that resemble actions remain data.

The source hook/accounting/text fixture and credential-free demo also passed.
The bundled fixture exercises those built-ins; independently compiled custom
tools/commands/services are source tests at this point. A separate imported SDK
artifact proof in extracted runtime isolation remains required before P22
completion. Host action/state/composition/workflow/observation capabilities are
not implemented by this increment. See [contract](extension-invocations.md) and
[operator controls](../operator/extensions.md).

The Linux glibc-2.44 archive rebuilt with the matching OTP 29.1.1 notices and
passed `scripts/verify-package.exs` under extracted-runtime isolation, a
utility-only PATH and fresh homes. This is a local archive, not a release or
live-account/macOS check. Documentation review checked **64 Markdown files /
619 local file and heading links** with no broken targets.

[Hosted SDK verification](https://github.com/lexlapax/ipse/actions/runs/38992510651)
for `a8e907d` passed the Ubuntu/macOS-14 Elixir 1.18 / OTP 27 jobs: format, compile,
default tests, demo, package and extracted checks on both, plus macOS native
enforcement. This is hosted evidence for catalogs/invocations, not local macOS
execution on Serenity or verification of later host-state changes.

## P22 host-call continuations and scoped state (2026-10-16)

On Linux Serenity, the source build, format check and warnings-as-errors compile
passed. The final `mix test --include native_sandbox` run passed **448 tests, 14
macOS excluded**, including the complete action-chain and namespace checks.
**38 focused state/invocation/catalog/session tests** also passed. An earlier
20-test run exposed shared synthetic state between fixtures, a linked failed
startup assertion and an undersized large-file fixture; these test setup issues
were repaired before the successful runs. No paid/provider/device check ran.

Fixtures cover separate full write approval/denial, denied headless proposals,
actual VM cleanup while awaiting approval, retained tombstones/stale CAS refusal,
generation-pinned pagination, metadata-only listings, cross-process native lock
contention/inode preservation, scope/source/artifact/instance isolation, quota/
JSON/symlink/corruption refusal, finite 16-operation loops and unknown host-call
shutdown without callback continuation. Recovery rejects altered, orphaned,
replayed and deleted action receipts, including deletion of the whole operation
chain, before tail repair. Committed and unknown receipts restore idle without
callbacks/storage replay or journal changes. See [host contract](extension-host-calls.md)
and [operator controls](../operator/extensions.md#scoped-state-host-calls).

The credential-free demo and existing source hook/accounting/text fixture passed.
The new independent state-calling artifact is a source fixture; it is not yet
the separately installed package coverage proof required to finish P22. This
increment adds no database, automatic memory adapter, general workflow/question
actions, remote exporter or release publication.

After explicitly excluding pending-approval phases from receipt commits,
**22 focused invocation/state tests** and the full **448-test native suite**
(14 macOS excluded) passed. The final Linux glibc-2.44 archive
rebuilt with matching OTP 29.1.1 notices and passed extracted-package verification
on a utility-only PATH and fresh homes. Its fixture covers the existing bundled
hooks/accounting/text capabilities; the independent custom state artifact remains
source-only evidence. Documentation review checked **65 Markdown files / 635
local file and heading links** with no broken targets.

[Hosted host-state verification](https://github.com/lexlapax/ipse/actions/runs/38993945716)
for `142b0b7` passed Ubuntu/macOS-14 on Elixir 1.18 / OTP 27: formatting,
compilation, default tests, demo, packaging and extracted verification on both,
plus macOS native enforcement. This is hosted evidence for host state, not a local
macOS run on Serenity or verification of subsequent question edits.

## P22 structured extension questions (2026-10-16)

On Linux Serenity, source build, formatting and warnings-as-errors compilation
passed. The initial full `mix test --include native_sandbox` passed **457 tests,
14 macOS excluded**. After adding a question counter digest and refusing unrelated
work during a pending question, **39 focused invocation/question/session tests**
and the final **457-test native suite** (14 macOS excluded) passed. No live account or
paid inference ran.

Independently compiled worker fixtures cover single/multiple/text questions,
explicit nonrecommended answers, closure of the actual VM before publication,
stale/invalid/oversized answers leaving journals unchanged, explicit fresh-VM
continuation with the exact JSON checkpoint, and unchanged idle question recovery.
Native extension tool questions preserve their actual call ID/provider data and
approval across crash/resume. Answers cannot authorize a following state write;
it needs separate full approval. Cancellation creates no answer/continuation,
unavailable questions select no default, and interrupted answered continuation
restores idle without initialization/replay. Missing/altered/duplicate question or
continuation records refuse restore before tail repair. See
[SDK contract](extension-questions.md) and [operator controls](../operator/extensions.md#structured-questions).

The credential-free demo and source hook/accounting/text fixture passed. Extension
question protocol fixtures are source tests, not yet the independent installed
extension package proof required by P22. General tool actions, service composition,
context contributions, worker stream handles and observability remain in progress.

The Linux glibc-2.44 archive rebuilt with matching OTP 29.1.1 notices and passed
`scripts/verify-package.exs` using the extracted runtime, utility-only PATH and
fresh isolated homes. This verifies existing bundled hooks/accounting/text and
runtime packaging; custom question artifact conformance remains source-only.
Documentation review checked **66 Markdown files / 651 local file and heading
links** with no broken targets. No release was published.

[Hosted question verification](https://github.com/lexlapax/ipse/actions/runs/38995020534)
for `ed422ac` passed Ubuntu and macOS-14 on Elixir 1.18 / OTP 27: formatting,
compilation, default tests, demo, package and extracted verification on both,
plus macOS native enforcement. This is hosted evidence for questions, not local
macOS execution on Serenity or verification of later workflow tool changes.

## P22 approved workflow tools (2026-10-16)

On Linux Serenity, **42 focused invocation/Runner tests** passed, including the
final job/identity-bound instruction gate. The initial full native suite passed
**464 tests, 14 macOS excluded**. Final build/package/full-suite evidence follows
below. Tests use synthetic local files/processes; no paid inference ran.

Independent worker fixtures exercise full approved/denied writes, ordinary read
policy, new nested instruction refusal before tool intent/approval, pinned context
receipts, escaped/out-of-workspace path and unsupported-tool refusal, normal
nonzero shell exit reporting, output/escaped-JSON bounds and unknown timeout
shutdown without callback continuation. Cancellation checks the actual shell PID
exits and delayed descendants do not write. Altered context receipts refuse
restore before tail repair. Runner fixtures count all drained bytes and report
truncation at Unicode/output boundaries. See [SDK contract](extension-tool-actions.md)
and [operator procedure](../operator/extensions.md#workflow-tools).

The final **42 focused tests** also cover known read failures/oversized reads
returning fixed failure codes without partial data, distinct from unknown write/
shell effects. Source build, format check, warnings-as-errors compile, the isolated
demo and existing hook/accounting/text fixture passed after that refinement.
The final full `mix test --include native_sandbox` also passed **464 tests, 14
macOS excluded**. Documentation review checked **67 Markdown files / 666 local
file and heading links** with no broken targets.

This increment reuses existing file/shell/sandbox facilities. It adds no runtime
dependency, production memory backend, service-composition engine or release.
Workflow artifact conformance is source-only; the separate imported extension
package proof and broader P22/P23–P25 remain in progress.

The final Linux glibc-2.44 archive rebuilt with matching OTP 29.1.1 notices and
passed extracted-package verification using fresh homes and a utility-only PATH.
It covers existing bundled hooks/accounting/text and runtime/helper behavior;
the custom workflow artifact remains source-only evidence. This is a local
verification archive, not a published release or live-account/macOS local check.

## Workflow formatter floor compatibility (2026-10-16)

[The workflow run](https://github.com/lexlapax/ipse/actions/runs/38996976329)
for `c752f07` stopped at formatting on both Ubuntu and macOS-14. Runtime tests,
native enforcement and package verification were skipped; they are not hosted
workflow evidence. Two short multiline `if`/`with` expressions format differently
under Elixir 1.18 and 1.20. Explicit block equivalents preserve behavior.

The official Elixir 1.18.4 OTP-27 archive was downloaded to `/tmp` and extracted
using OTP `:zip`, without replacing the system toolchain. A later P22A12 audit
found the initial `bin/mix` invocation resolved Elixir through the default PATH,
so that local invocation did not independently prove the 1.18 formatter ran.
The hosted result below establishes compatibility for the workflow repair. Use
an explicit Elixir executable with the Mix script as described in
[operator recovery](../operator/troubleshooting.md#build-and-sockets).

Warnings-as-errors compilation and **48 focused workflow/Runner/service tests**
passed in the current worktree, including ongoing service-composition fixtures.
The focused compatibility commit preserves that unfinished service work outside
its staged diff. Documentation checks passed **67 Markdown files / 668 local
file and heading links**.

[The repaired workflow run](https://github.com/lexlapax/ipse/actions/runs/38998415023)
for `8d7fad9` passed Ubuntu/macOS-14 on Elixir 1.18 / OTP 27: formatting,
compilation, default tests, demo, packaging and extracted checks on both, plus
macOS native enforcement. This establishes hosted workflow evidence, not local
macOS execution on Serenity or verification of the subsequent service changes.

## P22 typed service composition (2026-10-16)

On Linux Serenity, source build passed. **50 focused service/invocation/registry/
configuration tests** passed after using OTP graph utilities. The full
`mix test --include native_sandbox` passed **471 tests, 14 macOS excluded**.
The initial local floor-formatter claim was invalid because the Mix launcher
resolved Elixir from the default PATH. The
[service hosted run](https://github.com/lexlapax/ipse/actions/runs/38999961420)
for `ea0565b` stopped at a short multiline `if` layout on both platforms; runtime
and package checks were skipped. P22A12 replaces that expression with an explicit
block and validates both actual formatters; this does not retroactively establish
hosted service runtime evidence.

Two independently compiled artifacts exercise inert requirements/operator route
resolution, exact schemas/target activation pins, missing routes/targets and cycle
refusal, project trust denial, owned value jobs with host provenance, no model
requests or manufactured native messages, and byte-identical cached idle restore.
An attempted host action in a value reply is refused without execution. Cancellation
checks the actual target VM exits; interrupted service work stays idle/unknown on
resume. Altered provenance with a recomputed outcome hash and deleted service
receipts refuse restore before tail repair. See [contract](extension-services.md)
and [operator procedure](../operator/extensions.md#service-composition).

These are credential-free source fixtures. Nested interactive/effectful service
contracts, context/evidence contributions, worker streams, observability and the
independent installed package coverage proof remain separate work. No provider,
database, downloader, paid account or release is selected by this increment.

The Linux glibc-2.44 archive rebuilt with matching OTP 29.1.1 notices and passed
`scripts/verify-package.exs` from the extracted runtime with isolated homes and
a utility-only PATH. Help, demo, default/explicit workspaces, bundled MCP,
delegation and hook/accounting/text fixtures passed. This checks the current
package baseline; the independently installed service/workflow coverage proof
remains pending. It is not macOS or live-provider evidence for this increment.

## P22 session context and evidence (2026-10-16)

On Linux Serenity, build, warnings-as-errors compilation and credential-free demo
passed. **Six new independently compiled worker fixtures** passed, alongside
**55 existing extension regression tests**. The full
`mix test --include native_sandbox` passed **477 tests, 14 macOS excluded**.
Elixir 1.20.4 formatting and the actual 1.18.4 formatter passed; the latter was
invoked with its explicit Elixir executable and Mix script, on Serenity's OTP 29.
The service metadata expression now uses a portable explicit block. The prior
hosted formatting failure is recorded above, not counted as runtime verification.

Fixtures exercise asserted context and literal receipt-backed excerpts, invalid
evidence refusal with previous context preserved, caller-only clearing, fresh
session isolation, deterministic priority order/global byte bounds, exact provider
request projections, original/native message preservation, private diagnostic
summaries, inert byte-identical resume and committed publications surviving
interrupted callbacks without replay. Missing/altered request snapshots and changed
source proofs with recomputed outer hashes refuse before partial-tail repair.
See [contract](extension-context.md) and
[operator procedure](../operator/extensions.md#context-and-evidence).

These are source fixtures using a synthetic provider, not live inference or
freshness/semantic-truth evaluation. The independent installed-package proof,
worker stream access, observability/debugging and supervised review remain P22
gates. Production knowledge adapters remain P25; no provider/store is selected.

The source hook/accounting/private-text fixture passed through its explicit
`Ipse.ExtensionDemo.run/0` entry point. The Linux glibc-2.44 archive rebuilt with
matching OTP 29.1.1 notices and passed `scripts/verify-package.exs`: isolated
homes, default/explicit workspace paths, utility-only PATH, help/demo and bundled
MCP/delegation/extension checks. This is the package baseline, not an extracted
independent context artifact proof. The [current summary](#current-evidence-and-next-checks)
tracks subsequent platform results separately from this historical checkpoint.
Documentation validation passed **69 Markdown files / 705 local file and heading
links**, with no errors.

## P22 worker text resources (2026-10-16)

On Linux Serenity, build, warnings-as-errors compilation, both actual Elixir
1.18.4/1.20.4 formatter checks and the full native suite passed: **485 tests,
14 macOS-only exclusions**. A focused worker/broker/session text suite
passed **20 tests**. Seven independently compiled artifact fixtures exercise
ordered bounded JSON text and opaque handles, native/reasoning exclusion, inert
disabled behavior, no frame replay on byte-identical idle resume, fresh-resource
enrollment after explicit input, read-only host-action refusal, capacity refusal
before initialization/inference, and corruption refusal before tail repair.
Cancellation and untrappable owner death check the actual worker VM exits; both
restore idle without initializing it again. Broker admission additionally checks
live enrollment, preventing a surviving consumer PID from representing a removed
subscription. See [contract](text-streams.md) and
[operator procedure](../operator/extensions.md#visible-text-clients).

The credential-free source demo and explicit hook/accounting/text fixture passed.
The Linux glibc-2.44 package rebuilt with matching OTP 29.1.1 notices and passed
extracted help/demo, isolated homes, default/explicit workspaces, utility-only
PATH and bundled MCP/delegation/extension checks. This is the package baseline,
not an independently installed worker-text artifact proof in an extracted release.
The subsequent [hosted `dc07fb5` matrix](https://github.com/lexlapax/ipse/actions/runs/39004356777)
passed both Ubuntu and macOS, including source tests, demo and extracted-package
checks; macOS native/default experimental checks passed. Job/step conclusions
were inspected after completion. No live provider,
audio, exporter, external dependency or production knowledge backend was used.
Documentation checks passed **74 Markdown files / 889 local file and heading
links**, with no errors.
