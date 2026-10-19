> Historical reference only. Snapshot of `docs/operator/memory.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../operator/memory.md).

# Explicit working and persistent memory

P26 provides two independent, default-off bundled extensions: session/task notes
and persistent project/operator notes. They store only what you explicitly ask
them to remember. Recall is local lexical retrieval with source excerpts; there
is no automatic transcript capture, model extraction, embedding, database
installation or external memory service. Ordinary conversation and recovery work
without either extension. Source, installed and hosted Linux/macOS gates pass,
including the diagnosed diagnostic-worker cleanup repair. See the
[recorded scope and limits](../developer/testing.md#current-evidence-and-next-checks).

## Choose scope and retention

| Artifact | Scope | Lifetime of stored data |
| --- | --- | --- |
| `builtin:working-memory:1` | `session` only | Isolated by durable session ID and project; an explicit resume can read it, another session cannot |
| `builtin:persistent-memory:1` | Explicit `project` or `operator` | Project notes span sessions of the same canonical working directory; operator notes deliberately span projects |

A session-scoped note is not automatically deleted when a process exits. Both
extensions use configured retention and explicit collection. `retention_seconds`
is required (60–31,536,000); a remember call can choose a shorter positive TTL.
There is no implicit promotion from session notes to project/operator memory.
Choose operator scope only for information you intend to share across projects.
Retention bounds new writes/imports; changing configuration does not rewrite
existing stored expiry times. Explicitly forget affected existing notes when a
stricter policy must apply immediately, then follow the session-recovery procedure.

## Configure explicit memory

Merge the following into your operator version-1 configuration. Both instances
start disabled. Keep credentials and secrets out of note content and options.

```json
{
  "version": 1,
  "extension_trust": [
    {
      "artifact": "builtin:working-memory:1",
      "capabilities": ["invoke.tool", "invoke.command", "host.actions", "host.state.read", "host.state.scan", "host.state.write"],
      "allow_project": false,
      "allow_children": false
    },
    {
      "artifact": "builtin:persistent-memory:1",
      "capabilities": ["invoke.tool", "invoke.command", "host.actions", "host.state.read", "host.state.scan", "host.state.write", "host.state.bound"],
      "allow_project": false,
      "allow_children": false,
      "state_bindings": [
        {"version": 1, "instance": "project-notes", "id": "reviewed-project-notes", "scopes": ["project"]}
      ]
    }
  ],
  "extensions": [
    {
      "instance": "working-notes",
      "artifact": "builtin:working-memory:1",
      "enabled": false,
      "options": {"scope": "session", "retention_seconds": 86400},
      "order": 10,
      "lifetime": "persistent"
    },
    {
      "instance": "project-notes",
      "artifact": "builtin:persistent-memory:1",
      "enabled": false,
      "options": {"scope": "project", "retention_seconds": 2592000},
      "order": 20,
      "lifetime": "persistent"
    }
  ]
}
```

Inspect configuration locally, then select either or both instances for a new
chat using `--extension working-notes --extension project-notes`. Persistent
activation is a reviewed edit to `enabled`; `--no-extensions` disables selection
for a new invocation. These flags do not change existing pinned sessions.
Both packages together expose 24 catalog entries. The shared 32-entry/16 KiB
catalog bounds still apply; long instance names or additional exported schemas
can exhaust the byte limit before the entry count. Admission refuses explicitly
rather than dropping tools. Read-only sinks without exports do not consume entries.

Persistent memory requires the logical binding. It is an operator grant to
existing data, not a path chosen by extension code. Reusing its ID across reviewed
artifact/configuration versions shares that data; choosing a different ID opens
a separate empty store and leaves the previous data intact. Operator bindings
cannot be supplied or overridden by project configuration. Changing scope does
not move notes: operator sharing needs both `options.scope: "operator"` and an
explicit binding scope ceiling that includes `operator`.
Moving the project working directory also changes project-scoped storage; use
reviewed complete export/import rather than treating a new path as the old project.

## Remember, inspect and recall

`/ext` shows active exports. The examples below use `project-notes`; substitute
your instance name. Explicit commands need no model inference. The same remember,
recall and forget operations are also model tools, with ordinary tool approval.

```text
/ext ext__project-notes__remember {"source":"operator:release-checklist","source_generation":1,"title":"Release checklist","text":"Run the signed macOS check before release.","kind":"task_card","provenance":"Operator request in this task","expected_revision":0}
/ext ext__project-notes__recall {"query":"release macOS","limit":5}
/ext ext__project-notes__inventory {"limit":2}
```

Use `kind: "task_card"` or `"project_fact"`. `source` is an exact logical ID,
not an automatically fetched URL/path. Its SHA-256 is the storage key. Keep that
ID stable across edits and reingestion; spelling or alias changes create a
different source. Provenance describes where the assertion came from and does
not prove its truth. Notes have at most 2,048 text bytes, 128 title bytes, 512
source/provenance bytes and eight optional `derived_from` source IDs.
The complete encoded note must also fit the 8 KiB state-value bound and its
request the 16 KiB SDK bound; individually legal field maxima are not additive.

Every write still needs full host approval unless you explicitly enabled
session-wide execution. Approving the enclosing tool does not approve its later
state write. Headless denial writes no note; import/migrate/collect also need
approval. Read and write capabilities are separate from selecting an instance.

Recall scans one generation-consistent bounded namespace, ranks word overlap
and returns up to five excerpts with source, revision, source generation, text
hash and exact byte span. Scores express lexical overlap, not truth or confidence.
No matching words means an empty result, not an invented answer. Partial word
matches can still be irrelevant; inspect evidence before relying on it. Recall
results from a model tool enter its private conversation; standalone command
results are displayed separately. No automatic context publication is performed.

Inventory includes active logical source IDs, revisions, version/expiry and
derivative metadata without note text/provenance. The model-only `inspect` tool returns a source's complete current
record. Update using the current `expected_revision` and a strictly greater
`source_generation`; concurrent/stale writes conflict. These two numbers are
different: revision tracks store writes, generation tracks your source version.

## Forget, expiration and derivatives

```text
/ext ext__project-notes__forget {"source":"operator:release-checklist","expected_revision":1}
/ext ext__project-notes__collect {"source":"operator:expired-note","expected_revision":1}
/ext ext__project-notes__collect {"source":"operator:derived-checklist","cause_source":"operator:release-checklist","expected_revision":1}
```

Forget replaces current content with a minimal durable suppression record
(source digest/generation, schema version and timestamp). That exact source ID
cannot be remembered or imported again in the same logical store, including by
a worker that rereads the current revision. A delayed write with an older
revision conflicts. This policy deliberately has no automatic revival command;
a new name is a distinct explicit assertion, not a restoration guarantee.

Expired notes are excluded from recall. Reads do not secretly rewrite storage.
Explicit collection removes expired content and retains suppression. If a note
names a missing/forgotten/expired source in `derived_from`, recall excludes it and all
transitive dependents. Dependencies resolve only within this namespace; cross-store
invalidation is not provided. Collect direct dependents using a suppressed/expired
`cause_source`, then their
dependents in turn, to remove the stored derivative text. Unrecorded semantic
relationships cannot be inferred. Inventory exposes declared dependencies for
this procedure; explicitly forget an orphan whose declared parent is missing.
Raw notes persist until approved collection/forget.

TTL uses the system wall clock. It is a recall policy, not a scheduler, secure
erasure promise or proof against clock rollback. Apply collection for durable
suppression once expiration is established. Each namespace holds at most 256
records, including suppression, and 1 MiB encoded state. Suppression is not
silently discarded to reclaim slots. A full store refuses writes; plan an
explicit reviewed archival/migration policy instead of deleting locks/tombstones.

## Export, migration and recovery

`/ext ext__project-notes__export {"limit":2}` returns a bounded page including
suppression records. Add `"sources":["operator:release-checklist"]` to export
only selected logical sources (up to 16). Continue using its `next` as `after` and its `generation`;
stop at null. Concurrent changes cause a conflict: restart the export, never mix
pages from different generations. Export replaces expired/blocked derivatives
with portable suppression values without secretly changing the backend.

Import one exported `{key,value}` at a time using `/ext ext__project-notes__import`
and add the target's `expected_revision`. Preserve current suppression records
and import them before active records when building a new store. Existing
suppression always wins over older active exports; stale source versions and
retention beyond configured limits refuse. A complete current export is required
for migration: an old or partial backup cannot prove that a forgotten source was
never present. Do not declare restoration safe by restoring only its active rows.

Version-one active records require explicit `/ext ext__project-notes__migrate` with
`source` and `expected_revision` before recall. Migration adds the version-two
shape while preserving expiry and provenance. Importing a version-one minimal
suppression explicitly upgrades it to version two, preserving digest/generation
without needing its forgotten plaintext source ID or recreating content. Unknown or malformed
records refuse access rather than being silently repaired. Logical storage
binding does not approve arbitrary new code/schema semantics.

Exact code/configuration/host identity still governs session resume. For an
upgrade, retain the old runner for inspection, finish/cancel active work, review
new code and the storage/schema contract, then start a fresh session with the
same explicitly approved binding. Old unbound namespaces are not reassigned:
use their matching adapter/runner for explicit export and review an import.
After an interrupted write, inspect revision and operation ID before deciding
whether to retry. Inventory identifies keys/revisions; for an entirely local
check, open the relevant private `IPSE_HOME/extension-state-v1/NAMESPACE/state.json`
read-only and compare that record's `operation_id` with the saved host intent.
The model `inspect` tool also returns the full record, subject to ordinary model
and tool-disclosure policy. Do not edit state or remove locks as a repair shortcut.
Nothing is replayed automatically. Use the shared
[session recovery guide](recovery.md) for saved diagnostics and handoff.

## What deletion does not erase

Suppression governs **future retrieval in this logical store**. It does not erase
previous tool results, cached publications from other extensions, journals,
backups, exports or earlier provider transfers. The memory extensions have no
private history-read or history-redaction grant. Core retains mandatory recovery
and accounting records; deleting extension files is not secure erasure.
State-read receipts retain the full scanned value pages, including notes that
were not selected in the final recall/export result. They stay in the private
session journal and consume its finite quota. They are not automatically added
to model context, but TTL, forget and collection do not redact these copies.
Keep journal storage private and outside version control; repeated large scans
can reach the journal limit even when returned recall is small.

After forgetting, close every session that previously received affected recall
or copied derivative text. Start fresh without importing the forgotten material;
review any handoff manually and omit it. Resume restores old committed results
exactly and does not recheck them against the memory store. This explicit
affected-session handoff policy is required when the goal is to keep forgotten
content out of future inference. There is no live cross-session revocation,
automatic history redaction or retrospective remote erasure guarantee.
