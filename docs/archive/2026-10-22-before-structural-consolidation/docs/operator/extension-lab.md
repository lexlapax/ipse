> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/docs/operator/extensions.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Try the optional extension lab

Use the lab to see independently built extensions remember synthetic labels,
recall data through a bound lookup service, ask a question, and propose a file
workflow. It uses synthetic data and a scripted model, with no credentials,
network model, database, or paid service. Its literal corpus and deterministic
parser are teaching examples, not production memory or retrieval engines.

You need the source checkout, its supported Elixir/OTP toolchain, and an already
built Ipse SDK. Follow [developer setup](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/index.md#build-and-follow-your-first-session)
if you need to build it. Run commands from the checkout root. For ordinary explicit notes,
use [Memory](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/memory.md) instead of these lab artifacts.

## Build inert artifacts

```sh
IPSE_LAB_ARTIFACTS=$(mktemp -d)/artifacts
elixir scripts/build-artifact.exs extension-lab --sdk _build/dev/lib/ipse/ebin --output "$IPSE_LAB_ARTIFACTS"
```

Expect seven separately compiled local artifacts under the output directory.
The builder compiles reviewed example source and copies the license. Building
neither imports them nor enables them. Keep artifacts compatible with the
runner's platform and OTP version; activation refuses incompatible code.

Run the synthetic verification walkthrough:

```sh
elixir scripts/verify.exs source lab \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_LAB_ARTIFACTS"
```

It creates isolated workspace/state, exercises real host approvals/questions,
checks its assertions, and cleans scratch files. Its last deliberate service
crash leaves cleanup unconfirmed, so the report ends with
`safe_to_continue: false`. Exit zero means expected positive and negative cases
matched. It does not mean every callback succeeded or every cleanup was confirmed.

## Import examples into an isolated home

Use fresh directories so the exercise cannot mix with your ordinary notes or
session store:

```sh
IPSE_LAB_HOME=$(mktemp -d)
IPSE_LAB_WORKSPACE=$(mktemp -d)
elixir examples/extension-lab/config.exs "$IPSE_LAB_ARTIFACTS" "$IPSE_LAB_ARTIFACTS/operator.json"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension import "$IPSE_LAB_ARTIFACTS/memory"
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension import "$IPSE_LAB_ARTIFACTS/lookup"
```

Review the generated configuration and source. All instances start disabled.
Inspect the actual digests printed by import:

```sh
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse extension inspect DIGEST
```

Repeat for each imported artifact with its real digest. Import/inspect are inert;
they do not execute code or grant trust. The generated file grants the reviewed
lab capabilities and service routes. Both caller and lookup target must be
imported and selected; no missing dependency is installed automatically.

## Remember, recall, and run a file workflow

Launch only the memory and lookup instances:

```sh
IPSE_HOME="$IPSE_LAB_HOME" ./bin/ipse chat --provider demo \
  --config "$IPSE_LAB_ARTIFACTS/operator.json" --no-project-config \
  --extension memory --extension lookup --cwd "$IPSE_LAB_WORKSPACE"
```

In chat, use explicit commands:

```text
/ext ext__memory__remember {"text":"entity: Ada; link: Ada -> OTP"}
/ext ext__memory__recall {"text":"Ada"}
/ext ext__memory__export {}
/ext ext__memory__stats {}
/ext ext__memory__workflow {"path":"lab-note.txt"}
```

Review each state/file proposal and enter its own printed `allow CODE`. Answer
any structured question using its printed `answer CODE VALUE`; that answer does
not approve a later write. Expect recalled labels/source data, an export, and
counts/revision metadata from `stats`. `stats` returns no label/source content,
performs no lookup/context publication, and does not recreate missing state.
After the approved workflow, inspect `lab-note.txt` in the scratch workspace.

The lab memory is project-scoped to this working directory and its pinned
artifact/instance/configuration source. It is deliberately separate from the
bundled explicit-note memory's schema and deletion policy.

## Forget and inspect the outcome

```text
/ext ext__memory__forget {"entity":"all"}
/ext ext__memory__stats {}
/ext ext__memory__recall {"text":"Ada"}
```

After approved forgetting, expect a retained tombstone and no recreated labels.
Forget-all blocks recreation in that namespace. It does not erase old journals,
exports, or request context. Keep affected content out of a fresh session if
that is your goal. Do not edit state or remove locks to undo suppression.

For later persistent lab use, explicitly change only the desired instances to
`enabled: true` and `lifetime: "persistent"` in this dedicated file. Leave metadata,
usage, tool, and text observers disabled unless testing their additional views.
Changed code/configuration requires a fresh session; existing history stays
pinned. Follow [Extensions](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/extensions.md) for general recovery.

## Exercise an extracted release

To check an already-built compatible archive using these artifacts:

```sh
elixir scripts/verify.exs installed lab \
  --archive /path/to/ipse-release.tar.gz --input "$IPSE_LAB_ARTIFACTS"
```

Use the actual archive path for your OS/architecture/runtime. This checks the
unchanged archive's installed worker execution and temporary selection; it does
not build a new Ipse release. The verifier compiles the trusted proof with your development toolchain before
starting the extracted runner. The runner then uses its bundled runtime and the
prebuilt lab artifacts. Review actual failures and cleanup
status before accepting the result. [The developer lab guide](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/testing.md#learn-a-complete-workflow-through-the-compatibility-lab)
explains how the examples and their verification are structured.

When finished, exit every lab session before removing the disposable directories.
If cleanup is unconfirmed, inspect remaining processes first. Keep any report
you need, and never treat the lab's deliberate failure as authorization to retry
an uncertain effect automatically.
