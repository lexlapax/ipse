# Record attributed facts and query a graph

Use Graph when you want to record an explicit relationship, retain its source
quotation, and follow a bounded path through current facts. A fact is an
attributed assertion, not proof that its subject, predicate, and object are true.
Start with the explicit preset below. It uses no model, embeddings, MCP server,
or network service.

Graph is an independently built extension. It is separate from
[Corpus](corpus.md), [Research](research-extensions.md), and the [memory extensions](memory.md).
Importing or selecting one does not enable the others.

## Build and review an explicit graph

You need the source checkout and its [supported toolchain](arch-linux.md).
Run `./scripts/build.sh` from the repository root first, then run the following
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
work. Profile names select operator configuration, not modules, executables,
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
invoke Graph directly. Do not enter an ordinary conversational task if your goal
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

Traversal follows outgoing positive relationships, matching entity names without
case. Negative assertions can be retained but are not traversal steps. Bounds
are depth 0..4, 1..128 nodes, 1..256 edges, and 1..10 returned passages. Depth zero
follows no edge. `coverage.complete: false` means a traversal bound cut the path;
it does not mean the absent relationships were checked and disproved.

Facts retain one to eight citations. Subject/object IDs are at most 256 bytes,
predicates 128 bytes, and quotations 1024 bytes. Facts may be marked `inferred`
and have optional validity times. Structural conflict/inference labels describe
attributed assertions; they do not establish semantic truth. Review the exact
quoted source and the assertion before using the result for a decision.

Extraction selects one or two chunks and at most 32 facts. MCP-backed extraction
selects one chunk. Larger sources use the explicit source draft lifecycle in
[Corpus](corpus.md#use-larger-sources-and-optional-algorithms), rather than hidden
background extraction. Commands fit the ordinary 16-operation host allowance;
state scans have their separate read bound. A plan that cannot fit refuses.
Inspect the source and draft state before requesting a smaller explicit batch
instead of widening grants to evade the refusal.
The complete SDK request must fit 16 KiB and Graph's encoded result 12000 bytes.
Legal individual field maxima do not guarantee the combined object fits.

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

State permits 256 retained slots and 1 MiB per namespace, including drafts,
old pages, and tombstones. Collection removes unreachable bodies, but does not
recover slots. Export and plan a reviewed migration before filling the store.
Foreign imports preserve historical provenance and need explicit re-extraction
before becoming current evidence. Keep complete generation-consistent exports;
a partial export is not a complete restorable source.

For conflict, inspect again. For an unknown write/extraction, inspect source,
draft, and projection state before explicitly deciding what to finish or abort.
Resume never replays extraction or completes a draft. Keep locks and original
state intact. Artifact/options/configuration changes can prevent resume; use
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
  "extraction": {"assisted": {"kind": "model_complete", "profile": "extractor", "version": 1}}
}
```

Save them as `$IPSE_GRAPH_ARTIFACTS/graph-model-options.json`. Supply a separate
inference file with the exact
referenced host profile. This complete example expects an already available
local tool-capable model; it downloads nothing:

```json
{
  "profiles": {
    "extractor": {
      "provider": "ollama", "model": "qwen3:8b", "credential": "none",
      "timeout_ms": 120000, "max_output_tokens": 1024
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
/ext ext__graph__extract {"store":"notes","extraction":"assisted","source_id":"manual:model-release","generation":1,"max_edges":4,"chunks":["CHUNK_ID_FROM_INSPECT"],"facts":[]}
```

Wait for each command to finish and replace `CHUNK_ID_FROM_INSPECT` with its actual
64-character chunk ID before submitting extraction. Model extraction requires
`facts: []`; it does not accept a blend of supplied and generated facts. Model
profiles and billing remain explicit. See [profile configuration](model-profiles.md).

Model extraction has a separate full egress approval, followed by ordinary State
write approvals. Its proposed span must match a selected source chunk; malformed
JSON, invented chunk IDs, or invalid spans refuse. This establishes byte
attribution, not that the relationship accurately interprets the quotation.
Rendered extraction input is at most 4096 bytes and model output at most 8192
bytes. Two full 2048-byte chunks plus JSON framing can exceed the input allowance;
select a smaller batch when that happens. No source text is silently shortened.
Live optional model-extraction quality has not been measured. Do not infer that
an accepted response is a validated knowledge graph.

For remote storage, build `mcp-explicit` or `mcp-model` and select an `mcp_cas`
store with a fixed `binding`, `partition`, and `contract: "ipse-cas-v1"`. Supply
exact MCP aliases through the configuration generator and select the separate
MCP file at launch. The server must enforce partition access and atomic CAS.
Approvals display that route; they cannot enforce remote namespace policy.
Follow [the build guide](../../extensions/knowledge/README.md#choose-the-required-capabilities)
and [MCP configuration](mcp.md). No service is installed or chosen automatically.

To share retained sources with Corpus, use the same Ipse home, canonical project
workspace, logical State binding, and partition. A shared profile name alone does
not share data. Operator scope deliberately crosses workspaces; session scope
uses the durable session's identity. Review that sharing decision before enabling
another artifact against the same store.
