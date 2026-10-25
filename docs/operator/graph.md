# Record attributed facts and query a graph

Use Graph when you want to record an explicit relationship, retain its source
quotation, and follow a bounded path through current facts. A fact is an
attributed assertion, not proof that its subject, predicate, and object are true.
Start with the explicit preset below. It uses no model, embeddings, MCP server,
or network service.

Graph is an independently built extension. It is separate from
[Corpus](corpus.md), [Research](research.md), and the [memory extensions](memory.md).
Importing or selecting one does not enable the others.

## Build and review an explicit graph

You need the source checkout and its [supported toolchain](arch-linux.md).
Run `./dev/build.sh` from the repository root first, then run the following
commands in that same terminal:

```sh
IPSE_GRAPH_ARTIFACTS=$(mktemp -d)
IPSE_GRAPH_HOME=$(mktemp -d)
IPSE_GRAPH_WORKSPACE=$(mktemp -d)
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_GRAPH_ARTIFACTS/graph" \
  --package graph --preset state-explicit
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_GRAPH_ARTIFACTS/graph" \
  --package graph --preset state-explicit --instance graph \
  --options extensions/knowledge/options/graph-explicit.json \
  --state-binding knowledge \
  --output "$IPSE_GRAPH_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_GRAPH_HOME" ./bin/ipse extension import "$IPSE_GRAPH_ARTIFACTS/graph"
```

The builder requires a fresh artifact output path and compatible platform/OTP
version. It compiles the selected preset into the artifact. Configuration cannot
add capabilities to an existing artifact. These commands do not call a model.
The artifact declares SDK 2 and `invoke.result.pages`; review that complete-result
grant in the generated trust alongside the selected State capabilities.
If you already have a reviewed compatible artifact, skip building and import it
instead. See [the package build guide](../../extensions/knowledge/README.md).

Review the source, manifest, and generated configuration. Import prints the
artifact digest. Inspect that actual digest using the same private home:

```sh
IPSE_HOME="$IPSE_GRAPH_HOME" ./bin/ipse extension inspect DIGEST
```

Replace `DIGEST` with the import result. Import/inspection are inert. They do not
execute the worker, approve writes, or activate the instance.

The supplied options file contains this complete closed selection:

```json
{
  "version": 1,
  "stores": {"notes": {"kind": "state", "scope": "project", "partition": "manual"}},
  "search": {},
  "fetch": {},
  "retrieval": {},
  "embedding": {},
  "rerank": {},
  "extraction": {"asserted": {"kind": "explicit", "version": 1}}
}
```

All seven registries must be present, including empty ones. Unknown fields,
unused authority, missing profiles, and incompatible presets refuse before host
work. Graph's `retrieval` registry must remain empty. Its query command uses the
explicit traversal bounds below rather than a Corpus retrieval profile.
Profile names select operator configuration, not modules, executables,
endpoints, or arbitrary host requests supplied in command arguments.

## Prepare one explicit fact without a model

This walkthrough records `Release requires quiescence.` as a source and asserts
that relationship with an exact quotation. Facts carry source/chunk hashes and
byte coordinates. Use the reviewed local evidence helper to construct those
fields instead of inventing them.

Run this before opening chat. It writes one command to a local text file. It
performs no host action, model request, or change to graph state:

```sh
elixir -r extensions/knowledge/src/evidence.ex -e '
alias IpseKnowledge.Evidence
{:ok, source} = Evidence.source(%{
  "source_id" => "manual:release",
  "partition" => "manual",
  "generation" => 1,
  "title" => "Release policy",
  "text" => "Release requires quiescence.",
  "uri" => "local:release-policy",
  "observed_at_ms" => 1700000000000,
  "event_at_ms" => nil,
  "expires_at_ms" => nil,
  "origin" => %{
    "kind" => "provided", "store_profile" => "notes",
    "partition_or_scope" => "manual", "receipt" => nil,
    "historical" => false
  }
})
{:ok, [chunk]} = Evidence.chunks(source)
{:ok, citation} = Evidence.citation(source, chunk, 0, byte_size(source["text"]))
{:ok, fact} = Evidence.fact(%{
  "subject" => "Release", "predicate" => "requires", "object" => "quiescence",
  "polarity" => "positive", "inferred" => false,
  "valid_from_ms" => nil, "valid_to_ms" => nil,
  "extraction" => %{"kind" => "explicit", "profile" => nil, "version" => 1},
  "citations" => [citation]
})
arguments = %{
  "store" => "notes", "extraction" => "asserted",
  "source_id" => source["source_id"], "generation" => 1,
  "max_edges" => 1, "chunks" => [chunk["chunk_id"]], "facts" => [fact]
}
IO.puts("/ext ext__graph__extract " <> JSON.encode!(arguments))
' > "$IPSE_GRAPH_ARTIFACTS/extract-command.txt"
cat "$IPSE_GRAPH_ARTIFACTS/extract-command.txt"
```

The helper runs in a separate Elixir process; it is an authoring step for your
explicit assertion. It does not extract the relationship from language or verify
its meaning. Keep the source text, ID, generation, URI, timestamps, partition, and
origin consistent with the source you store next. Changing any of them can
invalidate its citation. A different assertion needs its own reviewed fields and
source span.

## Select Graph and store the source

Inspect the generated disabled instance, then explicitly select it:

```sh
IPSE_HOME="$IPSE_GRAPH_HOME" ./bin/ipse config \
  --config "$IPSE_GRAPH_ARTIFACTS/operator.json" --no-project-config \
  --extension graph
IPSE_HOME="$IPSE_GRAPH_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_GRAPH_ARTIFACTS/operator.json" --no-project-config \
  --extension graph --cwd "$IPSE_GRAPH_WORKSPACE"
```

The demo main provider avoids model credentials. The following `/ext` commands
invoke Graph directly. Enter one command, finish its approvals and wait for
`Finished.` before entering the next; a later `/ext` sent while work is active
is refused as busy. Do not enter an ordinary conversational task if your goal
is to exercise only these explicit commands.

In chat, enter:

```text
/ext ext__graph__source {"store":"notes","action":"put","args":{"source_id":"manual:release","generation":1,"expected_revision":0,"title":"Release policy","text":"Release requires quiescence.","uri":"local:release-policy","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}}
/ext ext__graph__source {"store":"notes","action":"inspect","args":{"source_id":"manual:release"}}
```

Wait for each command to finish. Review every proposed State write and approve
only the intended data using its printed `allow CODE`. A put can require several
writes because immutable source pages precede publication. Denial or interruption
can leave an unpublished draft; it does not authorize skipping approval.

Expect `status: "ok"`. Inspect reports the current source generation, root
revision, state, chunk IDs/spans, and projection metadata without returning the
full source body. Keep the actual revision for later changes. Do not assume the
root revision equals the source generation or the number of user commands.

## Publish and traverse the relationship

Paste the entire line from `extract-command.txt` into chat. The command selects
the stored source generation, one exact chunk, and the explicit fact. Review its
State writes separately. Expect `status: "ok"` when publication completes. A
saved source alone does not create a fact projection.

Then enter:

```text
/ext ext__graph__query {"store":"notes","entity":"Release","depth":2,"max_nodes":8,"max_edges":8,"top_k":5,"as_of_ms":null}
```

Expect a graph passage quoting `Release requires quiescence.`, an attributed
`Release`/`requires`/`quiescence` claim, and coverage with `revalidated: true`.
`as_of_ms: null` selects and records the current time. An explicit value is Unix
milliseconds. Sources observed after that time, expired sources, historical
imports, and facts outside their validity interval are not current evidence.
As-of queries filter retained generations; they do not reconstruct replaced
source generations or deleted graph history. A past timestamp cannot recover
facts whose source generation has been replaced or forgotten.

Traversal follows outgoing positive relationships, matching entity names without
case. Two positive requirements such as `Release requires quiescence` and
`Release requires tests` can coexist. Graph flags a conflict when current
assertions give opposite polarities to the same subject, predicate and object.
Both assertions remain separate claims with their supporting citations.
Negative assertions whose subjects were reached remain attributable context,
including when the seed has no positive outgoing relationship. They never count
as traversal steps or make their objects into reached nodes.
Object names use the same case-insensitive matching: `lock` and `LOCK` name the
same traversal node. Claims keep the original recorded spelling and citations.
Read both claims before treating a `conflict` as resolved.

`coverage.seed` records the requested starting entity. `edges` counts positive
traversal steps. `context_facts` includes the selected facts and retained context,
while `negative_context` counts negative assertions in that context.
`counterassertions` counts additional assertions that conflict with selected
positive facts. A negative assertion with a different predicate can remain
context without being a counterassertion. A negative-only result can return
`status: "ok"`, its exact supporting quotation, zero edges and one seed node.

Bounds are depth 0..4, 1..128 nodes, 1..256 traversal edges, and
1..10 returned passages. Depth zero follows no edge. Reaching the depth limit
while an unvisited positive outgoing fact remains makes coverage incomplete,
including at depth zero. Reaching a leaf or finishing a cycle does not leave
unfinished traversal work. `coverage.complete: false` means a traversal bound cut
the path; the result is `partial`, and absent relationships have not been checked
and disproved. An unpublished source also makes the result partial, including an
empty result. Complete empty traversal returns `abstain`.

The query examines the bounded store population before selecting a path; the
256-edge limit does not cap unrelated stored facts. Supporting assertions and
negative context for reached entities must together fit 256 facts. If that
complete context is larger, the query refuses with `graph_context_limit` and
returns no claims. It does not drop counterassertions to fit. Query a more
specific entity or a smaller depth or edge limit, then inspect the new coverage.

Forgotten and non-current sources remain excluded, with diagnostics in `gaps`
and `coverage.exclusions`. Facts outside their validity interval also appear
there as `excluded_fact`. These exclusions alone do not make a completed
traversal partial. A missing source or changed source generation leaves a
`stale_fact` gap and partial coverage. Read the
coverage and supporting citations before drawing a conclusion from absence.

Facts retain one to eight citations. Subject/object IDs are at most 256 bytes,
predicates 128 bytes, and quotations 1024 bytes. Facts may be marked `inferred`
and have optional validity times. Extraction retains a correctly attributed fact
even when its validity interval is in the future or past. Use `as_of_ms` to query
inside that interval. The source must also be eligible at the selected time.
Queries outside the interval report `excluded_fact` without deleting the fact.
Structural conflict/inference labels describe
attributed assertions; they do not establish semantic truth. Review the exact
quoted source and the assertion before using the result for a decision.

Extraction selects one or two chunks and at most 32 facts. MCP-backed extraction
selects exactly one chunk. Explicit facts are packed and checked against actual
encoded storage and effect costs before the draft is claimed. The count ceiling
does not guarantee that every combination of large citations fits.
Each source retains at most eight projection heads across profiles. A new profile
at that ceiling refuses with `projection_bounds` before model inference or a draft
claim. Updating an existing profile still uses its current head. Inspect the
source's projection metadata and reuse an existing profile. If a new profile is
required, publish a new source generation and explicitly rebuild its projections.
Larger sources use the explicit source draft lifecycle in
[Corpus](corpus.md#publish-a-larger-source), rather than hidden
background extraction. Each invocation has at most 16 effects and a separate
read allowance. A plan that cannot fit refuses.
Inspect the source and draft state before requesting a smaller explicit batch
instead of widening grants to evade the refusal.
The complete SDK request must fit 16 KiB. Legal individual field maxima do not
guarantee the combined request fits.

## Read every claim's supporting citations

`top_k` limits returned evidence passages. Attributed claims retain their own
complete `basis`, including supporting citations outside that evidence list.
Read a claim's basis when checking its provenance; the first evidence passage
alone need not support every returned claim.

Small results print directly. A larger result returns a `saved.result` descriptor
with its output ID, byte count and SHA256. Graph keeps the complete claims,
citations, gaps and coverage in that document, up to the 4 MiB aggregate limit.
Each quotation still allows at most 1024 bytes. No claim basis is removed to
make the result fit an inline reply.

In the same chat, replace the example ID with the returned output ID and inspect
the first claim's first supporting quote:

```text
/result {"output_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","path":["claims",0,"basis",0,"quote"]}
```

After closing chat, print the whole result with the original session ID and
state directory:

```sh
IPSE_GRAPH_OUTPUT_ID='COPY_THE_64_CHARACTER_OUTPUT_ID'
IPSE_GRAPH_SESSION_ID='COPY_THE_SESSION_ID'
IPSE_HOME="$IPSE_GRAPH_HOME" ./bin/ipse result "$IPSE_GRAPH_OUTPUT_ID" \
  --resume "$IPSE_GRAPH_SESSION_ID" --state-dir "$IPSE_GRAPH_HOME/sessions"
```

This read starts no traversal, extraction, worker or model call. It returns a
historical receipt, not a new eligibility check on its sources. Suppression or
expiry affects future queries while earlier journal bytes remain. A model can
read a saved result only after an original tool invocation discloses it in that
session; direct command output stays separate. See [saved-result reading](extensions.md#invoke-a-command-and-inspect-its-complete-result)
for bounded views, cursors and capacity or recovery errors.

## Replace, suppress, and recover a source

Inspect the source before any update. A replacement needs a strictly newer source
generation and the inspected root revision. Existing facts cite the old
generation; replacement requires explicit fresh extraction. Queries do not
silently regenerate projections.

To suppress the source, use this command shape with the actual current revision:

```text
/ext ext__graph__source {"store":"notes","action":"forget","args":{"source_id":"manual:release","expected_revision":CURRENT_REVISION}}
```

Replace `CURRENT_REVISION` with the integer from inspection before submitting.
Suppression prevents future retrieval and stale projection resurrection. It does
not erase earlier conversation, journals, exports, backups, or provider transfers.
Close affected conversations and start fresh without forgotten text when that is
your goal. Ordinary resume retains earlier committed results.

Each partition permits 32 source roots, including unpublished drafts and suppression markers. Importing
a new suppression marker consumes a source slot just as ingestion does. A full
partition needs a separate reviewed partition for new sources; collection retains
its existing roots.
State permits 256 retained slots and 1 MiB per namespace. A qualified MCP v3
partition permits 88 retained records and at most 1 MiB. Both counts include old
pages, drafts' staged pages and tombstones. Collection removes unreachable bodies
but does not recover slots. Follow the [export procedure](corpus.md#export-sources-before-migration)
and plan a reviewed migration before filling the store.
Foreign imports preserve historical provenance and stay excluded from current
queries even after extraction. To use a freshly verified capture as current
evidence, inspect the root and explicitly replace the source through the earlier
ingestion procedure, using a newer generation and the current revision. Submit
that fresh capture without `historical_import`, then extract new facts from it.
Keep complete generation-consistent exports;
a partial export is not a complete restorable source.

Creation checks the store generation used to count available slots. A different
source's concurrent write can therefore cause `conflict`; inspect before
explicit new work. Unknown creation may already have occupied its slot.
Before upgrading artifacts that share a binding, close older Sessions and wait
for their admitted effects to finish, then retire their old writer configuration.
The limit relies on all writers using the current admission check. Existing
valid stored data needs no conversion.

If a legacy partition already exceeds 32 roots, whole-store queries refuse with
`root_capacity_exceeded`. Keep its data. Addressed inspection, paged export and
existing-source maintenance remain available within other limits. Suppression
retains a root and cannot reduce the count. Plan a deliberate migration into
bounded partitions; do not delete suppression markers to make room.

New MCP record additions require an explicit `ipse-cas-v3` selection and a server
that enforces the atomic 88-record ceiling across all its writer routes.
A full snapshot costs `1 + ceil(records / 8)` MCP calls. Each call consumes one
of the invocation's 16 effects, so at 88 records the snapshot alone uses 12.
Other work can therefore hit `effect_limit` before storage fills. An inherited
larger store returns `remote_snapshot_limit` before the
root-count check, including for addressed inspection, export and maintenance.
Use the configured server's reviewed administrative export/migration procedure
for recovery, preserving source identities and suppression markers. Follow the
[store limits](corpus.md#keep-stores-bounded-and-recover-from-refusal) before filling
a remote store.

For conflict, inspect again. After a denied, failed or interrupted extraction,
inspect its source before deciding whether to discard the unpublished draft:

```text
/ext ext__graph__source {"store":"notes","action":"inspect","args":{"source_id":"manual:model-release"}}
/ext ext__graph__source {"store":"notes","action":"abort","args":{"source_id":"manual:model-release","draft_id":"DRAFT_ID_FROM_INSPECT","expected_revision":CURRENT_REVISION}}
```

Wait for inspection, then replace `DRAFT_ID_FROM_INSPECT` with `coverage.draft.id`
and `CURRENT_REVISION` with `coverage.revision`. Use the actual source ID of your
failed extraction. Approve the exact State write. Abort requires the current
draft ID and root revision; a stale ID or revision refuses without clearing a
newer draft. It preserves the source and already published projections. A late
result from the aborted draft cannot publish. Abort also works for an unfinished
source-ingestion draft. It does not cancel or undo work at a remote model service.

For an unknown model outcome, inspect the service and retained journal before
explicitly deciding whether to request new work. Resume never replays extraction
or completes a draft. Keep locks and original state intact.
Artifact/options/configuration changes can prevent resume; use
[Recovery](recovery.md) with reviewed context rather than editing saved receipts.

## Add optional model extraction or an MCP store

Explicit State Graph is the default. Model extraction is a separate artifact
preset, not an invocation flag that grants inference. To use it, prepare complete
options retaining the same seven registries, but select an extraction profile
such as:

```json
{
  "version": 1,
  "stores": {"notes": {"kind": "state", "scope": "project", "partition": "manual"}},
  "search": {}, "fetch": {}, "retrieval": {}, "embedding": {}, "rerank": {},
  "extraction": {"assisted": {"kind": "model_complete", "profile": "extractor", "version": 1, "output_contract": "json_schema_v2"}}
}
```

Save them as `$IPSE_GRAPH_ARTIFACTS/graph-model-options.json`.
`output_contract: "json_schema_v2"` asks the host to send a task-specific schema
and accept only matching JSON. It requires a host supporting `model.complete`
version 2 and a compatible native Ollama service. Other providers refuse before
model approval or dispatch. Omit `output_contract` to retain the original text
contract for other providers. There is no automatic fallback between these modes.
Keep `version: 1` in the extraction profile. `output_contract` selects version 2
of the host model request; it does not change Graph's profile version.

Supply a separate inference file with the exact
referenced host profile. This complete example expects an already available
compatible local model; it downloads nothing. This profile explicitly requests
disabled thinking. Check that the model's `/api/show` response permits `false`,
or select a supported model/profile before using it:

```json
{
  "profiles": {
    "extractor": {
      "provider": "ollama", "model": "qwen3:8b", "credential": "none",
      "reasoning_effort": "none",
      "timeout_ms": 120000, "max_output_tokens": 4096
    }
  }
}
```

Save this file as `$IPSE_GRAPH_ARTIFACTS/graph-inference.json`, then build and
configure a fresh artifact:

```sh
elixir extensions/knowledge/build.exs \
  --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_GRAPH_ARTIFACTS/graph-model" \
  --package graph --preset state-model
elixir extensions/knowledge/config.exs \
  --artifact "$IPSE_GRAPH_ARTIFACTS/graph-model" \
  --package graph --preset state-model --instance graph \
  --options "$IPSE_GRAPH_ARTIFACTS/graph-model-options.json" \
  --state-binding knowledge \
  --inference-config "$IPSE_GRAPH_ARTIFACTS/graph-inference.json" \
  --output "$IPSE_GRAPH_ARTIFACTS/operator-model.json"
IPSE_HOME="$IPSE_GRAPH_HOME" ./bin/ipse extension import "$IPSE_GRAPH_ARTIFACTS/graph-model"
```

Inspect its actual digest. Validate `operator-model.json` with `--extension graph`,
then select that file/instance in a fresh chat as above. Keep the main provider
`demo` if you want model use only through the separately approved extractor.
The same logical binding grants the new artifact access to existing sources.
It does not remove suppression. For a new unsuppressed demonstration source:

```text
/ext ext__graph__source {"store":"notes","action":"put","args":{"source_id":"manual:model-release","generation":1,"expected_revision":0,"title":"Release policy","text":"Release requires quiescence.","uri":"local:release-policy","observed_at_ms":1700000000000,"event_at_ms":null,"expires_at_ms":null}}
/ext ext__graph__source {"store":"notes","action":"inspect","args":{"source_id":"manual:model-release"}}
/ext ext__graph__extract {"store":"notes","extraction":"assisted","source_id":"manual:model-release","generation":1,"max_edges":1,"chunks":["CHUNK_ID_FROM_INSPECT"],"facts":[]}
```

Wait for each command to finish and replace `CHUNK_ID_FROM_INSPECT` with its actual
64-character chunk ID before submitting extraction. Model extraction requires
`facts: []`; it does not accept a blend of supplied and generated facts. Model
profiles and billing remain explicit. See [profile configuration](configuration.md#reuse-a-named-model-profile).

The extractor sees short chunk IDs and copies exact supporting quotations.
Ipse derives their byte positions and retains the canonical source/chunk hashes.
Continue using the inspected 64-character IDs in your `/ext` command; short IDs
exist only inside that model request.
An explicitly denied relationship can carry `negative` polarity. Repeated text
must have a unique supporting quote within the selected chunk; ambiguous or
altered quotes refuse the entire model response. No automatic correction call
follows. Inspect the retained draft after `invalid_model_output` before deciding
whether to abort it or request new work. Valid source attribution still requires
you to review whether the quotation supports the proposed relationship.

First review the State writes that claim the extraction draft. Then review the
separate full model-egress approval and the State writes that publish its result.
Its supporting quote must match exactly once in the selected source chunk;
malformed JSON, invented chunk IDs, or invalid attribution refuse. This establishes byte
attribution, not that the relationship accurately interprets the quotation.
The model receives the explicit `max_facts` bound. In the structured mode selected
above, the host also sends a schema requiring the closed fact shape and that
count limit. Invalid JSON or a schema mismatch fails the model action while
retaining its completed usage. No repair request follows.
Graph then checks the count, UTF-8 byte limits, unique supporting quote and cited
source spans independently. Schema validity does not prove that a quotation
supports the relationship.
Rendered extraction input is at most 4096 bytes and model output at most 8192
bytes. The complete structured request, including schema and JSON escaping, is
at most 12 KiB. The adapter checks that bound before emitting a model action.
Two full 2048-byte chunks plus JSON framing can exceed the input allowance;
select a smaller batch when that happens. No source text is silently shortened.
Start with the one-fact batch above. Before inference, Store checks the remaining
effect, read and record allowance and returns a bounded page plan for publication.
The model still receives the requested `max_facts`, up to 32. The actual returned
facts must fit both that count and the admitted page/encoded-byte plan.
The plan is not a promise that every set of 32 large facts fits. A result that
exceeds it refuses publication and leaves the draft available for inspection and
exact abort. A competing writer can also consume capacity after the draft claim.
Live optional model-extraction quality has not been measured. Do not infer that
an accepted response is a validated knowledge graph.

For remote storage, build `mcp-explicit` or `mcp-model` and select an `mcp_cas`
store with a fixed `binding`, `partition`, and `contract: "ipse-cas-v3"`. Supply
exact MCP aliases through the configuration generator and select the separate
MCP file at launch. The server must enforce partition access, atomic CAS and the
partition-wide 88-record ceiling across every accepted writer/version route.
Approvals display that route; they cannot enforce remote namespace policy.
Follow [the build guide](../../extensions/knowledge/README.md#choose-the-required-capabilities)
and [MCP configuration](mcp.md). No service is installed or chosen automatically.
The [remote Corpus procedure](corpus.md#select-a-remote-store) shows the complete
store selection and binding files; retain Graph's extraction registry and preset
when applying it here. Keep Graph's retrieval registry empty. Legacy v1/v2
profiles retain reads and zero-record maintenance, including exact abort and
forget, within snapshot limits. Replacement `put` and projection publication
still add pages, so those operations require v3. Follow the explicit cutover
procedure after draining older writers. Ipse never upgrades or falls back from
the selected contract automatically.

To share retained sources with Corpus, use the same Ipse home, canonical project
workspace, logical State binding, and partition. A shared profile name alone does
not share data. Operator scope deliberately crosses workspaces; session scope
uses the durable session's identity. Review that sharing decision before enabling
another artifact against the same store.
