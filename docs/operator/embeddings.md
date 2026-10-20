# Create embeddings through a reviewed extension

Use an embedding extension to turn explicitly supplied text into numeric vectors.
Ipse sends the approved inputs to one named embedding profile and records its
usage. A vector is a model output, not a citation, a saved memory or proof that a
retrieval answer is correct. An extension must separately implement those tasks.

You need a reviewed compatible embedding artifact and an available embedding
service. OpenAI API and local Ollama are supported. ChatGPT subscription,
Anthropic and the scripted demo do not supply embeddings. Selecting a profile
does not download a model or authorize a request.

## Configure one local profile and extension

The repository's [embedding example](../../examples/embedding-actions/README.md)
provides a small command that reconstructs the returned vectors and reports their
hashes. Obtain or build its compatible artifact, review it, then import it:

```sh
ipse extension import /path/to/reviewed-embedding-artifact
ipse extension inspect DIGEST
```

Replace `DIGEST` below with the printed artifact digest. Save the complete file
as `/private/path/embeddings.json`. This example expects an already installed
`embeddinggemma:latest` model at the selected local Ollama endpoint. Confirm your
service and model before invoking it; choose your actual model and exact native
dimensions if they differ.

```json
{
  "version": 1,
  "embedding_profiles": {
    "local_embedding": {
      "operation": "embedding",
      "provider": "ollama",
      "model": "embeddinggemma:latest",
      "dimensions": 768,
      "dimension_mode": "native",
      "credential": "none",
      "base_url": "http://127.0.0.1:11434",
      "timeout_ms": 30000
    }
  },
  "extension_trust": [{
    "artifact": "DIGEST",
    "capabilities": ["invoke.command", "host.actions", "host.embedding", "host.results", "host.actions.mixed"],
    "allow_project": false,
    "allow_children": false
  }],
  "extensions": [{
    "instance": "embeddings",
    "artifact": "DIGEST",
    "enabled": true,
    "options": {},
    "order": 0,
    "lifetime": "persistent"
  }]
}
```

Inspect configuration, then open chat with the scripted main provider:

```sh
ipse config --config /private/path/embeddings.json --no-project-config
ipse chat --provider demo --config /private/path/embeddings.json --no-project-config --cwd /path/to/scratch
```

Configuration inspection makes no inference. The main provider and embedding
profile are separate choices. In chat, invoke the reviewed command explicitly:

```text
/ext ext__embeddings__embed {"profile":"local_embedding","inputs":["The release checklist lives in the project handbook."],"timeout_ms":30000}
```

Inspect the approval's complete input, profile, model, dimensions, endpoint origin
and target digest. Approve only if this is the intended service. Invoking the
command alone does not approve its later embedding request. Headless mutations
are denied without the explicit session-wide `--yes` setting.

On success, expect `status: "ok"`, request/model/usage facts and one vector's
index, byte count, SHA-256 and page count. A 768-coordinate float32 vector occupies
3,072 bytes. The example reports metadata rather than printing thousands of
numbers. Provider errors return a bounded failure; the command does not retry or
select another service.

## Select dimensions and endpoints

At most eight operator embedding profiles are allowed. They remain separate from
main/routine/review text profiles. Project configuration cannot define or replace
the embedding registry, even with project trust enabled.

`dimensions` is an exact expected width from 1 through 4,096. With
`dimension_mode: "native"`, Ipse omits the wire dimensions field and checks the
response width. With `"request"`, it sends the configured width. Use request mode
only with a provider/model that supports it. A mismatch fails; Ipse never silently
shortens vectors or truncates input. Ollama requests explicitly disable truncation.

For OpenAI API, use `provider: "openai"`, your selected embedding model, its
dimensions and `credential: "OPENAI_API_KEY"`. Set that fixed environment variable
privately. The default endpoint is the public OpenAI API. A custom `base_url`
must use HTTPS or explicit loopback HTTP. Endpoints reject userinfo, queries and
fragments. Keep credentials out of configuration and URL paths.

Each call supplies one to eight nonempty UTF-8 inputs, at most 4,096 bytes each
and 12,288 input bytes together, within the full 16 KiB SDK object bound.
Escaping can make the encoded request larger than its input bytes. Timeouts are
1,000 through 120,000 milliseconds and narrow to the profile and session limits.
The provider may still reject input beyond its own context limit.

## Inspect usage and recover

Embedding requests consume ordinary action and model-step allowances and share
configured [session-tree budgets](budgets.md). Their accounting explicitly names
the embedding operation. Generated output tokens do not apply; the recorded
output count stays null. Missing applicable counters remain unknown. A local
service can consume resources even without an API invoice.

[Version-2 rate cards](usage-accounting.md#configure-a-rate-card) can separately
price embedding input and reported duration. A text-only card does not price an
embedding merely because provider/model names match. Unknown prices retain money
reservations.

If an embedding command refuses before approval and sends no request, check an
operator `journal.max_record_bytes` override. The selected vector count and
width, complete source and repeated result arguments must fit that ceiling.
For example, four 4096-coordinate vectors cannot fit a 65536-byte record.
Choose a smaller batch or an appropriate journal record limit in your explicit
configuration, then start a fresh invocation. The normal 16 MiB record ceiling
supports the documented vector bounds. Total journal byte/event limits still
apply during execution.

Cancel through the normal session controls if needed. Remote work may already
have happened. Failed or unconfirmed budget settlement prevents readable vector
publication and retains applicable liabilities. Diagnosis can retain genuine
final counters even if ledger coverage cannot be proven; resume then refuses.
Use [Recovery](recovery.md) to inspect original state rather than replaying it.

Idle resume makes no embedding call and reads no result pages. Changing a profile
can prevent resume because the old session pins its exact selection. Preserve the
original configuration or create a reviewed fresh-session handoff. A model alias
does not prove unchanged model weights. An extension index needs an explicit
generation/reindex policy when its selected model or profile changes. Corpus
binds current vectors to the approved embedding selection and requires an
[explicit reindex](corpus.md#add-explicit-embeddings-and-reranking) for older or
incompatible vectors. A timeout-only change preserves that vector identity.
