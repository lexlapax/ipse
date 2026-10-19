# Build a supervised evaluation

Use an evaluation when you need to compare a candidate behavior with a fixed
reference. This chapter teaches how to construct a bounded task, freeze its
inputs, run it through Ipse, and assess its artifacts. It applies to extension
features and supervised self-development. It does not authorize a provider call,
external scan, installation or publication.

Start with the [architecture](architecture.md), [test workflow](testing.md) and
[security threat model](../../SECURITY.md). For operating an installed runner on a
candidate checkout, use the [user procedure](../operator/self-development.md).

## Define the observable result

Choose one question a fixture can answer. For example: does a selected prompt hook
add a note to the effective user input while leaving the original prompt intact?
The repository already has a complete credential-free case:

```sh
./bin/ipse extension check --config priv/conformance-operator.json --fixture priv/conformance-demo.json --extension annotation --no-project-config
```

Read [the fixture](../../priv/conformance-demo.json) and
[its operator configuration](../../priv/conformance-operator.json). The expected
result checks one provider request, the effective input, the final synthetic
answer and a durable transform receipt. A passing report establishes those
properties. It does not establish that an arbitrary model will use the note well.

Write acceptance conditions before implementation. Include a positive control,
a relevant refusal, cancellation and saved recovery. Decide what counts as a
failure, an unverified claim and an allowed limitation. Avoid measuring success
with a rule chosen after seeing the candidate's answer.

## Separate authoring from judgment

An author produces the candidate or report. A reviewer checks that frozen result
against the original criteria and independently inspects its evidence. Keep each
reviewer's source, instructions, account/model selection and assistance explicit.
Two labels on reports do not establish independent execution or model diversity.

Use a fresh conversation for a review that must not inherit the author's private
reasoning. Supply the task, source revision and bounded artifacts the reviewer
needs. Do not send private transcripts or credentials. A static reviewer cannot
certify runtime or OS enforcement without running those checks.

For a repair, require both the original counterexample and the repaired result.
A failed task may already have changed files or started external work. Review its
effects before repeating it; never let the evaluation automatically replay an
unknown effect. A passing rerun is a result, not a diagnosis.

## Freeze the runner and candidate

Record the Git revision, uncommitted changes, configuration and artifact hashes.
For self-development, install the runner outside the candidate workspace. Its
application/helper files must not be writable through that candidate's native
workspace. Keep a recovery path to inspect work if the candidate stops building.

```sh
git rev-parse HEAD
git status --short
./scripts/package.sh
```

Retain the exact archive path printed by the packager. Building the candidate
later must not replace the executable under the active runner. Build outputs and
fixture stores must also be separate when runs overlap. A benchmark that reads
one checkout while another process recompiles it has not frozen its input.

The [independent artifact proof](extension-proof.md) demonstrates this separation:
build a reviewed artifact once, then execute it in an extracted runtime without
a development toolchain. Compare archive/host bytes before and after. Do not
rebuild the artifact to make a failing compatibility result disappear.

## Make source evidence inspectable

For a research or architecture task, keep an explicit input manifest: source
revision, included paths or captured sources, exclusions and a digest for each
input. A compressed packet is a selected representation, not complete repository
coverage. Record what was omitted and let the reviewer inspect original source
where the task permits it.

For a code task, inspect the actual diff and output artifact. A narrative claim
that a test ran is weaker than its command, exit status and retained sanitized
result. The author should not be the only process that reads the delivered file.
For a research task, distinguish a source's claim from an observed test result.
A citation is not proof that a design works in Ipse.

A compact evaluation ledger can use these fields:

```text
candidate_revision | runner_archive_sha256 | input_manifest_sha256
case_id | expected_property | observed_result | command_or_artifact
reviewer_scope | assistance | exclusions | outcome
```

Keep private evidence outside Git. Publish only sanitized records authorized for
that destination. The [archive](../archive/index.md) holds the project's dated
public evaluation records, including failed attempts and their original scope.

## Add held-out and lifecycle checks

A development case helps the author find the repair. A held-out case tests the
claimed behavior with different source material or timing after the candidate is
fixed. Keep its generation and assessment separate from the author's loop.
Do not present repeated runs of the same input as independent task coverage.

For a stateful feature, include these interventions where relevant:

- Deny the exact proposed action and verify the effect is absent.
- Interrupt after admission and inspect whether the effect is known or unknown.
- Resume a pending question and answer it explicitly without restarting old work.
- Close and idle-resume committed results; verify no callback/model replay.
- Exhaust the relevant byte, quota or deadline bound and inspect the saved state.

The [self-development skill fixture](../../scripts/demo-self-development.exs)
checks that its instructions/resources load through ordinary Session tools:

```sh
mix run scripts/demo-self-development.exs
```

It uses a scripted provider and performs no model inference or candidate edit.
Use it to understand the instruction-loading path, not as evidence of coding
quality or unattended operation.

## Measure the property you name

The explicit-memory measurement is a useful worked example:

```sh
mix run scripts/measure-memory.exs
```

Read [the measurement guide](../../examples/memory/README.md) and the script.
It fixes synthetic records and queries, forbids provider dispatch, checks exact
sources/spans and validates saved Sessions. Its corpus digest identifies the
input. Lexical retrieval scores, current-state bytes, latency and sampled VM
memory describe different dimensions. They do not establish semantic quality,
peak memory, invoice cost or another host's performance.

For a model-assisted task, record actual request usage, unknown coverage and the
configured cost basis. Review any shared budget reservation separately from a
cost estimate. Missing usage is unavailable, not zero. Use the
[accounting chapter](usage-accounting.md) when designing aggregation.

## Deliver a bounded conclusion

State which criteria passed, which failed, what assistance occurred and which
claims remain unverified. Bind each conclusion to the source and configuration
actually assessed. A partial external review or scan retains its omissions after
you repair a finding; a local fixture cannot expand that review's coverage.

Before merging a candidate, follow [change review](reviewing-changes.md), run the
appropriate source/native/installed checks, and inspect the exact candidate
revision's results. Preserve failed attempts and superseded evaluation methods
in the archive. Keep the active training/manual pages focused on repeatable
procedures rather than accumulating scorecards or milestone reports.
