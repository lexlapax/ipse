# Contributing

Run `./scripts/build.sh`, then `mix test`. A small change with a clear problem,
observable behavior, and relevant verification is welcome. Open an issue for
larger changes before expanding the architecture.
Use the [private security reporting policy](SECURITY.md#reporting) for potential
vulnerabilities; the same guide supplies the review threat model and evidence rules.

Ordinary tests exclude host-dependent native sandbox enforcement. On a supported
Linux host, also run `mix test --include native_sandbox` for OS-boundary changes;
included checks fail when enforcement is unavailable. See the
[fixed profile](docs/developer/sandbox.md#verification).

Read [AGENTS.md](AGENTS.md) for repository conventions and the code map. Start
with [docs/operator/arch-linux.md](docs/operator/arch-linux.md) for a local Codex CLI setup;
[docs/plan.md](docs/plan.md) describes priorities and acceptance criteria.
Use the [documentation map](docs/index.md) to find operator and developer guides,
including [testing and evidence](docs/developer/testing.md).

Use Elixir for orchestration and Rust for narrow OS integration. Keep scripts and
provider fixtures credential-free. Avoid committing transcripts, credentials,
build artifacts, or generated binaries.
Use Elixir for scripts wherever possible, then Bash/portable shell or Ipse's
Rust helper for appropriate OS work. Document dependencies in the
[inventory](docs/developer/dependencies.md); new dependencies outside Elixir or
Rust packages require explicit developer approval with recorded reasons.

Contributions are provided under the repository's MIT license. This early prototype
has no stability or support guarantee; changes should document any compatibility
impact. Never claim live-provider validation when only fixtures were used.

Before completing a sub-goal or milestone, review and update developer and
operator documentation for accurate content, current commands, actual results,
and valid file links and heading anchors. Keep one authoritative guide per topic,
update the documentation map, and preserve superseded guides using the
[archive policy](docs/archive/index.md#archive-policy). Commit and push focused
changes to `origin` after the relevant checks pass; see
[AGENTS.md](AGENTS.md#finish-a-change).
