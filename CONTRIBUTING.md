# Contributing

Run `./scripts/build.sh`, then `mix test`. A small change with a clear problem,
observable behavior, and relevant verification is welcome. Open an issue for
larger changes before expanding the architecture.

Read [AGENTS.md](AGENTS.md) for repository conventions and the code map. Start
with [docs/arch-linux.md](docs/arch-linux.md) for a local Codex CLI setup;
[docs/plan.md](docs/plan.md) describes priorities and acceptance criteria.

Use Elixir for orchestration and Rust for narrow OS integration. Keep scripts and
provider fixtures credential-free. Avoid committing transcripts, credentials,
build artifacts, or generated binaries.

Contributions are provided under the repository's MIT license. This early prototype
has no stability or support guarantee; changes should document any compatibility
impact. Never claim live-provider validation when only fixtures were used.
