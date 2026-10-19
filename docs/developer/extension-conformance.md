# Write repeatable extension conformance scenarios

`ipse extension check` drives selected extensions through real Sessions with a
synthetic model and isolated workspace/state. Use it to turn an author workflow
into inspectable assertions about prompts, actions, questions, files, and recovery.
The fixture grants no code trust or capabilities. Review and select the exact
artifacts through normal operator configuration first.

## Run the first scenario

The checkout includes a dedicated operator file and prompt fixture. Read
`priv/conformance-operator.json` and `priv/conformance-demo.json`, then run:

```sh
./bin/ipse extension check --config priv/conformance-operator.json --fixture priv/conformance-demo.json --extension annotation --no-project-config
```

The operator file trusts the builtin annotation but leaves it disabled by default.
`--extension annotation` selects it for this run. The fixture sends synthetic input
and asserts one admitted request, the appended marker, final presentation, and one
transform result. It needs no credentials or model service.

The fixture body is:

```json
{
  "version": 1,
  "cases": [{
    "id": "annotate", "kind": "prompt", "text": "Synthetic question",
    "expect": {
      "status": "ok", "requests": 1, "user_contains": "Synthetic note",
      "final": "Conformance fixture completed.",
      "records": {"extension_transform_result": 1}
    }
  }]
}
```

The report includes assertion booleans, status/counts, fixture digest, and exact
artifact/runtime/API identities. It excludes input text, options, answers, values,
and journal bodies. Nonzero exit indicates invalid setup, unexpected behavior,
or a suite stopped before all cases ran. A matching negative case is useful
behavioral evidence, not OS-containment certification.

## Fixture and execution contract

`Conformance.schema/0` owns the version-1 closed schema. Input is at most 16 KiB
and rejects duplicate keys and unknown fields.

| Field | Meaning and limits |
| --- | --- |
| `files` | Optional seed files, at most 16 safe relative paths up to 256 bytes; contents up to 4,096 bytes |
| `options` | Optional instance-to-options objects for already selected IDs |
| `cases` | 1–16 ordered cases, unique lowercase ASCII IDs up to 32 characters |
| `kind` | `prompt`, `tool`, `command`, or `service` |
| `text` | Required prompt text; optional synthetic prompt for a tool case |
| `name`, `arguments` | Actual qualified export and schema-valid arguments for tool/command/service |
| Case `options` | Complete replacement option objects, overriding common fixture options |
| `script` | Prompt-only array, at most eight replies, each exactly `{"assistant":"text"}` or `{"tool":{"name":"name","arguments":{}}}` |
| `answers` | At most eight explicit answers, checked in order by the real validator |
| `timeout_ms` | 100–60,000, default 15,000; timeout cancels owned work |
| `cancel_after_ms` | Optional 1–60,000 cancellation delay |
| `expect` | Required expected status and optional assertions |

Tool cases request one synthetic tool call and then finish. When a prompt script
is exhausted, the synthetic model returns `Conformance fixture completed.`
Commands/services use explicit invocation. Model-selected tools and later host
mutations remain denied without `--yes`. Question answers never grant permission;
missing answers stop at `question` rather than selecting recommendations.

Cases share one scratch workspace and isolated application home, using fresh
session IDs. This permits explicit remember/recall sequences without touching
operator state. Files seed once. Literal `{{workspace}}` and `{{home}}` expand
inside option/input/expected values, never keys. No shell/environment interpolation
occurs. Options are validated and pinned before execution.

Use synthetic data and dedicated configuration. Host inference is replaced;
MCP, delegation, and compaction are not activated. Live-provider/replay CLI options
refuse. Trusted workers and explicitly approved shell still have ordinary OS
permissions. Real absolute paths in options are not redirected, so use scratch
placeholders for IO adapters. Shell policy retains its own platform limits;
it does not sandbox workers.

## Assert observable behavior

`expect.status` is `ok`, `error`, `question`, `cancelled`, `refused`, or `timeout`.
Add assertions that prove the user's intended result:

| Assertion | What it checks |
| --- | --- |
| `requests` | Synthetic host-admitted request count, 0–10 |
| `final` | Exact completed presentation |
| `value` | Exact last invocation object |
| `user_contains` | Marker in an effective user message sent to the synthetic model |
| `context_contains` | Marker in labelled reference context, useful for recall |
| `records` | Exact counts for named journal types, each 0–1,000 |
| `action_statuses` | Exact ordered action outcomes, at most 128 |
| `files` | Exact contents at safe workspace-relative paths |
| `cleanup` | Expected Session close acknowledgment, default true |

A handler's `value` assertion cannot prove a file or state write. Assert host
action receipts and files/snapshots separately. After close, the checker validates
saved diagnostics, usage/session links, physical sources, and text resources
without repair or replay. Missing journal evidence cannot pass.

Cases run once in order. Unexpected assertions or unconfirmed cleanup stop later
cases. Inspect `case_count`, `declared_cases`, `stopped_early`, and
`safe_to_continue`. An explicitly expected unknown-cleanup case may match while
still preventing further execution. Nothing retries or resumes automatically.

## Inspect a failure

Add `--keep-fixture` to retain the private scratch directory and print its path.
Its journals contain fixture content, so avoid private transcripts. Without the
flag, scratch data is removed normally; abrupt host termination may still leave
it behind. Filesystem deletion and process cleanup are separate results.

For bounded argument-free dispatcher samples, add `--developer-trace`.
`--trace-ms` is 1–5,000, default 1,000; `--trace-events` is 1–128, default 32.
Both require tracing. Capture failure fails the check; a normal sample/time limit
does not. These flags are operator policy, never fixture grants. See
[synthetic tracing](observability.md#diagnose-with-synthetic-data).

## Extend the training fixture

Copy the demo fixture into a scratch file. Change `user_contains` to a marker
that is not appended and observe the failed assertion. Then restore it and add
an exact record count. For a stateful package, use the lab's remember/recall cases
as a model and add a denied write after an explicit question answer.

```sh
mix test test/extensions_conformance_test.exs
```

The tests cover trust ceilings, scratch isolation, placeholders, questions without
implicit answers, denial before code loading, honest cancellation reports,
tracing ownership, and stopping later effectful cases. Use the
[compatibility lab](extension-proof.md) when you also need evidence against an
unchanged extracted runtime; conformance scenarios alone do not establish every
platform, crash schedule, provider, or production algorithm.
