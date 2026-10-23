# P28 and P29 implementation briefs

Proposal record, 2026-10-23. Nothing in these briefs is implemented. They were
written against `dd510a7` from a read-only survey of the source, with file and
line references taken at that commit. Line numbers drift; treat each reference as
a starting point and confirm it before editing. Scope and acceptance belong to the
[plan](../../plan.md#p28-operator-usability-and-release-readiness). Current
behavior belongs to the [user manual](../../operator/index.md) and the
[contributor manual](../../developer/index.md).

| Brief | Milestone |
| --- | --- |
| [P28 brief](p28.md) | [P28: operator usability and release readiness](../../plan.md#p28-operator-usability-and-release-readiness) |
| [P29 brief](p29.md) | [P29: provider registry, OpenRouter and Gemini](../../plan.md#p29-provider-registry-openrouter-and-gemini) |

## How to use these briefs

Each brief is a sequence of work packages. A package lists its purpose, the files
to change, the required behavior, tests and the package's own done condition.
Implement packages in order unless the brief says they are independent. Commit
and push each verified package separately, following
[AGENTS.md](../../../AGENTS.md#finish-a-change).

Every package keeps the repository invariants: explicit provider and billing
selection, approvals, journal intent before effects, no automatic replay of
unknown outcomes, bounded input and output, owner-only credential storage, and
TLS verification. No package may weaken an existing test or product timeout to
pass. A package that discovers a needed change outside its listed files stops and
records the reason before widening scope.

Decisions marked **Decision** need the developer's answer before the package that
depends on them. Each brief recommends an answer. Record the answer in the plan or
in the package commit message.

The developer accepted every recommended answer in both briefs on 2026-10-23.
The plan records them under each milestone.

## Shared baseline checks

Run these from the repository root at the end of every package that changes code:

```sh
./dev/build.sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
./bin/ipse demo
elixir dev/check-docs.exs
```

Run `mix test --include native_sandbox` on Linux when a package touches the native
helper, sandbox resolution or doctor sandbox checks. Run `./dev/package.sh` and the
installed verifier when a package touches packaging, the launcher or release
output:

```sh
./dev/package.sh
elixir dev/verify.exs installed package --archive dist/ARCHIVE.tar.gz --input examples/memory-corpus.json
```

Hosted CI on Ubuntu and macOS must pass for the pushed commit before a package is
called done. Live provider or account checks are separate, opt-in and recorded
with their exact conditions. Fixture tests never prove live behavior.
