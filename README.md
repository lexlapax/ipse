# Ipse

Ipse is a general-purpose local AI harness with a terminal client, resumable
conversations, project instructions, skills and approved tools. Its core is
Elixir/OTP with a small Rust OS helper. Projects handled by Ipse may use other
languages and runtimes. The project is licensed under Apache-2.0.

The current prototype runs on Linux and macOS. It is a line-oriented terminal
application and an embeddable Session API. Start with the scripted demo, then
choose a provider explicitly when you are ready to use a model.

P27 is complete within its optional Corpus, Graph and Research scope. The
[plan](docs/plan.md#p27-optional-research-graph-and-rag) records acceptance, the
selected hybrid reference configuration and its limits. OpenRouter, Gemini and
the provider registry (P29) are implemented and pass local and hosted checks.
The developer accepts the fresh-account P28 run; session permission improvements
are implemented and their verification is recorded in the plan. Grok API-key and
registered-client subscription routes are under verification as a P29 follow-up;
live OAuth requires an Ipse registration from xAI. Release acceptance and stable
publication remain open. Advisory decision engines (P30) remain proposed; voice
and media (P31) remain deferred.

## Build and try the demo

You need Elixir 1.18+, Erlang/OTP 27+, Rust 1.85+, Git and a C linker. From a source
checkout:

```sh
git clone https://github.com/lexlapax/ipse.git
cd ipse
mix local.hex --force
mix local.rebar --force
./dev/build.sh
./bin/ipse demo
```

The demo creates a temporary workspace, loads the review skill and its checklist,
writes and reads `ipse-demo.txt`, and runs a small shell command. It needs no
credentials or model service. Its answer is scripted, not inference. Expect tool
results followed by `Demo finished` and a saved session ID.

For a bundled release, follow [installation](docs/operator/install.md) to verify
the checksum, extract an OS/architecture/libc-compatible archive and link the
launcher. The bundle contains the VM, application and helper; no development
toolchain is needed. Run `ipse setup`, `ipse doctor`, then `ipse demo`.

## Start a real conversation

Save an explicit provider/model choice, check it, then start a conversation using
that route. Without a choice, chat and run announce the built-in ChatGPT
subscription default before auth:

```sh
./bin/ipse setup
./bin/ipse doctor
./bin/ipse chat --cwd /path/to/your/project
```

For ChatGPT subscription, complete the setup sign-in offer or run `./bin/ipse login`.
Open its displayed URL in a browser that can reach the same machine's loopback
listener. Other providers use their documented credential source. Replace the
example project path with an existing directory. Then ask a bounded task, such as:

```text
Read README.md and explain how to run this project. Do not change files.
```

Review full proposed arguments before approving any mutation or shell command.
Interactive approvals require the fresh `allow CODE` printed with that proposal;
`n` denies it. For repeated work, [session permissions](docs/operator/usage.md#approve-a-small-task)
offer native workspace edits and exact shell-call reuse. Inspect or revoke them
with `/permissions` and `/permissions clear`. A question answer grants no action permission. Headless `run`
denies mutations without `--yes`.

Use the [user manual](docs/operator/index.md) for API or local providers, model
profiles, commands and complete configuration examples. Selecting an API provider
uses its billing separately from a subscription. Ipse never silently switches
providers or billing modes.

## Find your next task

| Task | Guide |
| --- | --- |
| Work with approvals, skills and workspace instructions | [Terminal usage](docs/operator/usage.md) |
| Configure providers, profiles and project policy | [Configuration](docs/operator/configuration.md) |
| Connect external tools | [MCP](docs/operator/mcp.md) |
| Select reviewed extensions | [Extensions](docs/operator/extensions.md) |
| Store explicit notes with retention and suppression | [Memory](docs/operator/memory.md) |
| Retain sources and retrieve cited passages | [Corpus](docs/operator/corpus.md) |
| Record attributed facts and traverse relationships | [Graph](docs/operator/graph.md) |
| Investigate a question and inspect its evidence | [Research](docs/operator/research.md) |
| Recover interrupted work or start from a reviewed handoff | [Session recovery](docs/operator/recovery.md) |
| Inspect usage and shared quotas | [Resource controls](docs/operator/resources.md) |
| Contribute to the harness or build an extension | [Developer training](docs/developer/index.md) |

Corpus, Graph and Research are independently configured optional extensions.
Lexical retrieval can run without a model service. Embeddings, model extraction
and reranking require explicitly selected profiles; follow the linked setup guides
before enabling them.

Shell commands use your ordinary account permissions by default. An explicit
`--sandbox native` requests the supported workspace OS policy and fails closed
when unavailable. Approvals, process supervision and OS confinement are different
boundaries. Deliberately detached macOS descendants may survive cancellation with
workspace access. See [native policy](docs/operator/usage.md) before using it on
sensitive data.

Journals retain user/model/tool content locally. Resume restores saved work and
marks interrupted effects unknown; it never automatically replays them. Protect
that state and inspect effects before asking for a retry. Optional extensions,
MCP, memory, delegation and diagnostic capture require their own selection and
authority. Loading a skill or importing code grants no permission to execute it.

## Develop Ipse

Follow the [developer learning path](docs/developer/index.md) to build a checkout,
run a credential-free Session example and trace its owners. Read
[AGENTS.md](AGENTS.md) before repository changes and
[CONTRIBUTING.md](CONTRIBUTING.md) before submitting them.

The [documentation map](docs/index.md) separates user and contributor manuals.
The [plan](docs/plan.md) owns project status. Dated verification and research records
live in the [archive](docs/archive/index.md). The [security policy](SECURITY.md)
explains the threat model and private reporting procedure.

The name comes from Latin *ipse*, the emphatic "self", with inspiration from
Douglas Hofstadter's *I Am a Strange Loop*. See [naming](docs/naming.md).

## License

[Apache-2.0](LICENSE), Copyright (c) 2026 Sandeep Puri. Dependencies and bundled
Erlang/Elixir runtimes retain their licenses and notices; see
[third-party notices](THIRD_PARTY_NOTICES.md).
