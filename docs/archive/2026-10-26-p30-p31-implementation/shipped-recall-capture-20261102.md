# Shipped recall followed by pending capture

Dated **2026-11-02 UTC** (**2026-11-01 US/Pacific**), author-run Linux synthetic
implementation and verification based on `460a358`. Historical engineering
record; current behavior belongs to the [source guide](../../developer/session-sources.md)
and [operator manual](../../operator/knowledge-permissions.md). The [plan](../../plan.md)
owns remaining P30/P31 acceptance. This is neither independent review nor model,
installed-user or whole-milestone qualification.

## Actual gap and repair

The earlier [current-source publication adapter](current-source-capture-publication-20261102.md)
retains a genuine literal through a new pending save. Its generic fixture did
not exercise the shipped artifact's automatic recall, which also reads a
nonempty metadata-only index before publishing its Reference. A new default
`recall_capture_session_test.exs` exercises that actual artifact and exposes
three successive gaps: main-model source lookup refused the literal-bearing
union; publication refused its index/literal union; after successful publication,
the old index root prevented the Worker continuation.

The repaired main source gate admits canonical dependency versions 3–6 through
one-use all-selected-source preflight. The actual query and independent result
release still reacquire full current-use authority. Saved rederives historical
source provenance chronologically and grants no live read authority.

One-new-v3 capture admits the same full canonical union through the existing
retained publication adapter. Original sources, current signed records, recipes,
policy and complete native root still require fresh validation; merely passing
the shape gate grants no publication. The earlier CAS-prerequisite classification
remains unchanged and narrower.

The host separately classifies authenticated metadata-only index descriptors for
historical use after an exact successful own write. Original observation/result
pairs populate the bounded cache; worker flags or serialized cache data do not.
Only metadata version 3 receives the authenticated adjacent-root mapping.
Literal/history/accepted dependencies remain attached to their original producer
and Reference occurrences. They never become root guards, retain their original
deadlines and require current eligibility and original-source ownership at each
later use. Scans and mixed metadata roots receive no such history transition.
Original messages remain unchanged; an independently guarded host notice explains
the historical metadata. No dependency, native ABI, schema/quota enlargement,
alternate provider or permission bypass was introduced.

## Shipped journey and loss controls

Each case creates a fresh private synthetic home/project, enables the shipped
artifact through genuine native permission review and publishes literal A through
actual native `/remember ordinary` review. Trusted fixture configuration explicitly
selects a registered loopback Ollama protocol server; no installed daemon, model
account or external inference is used. Its responses select actual `source_list`,
then the exported Knowledge capture tool with the actual new-input read handle.
Normal read jobs run; publication is selected by the main-model tool call.

The positive checks genuine version-4 A in the first request, complete successful
source lookup, one attributed pending B save, `never_current` normalization,
successful final request containing A and the historical notice, retained A in
Saved's output and Reference dependency sets, and no version-4 root mapping.
Altering own-action/operation evidence or deleting the Worker transition rejects
strict replay. Confirmed close and idle resume preserve the original conversation
and perform no replay.

Two paired controls hold the incoming `worker_input_prepare` for the exact known
successful capture action, before its reply or the next source/policy scope.
One renames only A's original journal; the other revokes the actual protected
policy through Consent. Both require known successful publication, settled usage,
an unknown input for that exact capture result, unavailable saved lineage and
exactly two model requests. Idle resume preserves accounting and starts no old
callback or model request. Original source bytes are restored after the case.

## Retained attempts and verification boundaries

| Seed | Selection or repair | Result | Seconds | Exit |
| --- | --- | --- | --- | --- |
| 791732 | First shipped journey; fixture policy identity mismatched its operator source path | 0/1 passed | 7.7 | 2 |
| 791735 | Correct policy preparation; test expected v2 framing for a v1 literal Reference | 0/1 passed | 6.1 | 2 |
| 791736 | Genuine shipped recall before source gate repair | 0/1 passed | 6.0 | 2 |
| 791737 | Owned main source lookup; full publication union still refused | 0/1 passed | 9.1 | 2 |
| 791738 | Known successful publication; continuation still withheld by old index metadata | 0/1 passed | 9.5 | 2 |
| 791739 | Shipped positive through own-write historical metadata | 1 passed | 12.3 | 0 |
| 791740 | Six complete source/root/preflight/replay component modules | 29 passed | 4.2 | Completion recorded in log; terminal handle unavailable after handoff |
| 791741 | Three new controls; cross-process on-exit Task shutdown error and late revocation hold | 0/3 passed | 35.9 | 2 |
| 791742 | Correct cleanup; late reply hook still let the next scope acquire Consent first | 2/3 passed | 36.5 | 2 |
| 791743 | Selected revocation diagnostic; native lock acquisition refused before any policy write | 0/1 passed, 2 excluded | 14.3 | 2 |
| 791744 | Incoming hook attempted to use the debug callback name as Session state; hook ineffective | 1/3 passed | 76.8 | 2 |
| 791745 | Remember committed state, then hold the incoming preparation before reply | 3 passed | 32.2 | 0 |
| 791746 | Overbroad native-approval selection, deliberately stopped | Incomplete; no aggregate | Not a completed run | Shell returned 0 after SIGTERM; not a pass |
| 791747 | Shipped cases plus capture/inheritance/accounting/deadline regression set | 16/17 passed, 176 excluded | 112.7 | 2 |
| 791748 | Same focused set with preserved stale-root controls and strengthened actual-store/replay assertions | 17 passed, 176 excluded | 99.2 | 0 |
| 791749 | Fourteen complete related component modules | 165 passed | 82.0 | 0 |
| 791750 | Three shipped cases and stale-root refusal after the full repository build | 4 passed, 189 excluded | 48.0 | 0 |

The final focused command includes the actual shipped-artifact cases and the
existing stale-union, original-source, native-loss, accounting and deadline controls:

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs test/extensions/knowledge/recall_capture_session_test.exs --only current_literal_publication --only managed_ab_probe --only worker_inherited_union --only registered_capture --only publication_accounting --only strict_deadline_gate --only recalled_literal_capture --max-cases 1 --seed 791748
mix test test/ipse/session/managed_root_cache_test.exs test/ipse/session/managed_root_transition_test.exs test/ipse/session/managed_source_preflight_test.exs test/ipse/session/managed_source_provenance_test.exs test/ipse/session/managed_tool_use_test.exs test/ipse/session/managed_use_test.exs test/ipse/session/managed_lineage_test.exs test/ipse/session/managed_reads_test.exs test/ipse/session/managed_reference_test.exs test/ipse/extension/source_read_session_test.exs test/ipse/extension/managed_collection_call_test.exs test/ipse/extension/collection_managed_v3_test.exs test/ipse/extension/notes_publication_admission_test.exs test/ipse/extension/collection_deadline_gate_test.exs --max-cases 1 --seed 791749
```

The policy fixture uses `SemanticConsent.prepare` with the selected Registry
identity; editing a policy from another operator source path cannot establish
matching admission. The literal framing assertion was corrected to the actual
shipped v1 representation without changing production output.

The reply-hook diagnostic established that GenServer sends its reply before
the debug `:out` hook. Pausing that hook cannot prevent the publisher acquiring
the next scope. The final controller remembers committed state from `:out`, then
holds the matching incoming preparation before Session replies. It changes no
Session state, grant, read receipt or product deadline. Test cleanup monitors
actual task termination; ExUnit's separate on-exit process cannot call owner-only
`Task.shutdown` on the test process's task.

The overbroad 791746 selection was explicitly terminated, not retried after an
observation timeout. Its exact parent BEAM and exec handle became terminal;
the remaining identified synthetic PTY child subsequently exited naturally,
and a host process check found no remaining BEAM before the next cohort. Three
parent cases had printed completion dots; no complete selection total is claimed.

The 791747 failure was the prior stale-A/B test's expected structural refusal.
The full union still reaches the publication guard and the stale read still
prevents an actual save, but a supported new-v3 shape now journals its intent
before owned current-use validation. Its updated expectation retains the exact
full union, independent B quote, unchanged winner root, no successful save,
settled operation count and inert strict recovery.

Runs use this development checkout and ordinary build outputs, not a frozen
independent runtime inventory. Seed 791748 verifies the final strengthened test
assertions; 791750 repeats the shipped cases and stale-root refusal after the
full build. Earlier failures remain available in the local
logs named by their seed; they are not subtracted from complete module/suite
results. The latest complete module remains **170 passed, 5 failed, 15 skipped**
at `2f628a9`; the latest complete whole-source baseline remains **3,653 passed,
54 failed, 116 skipped, 112 excluded** at `f44b63c`.

Historical/accepted-note capture combinations, maximum unions, broader expiry and
loss, independent quality, installed workflows and full C0/P31 remain open.
No external model calls were charged by these synthetic fixtures.

The full `./dev/build.sh`, `mix compile --warnings-as-errors`, global
`mix format --check-formatted` and credential-free `./bin/ipse demo` each exited
0. Formatting validation and the no-op final compile briefly overlapped; neither
ran concurrently with native tests or rebuilding. Runtime and native test cohorts
otherwise ran serially. The rebuilt helper retains SHA-256
`5487c57a84b99be7b5b4381d097b637d3c45350b92b492d1786712f2bfbf8c7a`.
The [selected-file/log receipt](shipped-recall-capture-20261102.json) records final
edited source/test identities and local log hashes. It is not a whole-runtime
freeze or a claim that the full `mix test` suite passes.

The operator permission/recall chapter and developer source/collection chapters
were reviewed as whole documents. Their existing procedures, authority scopes,
historical metadata explanation, source previews and replay limits were reconciled
with implementation and actual synthetic command/Session controls. Audience
entry points retain their existing topic owners; the implementation index and
plan link this dated evidence separately from current instructions.

`elixir dev/check-docs.exs` checked 1,033 Markdown files and 8,557 local links
with zero errors. Its Git enumeration emitted permission warnings for existing
private staging directories; their contents were not read or added to this change.
