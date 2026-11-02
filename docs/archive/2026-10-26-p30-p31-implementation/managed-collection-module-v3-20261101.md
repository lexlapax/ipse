# Complete current V3 managed-collection regression

Dated **2026-11-01 US/Pacific**, terminal capture **2026-11-02 UTC**, author-run
synthetic Linux verification of clean commit `7e9f533` on `codex/p30-p31`.
The [receipt](managed-collection-module-v3-20261101.json) records the complete
result, all parent failures and native fixture roots. This supersedes the
[earlier module baseline](managed-collection-module-20261101.md) as the latest
complete module run, while preserving that earlier failed cohort unchanged.
The [plan](../../plan.md) owns milestone scope and open acceptance.

## Terminal result and frozen inputs

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --max-cases 1 --seed 791718
```

Result: **164 passed, 7 failed, 15 skipped, zero excluded**, 1,828.1 seconds,
exit 2. All **186** declared parent cases are accounted for; **171** ran.
Child results are not added to the parent total. The log retains **45** native
parent fixture roots. Skipped cases establish no executed or qualified behavior.

Test-runtime `mix compile --warnings-as-errors` exited zero before the inventory.
Prelaunch captured **7,864 tracked source files**, **632 test-build BEAM/app
files** and the selected helper, with the exact commit and clean tracked status.
After terminal exit and before any source edit, verification found the same
source/build path sets and bytes, helper, HEAD and tracked status. Private
untracked `.serenity-*` directories were neither opened nor copied.

The inventory hashes regular source bytes and symlink targets, and also hashes
followed build-file bytes. It excludes system Elixir/ERTS, environment, in-memory
test code, generated child artifacts and filesystem permission/inode inventories.
This is not a complete loaded-runtime attestation. No other native/Mix/PTY cohort
ran concurrently and no source/build/helper edit occurred during the run.

| Retained artifact | SHA256 |
| --- | --- |
| `/tmp/ipse-managed-v3-module-20261101.log` | `ca9ce5d48db599e9792f548efa1b8d76ac914c43491ae0371e0bda964c26874f` |
| `/tmp/ipse-managed-v3-module-prelaunch-20261101.json` | `5c61ea5aefaa497b5dd411b0ce71260f52665c15aa6489b42e0ce7235b4b3650` |
| `/tmp/ipse-managed-v3-module-postcheck-20261101.json` | `e42f48fad09bf72bd860799f59e3edf7c5a5f34c806024235e3632352e8c3bdc` |
| `/tmp/ipse-managed-v3-module-inputs-20261101.exs` | `d338805602ea86e0913269f1ee37429a8cd1477ce323335901f1c480c65c1d31` |
| `/tmp/ipse-managed-v3-module-report-20261101.exs` | `72a3a580d6d0230de012cd60028c7999524fdff818defa2df37750cbeabbf109` |
| Selected native helper | `5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a` |

## All seven parent failures

The parser accepts both one- and two-space numbered parent headings, verifies
their consecutive numbers against the terminal failed count, and excludes more
deeply indented child headings. Locations refer to the frozen source.

| # | Test | Location |
| --- | --- | --- |
| 1 | ordinary text private delivery retains its actual callback | `managed_collection_call_session_test.exs:4781` |
| 2 | V2 outer Identity loss after checked deferred publication retains full liability across inert resume | `managed_collection_call_session_test.exs:8749` |
| 3 | publication cannot discard an earlier stale managed A while citing current source B | `managed_collection_call_session_test.exs:2328` |
| 4 | upgraded literal v4 A cannot be discarded while candidate cites independent current B | `managed_collection_call_session_test.exs:2213` |
| 5 | legacy saved-consent publication refuses a full pending queue | `managed_collection_call_session_test.exs:3691` |
| 6 | protected managed publication applies its admitted deadline policy | `managed_collection_call_session_test.exs:1624` |
| 7 | competing legacy saved-consent Sessions cannot both publish at 63 pending records | `managed_collection_call_session_test.exs:3737` |

Failure 1's sink contains start/end for the first tool-only request, but not the
second request's answer text. The fixture waits only for any payload and then
closes Session, which may cancel an optional consumer before that callback.
The required-consumer positive passed. Current source and existing stream tests
separate optional transport completion from final answer admission.

Failure 6 records a successful V3 publication action, then the
unregistered demo continuation refuses managed history. A route error is not a
passing end-to-end publication positive. Failure 3 likewise stops at its seed's
unregistered continuation before reaching the A/B race. Failures 2, 5 and 7 use
gated legacy publication shapes and do not reach their intended later boundaries.
Failure 4 requires the missing external historical `IPSE_LITERAL_AB_ROOT`; it is
distinct from the passing fresh-source inherited-union controls. Historical
upgrade coverage must not silently become a current-source fixture.

The legacy extension-question cases passed in this cohort. Earlier speculation
about their current failure is not a reason to rewrite them or weaken their
recovery assertions. The terminal list above controls next repairs.

These automatic Linux tmpfs/native-terminal/local-HTTP controls establish no
independent semantic quality, live account, installed, human, non-Linux or
sandbox-confinement acceptance. The latest complete whole-source suite remains
**3,653 passed, 54 failed, 116 skipped, 112 excluded** at `f44b63c`; this module
neither replaces that aggregate nor permits arithmetic subtraction from it.
Full P30/P31 implementation, qualification, adversarial audit and final handoff
remain open.

## Focused text-delivery and deadline follow-up

After the terminal result and successful unchanged-input check, the fixture now
waits for the actual answer-text marker before closing an ordinary text consumer.
It retains the later exact JSON frame-text assertion, physical workspace write,
required-consumer positive, other private delivery roles and managed-content
refusals. Waiting for the first generic payload had synchronized only with the
earlier tool-only request. No optional-consumer drain promise or runtime behavior
was changed to satisfy this test.

The managed deadline positive now selects its registered synthetic native route
and capture export so the successful publication can continue to a completed
turn. The distinct unmanaged legacy publisher keeps its original route and
checks. Both require successful action outcome, settled Consent accounting,
generation one, strict reconstruction and confirmed close.

| Seed | Command selection | Result | Seconds | Exit |
| --- | --- | --- | --- | --- |
| 791719 | Complete `managed_sink_input` matrix and both `strict_deadline_gate` cases | 15 passed, 171 excluded | 32.4 | 0 |
| 791720 | Three complete text-stream/worker test files | 37 passed, zero excluded | 44.9 | 0 |

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only managed_sink_input --only strict_deadline_gate --max-cases 1 --seed 791719
mix test test/ipse/session/text_stream_test.exs test/ipse/session/text_stream_integration_test.exs test/ipse/extension/text_test.exs --max-cases 1 --seed 791720
```

Selected post-run hashes, not a separate complete loaded-runtime inventory:

| File | SHA256 |
| --- | --- |
| `/tmp/ipse-managed-v3-text-deadline-20261101.log` | `4e13fb95099cc0b98eab939ca7b893758f2d31620e6e0f773e51a9ee45bcb152` |
| `/tmp/ipse-managed-v3-text-regressions-20261101.log` | `ebd49dfe866ec7193246500ec0f7b321154e99264f0fd869fb169de80053110f` |
| Follow-up Session test module | `a23df61768e4007df2ea5db660656bdd49aaa0cc300c42b8732a05a0548aa93e` |

The whole developer lifecycle/source-delivery chapter and operator extension
chapter were reviewed. Their existing text flows now explain optional callback
timing and close cancellation. The developer chapter also corrects the stale
claim that final canonical accounting precedes every transport end: an existing
integration control observes a completed optional end followed by failed required
delivery and a failed canonical request. Transport completion remains distinct
from answer acceptance. Testing guidance teaches the actual callback observation;
no acceptance ledger was appended to the manuals. Current real-service examples
were reviewed against implementation without contacting those services.

The complete module still has the frozen seven-failure result above; these two
focused repairs are not subtracted to invent a new aggregate. No runtime,
dependency, native helper or package changed, and no external model call ran.
Full-suite, integrated quality/capacity, installed/platform qualification, final
adversarial audit and complete P30/P31 delivery remain open.

Final formatting and diff-whitespace checks exit zero. Documentation checking
reports 1,030 Markdown files, 8,532 local links and zero errors; existing private
directory discovery warnings remain separate. No build/package check was repeated
for this test/documentation-only follow-up.

## Late A/B publication boundary

Subsequent test-only work based on committed `38e5816` restores failure 3's
actual publication purpose. The registered response sequence is explicitly
interleaved: seed capture/answer, consumer capture, concurrent capture/answer.
Repeating complete pairs would incorrectly answer the concurrent Session before
its capture. Both real saves must finish and settle through the native adapter.

The dedicated fixture mode reads root-bound A data, then obtains and receives
the exact source list/read/quote for independent unattended input B while A is
still current. It blocks inside the quote callback after constructing its normal
SDK proof, before requesting publication, and reuses A's original generation.
Only then does the independent writer advance the root from one to two.
No state replacement, fabricated dependency or grant bypass is used.

At the released consumer's actual `publication_prerequisites?/3` call, the
controller requires the exact inherited union captured before the root change,
including A's observed dependencies. The attempted candidate must contain B's
exact complete proof and the submitted proof request must use its original page
handle. The real guard must return false. The consumer records no managed
publication intent or successful write; the winner's snapshot stays unchanged.
Strict Saved and idle resume preserve messages and the ownership suffix without
Worker replay; the two successful operations remain settled and exactly five
actual local HTTP requests finish.

This is root-bound record-content inheritance, not a signed literal/accepted-note
publication positive. The existing fresh-source `worker_inherited_union` pair
separately covers literal A withdrawal before B's next input and successful
independent B capture. Historical upgraded A requires its distinct missing fixture
and is not silently replaced by these controls. Full current-source publication
and C0 integration remain open.

| Seed | Selection | Result | Seconds | Exit |
| --- | --- | --- | --- | --- |
| 791721 | First restored publication fixture | 0 passed, 1 failed, 185 excluded | 12.8 | 2 |
| 791722 | Exact proof/union/guard and recovery control | 1 passed, 185 excluded | 14.7 | 0 |
| 791723 | Late publication plus both genuine inherited-input cases, registered capture, accounting and deadlines | 10 passed, 176 excluded | 37.5 | 0 |

The first run failed a new assertion for a nonexistent top-level `session_id`
in the quote response. The correction authenticates B through its committed
source-read page's window and the public SDK's exact proof constructor, then
compares that complete proof at the attempted publication. Source schema,
runtime guard and retained refusal assertions are unchanged.

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only managed_ab_probe --only worker_inherited_union --only registered_capture --only publication_accounting --only strict_deadline_gate --max-cases 1 --seed 791723
```

Selected post-run hashes, not a complete runtime inventory:

| File | SHA256 |
| --- | --- |
| `/tmp/ipse-managed-ab-publication-20261101.log` | `a0ab7c09b0fd2165b137c547f6fdadd76a9368081f47c628e95fc8847a097383` |
| `/tmp/ipse-managed-ab-publication-paired-20261101.log` | `09f1ed7c68e8b4fa3077c9bcc4f7b32fba66760d80ecc269661dbfeb999d675d` |
| `/tmp/ipse-managed-ab-publication-regressions-20261101.log` | `1084ab8650f6fd407096b4201c9306b064774384d7232b8dfa42bf53a27b3795` |
| Final Session test module | `7c4ed3f45446bfc12dc9923f66489aec293c1050c24a0828d8dcee3098f500da` |

The whole Collection SDK/source and operator extension/recovery explanations
were reviewed in the preceding increments; this fixture changes no operator
behavior. Testing guidance now separates the two actual race points within its
existing positive/uncertainty flow. Each cohort reached terminal completion
before source edits. No production, helper, dependency, package or external
model call changed. The frozen complete-module and suite totals above remain
unchanged; these focused results supply no new aggregate or milestone acceptance.

Final formatting and diff-whitespace checks exit zero. Documentation checking
reports 1,030 Markdown files, 8,533 local links and zero errors; existing private
directory discovery warnings remain separate. No runtime/build/package check was
repeated for this fixture/documentation-only increment.

## Open positive: capture after a current literal read

On **2026-11-02 UTC**, a separate acceptance probe based on committed `1560cb7`
tested the positive complement of the preceding refusals. This is an expected
current implementation gap, not an enabled capability or a passing qualification.
The [exact generator](current-literal-publication-probe-20261102.exs) derives an
isolated temporary test module from that committed Session fixture. Its synthetic
worker mode reads a genuine freshly native-reviewed literal A, obtains B's real
source list/read/quote, then submits a normal new-V3 pending candidate at A's
original generation. No source is withdrawn, no root changes, no tracking is
erased, and no grant or gate is bypassed. A's source and B's new candidate belong
to distinct Sessions. The selected main route is the registered local fixture.

```sh
mix test /tmp/ipse-current-literal-publication-20261102_test.exs --only current_literal_publication --max-cases 1 --seed 791724
```

Terminal result: **0 passed, 1 failed, 186 excluded**, 14.4 seconds, exit 2.
The generated test first requires A's genuine version-4 read, B's successful
unattended-input quote and valid Saved reconstruction. Those assertions pass;
the required completed capture fails, with no publication action results.
This probe is outside the default source suite and is not added to or subtracted
from its aggregates.

A subsequent read-only [diagnostic receipt](current-literal-publication-probe-20261102.json)
identifies the actual synthetic consumer and original seed. The source journal
still matches its saved hash. A's observed validity is `eligible`, with its
original finite deadline retained. There is one model admission, successful B
quote and **zero publication intents and zero publication results**. The retained
root is `/tmp/ipse-worker-inherited-f161fb5a9c32b5d546cfad2d9f70354c`; the
diagnostic mutates/replays nothing and supplies no new current-use permit.

Source inspection locates the current restriction in
`ManagedToolUse.publication_prerequisites?/3`: an empty union can enter, otherwise
every member must classify as a cached root-only CAS prerequisite. A literal
version-4 dependency cannot supply that classification. This explains the early
refusal; it does not justify deleting or relabeling the dependency. A full current
source publication needs original-source and consuming Session/Writer ownership,
fresh policy and selected-root validation at the actual native publication
decision, conservative accounting, guarded result delivery and causal replay.
Reusing `ManagedUse`, the retained publication owner and the Session source bridge
requires a concrete integration design; a userspace precheck followed by an
unfenced write would not implement the required positive.

| Selected post-run artifact | SHA256 |
| --- | --- |
| Exact generator | `b8b7ef43b2467dab484f95233480a171b590430452b1ca3aa822ffc2b13cb4d1` |
| Generated temporary test module | `6ea5409f3f6fce555c64c1a117515ce06d4f390e35fc2de8465b83c5455f0344` |
| `/tmp/ipse-current-literal-publication-20261102.log` | `55b44a78c35b52db79f731d422036acc6bbbcdf44c391c4abaf919a9e969c1ad` |

These are selected hashes, not a prelaunch or complete loaded-runtime inventory.
Only the known synthetic root was inspected; private qualification labels and
untracked `.serenity-*` directories remain unopened. No runtime, helper,
dependency or external model call changed. The current manuals already describe
the narrower CAS-only publication scope and are not widened by this record.
This positive is a next implementation target for full C0, independently of the
remaining obsolete/externally supplied regression fixtures. Safe refusal alone
does not complete the authorized notes capture/recall goal.

The subsequent [source-dependent capture implementation](current-source-capture-publication-20261102.md)
adds the genuine positive and paired native faults. It supersedes this observed
implementation gap within that stated scope, preserving the failing probe and
leaving broader C0 and complete-suite acceptance open.

The evidence-only follow-up passes diff-whitespace checking. Documentation
checking reports 1,030 Markdown files, 8,536 local links and zero errors;
pre-existing private-directory discovery warnings remain separate. No passing
runtime aggregate, package result or milestone acceptance is inferred.
