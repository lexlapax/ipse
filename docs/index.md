# Ipse documentation

Start with the [README](../README.md) for the overview and credential-free quick
start. Use the guides below for operation, development, and project context.

## Operate Ipse

| Guide | Covers |
| --- | --- |
| [Arch Linux setup](operator/arch-linux.md) | Prerequisites, source installation, development setup, release requirements |
| [Usage](operator/usage.md) | Providers, login, approvals, skills, resume, logout, state, limits |
| [Troubleshooting](operator/troubleshooting.md) | Build, callback, account, lock, and recovery problems |

## Develop Ipse

| Guide | Covers |
| --- | --- |
| [Contributing](../CONTRIBUTING.md) | Contribution scope and handoff requirements |
| [Agent instructions](../AGENTS.md) | Rules, code map, documentation and commit requirements |
| [Architecture](developer/architecture.md) | Modules, ownership, persistence, trust boundaries |
| [Context compaction](developer/context-compaction.md) | Preserved context, bounds, checkpoint and recovery contract |
| [Dependencies](developer/dependencies.md) | Runtime/build/CI inventory, script policy, approval requirements |
| [Testing and evidence](developer/testing.md) | Source/release checks, live acceptance, actual results |

## Project context

- [Plan](plan.md): priorities and acceptance criteria.
- [Naming](naming.md): the name and its sources.
- [Archive](archive/index.md): superseded documentation preserved for historical reference.

## Documentation ownership

Keep operating procedures in `operator/`, implementation and verification
guidance in `developer/`, and shared project context directly under `docs/`.
The README is the quick start; this page is the navigation map. Keep one
authoritative guide per topic and link to it from other entry points.

Before completing a sub-goal or milestone, follow the
[documentation completion rule](../AGENTS.md#finish-a-change): review both
audiences' guidance, update stale content, verify commands and evidence, check
file links and heading anchors, and keep this map current when documents move.
Preserve superseded material using the [archive policy](archive/index.md#archive-policy).
