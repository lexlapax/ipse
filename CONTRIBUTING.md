# Contribute to Ipse

Start with the [contributor training manual](docs/developer/index.md). It walks
through a credential-free Session example, the ownership of a turn, and the
verification needed to change it. Read [AGENTS.md](AGENTS.md) for repository
conventions, invariants and the source map. The [plan](docs/plan.md) describes
priorities; it does not authorize implementing every proposed feature.

## Prepare a change

Choose a small, observable behavior. Read its implementation and focused tests
before editing. Discuss larger architectural changes before expanding their
scope. New domain behavior should use the documented extension APIs where they
fit; core changes should address host correctness, invariants or an identified
extension API gap.

Keep orchestration in Elixir/OTP and OS helpers in Rust. Use Elixir for repository
scripts where possible, then Bash or portable shell when appropriate. Consult
maintained packages before building common machinery, and record every dependency
in the [inventory](docs/developer/dependencies.md). Dependencies outside Elixir or
Rust packages require explicit developer approval with recorded reasons.

Use synthetic providers and isolated temporary homes. Keep credentials, private
transcripts, generated binaries and build artifacts out of commits. Report
potential vulnerabilities through the [private reporting procedure](SECURITY.md#reporting).

## Verify the result

For runtime changes, run the baseline from the repository root:

```sh
./scripts/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/ipse demo
```

The [verification manual](docs/developer/testing.md) explains focused fixtures,
loopback requirements, native enforcement and packaging checks. Native tests need
a supported host; a fixture pass does not establish live-provider behavior or
coverage on another operating system. State exactly what ran and what remains
unverified.

Review the affected manuals as whole chapters. Operator chapters must teach
users through prerequisites, complete usage examples, expected results and
recovery. Developer chapters must teach contributors through execution flow,
source ownership, worked examples and focused change exercises. Keep status in
the plan and dated evidence in the [archive](docs/archive/index.md), following its
[archive policy](docs/archive/index.md#archive-policy).

For documentation changes, validate the examples against the implementation and
run the local link, heading, manual and archive checks:

```sh
elixir scripts/check-docs.exs
```

## Submit focused work

Describe the problem, resulting behavior, relevant verification and compatibility
impact. Keep changes focused and preserve unrelated edits. Once a complete
sub-goal passes its required checks, commit it and push to `origin`; do not
force-push another contributor's work. Contributions use the repository's
Apache-2.0 license. This prototype does not promise a stable public API or support
service.
