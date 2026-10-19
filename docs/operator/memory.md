# Keep and recall explicit notes

Ipse's optional memory extensions store notes that you explicitly ask them to
remember. Recall uses local word overlap and returns source excerpts. There is
no automatic conversation capture, extraction model, embedding service, or
database installation. Ordinary conversations work without these extensions.

## Choose where a note belongs

| Artifact | Scope | Sharing |
| --- | --- | --- |
| `builtin:working-memory:1` | `session` | Same durable session and project, including explicit resume |
| `builtin:persistent-memory:1` | `project` | Sessions using the same canonical working directory |
| `builtin:persistent-memory:1` | `operator` | Deliberately shared across projects |

A session note does not disappear when the process exits. Both artifacts require
`retention_seconds` in 60..31536000. A remember operation may choose a shorter
positive `ttl_seconds`. Expiry excludes note text from recall and model inspection;
removal from the store needs explicit collection. Backups preserve stored records,
including expired text. Changing configuration bounds future writes and imports.
It does not change existing expiry times. Forget affected notes if a stricter
policy must apply immediately.

Choose operator scope only for notes intended to cross project boundaries.
Changing a project's working directory changes project-scoped storage. Use a
reviewed complete export/import to move notes. There is no implicit promotion
between scopes.

## Configure project notes

Save the following as a private operator file, for example
`/private/path/project-memory.json`. It grants the selected instance a logical
store while leaving activation disabled:

```json
{
  "version": 1,
  "extension_trust": [{
    "artifact": "builtin:persistent-memory:1",
    "capabilities": ["invoke.tool", "invoke.command", "host.actions", "host.state.read", "host.state.scan", "host.state.write", "host.state.bound"],
    "allow_project": false,
    "allow_children": false,
    "state_bindings": [{
      "version": 1,
      "instance": "project-notes",
      "id": "reviewed-project-notes",
      "scopes": ["project"]
    }]
  }],
  "extensions": [{
    "instance": "project-notes",
    "artifact": "builtin:persistent-memory:1",
    "enabled": false,
    "options": {"scope": "project", "retention_seconds": 2592000},
    "order": 10,
    "lifetime": "persistent"
  }]
}
```

Inspect locally, then activate the configured instance temporarily in a new chat:

```sh
ipse config --config /private/path/project-memory.json --no-project-config --extension project-notes
ipse chat --provider demo --config /private/path/project-memory.json \
  --no-project-config --extension project-notes --cwd /path/to/scratch
```

These examples need no real model service. `/ext` commands run directly and return
JSON separately from assistant answers. The demo provider is suitable for trying
the explicit commands below; use your deliberately chosen provider for later
model-assisted note use.

Persistent memory requires a binding. Reusing its logical `id` across reviewed
code/configuration versions grants the selected code access to existing notes.
A different ID opens a separate store without deleting the old one. Projects
cannot grant or override the binding. Operator sharing requires both
`options.scope: "operator"` and a binding scope ceiling containing `operator`.
An incompatible scope refuses activation with `extension_admission_refused`.
Review both fields in your private operator configuration before retrying.

For session notes instead, use artifact `builtin:working-memory:1`, options
`{"scope":"session","retention_seconds":86400}`, and remove `host.state.bound`
and `state_bindings` from the trust entry. Keep matching artifact/instance
references throughout. You may configure both artifacts independently, but their
combined 24 exports share the 32-entry/16 KiB catalog limit with other extensions.
Long instance names can exhaust catalog bytes before its entry count.

## Remember and inspect a note

In the configured chat, enter:

```text
/ext
/ext ext__project-notes__remember {"source":"operator:release-checklist","source_generation":1,"title":"Release checklist","text":"Run the signed macOS check before release.","kind":"task_card","provenance":"Operator request in this task","expected_revision":0}
/ext ext__project-notes__remember {"source":"operator:derived-checklist","source_generation":1,"title":"Release preparation","text":"Release preparation follows the signed macOS checklist.","kind":"task_card","provenance":"Derived from the operator release checklist","derived_from":["operator:release-checklist"],"expected_revision":0}
/ext ext__project-notes__recall {"query":"release macOS","limit":5}
/ext ext__project-notes__inventory {"limit":2}
```

Approve each displayed state write using its own `allow CODE`. Invoking the command
or approving an enclosing model tool does not authorize that write. Denial creates
no note. Imports, migration, and collection also require their own approval.

Expect recall to return matching excerpts with source, revision, source generation,
text hash, and exact byte span. Scores measure word overlap, not confidence or
truth. No shared words yields an empty result. Command recall does not automatically
publish context to the main model. When the model calls the recall tool, its result
enters that conversation under the ordinary tool-disclosure policy.

`source` is your exact logical ID, not a URL or file that Ipse fetches. Its SHA-256
is the storage key. Keep the ID stable across updates; an alias is a different
source. `kind` is `task_card` or `project_fact`. Provenance states where the note
came from, without certifying its truth. Limits are 2048 text bytes, 128 title
bytes, 512 source/provenance bytes, and eight optional `derived_from` source IDs.
The complete record must fit 8 KiB and its SDK request 16 KiB.

Inventory gives source/revision/version/expiry/dependency metadata without note
text. The model-only `inspect` tool returns full text, title and provenance only
for a live version-two note whose declared dependencies are also eligible.
Expired, unmigrated or dependency-blocked notes return metadata and revision with
`visibility: "metadata_only"`. A changed scan generation refuses instead of
mixing old and new records. These reads do not change storage. To update a note,
use its current `expected_revision` and a strictly greater `source_generation`.
Revision counts store changes; generation is your version of the source. Stale
or concurrent updates conflict instead of overwriting newer data.

Approve an update while the existing note is still live. Remember and active
import proposals include `write_before_ms` in the displayed state request, copied
from that note's expiry. If the note expires while approval is pending, approving
the proposal returns `source_expired` and leaves the old record unchanged. Ipse
does not retry the renewal. Inspect or collect the expired note instead.

## Forget or collect a note

For the newly created note at revision 1:

```text
/ext ext__project-notes__forget {"source":"operator:release-checklist","expected_revision":1}
/ext ext__project-notes__recall {"query":"release macOS","limit":5}
```

Approve the write, then expect the forgotten note to be excluded. Forget retains
a minimal suppression record. That exact logical source cannot be remembered or
imported again in the same store, even with its latest revision. There is no
revival command. Naming a different source is a distinct assertion.

Forgetting an ID that was never written creates permanent suppression and uses
one namespace record slot. Check the literal ID before approving; a typo cannot
be undone by remembering that same ID later.

For an expired note, use `collect` with its actual source and current revision.
For a declared derivative of a suppressed/expired note, include its cause:

```text
/ext ext__project-notes__collect {"source":"operator:derived-checklist","cause_source":"operator:release-checklist","expected_revision":1}
```

The earlier remember example creates this derivative at revision 1. If you have
changed it, inspect inventory and use its current revision. Collecting a source
that does not exist returns `not_found` when `expected_revision` is zero, without
writing or reserving that ID. A mismatched expected revision returns `conflict`
before collection. Recall and model inspection exclude note text whose declared
dependencies are missing, forgotten, expired, or awaiting
migration, including transitive dependents. Collect direct dependents,
then their dependents, to remove stored derivative text. Explicitly forget an
orphan whose parent is missing. Ipse cannot infer undeclared semantic relationships
or invalidate another store.

TTL uses wall-clock time and is not a scheduler or secure erasure guarantee.
Reads do not remove expired values. Each namespace holds at most 256 records,
including suppression, and 1 MiB encoded state. Full stores refuse writes;
suppression is never silently discarded to free space.

## Export, migrate, and upgrade

Start a complete generation-pinned export:

```text
/ext ext__project-notes__export {"limit":2}
```

For the next page, pass returned `next` as `after` and retain `generation`.
Continue until `next` is null. If the store changes, restart instead of mixing
generations. Optional `sources` selects up to 16 source IDs, but a selective or
partial export cannot establish complete deletion history.

Export preserves each stored value, including expired notes, blocked derivatives,
dependency links and suppression records. It does not collect text or invent
suppression. An orphan remains blocked until its parent is present and eligible;
restoring the backup does not make that block permanent. If expired text must be
absent from a backup, explicitly collect it before exporting.

Import each exported `{key,value}` with
`/ext ext__project-notes__import`, adding the target's current `expected_revision`.
Import suppression before active notes and preserve it. Older active backups
cannot override existing suppression. Import preserves the original expiry,
including an expiry already in the past. An expired restored note stays hidden
and cannot be renewed under that source. A newer-generation expired import may
also replace a live note and immediately hide it. Review the imported expiry
before approving. A valid version-one import may replace a live version-two note;
the imported note then stays hidden until you explicitly migrate it. Both
replacements still need the current target revision and a strictly greater
source generation. Stale source generations, excessive
retention, malformed records, and unsupported schemas refuse explicitly.
You may restore version-one active records unchanged, but they and their declared
dependents stay hidden until you explicitly migrate the restored records. For
example, if your backup contains `legacy:release-checklist` restored at revision 1:

```text
/ext ext__project-notes__migrate {"source":"legacy:release-checklist","expected_revision":1}
```

Use the source and revision from your actual import result and inventory. Approve
the migration write separately. Migration preserves expiry and provenance, so an
expired restored record remains hidden after migration. Minimal old
suppression upgrades without recreating forgotten plaintext.
Importing a newer active backup over an unmigrated target also requires migration
first. An incoming suppression record still takes priority.

For a code/configuration upgrade, finish/cancel active work, retain the old runner
for inspection/export, review the new schema, and start a fresh session with the
same approved logical binding. Old unbound namespaces are not automatically
reassigned. Exact session identity pins still apply to resume.

After an interrupted write, inspect revision and operation ID before retrying.
For local-only diagnosis, inspect the relevant private
`IPSE_HOME/extension-state-v1/NAMESPACE/state.json` read-only and compare its
`operation_id` with the saved host intent. Do not edit state or remove locks to
repair it. See [Recovery](recovery.md).

## Keep forgotten content out of later inference

Forgetting affects future retrieval and model inspection from this store. It does
not erase prior recall results, scanned-value receipts, cached publications,
journals, exports, backups, or earlier provider transfers. State-read receipts can
retain full pages of notes that were not in the final recall and consume journal quota. These
extensions have no private-history redaction grant.

After forgetting, close every session that received the affected note or copied
derivative text. Start fresh without importing that material. Review handoffs
manually and omit it. Ordinary resume restores old committed results exactly;
it does not recheck those results against today's note store. There is no live
cross-session revocation or retrospective remote erasure guarantee.
