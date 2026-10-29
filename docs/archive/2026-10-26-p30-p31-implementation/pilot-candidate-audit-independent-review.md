# Independent pilot audit review — 2026-10-29

This scoped review covers the optional candidate-audit callback in
`dev/knowledge/pilot.exs`, its opt-in command-line wiring in
`dev/pilot-knowledge.exs`, the focused test additions and the
[contributor procedure](../../developer/capture-pilot.md). It does not qualify
actual model behavior, protected Session capture or held-out quality.

The review found a default-output leak in rejected candidates. Proposal progress
copied the raw model-supplied category even when validation rejected that category.
With audit disabled, a synthetic marker in that field appeared in both the
public progress callback and returned records. The owner repaired this by retaining
only the three fixed category labels and representing other values as nil.

The [independent counterexample](pilot-candidate-audit-review/category-probe.exs)
was run before and after that repair. Before repair its two leak flags were true;
on the repaired source both `raw_invalid_category_in_progress` and
`raw_invalid_category_in_records` were false. Each probe used a local mocked
request, charged exactly one request and stopped with
`pilot_call_contract_refused`. No provider call or actual model data was involved.
The added regression covers invalid string and map categories in both output
paths. The recorded focused suite progressed from 13 passing tests at seed46993
to 14 passing tests at seed46994; those passing suites were inspected rather than
rerun by the reviewer.

No further concrete defect was found within the reviewed change:

- Default output retains numerical and fixed validation fields rather than
  candidate text, quotes or assistant prose. The optional sink receives validated
  source/candidate fields, including explicit empty-candidate records.
- Source-invalid proposals refuse before the audit sink. Callback error, raise
  or throw produces a typed failure after the observed request and before its
  continuation; that request remains counted. The path has no retry or replay.
- Audit creation requires a new directory, applies mode0700 before opening the
  exclusive file and applies mode0600 before any candidate write. Existing
  directories and overwrite are refused.
- Each encoded audit row is bounded to64KiB, written and file-synced before
  another request. The file closes in the command's `after` clause. This does not
  claim atomic directory creation, parent-directory durability or a transaction
  with the model service; the manual states those limits.

The opt-in environment variable is absent by default and does not change the
selected provider, model, finite request ceiling or publication behavior. Exact
source-byte matching remains attribution evidence, not semantic acceptance.
Independent labels and actual main-route model evaluation remain open. This
review changed no implementation, used no live service and ran no aggregate
validation. The parent batches documentation validation and final integration.
