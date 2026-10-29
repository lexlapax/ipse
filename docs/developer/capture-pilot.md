# Inspect capture proposals on synthetic inputs

Use the finite capture pilot to inspect what a selected main model proposes from
exposed synthetic project statements. It publishes no knowledge or task effects.
Exact source matching tests attribution; semantic review must separately decide
whether a proposal is useful, durable, duplicated, misleading or unsupported.
For held-out retrieval and answer qualification, follow the
[frozen comparison runbook](knowledge-evaluation.md).

## Follow the bounded request loop

`dev/knowledge/pilot.exs` owns twenty exposed cases and a simulated capture tool.
It runs three independent conversations, each with the same twenty cases. Each
turn permits one initial request and at most one continuation, for at most 120
requests overall. The provider stays selected by the caller. The command-line
runner accepts the configured ChatGPT route with no active extensions; the pure
runner also supports an explicitly selected Ollama route. Neither switches models
or downloads anything.

The pilot narrows request timeout to at most 60 seconds and response size to 128 KiB.
It refuses shared budgets because its direct provider loop cannot enforce that
contract. Obtain a finite call allowance before a live run and account for prior
runs against it. A failed request counts as attempted; the pilot stops rather
than retrying. A local pre-dispatch history-limit refusal does not count a
nonexistent request.

Run the local synthetic controls first:

```sh
mix test test/dev/knowledge/pilot_test.exs
```

The fake provider exercises the real pilot loop without model access. Controls
cover exact source matching, malformed calls, bounded continuations, request
accounting and audit failures. They do not qualify model behavior.

## Choose whether to retain candidate text

Public progress contains numerical request metrics and proposal validation
summaries. It omits candidate text, source quotations and assistant prose. This
default cannot support an independent entailment or usefulness judgment later.
Its `usage` field uses Ipse's normalized counter record, including explicit
unknown/invalid counter quality. Raw provider usage is excluded because it can
contain attribution content as well as token counters.

To retain inspectable inputs, supply a new audit directory explicitly. Start with
an already configured and authenticated Ipse ChatGPT profile without extensions;
use Ipse's [documented authentication](../operator/usage.md), and verify the
selected model and finite allowance before running:

```sh
IPSE_PILOT_PARENT=$(mktemp -d)
IPSE_KNOWLEDGE_PILOT_CONFIRM=chatgpt \
IPSE_KNOWLEDGE_PILOT_AUDIT_DIR="$IPSE_PILOT_PARENT/capture-audit" \
  mix run dev/pilot-knowledge.exs
```

The runner creates the audit directory with mode 0700 and a new
`candidates.jsonl` file with mode 0600. An existing directory is refused so a
previous run is not overwritten. Omit `IPSE_KNOWLEDGE_PILOT_AUDIT_DIR` to retain
only public numerical progress. The first plan record reports whether the
private candidate audit is enabled.

Each accepted initial response produces one audit record, including when it
proposes no candidate. The record contains the exact exposed source, validated
candidate fields, conversation/request numbers, zero-publication marker and an
explicit absence of independent semantic labels. Source classes come from the
development cases; they are not independent gold judgments. Continuation prose,
provider configuration, credentials and unrelated assistant content are excluded.
Source-invalid candidates stop the run before the audit callback.

Audit rows are bounded to 64 KiB and the file is synced before another request.
This sync is not a claim of a crash-atomic audit directory or a model-service
transaction. If encoding, writing, syncing or a supplied audit callback fails,
the run reports `pilot_audit_failed`, counts the response already received and
does not send its continuation or replay the request. Preserve a partial file as
partial evidence; do not merge it with a later run as though uninterrupted.

The pure API's optional fourth argument is an audit callback returning `:ok`.
Its ordinary third argument remains the public progress callback. Keep these
outputs separate when embedding the pilot in another development command.

## Freeze evidence before judging proposals

Retain the exact source revision/diff, case/tool hashes, selected route/model,
request limits, attempted-call count, first failures, numerical output and private
audit hash. Keep candidate data private for the authorized reviewers; do not
commit private model transcripts or credentials. Review original source and
candidate together, including omitted, uncertain, contradictory and repeated
cases. Source-byte validity does not establish entailment or usefulness.

This exposed development pilot is not a protected Session capture journey,
installed-user acceptance or held-out quality evaluation. For decision-engine
assessment, the actual candidate admission and replay/shadow contracts still
apply; this audit output alone grants no decision calls or publication authority.
