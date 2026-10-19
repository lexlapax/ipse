> Historical reference only. Snapshot of `docs/developer/workspace-context.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../developer/workspace-context.md).

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

Before a file tool targets a deeper directory, the session checks the target path
and discovers applicable nested `AGENTS.md` files. Preflight happens before tool
start or an approval decision. If path/context preflight refuses, the affected
call's tool result retains the specific refusal and asks the model to check that
call's target path and workspace guidance before retrying. Later queued calls
receive only a generic stopped-before-start result: the first target's failure is
not attributed to their paths. All of these calls remain `not_started` with
approval `not_decided`; a failed preflight is not evidence that a read ran.

When discovery changes the snapshot, Session journals it before settling the old
proposal and requesting reconsideration. The affected call's result tells the
model that new scoped context was loaded and must be reviewed before retrying;
the next model request contains both the saved context and that reason. Later
queued calls remain generically not started. A revised mutation proposal still
passes through normal approval; loading guidance neither executes old calls nor
transfers permission to new ones. A useful diagnostic enables replanning but does
not guarantee that a model will recover or complete the task.

These are preflight-specific results, not a change to interruption settlement.
An actually started effect interrupted before a recorded result remains unknown;
subsequent unstarted calls remain not started. Saved tool messages retain their
reasons during restoration, and idle resume does not replay either old proposal
or effect.

An arbitrary shell string has no reliably inferable target set. The model sees
the active workspace context and explicit scope warning; the host cannot claim
that every directory mentioned indirectly by a command was resolved. Review
shell arguments and applicable deeper instructions before approval.

## Persistence and refresh

A `workspace_context_snapshot` journal event retains the bounded source text and its
manifest. Resume uses the last validated saved snapshot rather than silently
substituting changed instructions. Invalid saved snapshots stop recovery.
Drift diagnostics identify changed or unavailable saved sources without adopting
new text. Explicit refresh adopts changed saved text and rediscovers launch-scope
sources; drift is not a recursive filesystem watcher. Action preflight can add
previously unseen nested guidance as described above.

The selected skill catalog is independently checkpointed with names, descriptions,
canonical paths, content digests and shadowed-source provenance, capped at 256
entries and 256 KiB encoded metadata. Resume retains this selection and diagnoses
fresh discovery drift. Skill loading and resource loading recheck the selected
source path/digest; changed or missing bodies refuse until explicit refresh.
Catalog snapshots contain metadata, not skill bodies. Older journals acquire
their first catalog checkpoint at the next model boundary, not on idle inspection.

`/context` displays instruction and skill manifests without inference or source
contents; `/skills` shows the saved catalog. The standalone `ipse skills` command
performs fresh discovery. `/context refresh` reloads both while idle through an owned task,
then commits the new snapshots before replacing the active selections. Cancellation
must not commit a partial refresh. These events do not replay effects, transfer
old approvals, or change provider settings. Journals contain workspace instruction
text and should be treated as private session data.

Workspace text, selected skill metadata and extension contributions enter a
labelled user-role reference message. Core rules remain in system text. Explicit
skill bodies remain in the operator turn that requested them. Reference context
is not a new task, instruction-authority upgrade or permission grant.

See [operator usage](../operator/usage.md),
[architecture](architecture.md), and [verification evidence](testing.md).
