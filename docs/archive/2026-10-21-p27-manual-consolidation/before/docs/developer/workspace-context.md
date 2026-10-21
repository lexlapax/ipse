Historical manual from `d35287afbfc0101938f0c86e70748a5e1c354c9f`, archived on 2026-10-21 before topic consolidation. Commands and ownership may be obsolete. Use [the current chapter](../../../../../developer/workspace-context.md). The original body is retained; relative links outside code fences are rebased, and links to jointly preserved chapters point to these snapshots.

# Loading workspace instructions without changing authority

Workspace context tells the model how a project wants work done. It does not
choose credentials, grant tool permission, or enforce an OS sandbox. Explicit
operator requests take precedence; nearer `AGENTS.md` guidance overrides broader
guidance within a project, while Ipse-wide instructions supply defaults.

`Ipse.WorkspaceContext` owns discovery, bounds, manifests, drift, and nested-path
checks. Session owns when a snapshot becomes active and durable. Skills have an
independent saved catalog. Read `lib/ipse/workspace_context.ex` alongside
`test/workspace_context_test.exs` to keep filesystem policy concrete.

## Build the launch snapshot

`snapshot/2` takes the launch directory and Ipse home. It canonicalizes the
workspace and searches upward to the nearest valid Git repository/worktree
boundary. A Git directory needs a regular `HEAD`; a worktree pointer must resolve
to a valid Git directory. Outside a repository, cwd itself is the boundary.
Unrelated ancestors never become instructions.

Discovery reads `IPSE_HOME/AGENTS.md`, boundary-to-workspace `AGENTS.md` files, and
the workspace `README.md`. One level of explicit local Markdown references may
load `.md`, `.txt`, `.adoc`, or `.rst` resources inside the boundary. Discovery
never recursively runs scripts or loads arbitrary links. Absolute/outside links,
symlink sources, and sensitive components such as `.git`, `.ipse`, `.ssh`, `.aws`,
`.codex`, `auth`, `secrets`, and `tokens` are excluded.

| Resource | Limit |
| --- | --- |
| One UTF-8 source | 32 KiB |
| Source count | 16 |
| Aggregate source text | 128 KiB |
| Skill catalog | 256 entries, 256 KiB encoded metadata |

Missing optional sources are normal. Invalid, oversized, or inaccessible files
produce bounded diagnostics. Each source carries path, scope, kind, and SHA-256.
Path checks are not protection from a hostile process concurrently replacing
filesystem entries.

## Reconsider a tool after discovering deeper guidance

Read the fixture "loads only one-level local Markdown references and applies
nested guidance by target". It creates a launch snapshot, then targets a deeper
directory containing another `AGENTS.md`.

Before a file tool starts or asks for approval, Session calls nested preflight for
its target. New scoped guidance is synced as a snapshot, the old proposal settles
not started, and the model is asked to reconsider. The next request sees the new
context and the affected call's specific reason. Later queued calls receive a
generic stopped-before-start result. They do not inherit the first target's
path-specific diagnosis. Approval remains `not_decided`; preflight is not a read
or mutation receipt.

A revised mutation must obtain its own approval. An actually started interrupted
effect still has an unknown outcome. A shell string has no reliably inferable
complete target set, so this path preflight does not certify every directory a
shell may reach. Preserve that distinction when adding tool kinds.

## Keep saved instructions stable

A `workspace_context_snapshot` event stores bounded source text and manifest.
Resume uses the last validated saved snapshot and diagnoses changed/missing
sources without adopting their contents. Invalid snapshots stop recovery.
Explicit `/context refresh` reloads saved text and launch-scope sources through an
owned idle task, then commits both instruction and skill selections. Cancellation
must not commit half a refresh. Execution configuration is not reloaded.

The skill catalog records names, descriptions, canonical paths, digests, and
shadowed-source provenance, not skill bodies. Loading a selected skill or resource
rechecks path/digest; drift refuses until explicit refresh. Older journals acquire
a first catalog snapshot at the next model boundary, never on idle inspection.
`/context` and `/skills` show saved manifests; standalone `ipse skills` performs
fresh discovery.

Workspace text, skill metadata, and extension contributions enter a labelled
user-role reference message. Core rules stay in system text. Explicitly requested
skill bodies remain in the requesting operator turn. Neither representation
upgrades text into a fresh task or permission grant.

```sh
mix test test/workspace_context_test.exs
```

This suite checks repository boundaries, aliases, reference depth, sensitive paths,
size/UTF-8 limits, snapshot validation, and drift. For a Session preflight change,
find its assertions in the Session fixtures as well; pure discovery cannot prove
that intent journaling and approval occur after reconsideration.
