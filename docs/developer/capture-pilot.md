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
requests overall. The provider stays selected by the caller. The ChatGPT runner
uses the configured route without active extensions. The separate local runner
uses the exact pinned Ollama route described below. Neither runner switches
models or downloads anything.

The pilot narrows request timeout to at most 60 seconds and response size to 128 KiB.
The ChatGPT runner refuses shared budgets because its direct provider loop cannot
enforce that contract. The local runner uses its own fixed configuration and does
not enforce ordinary configured budgets or service slots; coordinate separately.
Obtain a finite call allowance before a live run and account for prior
runs against it. The loop counts a failed request attempt conservatively and
stops rather than retrying; the count does not by itself prove dispatch. A local
pre-dispatch history-limit refusal does not count a
nonexistent request.

Run the local synthetic controls first:

```sh
mix test test/dev/knowledge/pilot_test.exs \
  test/dev/knowledge/local_pilot_test.exs \
  test/dev/knowledge/pilot_reservation_test.exs
```

The fake provider exercises the real pilot loop without model access. Controls
cover exact source matching, malformed calls, bounded continuations, request
accounting and audit failures. The reservation tests also use Ipse's native
protected helper and temporary owner-only directories. These controls do not
qualify model behavior.

## Choose whether to retain candidate text

Public progress contains numerical request metrics and proposal validation
summaries. It omits candidate text, source quotations and assistant prose. This
default cannot support an independent entailment or usefulness judgment later.
Its `usage` field uses Ipse's normalized counter record, including explicit
unknown/invalid counter quality. Raw provider usage is excluded because it can
contain attribution content as well as token counters.

To retain inspectable inputs, supply a new audit directory explicitly. The local
runner requires this directory; the ChatGPT runner can instead retain only public
numerical progress. Each route needs its own allowance and evidence. Do not
resume an uncertain request or combine an interrupted run with a later run as
though they were uninterrupted. The local pilot does not complete an interrupted
ChatGPT pilot; their allowances are accounted separately.

### Use the configured ChatGPT route

Start with an already configured and authenticated Ipse ChatGPT profile without
extensions; use Ipse's [documented authentication](../operator/usage.md), and
verify the selected model and finite allowance before running:

```sh
IPSE_PILOT_PARENT=$(mktemp -d)
IPSE_KNOWLEDGE_PILOT_CONFIRM=chatgpt \
IPSE_KNOWLEDGE_PILOT_AUDIT_DIR="$IPSE_PILOT_PARENT/capture-audit" \
  mix run dev/pilot-knowledge.exs
```

The ChatGPT runner's first plan record reports whether its private candidate
audit is enabled. Omit `IPSE_KNOWLEDGE_PILOT_AUDIT_DIR` for numerical progress
only. The runner creates a mode-0700 audit directory and a new mode-0600
`candidates.jsonl` file; an existing directory is refused.

### Use the one-shot local route

This source-checkout launcher is tied to the previously selected primary answer
model, `qwen3.5:4b`, on `http://127.0.0.1:11434`. It requires the recorded
manifest `d8b0f5e9760cd1682034f292d7ef72ec46f432149be0df7574bf2d6e92e38c04`,
metadata digest `c2ed7207a7cd47d14d7f7ddd1ab7a9e013ba0b94e95e11ab9c582f91c545cbe2`,
and Ollama runtime version `0.40.13`. It requests an 8,192-token context, at
most 4,096 output tokens and `think: false`. It does not pull a model. Inspect
the selected installation and compare these values before running:

```sh
./bin/ipse model inspect --provider ollama --model qwen3.5:4b \
  --base-url http://127.0.0.1:11434 --json
```

The launcher uses a fixed authorization ID under the local account's canonical
`.ipse/p31a-pilot-authorizations` directory. The home is resolved from exactly
one local `/etc/passwd` entry for the native helper's UID, not from `IPSE_HOME`
or the audit directory. The account must have a unique local entry; its `.ipse`
and pilot-authorization directories must be canonical, owner-only and usable by
the protected native helper. This launcher currently requires Linux. Ambiguous or
nonlocal account records refuse, as does any existing entry in the authorization
directory.
Prepare and review the installation without deleting existing locks or changing
this location to bypass a prior run.

Before the first metadata or inference request, the launcher durably reserves
**120 local inference calls** under that fixed ID. Once the reservation exists,
all 120 remain charged even if the run finishes early, fails, or is interrupted;
this tool has no refund or replay path. An existing lock or reservation,
including incomplete state, refuses a new run. Inspect the retained private
evidence and the project's
[call accounting](../archive/2026-10-26-p30-p31-implementation/live-call-accounting.md)
before deciding how to proceed. The reservation protects this one pilot; it is
not a shared service budget and does not account for other clients. The direct
pilot does not acquire an Ipse registered-service slot. Stop or coordinate
other users of the selected daemon and account for unresolved service work
before launching.

Once the selected route, allowance and private destination are ready, run once
from the built checkout:

```sh
umask 077
IPSE_PILOT_PARENT=$(mktemp -d)
IPSE_KNOWLEDGE_PILOT_CONFIRM=ollama-qwen3.5:4b \
IPSE_KNOWLEDGE_PILOT_AUDIT_DIR="$IPSE_PILOT_PARENT/audit" \
  mix run dev/pilot-knowledge-local.exs > "$IPSE_PILOT_PARENT/run.log" 2>&1
```

The audit path must be a new absolute, canonical directory. The runner creates
it mode 0700 and writes mode-0600 declaration, candidate, progress and attempt
files. Each pre-dispatch attempt record is synced before the provider call; it
is an intent, not proof the daemon received the request. When the loop returns a
completed or stopped result and owner cleanup is confirmed, `result.json` reports both the loop's
count and the full 120-call charge. The loop count is conservative: a model-pin
precheck can increment it before an attempt record or provider invocation. A
synced attempt record is a separate pre-dispatch intent, and neither proves that
the daemon received an inference request. If the result or cleanup is missing or
unverifiable, retain the full charge and preserve the directory; never infer a
zero-call refund from absent rows. Keep the output and audit files private.

The host's existing cooperative model-pin check reads metadata before each
attempt and, after a successful inference, checks the reported model and loaded
context again. Up to 1,440 read-only metadata requests are separate from the
120-call inference ceiling. A selected installed model may load during a
request. Changed metadata, a missing model, an invalid result or a failed
postcheck stops the loop; there is no automatic retry. These checks do not attest
the weights used for each request, rule out server-side context truncation, or
confine or attest the daemon's own network behavior.

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
the loop stops after counting the response already received and does not send
its continuation or replay the request. Preserve a partial file as partial
evidence. The local runner retains its entire 120-call charge regardless of the
loop's observed count.

The pure API's optional fourth argument is an audit callback returning `:ok`.
Its ordinary third argument remains the public progress callback. Keep these
outputs separate when embedding the pilot in another development command.

## Bind judgments to the observed evidence

Retain the exact source revision/diff, case/tool hashes, selected route/model,
request limits, attempted-call count, first failures, numerical output and private
audit hash. Build and inspect the recorded source and loaded BEAM hashes; the
declaration does not prove that fingerprinted source corresponds to the code
executing in the VM. Keep candidate data private for the authorized reviewers; do not
commit private model transcripts or credentials. Review original source and
candidate together, including omitted, uncertain, contradictory and repeated
cases. Source-byte validity does not establish entailment or usefulness.

Store labels separately from the original audit. Bind their exact input hash,
conversation/request IDs and candidate indices; include empty-candidate turns.
Distinguish an independent agent's development judgment from human review and
held-out quality. Check that every observed initial response has its audit and
label row and that every candidate has the required typed verdicts. Continuation
response records do not add candidate-bearing turns. Recompute aggregates from
the rows rather than copying a summary. Original audit fields saying labels were
absent describe the time of capture; do not rewrite them when later labels exist.

For a partial run, preserve the missing turns and final receipt as unknown.
An absent final result cannot establish the exact attempted-call count or refund
its allowance. Complete labels for observed rows do not make the run complete,
prove critical-fact coverage or establish a representative intake rate. Do not
run another paid or local pilot merely because an old startup field still says
labels were absent.

## Freeze a provisional integrated workload

Apply the frozen baseline's intake rule only after naming its denominator and
what counts as a useful unique item. A replacement is a capture event without
necessarily adding a new current fact. For example, a declared 40-turn schedule
with twenty new captures, four corrections and four temporal supersessions has
28 materialization events, not 28 new facts. Two forgets are separate reducing
effects. Additional churn belongs in its own ledger; ordinary lifecycle actions
cannot also count toward the additional-change requirement.

Keep prototype duration categories separate from native retention. A pilot label
of `persistent` does not choose a pin, preference, current statement or ordinary
90-day note. Record the native mix and representative payload shape as explicit
assumptions when the pilot does not measure them. A maximum source statement is
not necessarily a maximum encoded signed record. Primitive padded storage maps
cannot replace source-authenticated native maximum-payload evidence.

Measure the source, complete proof and stored value separately through the native
statement path. `/remember` limits the statement to 1,024 UTF-8 bytes, while the
complete encoded source proof must fit 2,048 bytes. The record repeats the exact
statement as its text and evidence quote, with the host's fixed reason. Escaping
can therefore exhaust the proof bound before the source-byte bound. A shorter
source can produce a larger encoded value when its byte-offset fields use fewer
digits. The 6,144-byte note-value ceiling does not imply that this direct path can
produce a value of that size. Preserve the actual source/proof/value sizes, the
known refusal just beyond the binding bound, and the existing head, provenance
and accounting checks. An unknown outcome stops the fixture without replay.

Keep these functional boundary checks separate from the
[storage measurement's coverage](measurement.md#interpret-latency-and-storage-coverage-honestly).
Run `mix test test/dev/knowledge/native_notes_seed_test.exs` to check the geometry
and fixture result contracts. These pure cases do not execute a native capture.

Keep the declaration beside the prepared developer workload, with an exact hash
in its manifest and retained attachment. Verify the selected ordered effects and
the full turn schedule before execution; changing the declaration or plan requires
a fresh review. This is an assumption freeze, not a permission grant. A planner's
100-operation daily scheduling cap does not prove the actual saved allowance;
revalidate that permission independently. Preserve original sources, unknown
effects and one-shot run markers rather than editing them to fit a new calendar.

The [provisional day fixture](../../dev/fixtures/knowledge-qualification/notes/provisional-day-v2.json)
illustrates event accounting and explicit assumptions. Its ordinary day and
twofold calendar stress do not cover the separate 320-proposal burst. That gate
must exercise actual finite allowance, validation/deduplication, warning and pause
behavior without evicting protected records. Keep native maximum payloads,
concurrent owners, offline/restart, imports, complete Session turns and measured
resource/history/cache behavior as separate required checks. There is no public
knowledge CLI command that turns a workload declaration into permission or
executes this development calendar.

This exposed development pilot is not a protected Session capture journey,
installed-user acceptance or held-out quality evaluation. For decision-engine
assessment, the actual candidate admission and replay/shadow contracts still
apply; this audit output alone grants no decision calls or publication authority.
