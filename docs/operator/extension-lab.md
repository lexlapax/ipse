# Run the independent extension lab

The lab demonstrates separately built memory/workflow/retrieval artifacts using
synthetic data and a synthetic model adapter. It needs no credentials, model
service, database or network endpoint. Its deterministic label parser and literal
corpus are SDK examples, not production memory or research engines.

## Build against an existing runtime

Use an already-built checkout and its supported Elixir/OTP toolchain:

```sh
IPSE_LAB_ARTIFACTS=$(mktemp -d)
elixir examples/extension-lab/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LAB_ARTIFACTS"
mix run --no-compile examples/extension-lab/verify.exs "$IPSE_LAB_ARTIFACTS"
```

The explicit compiler step creates seven inert local artifacts. Import does not
compile code, fetch dependencies, grant trust or enable an instance. The proof
creates isolated workspace/state, drives actual approvals/questions and cleans
its scratch files. Its last deliberate service crash keeps cleanup unconfirmed;
the report stops with `safe_to_continue: false`. Exit zero means the declared
positive and negative assertions matched, not that every cleanup was confirmed.

To test those same artifacts against an already-built archive, without rebuilding
Ipse or using system development tools inside the release:

```sh
elixir examples/extension-lab/verify-package.exs dist/ipse-0.1.0-linux-x86_64-glibc-2.44.tar.gz "$IPSE_LAB_ARTIFACTS"
```

Use your actual archive filename. Build artifacts with a compatible SDK/toolchain
for that archive's platform and OTP version; activation refuses incompatible
artifacts. This procedure verifies the unchanged archive plus installed worker
execution and explicit temporary selection. [Verification scope](../developer/extension-proof.md)
distinguishes those results from production quality and supported-host evidence.

## Inspect and select the examples manually

Review the source/license and use a dedicated application home and scratch
workspace. The generated operator configuration leaves every instance disabled:

```sh
IPSE_LAB_HOME=$(mktemp -d)
IPSE_LAB_WORKSPACE=$(mktemp -d)
elixir examples/extension-lab/config.exs "$IPSE_LAB_ARTIFACTS" "$IPSE_LAB_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension import "$IPSE_LAB_ARTIFACTS/memory"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension import "$IPSE_LAB_ARTIFACTS/lookup"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse chat --provider demo --config "$IPSE_LAB_ARTIFACTS/operator.json" --extension memory --extension lookup --no-project-config --cwd "$IPSE_LAB_WORKSPACE"
```

Inspect each printed digest with `ipse extension inspect DIGEST`. Both caller and
lookup target must be imported and selected; there is no implicit installation
or fallback. The examples use private prompt views and can propose scoped writes
and file actions under ordinary approval. The question's answer never approves a
write. The demo provider is deterministic and uses no model service.

In chat, explicit commands include:

```text
/ext ext__memory__remember {"text":"entity: Ada; link: Ada -> OTP"}
/ext ext__memory__recall {"text":"Ada"}
/ext ext__memory__export {}
/ext ext__memory__workflow {"path":"lab-note.txt"}
/ext ext__memory__forget {"entity":"all"}
```

The memory state is project-scoped to this workspace and pinned artifact/instance/
configuration source. Forget-all retains a tombstone and blocks recreation in that
namespace; it does not erase journals or old request context. The lab's conservative
deletion behavior is described in the [developer contract](../developer/extension-proof.md#capture-recall-and-deletion).

For deliberate persistent selection, change only the memory/lookup instances to
`enabled: true` and `lifetime: "persistent"` in that dedicated operator file.
Keep the metadata, usage, tool and text observers disabled unless explicitly testing them. Existing
sessions pin their selection; use a fresh session for changed code/configuration.
See [general trust and recovery procedures](extensions.md).
