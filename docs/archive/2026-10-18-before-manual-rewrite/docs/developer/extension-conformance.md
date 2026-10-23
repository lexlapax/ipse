> Historical reference only. Snapshot of `docs/developer/extension-conformance.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../2026-10-22-before-structural-consolidation/docs/developer/extensions.md#turn-the-hook-into-a-repeatable-scenario).

# Synthetic extension conformance checks

`ipse extension check` exercises selected extensions through ordinary Sessions,
using a synthetic model and scratch workspace/state. Built-in and installed
worker artifacts share the existing callback, approval, question, context and
recovery validators. It does not replay a saved journal or use host model credentials.
Optional [dispatcher tracing](observability.md#synthetic-dispatcher-tracing) samples
only the synthetic Sessions created by this runner.

## Review and select code

Use a dedicated operator configuration with reviewed trust and fixture instances.
Import independent artifacts through the normal
[inert import procedure](../operator/extensions.md#import-and-inspect), then set
their trust/selection explicitly. Check activates the effective selected set,
including other enabled instances; fixture data cannot add artifacts or capabilities.
Use `--no-project-config` to avoid unrelated project settings.

For a credential-free first check, save this dedicated operator configuration:

```json
{
  "version": 1,
  "extension_trust": [
    {"artifact": "builtin:prompt-annotation:1", "capabilities": ["transform.prompt"],
     "allow_project": false, "allow_children": false}
  ],
  "extensions": [
    {"instance": "annotation", "artifact": "builtin:prompt-annotation:1",
     "enabled": false, "options": {"text": "Synthetic note"},
     "order": 0, "lifetime": "session"}
  ]
}
```

Save this separate fixture:

```json
{
  "version": 1,
  "cases": [
    {"id": "annotate", "kind": "prompt", "text": "Synthetic question",
     "expect": {"status": "ok", "requests": 1,
       "user_contains": "Synthetic note", "final": "Conformance fixture completed.",
       "records": {"extension_transform_result": 1}}}
  ]
}
```

```sh
./bin/ipse extension check --config /path/to/fixture-operator.json --fixture /path/to/scenarios.json --extension annotation --no-project-config
```

The same reviewed examples ship as [operator config](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/priv/conformance-operator.json)
and [fixture](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/priv/conformance-demo.json), runnable directly from the checkout:

```sh
./bin/ipse extension check --config priv/conformance-operator.json --fixture priv/conformance-demo.json --extension annotation --no-project-config
```

The report contains assertion booleans, statuses/counts, fixture digest and selected
artifact/runtime/API identities. It excludes input text, options, answers, returned
values and journal content. Exit is nonzero for invalid configuration, an unexpected
result or a suite stopped before all declared cases ran. Matching negative cases
are behavioural evidence, not a safety certificate or independent OS-containment proof.

Add `--developer-trace` to include bounded, argument-free dispatcher samples in
each case report. `--trace-ms` is 1..5000 (default 1000); `--trace-events` is 1..128
(default 32). Both limit flags require tracing to be enabled. These are explicit
operator options, not fixture fields or extension grants. Capture failure makes
the check fail; reaching a normal time/sample limit does not. The
[tracing contract](observability.md#synthetic-dispatcher-tracing) explains sampling
gaps, cleanup and the distinction from source debugging.

## Fixture and execution contract

Input is a duplicate-key-rejecting JSON object of at most 16 KiB. Version is 1;
unknown fields refuse. `Conformance.schema/0` owns the closed schema, validated
through the existing bounded JSON Schema adapter. Other checks below enforce
ownership/cross-field policy rather than duplicating the worker protocol.

| Field | Meaning and bounds |
| --- | --- |
| `files` | Optional initial workspace files; at most 16 relative paths, 256 bytes each, no traversal; contents at most 4096 bytes |
| `options` | Optional instance-to-options objects, limited to already selected instance IDs |
| `cases` | 1..16 ordered cases with unique lowercase ASCII IDs of at most 32 characters |
| Case `kind` | `prompt`, `tool`, `command` or `service` |
| Case `text` | Required for `prompt`; optional synthetic prompt for `tool` |
| Case `name`, `arguments` | Required for tool/command/service, using actual scoped catalog names and schemas |
| Case `options` | Instance options replacing the complete object; overrides common fixture options |
| Case `script` | Prompt-only array of at most eight synthetic replies: exactly `{"assistant":"text"}` or `{"tool":{"name":"name","arguments":{}}}` |
| Case `answers` | At most eight explicit answer objects, consumed in order through the real question validator |
| Case `timeout_ms` | 100..60000, default 15000; timeout cancels owned work |
| Case `cancel_after_ms` | Optional 1..60000 cancellation delay; use a deliberately blocked fixture when testing cancellation |
| Case `expect` | Required assertions described below |

Tool cases issue one synthetic tool call, then finish. Prompt scripts use their
declared replies in order; when exhausted, the model returns
`Conformance fixture completed.` A tool reply needs ordinary approval. Commands
and standalone services use explicit operator invocation; each later mutation
still needs its own permission. Host mutations and model-selected tools are denied
without `--yes`. Question answers never grant that permission, and missing answers
stop at `question` without selecting a recommendation.

All cases share one scratch workspace and isolated application home, but use fresh
session IDs. This supports explicit remember/recall sequences without borrowing
operator state. Files are seeded once. Literal `{{workspace}}` and `{{home}}`
placeholders expand in option/input/expected values to those scratch paths; keys
are not expanded, and no environment or shell interpolation occurs. Options are
schema-checked and pinned again before executable startup.

Use synthetic inputs only. Host inference is replaced, MCP/delegation and compaction
are not activated by this runner, and live provider/replay CLI options refuse.
Reviewed code and explicitly approved shell still have ordinary OS permissions;
scratch host state is not an OS sandbox. In particular, real absolute paths in
callback options are not automatically redirected: use placeholders in a dedicated
configuration for I/O adapters. Shell sandbox selection retains its ordinary
[platform boundary](sandbox.md); workers remain outside that shell profile.

## Assertions, failure and inspection

`expect.status` is one of `ok`, `error`, `question`, `cancelled`, `refused` or
`timeout`. Optional assertions are:

- `requests`: count of host-admitted synthetic requests, 0..10.
- `final`: exact final presentation string.
- `value`: exact object returned by the last extension invocation.
- `user_contains`: marker in the latest effective user message of any synthetic request.
- `context_contains`: marker in the labelled user-role reference context of any synthetic request, useful for recall.
- `records`: exact counts for the named journal types, each 0..1000.
- `action_statuses`: exact ordered host-action outcome statuses, at most 128.
- `files`: exact contents at safe relative workspace paths.
- `cleanup`: expected result of Session close acknowledgment, default true.

Returned values remain extension assertions. Check host action receipts, context
snapshots and file results separately for effects. After close, saved diagnostics,
usage/session bindings, physical prompt sources and text-resource receipts are
validated without repair or callback replay. Unexpected loss of journal evidence
cannot pass. `cleanup_confirmed` reports the Session close result, not a separate
proof about detached descendants; see [actual platform limits](sandbox.md).

Cases run once in order. An unexpected assertion failure or unconfirmed cleanup
stops later cases; the report distinguishes `case_count`, `declared_cases`,
`stopped_early` and `safe_to_continue`. An explicitly expected unknown cleanup can
match its case while still preventing further execution. No automatic retries,
resume or recommended answers occur.

Scratch files/journals are removed by default. Add `--keep-fixture` to retain the
private directory for local inspection; its path appears only with that flag.
Retained journals contain fixture inputs/results, so do not use private account
transcripts. Abrupt process/host termination can leave scratch directories even
without the flag; ownership cleanup and filesystem deletion are separate concerns.

The current checker validates declared scenarios, not arbitrary extension quality,
production services, real account providers, all crash schedules or compatibility
with every runtime. The [independent lab](extension-proof.md) uses this checker
for temporary CLI selection, then a separate operator verifier for its broader
domain assertions. Its supervised trial and the lifecycle audit are recorded;
hosted Linux/macOS verification passed. See [P22's completion scope](../plan.md#p22-extension-scaffold-and-lifecycle-hooks).
See [verification scope](testing.md#current-evidence-and-next-checks).
