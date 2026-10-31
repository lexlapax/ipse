# Native ownership for standalone management journals

Implementation design, 2026-10-29. The [plan](../../plan.md) owns acceptance.
This repairs the journal owner independently of still-gated Review publication
and terminal output. It reuses the [native journal primitives](../2026-10-29-native-shared-lease/native-journal-owner.md);
it does not enable forgetting, retention choices or capture.

`Management.owned_forget/4`, also used by expiry, currently creates and syncs a
header through the BEAM file server before acquiring a legacy native lock. Its
Writer also uses legacy appends. That ordering cannot guarantee that the actual
flock owner retains the lock through a queued header/append syscall after its
BEAM owner dies. The Session repair does not cover this separate caller.

The standalone owner will choose its random journal ID first, create only its
private management directory, acquire the existing `header_v1` lock mode, then
use `Journal.create_with_locked_id/5`. Its tracked Writer will use that same
native mode. Every acquired lock is released through the confirmed native close
path, including header or Writer startup refusal. Writer close and lock release
must both be confirmed before a known operation result is returned. Loss after
an attempted publication remains unknown; no journal or operation is replayed.

A separate `native_journal_layout` metadata marker identifies native-only
journal mutation. It must not claim the Session signed-release protocol or add
Session lifecycle records to management's closed intent/result stream. A common
Journal predicate will recognize either a non-null generic marker or the
existing non-null release marker. Ordinary create, inactive append, legacy
Writer and unfenced tail-repair entry points will refuse either protected
layout. Read-only load, header discovery and management operation inspection
remain available. Existing unmarked journals are not rewritten or upgraded.
The generic marker is a format selector, not an authority grant: actual native
mutation still requires the retained guard and its tracked Writer.

The directory setup must refuse an existing symlink or public directory rather
than chmod it into apparent safety. The native helper retains and rechecks the
private directory, lock and journal identities. New directory creation is the
only preliminary file effect; old helpers lacking native header mode must
refuse before any management journal is published, without a legacy fallback.

Focused controls will cover a real native management-layout header, tracked
append/reservation/close, all inactive mutation refusals, helper loss before
append with an independent contender, owner death during native append with
the existing test-only syscall hook, and old-helper refusal before header
publication. A standalone management invocation must additionally demonstrate
the selected mode and cleanup, without claiming successful note expiry unless
an authentic stored target and its complete publication path are exercised.
No extra native protocol, package, dependency, model call or quota increase is
required. Whole-source checks and final audit remain separate.
