# Standalone management journals use the native owner

Focused implementation evidence, 2026-10-29. This implements the
[management journal design](management-journal-owner-design.md), reusing the
[native Session journal owner](../2026-10-29-native-shared-lease/native-journal-owner.md).
The [plan](../../plan.md) owns completion. Review publication, terminal output,
forgetting, retention choices and notes capture remain gated.

## Ownership and failure behavior

Standalone management now selects its journal ID and acquires the existing
native header lock before publishing the header. It starts and tracks Writer
in that same `header_v1` mode; header publication, append and sync execute in
the helper retaining the actual flock. The locked constructor no longer calls
BEAM directory creation/chmod after lock acquisition. Management creates only
its private child directory and refuses existing symlinks or public directories
without repairing them. Native code retains and rechecks directory, lock and
journal identities before mutation.

The separate `native_journal_layout: "native-journal-v1"` marker prevents
unfenced create, inactive append, legacy Writer and unfenced tail repair. Any
non-null generic marker refuses those legacy mutation paths, including an
unknown version. The existing Session release marker retains its previous
protection. Management records no Session release-claim layout or lifecycle
records; its reader still accepts the closed management intent/result stream.
Read-only discovery, load and operation inspection remain available. Existing
unmarked journals are unchanged and acquire no stronger guarantee.

An acquired guard is released after header or Writer startup failure as well as
the operation path. Header/Writer uncertainty, failed Writer close or failed
native release cannot return a settled result. Native setup refusal has no
legacy fallback. This does not make an interrupted knowledge effect safe to
retry; management journals and effects are never automatically replayed.

## Subsequent serialized-metadata repair

The [independent review](management-journal-owner-independent-review.md) found
one real bypass in the initial cohort: metadata maps also accept atom and
charlist keys, which Jason converts to strings. A string-only check before
encoding could therefore create a native-only header through the unfenced
constructor. Both the generic and Session release markers reproduced this
without a lock file. The original source, probes and failures remain retained.

The repaired constructor checks the actual normalized serialized metadata
before directory effects, in addition to recognizing the static atom spellings.
Jason's strict map encoding rejects duplicate converted names in both ordinary
and locked constructors. This handles all admitted key conversions without
creating atoms or restricting unrelated ordinary metadata to a new schema.
The [repair manifest](management-journal-owner-alias-repair/manifest.sha256),
SHA-256 `65284e7da1568b68bb3ef18f08b72fa6b0ca6020d1e274cf8a5225721884d412`,
pins the two-file delta and copied standard runtime. Only Journal is recompiled;
the helper and original unchanged sources retain their prior pins.

Strict compile47088 passed. Two focused metadata tests47089 pass for string,
atom and charlist spellings of both markers before directory creation, duplicate
encoded names and ordinary unmarked creation. The actual native caller47090
also passes its startup and unsafe-directory cases. No native loss/hook or
aggregate suite was repeated for this metadata repair. These handles are
terminal. The additive independent review accepts the repaired boundary after
verifying that only Journal's BEAM changed and rerunning the original atom and
charlist counterexamples against the repaired graph. They refuse before creating
the directory. The initial finding and exact original probes remain intact.

## Focused controls and provenance

The [initial implementation manifest](management-journal-owner/manifest.sha256), SHA-256
`eaed2cef565540363d09c58bb5162bbb030245ed14f95367f59a4a066ead38c4`,
pins 34 source files, chronological logs, three runtime inventories and three
helper hashes. The standard graph copies the frozen Session share candidate v4
and overlays nine management/expiry/journal modules. The additional expiry
modules supply existing APIs absent from that older base; they are not new
expiry implementation in this section. The hook graph differs by a matching
Runner compiled against a helper with the existing test-only native journal
hook. Its native sources and Runner are in the snapshot. The old graph uses
the retained pre-header helper and the same new host interfaces, with a newly
compiled matching Runner pin. No current native source was changed.

| Final run | Observed result |
| --- | --- |
| 47081–47083 | All three frozen graphs compiled with empty compile/runtime diagnostics. |
| 47084 | Three native component cases passed: protected-layout creation refusal; native header/reserved appends/close plus all inactive mutation refusals; real helper death followed by a real contender and refused append with unchanged bytes. The hook case was skipped. |
| 47085 | One hook-only case passed: killing the standalone BEAM owner while native append awaited sync kept the actual flock unavailable until the helper completed. The incomplete event is observable; no settled result is invented. |
| 47086 | One actual standalone native-PTY caller test passed with three cases: absent target leaves an inspectable native-owned header and releases the lock; public directory and symlink refuse unchanged. The missing target deliberately exercises startup/cleanup, not successful expiry. The old-helper case was skipped. |
| 47087 | One actual standalone caller test passed on the older pinned helper: startup refuses and no management header is published. |

The first compile47071 exposed a stale base graph, not a source success: current
Writer sharing and expiry callers referenced APIs absent there.47072 identified
two additional older dependency modules;47073 compiled the complete selected
overlay cleanly. The initial component47074 incorrectly reused the fixture
process's dead guard after releasing it; the fixture clears its process-local
guard before acting as an inactive caller, and47075 passed. The first native
PTY47076 correctly refused the sandbox's untrusted remapped `/tmp` owner.
47077 used the real trusted `/tmp` in the permitted execution context and passed.
Earlier source variants are represented by their retained logs, not claimed to
be recoverable from the final snapshot.47078–47080 built, pinned and checked
the hook graph before the final constructor cleanup and frozen runs above.

The final affected runs repeated only after removing the locked constructor's
unfenced directory setup and making header/Writer startup uncertainty explicit.
They are section controls, not repeated aggregate verification. All listed
process handles are terminal. No model, external service, download, package or
new native protocol was used. The supplied native PTY bytes are synthetic and
do not establish human review.

This does not qualify complete signed-target expiry, Management's future
four-owner export, production Session cancellation barriers, tty all-copy
closure, full source/package compatibility, non-Linux behavior or the final
adversarial audit. The read-only `knowledge operation` control does not resume,
repair or settle an operation. Independent acceptance covers this exact repaired
boundary, not coherent whole-source verification or milestone completion.
