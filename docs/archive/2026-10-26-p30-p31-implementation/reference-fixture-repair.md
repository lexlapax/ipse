# Reference-aware fixtures and close-time journal comparisons

Dated **2026-10-27**. Test-fixture corrections against one frozen application
runtime. The [plan](../../plan.md) owns acceptance status; the
[developer testing chapter](../../developer/testing.md) explains current fixture
construction. This record establishes no new product capability, complete latest
source baseline, package, installed workflow or model quality.

## Original complete run and diagnosis

The private graph `/tmp/ipse-p30b-components-baseline-20261027-01` copied admitted
source from base `3b5a643` plus the ManagedReference-v2 changes subsequently
committed as `2461a96`. Its build metadata names the base, which is not a claim of
a clean checkout. A private `./dev/build.sh` fetched locked dependencies, built
the native helper with the production flags and strictly compiled 128 source
files. Its complete formatter check passed.

The full command used its own `MIX_BUILD_PATH`, test environment, two schedulers,
seed `20261109` and maximum cases 2:

```sh
mix test --no-compile --seed 20261109 --max-cases 2
```

It exited **2**, after **1,715.6 seconds**. The literal completed summary is:

```text
Result: 2374/2418 passed, 4 skipped, 36 excluded
Failed: 44 tests
```

The default OS-enforcement/memory exclusions and optional-PDF skips are not
passes. Deliberate TLS, process-loss and journal-failure diagnostics are separate
from the 44 numbered failures. Original full-log SHA256:
`1a95d031d2c25eaf0ed205ce57137eec41608921441a61858ca4ae16e40a05dc`.

| Failure group | Number | Confirmed cause and correction |
| --- | --- | --- |
| MCP catalog and Session | 10 | Fake providers interpreted a valid trailing host Reference as another task; select the latest nonreference through the public validator |
| Permissions | 6 | Fake decoded host Reference prose as JSON tool calls; retain its real-task decoder after exact reference selection |
| Extension feeds | 8 | Fake repeated its first task after completed tools because the reference has user role; correct only the fake's branch selection |
| Text, subscriptions, workspace and extension Session context | 5 | Exact fixture shapes omitted the separately validated trailing reference; assert its actual position and preserve exact transformed/restored user data |
| Idle delegation, workspace-resource and HTTP MCP resume | 5 | Expected journal was captured before close; assert the exact close-time epoch append, then compare idle resume with the closed journal |
| Fresh handoff | 1 | A valid reference follows the fresh real user prompt; assert both exact task and reference rather than raw-last task equality |
| Declaration CLI | 2 | Original private source copy lacked Git metadata required by `git ls-files`; repair the next private graph's setup, without changing these tests |
| Operator questions | 7 | Reference-aware fake turn counting, valid synthetic Session IDs and exact earlier source-validation refusals; independently recorded in the [question repair](questions-fixture-repair.md) |

No production module, deadline, native helper source, approval, grant or replay
policy changed in this repair. Existing effect counts, separate approvals,
headless denial, cancellation, owner loss, unknown outcomes and inert-resume
assertions remain. Filtering applies only to fake-provider branch selection;
complete messages remain in actual provider input and assertions. Invalid markers
and real user prose remain selected as ordinary messages.

For close-time comparisons, the old journal must remain an exact prefix followed
by one `lifecycle_epoch_closed` record with the exact Session ID, `close` closure
and confirmed cleanup. Resume must preserve that closed journal. These assertions
distinguish a legitimate lifecycle append from effect replay.

## Focused combined candidate

The separate graph `/tmp/ipse-reference-fixture-repair-20261027-02` copies the
original compiled runtime and changes exactly 13 test files: the twelve owned
here and the separately committed question fixture. A private `git init` and
`git add .` occur before execution so the unchanged declaration fixture can
enumerate its admitted source. No private source commit, remote or push is used.
Its exact admitted path list is retained.

The combined driver loads Application and the test helper directly through the
copied BEAM paths, then explicitly requires those 13 files plus
`test/dev/evaluation/declaration_cli_test.exs`. It ran from its private project CWD
with private TMPDIR, seed `20261112` and maximum cases 2. **157/157 passed** in
**145.1 seconds**, including both declaration-CLI layouts. Raw-log SHA256:
`e7d0f801bb05948dbaa62f77fc6f14e3a941eaed105d768597d5df13278c0ed5`.
An earlier five-file candidate passed **53/53**, in 33.0 seconds, seed `20261110`;
its exact five sources, complete manifest, driver and log are retained separately
inside the combined preservation.

Actual Elixir **1.18.5** and **1.20.4** formatted all 13 exact candidate files
without changes, on host **OTP 29**. This is not an OTP 27 runtime or compatibility
compile claim. No runtime was rebuilt for the repair. The private native helper
remains `d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b`.

The complete testing chapter was reviewed and integrated around fixture ownership,
actual context, close-time records and earliest source refusal. Its stale final
45-minute CI budget was corrected to the workflow's actual 60 minutes. This
changes no product or test deadline.

## Independent scoped evidence

The separate MCP triage reproduced **10/20** before and passed **20/20** with the
clean candidate, keeping all original assertions. Its actual-input traces show
the complete tool group before a valid Reference; marker controls preserve forged
markers, wrong hashes and ordinary user tasks. Report SHA256:
`778495555b0082b5c69302f1b0b0773558b3d3e9398a9234772196d98438f943`;
preservation manifest:
`4be8c4af26596d183a564d96db9afd1915140993944acd62251bd1dd2e1c833a`.

The separate permissions triage reproduced **1/7** before and passed **7/7** with
the clean candidate, keeping all original authority/path/count assertions. Actual
initial inputs prove the JSON decoder selected a valid Reference rather than the
real task. Report SHA256:
`0c09f5c0516b98e5d84d75926463129afd9d924855a156ece0a833d83ea33081`;
preservation manifest:
`e60383d31e76c9c13426a5e9171277871582783dd3cac95aadaa89ae0bc57563`.
These reports describe their then-private candidates; Root subsequently applied
their exact clean patches. They are scoped fixture diagnoses, not a whole-runtime
audit or new implementation authorship.

The [post-repair review](reference-fixture-audit.md) independently examined the
other nine Root-owned fixture corrections and the whole testing chapter. It found
no weakened authority, no-replay or history assertion, passed **17/17** fresh
controls against the actual feed Model body, and reproduced the extra proposal
with the original body. Its reviewer excludes the three previously authored MCP
and permissions files from its independent-review claim. The review's P3 stale
CI-budget finding is closed by the exact 45-to-60 correction. Original harness
AST-loader and basename-collision failures are retained with their corrections;
all 42 selected source/runtime inputs match afterward. Report SHA256:
`46f61d6a678619c2b8aac96d5f314aa0eac551950d0ae3f7922055017352e451`;
94-payload preservation manifest:
`17ed336d3b371f887a41a75e4bab4529b58e6bd65b5d5a83c96b8f10373c118c`.

## Input integrity, preservation and limits

The first full-run manifest binds 2,304 regular source/build paths with SHA256
`24206c71b2337bb45f0bfa9ee79a8135c4e944ab521f713d61f5a4f4d5ea54d1`.
The after-run strict comparison failed because exactly one execution output,
`build/lib/ipse/.mix/.mix_test_failures`, changed. All other **2,303** inputs
remained exact; no added or removed path was reported. That original failed
comparison is preserved rather than discarded.

Durable first-run evidence is `p31-verification/full-baseline-first-failed` under
the task's owner-only artifact root. It retains 2,344 payloads, the complete failed
log, build/format/inventory diagnostics and full source/runtime. Its initial Mix
cache is explicitly reconstructed from the independent MCP snapshot's already
preserved manifest-matching bytes. The post-test cache is separately retained.
This reconstructs all 2,304 original manifest rows without modifying the original
graph or claiming its execution cache stayed unchanged. Preservation manifest:
`01d4bb1eb1e4225de035ee7eaedea843c6ea66f60521734b41b1f38a14f7ad1c`;
receipt: `8d4e18b64296435ad1a088553158f60591f1c6dabc081fbe4eb870cfdde8417b`.

The combined candidate's **2,303** source/runtime manifest rows remained exact
before/after its focused run, excluding only private Git metadata and the declared
Mix execution cache. Manifest SHA256:
`a25520ddda629e3f9120e2d52e0fa866985047e2b7b8d6f1567c56ca6082255b`.
Durable `p31-verification/reference-fixture-repair-focused` retains all those rows,
complete focused logs/drivers, exact formatter controls and the earlier 53-test
evidence. It contains 2,353 payloads; preservation manifest:
`ec124bc33be40ca5ff64f53f1d76104ccaf79629498533e8d5dc1eee94b77700`;
receipt: `2bb9a1eb8d837723217df2352a0e76efdb1880e0228bfcb96d9ab771f1e47838`.

All evidence directories are owner-only and regular data files are mode 0600,
single-link, byte-verified and synced. The runtime priv alias is materialized from
its exact bound project bytes; unused dependency source links are omitted. Copy
evidence into fresh private working directories before execution, make only
working native helpers executable and use a private TMPDIR. Never run or modify
the retained evidence in place.

At this record's checkpoint the full-suite repeat is **running**, so its partial
log supplies no complete pass. Later terminal results need a separate dated
receipt. The newer DomainAuth and planned directory/current-reader integration
are outside this frozen runtime. No package, installed, macOS, optional PDF,
default-excluded OS enforcement, human journey, model or live-account acceptance
is established here.
