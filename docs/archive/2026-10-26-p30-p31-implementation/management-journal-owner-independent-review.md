# Independent review of the management journal owner

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the design](management-journal-owner-design.md) and the exact
[implementation receipt](management-journal-owner.md), whose frozen manifest is
`eaed2cef565540363d09c58bb5162bbb030245ed14f95367f59a4a066ead38c4`.
It does not authorize Review, retained-target publication, terminal delivery or
any other currently closed gate. Later working-tree edits are excluded.

## Disposition

The frozen cohort has one concrete blocking defect in unfenced creation:
metadata key conversion can publish a protected-layout header after the marker
check has admitted its input. The actual Management caller uses string keys and
its lock-before-header ordering is sound by inspection; this finding concerns
the shared Journal guarantee that all ordinary creators refuse protected
layouts. It is not evidence of successful signed-target expiry, authority
escalation, a release receipt, or a native locking failure.

`Journal.create_with_id/4` checks `native_owner_required?/1` before encoding its
metadata. That predicate looks up only string keys. Jason subsequently converts
atom keys and other `String.Chars` keys to strings. With either
`%{native_journal_layout: "native-journal-v1"}` or
`%{~c"native_journal_layout" => "native-journal-v1"}`, the exact standard frozen
graph returns `{:ok, id}` through `write_new/4`, which writes and syncs through
the BEAM file server. The resulting header requires native ownership when read,
but no lock file was created or guard acquired. The corresponding atom and
charlist aliases for `release_receipt_layout` behave identically. The string-key
negative control refuses as intended.

The focused reproductions and output are retained separately:

- [Atom aliases](management-journal-owner-review/review-marker-alias.exs) and
  [their result](management-journal-owner-review/review-marker-alias.log).
- [Charlist aliases](management-journal-owner-review/review-marker-charlist.exs)
  and [their result](management-journal-owner-review/review-marker-charlist.log).

Both probes load the pinned standard graph, create only isolated temporary
journals, read their persisted headers, check the absent lock file, and remove
their temporary directory. They dispatch no native helper, model or network
operation. No passing runtime cohort was repeated.

The repair must examine the actual admitted JSON representation before any
ordinary creation or directory mutation. Merely adding the two static atom
forms leaves charlist and other Jason key conversions open. Normalizing and
rejecting duplicate encoded keys before applying the marker predicate is a
suitable narrow repair; alternatively explicitly constrain metadata key types
and reject unsupported aliases. Preserve the non-null marker rule, including
unknown versions and `false`, and preserve the existing release marker's
protection. This original counterexample and frozen cohort must remain intact.

## Source and evidence assessment

[The verification script](management-journal-owner-review/review-manifest.exs)
and [its result](management-journal-owner-review/review-manifest.log) verify all
25 manifest entries, all 34 archived source files against the source inventory,
three complete 670-file runtime inventories, and all three matching helper pins.
The standard helper is `a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995`;
the hook and old-helper graphs are distinct pinned cohorts. The older Session
share candidate remains the declared base, not a claim that every later working
source was tested. Native source is archived for provenance; this repair adds no
native protocol or dependency.

Management now chooses its ID, prepares the private child directory and acquires
`header_v1` before `create_with_locked_id/5`. The constructor no longer creates
or chmods the directory after lock acquisition. The existing helper creates the
pending header and retains the actual flock across header publication, journal
append and sync. SourceOrigin binds the pending inode before the native header
write; Writer's native mode routes its mutations back to that same guard.
A missing guard or lost native helper cannot fall back to a legacy append.

The generic marker is distinct from the Session release layout. Management's
closed intent/result reader remains intact, and inspection neither repairs nor
settles its journal. For a persisted string-key protected marker, inactive
append variants, direct inactive Writer, legacy Writer and unfenced tail repair
all refuse before their mutation. Read-only loading remains available. Existing
unmarked journals remain legacy journals.

Every successfully acquired Management guard reaches the release path after
header refusal, Writer startup refusal or operation completion. A successfully
started Writer is tracked, explicitly closed on the ordinary operation path,
and is also quiesced by guard cleanup. Header/Writer setup exceptions become
unknown; a failed Writer close or unconfirmed native release overrides a known
operation result. Owner loss retains the native owner until its in-flight
append completes; an interrupted event is observable without inventing a
settled operation result or replaying it.

The recorded final controls support these narrow conclusions:47084 passed
three component cases;47085 passed the one native sync-hook owner-death case;
47086 passed one actual standalone PTY test containing absent-target, public
directory and symlink cases;47087 passed the old-helper refusal. The PTY target
is deliberately missing. This establishes actual standalone setup and cleanup,
not authentic expiry or any protected full-facts display. Synthetic PTY bytes
do not establish human review. Earlier failed fixture/build/path attempts are
retained and distinguished from the final graphs; final compile receipts are
not a whole-source or package compatibility qualification.

No further concrete blocker was found in the scoped Management ownership and
cleanup path. Acceptance remains held for the metadata conversion defect.
Production Session cancellation barriers, the future Management four-owner
export, all-copy tty closure, authentic signed-target expiry, non-Linux behavior
and final adversarial audit remain open.

## Additive repair disposition

The [alias repair manifest](management-journal-owner-alias-repair/manifest.sha256),
SHA-256 `65284e7da1568b68bb3ef18f08b72fa6b0ca6020d1e274cf8a5225721884d412`,
closes the blocking defect above. The original archive, reproduction scripts and
results remain unchanged. This disposition accepts the repaired standalone
Management journal ownership section within the limits already stated; no
protected publication or terminal gate is opened.

[Repair verification](management-journal-owner-review/review-alias-repair-manifest.exs)
and [its output](management-journal-owner-review/review-alias-repair-manifest.log)
verify all seven additive manifest entries, both archived source files, all
670 repaired runtime files, and the unchanged helper. Comparing the complete
v2 and v3 inventories by graph-relative filename shows exactly one runtime
change: `lib/ipse/ebin/Elixir.Ipse.Journal.beam`. The original archive supplies all
unchanged source files. Writer, Runner, native code, hook and helper did not
change in this repair.

The frozen source now performs strict metadata encoding, decodes that encoded
representation, and checks the resulting marker keys before `ensure_state_dir`
or any header file creation. Its additional static atom checks are an early
refusal; the normalized representation check is the decisive defense against
charlist and other admitted JSON key conversions. Strict map encoding rejects
duplicate encoded names instead of allowing a duplicate to hide a marker. The
locked constructor also strictly encodes before beginning native header setup.
Unknown non-null marker values retain their existing refusal semantics.

[The narrow repair probe](management-journal-owner-review/review-marker-repair.exs)
and [its output](management-journal-owner-review/review-marker-repair.log) load
only the pinned v3 graph and repeat the original two atom and two charlist
counterexamples plus the original string negative control. Every call now
returns `{:error, :journal_lock_owner_required}` while the initially absent
parent directory remains absent. The probe dispatches no native helper, model
or network operation. Its first invocation had a script syntax error before
execution; [that diagnostic](management-journal-owner-review/review-marker-repair-initial.log)
is retained and does not represent a product failure.

The recorded47088 strict compile passed;47089 passed the two focused metadata
controls, including both markers' string/atom/charlist forms, unknown native
layout, duplicate normalized names, absence of directory effects and an ordinary
unmarked creation.47090 passed the actual standalone PTY startup/unsafe-directory
control again. These logs were inspected, not rerun. The hook and old-helper
controls remain supported by the unchanged earlier frozen cohort. No additional
scoped blocker remains. Full-target expiry and the integration limitations above
remain open.
