> Historical only. Preserved on 2026-10-22 from `5bffe00364d66f5012e5a0d4cd86c4180c74ebcb` before the structural/manual rewrite. Use [current guidance](https://github.com/lexlapax/ipse/blob/main/README.md). Relative prose links point to the original commit; commands and claims retain their original text.

# Ipse

Ipse is a general-purpose local AI harness with a terminal client, resumable
conversations, project instructions, skills and approved tools. Its core is
Elixir/OTP with a small Rust OS helper. Projects handled by Ipse may use other
languages and runtimes. The project is licensed under Apache-2.0.

The current prototype runs on Linux and macOS. It is a line-oriented terminal
application and an embeddable Session API. Start with the scripted demo, then
choose a provider explicitly when you are ready to use a model.

## Build and try the demo

You need Elixir 1.18+, Erlang/OTP 27+, Rust 1.85+, Git and a C linker. From a source
checkout:

```sh
git clone https://github.com/lexlapax/ipse.git
cd ipse
mix local.hex --force
mix local.rebar --force
./scripts/build.sh
./bin/ipse demo
```

The demo creates a temporary workspace, loads the review skill and its checklist,
writes and reads `ipse-demo.txt`, and runs a small shell command. It needs no
credentials or model service. Its answer is scripted, not inference. Expect tool
results followed by `Demo finished` and a saved session ID.

For a bundled release, extract an archive matching your OS/architecture/libc and
run `./ipse demo` from its root. It contains the VM, application and helper; a
development toolchain is not needed to run it.

## Start a real conversation

ChatGPT subscription is the default provider:

```sh
./bin/ipse login
./bin/ipse chat --cwd /path/to/your/project
```

Open the displayed sign-in URL and complete authorization in a browser that can
reach the same machine's loopback listener. Replace the example project path with
an existing directory. Then ask a bounded task, such as:

```text
Read README.md and explain how to run this project. Do not change files.
```

Review full proposed arguments before approving any mutation or shell command.
Interactive approvals require the fresh `allow CODE` printed with that proposal;
`n` denies it. A question answer grants no action permission. Headless `run`
denies mutations without `--yes`.

Use the [user manual](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/index.md) for API or local providers, model
profiles, commands and complete configuration examples. Selecting an API provider
uses its billing separately from a subscription. Ipse never silently switches
providers or billing modes.

## Find your next task

| Task | Guide |
| --- | --- |
| Work with approvals, skills and workspace instructions | [Terminal usage](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/usage.md) |
| Configure providers, profiles and project policy | [Configuration](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/configuration.md) |
| Connect external tools | [MCP](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/mcp.md) |
| Select reviewed extensions | [Extensions](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/extensions.md) |
| Store explicit notes with retention and suppression | [Memory](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/memory.md) |
| Recover interrupted work or start from a reviewed handoff | [Session recovery](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/recovery.md) |
| Inspect usage and shared quotas | [Usage](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/usage-accounting.md), [budgets](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/budgets.md) |
| Contribute to the harness or build an extension | [Developer training](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/index.md) |

Shell commands use your ordinary account permissions by default. An explicit
`--sandbox native` requests the supported workspace OS policy and fails closed
when unavailable. Approvals, process supervision and OS confinement are different
boundaries. Deliberately detached macOS descendants may survive cancellation with
workspace access. See [native policy](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/operator/usage.md) before using it on
sensitive data.

Journals retain user/model/tool content locally. Resume restores saved work and
marks interrupted effects unknown; it never automatically replays them. Protect
that state and inspect effects before asking for a retry. Optional extensions,
MCP, memory, delegation and diagnostic capture require their own selection and
authority. Loading a skill or importing code grants no permission to execute it.

## Develop Ipse

Follow the [developer learning path](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/developer/index.md) to build a checkout,
run a credential-free Session example and trace its owners. Read
[AGENTS.md](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/AGENTS.md) before repository changes and
[CONTRIBUTING.md](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/CONTRIBUTING.md) before submitting them.

The [documentation map](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/index.md) separates user and contributor manuals.
The [plan](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/plan.md) owns project status. Dated verification and research records
live in the [archive](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/archive/index.md). The [security policy](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/SECURITY.md)
explains the threat model and private reporting procedure.

The name comes from Latin *ipse*, the emphatic "self", with inspiration from
Douglas Hofstadter's *I Am a Strange Loop*. See [naming](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/docs/naming.md).

## License

[Apache-2.0](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/LICENSE), Copyright (c) 2026 Sandeep Puri. Dependencies and bundled
Erlang/Elixir runtimes retain their licenses and notices; see
[third-party notices](https://github.com/lexlapax/ipse/blob/5bffe00364d66f5012e5a0d4cd86c4180c74ebcb/THIRD_PARTY_NOTICES.md).
