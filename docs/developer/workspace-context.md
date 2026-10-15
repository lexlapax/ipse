# Workspace context

Workspace context is an instruction input, separate from provider selection,
billing, approvals, and OS enforcement. A file cannot grant permission to run a
tool. Explicit user requests take precedence over repository guidance. Within a
project, nearer `AGENTS.md` scope overrides broader guidance; Ipse-wide
`AGENTS.md` supplies defaults.

## Discovery and bounds

The workspace is the canonical launch directory, or explicit `--cwd`. Discovery
walks only to the nearest valid Git repository/worktree boundary. Outside a Git
repository, the workspace itself is the boundary: unrelated parent directories
are not imported. A Git directory needs a regular `HEAD`; a Git worktree pointer
must resolve to a valid Git directory. No Git command or new dependency is needed.

The snapshot loads `IPSE_HOME/AGENTS.md` (default `~/.ipse/AGENTS.md`), applicable
boundary-to-workspace `AGENTS.md` files, and the workspace's `README.md`.
One level of explicit local Markdown references from these files may load
`.md`, `.txt`, `.adoc`, or `.rst` resources within the project boundary. Resources
are context data, not additional permission or recursively discovered scripts.
Absolute/outside links, symlink sources, and sensitive path components such as
`.git`, `.ipse`, `.ssh`, `.aws`, `.codex`, `auth`, `secrets`, and `tokens` are excluded.

Each source is UTF-8 and at most 32 KiB, with at most 16 sources and 128 KiB
aggregate content. Missing optional sources are normal; invalid, inaccessible,
or oversized sources produce bounded diagnostics. Paths, scope, kind, and SHA-256
content digests accompany source text. These bounded path checks do not defend
against a hostile process concurrently replacing filesystem entries.

## Action scope

Before a file tool targets a deeper directory, the session discovers applicable
nested `AGENTS.md` files. A changed snapshot is journaled before the model sees
it. Pending calls from the earlier proposal are returned as not started, so the
model must reconsider its proposed actions with the new instructions. Loading
instructions never executes a pending mutation or bypasses approval.

An arbitrary shell string has no reliably inferable target set. The model sees
the active workspace context and explicit scope warning; the host cannot claim
that every directory mentioned indirectly by a command was resolved. Review
shell arguments and applicable deeper instructions before approval.

## Persistence and refresh

A `workspace_context_snapshot` journal event retains the bounded source text and its
manifest. Resume uses the last validated saved snapshot rather than silently
substituting changed instructions. Invalid saved snapshots stop recovery.
Drift diagnostics identify changed or unavailable saved sources without adopting
new text. Newly created, previously undiscovered files require an explicit refresh
to be discovered; drift is not a recursive filesystem watcher.

`/context` displays the manifest without inference or source contents.
`/context refresh` reloads instructions only while idle through an owned task,
then commits the new snapshot before replacing the active one. Cancellation
must not commit a partial refresh. These events do not replay effects, transfer
old approvals, or change provider settings. Journals contain workspace instruction
text and should be treated as private session data.

See [operator usage](../operator/usage.md),
[architecture](architecture.md), and [verification evidence](testing.md).
