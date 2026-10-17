# Documentation archive

Historical reference only. Archived commands and status claims may be obsolete.
Use the [current documentation map](../index.md) for supported guidance.

| Snapshot | Provenance | Current replacements |
| --- | --- | --- |
| [2026-10-17 before comparative self-hosting review](2026-10-17-before-self-hosting-review/index.md) | Commit `03d4187`; complete prior plan/knowledge design with rebased links and historical claims retained | [Plan](../plan.md), [evaluation protocol](../developer/self-hosting-evaluation.md), [knowledge design](../developer/knowledge-extensions.md) |
| [2026-10-17 metadata-only feed contract](2026-10-17-before-private-tool-feeds/index.md) | Commit `b8aae70`; original live feed contract before scoped tool views, with rebased links | [Feeds](../developer/extension-feeds.md), [tool sources/views](../developer/tool-events.md) |
| [2026-10-17 prompt-only delivery contracts](2026-10-17-before-answer-events/index.md) | Commit `22ac9e1`; notification/job contracts before completed-answer delivery, with rebased links | [Subscriptions](../developer/extension-events.md), [event jobs](../developer/extension-event-jobs.md) |
| [2026-10-17 capture before ring retention](2026-10-17-before-trace-ring/index.md) | Commit `59dd52f`; original operator/developer capture guides | [Operator controls](../operator/observability.md), [ring contract](../developer/observability.md#local-ring-retention) |
| [2026-10-17 observability proposal](2026-10-17-observability-proposal/index.md) | Commit `1d2d1cc`; original proposal with rebased links | [Operator controls](../operator/observability.md), [developer contract](../developer/observability.md) |
| [2026-10-14 documentation before restructuring](2026-10-14-before-restructure/index.md) | Repository commit `27fbf6d`; archived on 2026-10-14 | [Setup](../operator/arch-linux.md), [usage](../operator/usage.md), [architecture](../developer/architecture.md), [testing](../developer/testing.md) |
| [2026-10-15 Serenity return handoff](2026-10-15-serenity-handoff/index.md) | Repository commit `ec5fb85`; archived after Linux return verification | [Testing](../developer/testing.md#p0-closure-on-serenity-2026-10-15), [sandbox policy](../developer/sandbox.md), [plan](../plan.md) |
| [2026-10-16 extension editorial review](2026-10-16-extension-editorial-review/index.md) | Repository commit `7c2df84`; complete pre-review guide/plan snapshots with historical claims retained | [Quick start](../../README.md), [architecture](../developer/architecture.md), [extensions](../operator/extensions.md), [plan](../plan.md) |

## Archive policy

Archive superseded guides and substantial older versions that are useful for
understanding past behavior or decisions. Routine typo fixes do not need copies;
Git retains their history. Never archive credentials, private transcripts, or
generated build artifacts.

Use a dated, descriptive directory. Record the original paths, source commit or
other provenance, archive date, and links to current replacements in its index.
Mark every archived document as historical and retain its old body without
silently updating historical claims. Repair relative links for the archive's
location, noting that adjustment in the snapshot index. Keep active navigation
pointed at current guides; link historical material through this archive index.
