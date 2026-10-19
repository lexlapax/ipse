# Second-review follow-up and internal challenge, 2026-10-19

Historical investigation record, not a completion verdict. The
[second external review](review-2.md) reviewed `b1dc820`; the
[remediation index](index.md) owns later verification and acceptance.
Current procedures belong in the [memory user manual](../../operator/memory.md)
and [developer training chapter](../../developer/memory.md).

## Intent and scope

Reject failed deadline receipts that attribute the unchanged record to the failing
operation. Preserve valid missing-record and tombstone summaries, existing
success/conflict/denied/unknown outcomes, generic host ownership and inert recovery.
Document approved import behavior without changing it. Diagnose the inherited
hosted fixture timeouts and preserve the scenarios, assertions and deadlines.

The user requested another internal adversarial review and repairs, then P27 work.
No further external-review dispatch is required before that transition. P26 still
needs its actual verification gates; no CI waiver has been requested or granted.

## Receipt reproduction and repair

Adding a forged `record.operation_id` equal to the failing operation's ID to the
existing receipt test reproduced the external finding. The selected test failed
before the implementation change. The failed-outcome clause now requires the
record's previous writer to differ from the current operation. All seven State
tests then passed in 0.3 seconds. The existing real previous-writer and missing
summary controls still pass. Source review also traced retained tombstone support.

The manuals now describe approved newer-generation imports that replace a live
note with an expired record or a legacy record. The former hides it immediately;
the latter hides it until migration. The deadline still belongs to the existing
target. Contributor verification instructions include the generic State tests.

## Timing evidence and fixture boundaries

The exact `b1dc820` hosted run failed at `mix test` on both platforms. Its Ubuntu
failure was the suppressed-source seven-variant fixture; macOS also timed out in
the CLI freeze workflow. Both used ExUnit's 60,000-ms default. Historical
pre-repair failures remain in the external report; a green rerun cannot explain
those earlier failures by itself.

Two temporary Elixir probes traced the suppressed-source fixture locally before
reorganizing it. They retained function/stage counts and elapsed time, with no
source or fixture changes during either run. Each run passed one selected test
with eleven exclusions. Total times including setup were 58.5 and 58.3 seconds.
The probes add overhead and do not establish hosted performance.

| Measured work in the second probe | Count | Total | Maximum |
| --- | --- | --- | --- |
| Public extension commands | 117 | Totals overlap the following rows | 2.835 seconds |
| Worker initialization | 133 | 21.193 seconds | 0.169 seconds |
| Evaluation journal validation | 234 | 6.616 seconds | 0.076 seconds |
| State execution | 352 | 1.725 seconds | 0.006 seconds |
| File sync | 1,402 | 0.882 seconds | 0.003 seconds |
| Source-authoring subprocesses | 7 | 4.149 seconds | 0.598 seconds |
| Other subprocesses, including fixture builds and storage audits | 26 | 12.040 seconds | 1.197 seconds |

Probe files and logs were `/tmp/ipse-p26-r2-timing.exs`,
`/tmp/ipse-p26-r2-timing-stages.exs`,
`/tmp/ipse-p26-r2-timing-before.log` and
`/tmp/ipse-p26-r2-timing-stages-before.log`. The probes use ordinary Erlang
call/return tracing with monotonic timestamps. They observe fixture work, not
real providers or held-out predictions.

The old suppressed-source test charged seven independently owned variant runs
to one ExUnit deadline. Each variant already creates a separate Session, home,
workspace, budget and storage namespace. The tests now exercise those seven
suppressed cases independently. Both queries, all source exclusions, readable
controls, abstention, projections, storage lifecycle, model accounting and confirmed
cleanup remain checked for every variant. Their initialization counts still sum
to sixteen. The complete seven-variant current-source integration test remains.
Research retains its gateway accounting; isolated non-research cases additionally
require gateway artifacts to be absent.

The CLI successful workflow still freezes, executes, creates a blind packet,
checks permissions/output protection and records unmeasured scoring. Separate
refusal checks use another valid freeze and malformed prediction bytes with an
incorrect hash. The existing error assertions now also demonstrate rejection
before prediction parsing, data, labels or reviews are opened.

This changes the fixture units, not production execution speed. No runtime or
test deadline, SDK bound, assertion, model budget or cleanup acknowledgment is
relaxed. An initial functional timing run used `--slowest`, which enables tracing
and changes ExUnit's default timeout behavior. It is not deadline acceptance
evidence. Acceptance explicitly supplies `--timeout 60000`.

## Focused review of the follow-up

The panel reviewed HEAD `6a76950a0373172591e75398a7f0cedba9605aab` plus frozen
tracked diff SHA-256
`c5af67e40eddb3f58a359f3fa559cf9185d113db731af47535295a401c82edc6`.
The runtime-and-test subset SHA-256 was
`43cf47d15373b99b8fe70315b9af0c7e90f7c347c0c92a4a071583d87fcb9725`,
serialized as `git diff -- lib/ipse/extensions/state.ex
test/extensions_state_test.exs test/knowledge_evaluation_runner_test.exs`.
Each reviewer verified its anchors before and after reading. The panel was
read-only, with no tests, builds, service operations or edits.

| Reviewer | Requested model | Verdict |
| --- | --- | --- |
| A | `gpt-6-astra` | PASS, no actionable findings |
| B | `gpt-6.1-sol` | PASS, no findings |
| C | `gpt-6-sol` | PASS, no concrete findings |

The host did not expose independently verifiable serving-model identities.
Requested choices do not prove resolved-model independence.

All reviewers traced the receipt check through live commit and saved recovery,
and independently compared assertion coverage before and after fixture separation.
They accepted the existing execution boundaries as the reason to split the cases.
All emphasized that source review does not prove passing deadlines or hosted CI.
The lead agrees; there are no act-on, consider, noted or dismissed code findings
from this panel. Refreshed runtime verification remains required.

## Whole-milestone adversarial review

The user clarified that the requested adversarial review covers all of P26,
including unchanged implementation, rather than only the latest fixes. Three
fresh reviewers therefore examined the complete milestone independently, using
the same intent and rubric. They began with the P26 acceptance criteria and
current code, then cross-checked the external reports. No source edits occurred
during the panel.

Their anchor was HEAD `6a76950a0373172591e75398a7f0cedba9605aab` plus tracked
diff SHA-256
`bc1c6ad1c45bf154ebef6ae515b4eed349f48ac194ead37a63c785f79775299a`.
The runtime/test subset remained `43cf47d1…d87fcb9725`. All verified their anchors
before and after reviewing. Requested models were A `gpt-6-astra`, B
`gpt-6.1-sol` and C `gpt-6-sol`; serving identities were not exposed.
All three returned PASS with no actionable findings.

| Whole P26 requirement | Panel assessment |
| --- | --- |
| Independent default-off working/persistent selection and extension-owned domain behavior | No automatic capture, inference, publication or promotion; generic State remains schema-agnostic |
| Session/project/operator isolation, stable logical bindings and legacy namespaces | Operator grants and scope ceilings remain enforced at admission, revalidation and execution |
| Remember, recall, forget, inspect, export, inventory, import, collect and migrate | Reviewed every command and model tool, including unchanged handlers and callers |
| Provenance, source versions, TTL and conflicts | Closed note validation, bounded exact spans, canonical visibility and locked CAS agree with the stated contract |
| Missing/expired/suppressed/legacy ancestors and transitive derivatives | Recall and inspection share the same exclusion closure; inspection pins its dependency scan generation |
| Exact backups, approved imports and explicit migration | Stored values survive export; suppression wins; accepted expired/legacy replacement behavior is documented |
| Permanent suppression, concurrent forget and derivative collection | Stale writes cannot resurrect notes; missing collection does not reserve a source; direct causes are checked |
| Approval crossing target expiry and receipt integrity | Existing expiry reaches both locked clock checks; failed metadata retains its prior writer; recorded-time recovery is inert |
| Cancellation, worker/filesystem ownership and interrupted effects | Reviewed Session, Host, Worker, FileEffect and Runner paths; unfinished effects remain unknown and are not replayed |
| Quotas, bounded scans and results | Byte/record/page/work limits remain in force; read allowance does not extend write authority |
| History, cache, backup and erasure limits | Manuals distinguish future retrieval from retained receipts, prior conversations and earlier transfers |
| Measurement, dependency claims and manuals | Synthetic lexical corpus and resource scope are explicit; user procedures and contributor training agree with source |
| CI fixture organization | All suppressed variants and applicable assertions remain; combined current-source integration remains |

The lead independently read Memory/Records and State, checked binding and identity
admission, and challenged expiry, generation, dependency cycles, imports,
suppression, quotas and publication/recovery boundaries. No additional reachable
defect emerged. There are no act-on, consider, noted or dismissed findings from
this full panel. This remains source review, not native/package/CI execution.
No forced temporary-staging delay was tested.

## Refreshed candidate verification

The explicit-deadline focused run passed 60 tests in 207.0 seconds:

```sh
mix test test/extensions_memory_test.exs test/extensions_memory_session_test.exs \
  test/extensions_state_test.exs test/extensions_state_binding_test.exs \
  test/extensions_state_scan_test.exs test/knowledge_evaluation_runner_test.exs \
  --timeout 60000 --slowest 10
```

The complete current-source matrix took 33.496 seconds. Individual suppressed
variants took 6.325 through 8.131 seconds. CLI success and refusal workflows took 18.809
and 14.457 seconds. Every case retained the explicit deadline; no timeout was
waived. The log is `/tmp/ipse-p26-r2-focused.log`.

Build, local Elixir 1.20.3 formatting, Elixir 1.18.5 formatting, strict compilation
and CI action-pin policy checks also passed. Full baseline, refreshed native and
package checks, and the new hosted candidate remain pending.
