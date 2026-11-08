# Partial retirement live-owner fence, 2026-11-07

This is a historical synthetic investigation and source-candidate record. The
[plan](../../plan.md#p31-usable-knowledge-and-prompt-assistance) owns current
acceptance. It does not authorize interrupted retirement recovery.

## Counterexample

The earlier operation/invocation join did not distinguish a resumed Session
process from its predecessor. In a synthetic Session/controller journey, one
approved cleanup succeeded, a second was denied, and the original owner died
with an unknown release claim. A freshly approved abort after same-ID resume
then succeeded where the defensive test expected refusal. A separate fresh
public Corpus journey reached the same result: its newly approved abort settled
`ok` after the original owner died. The original operation was not replayed;
the problem was adoption of a partial retirement without proof of that owner.

The first public fixture used a 27,000-byte source outside its input limit and
stopped before its target action. A corrected 8,100-byte source in a fresh
fixture produced the public counterexample. The Session/controller wrapper
also hit a shell read-only variable after the test had reported its complete
failure; the wrapper exit is not the test result. These failed attempts remain
distinct from the later candidate checks.

## Scoped source candidate

The Session process keeps a bounded, non-restored registry of its own known
partial cleanups. It records a matching `ok` action result only after the
result is validated and journaled. The trusted live host obtains that Session's
registry entry for the current action; at locked draft authorization it must
match the head's exact operation, invocation, revision and retirement epoch.
The registry is empty on a fresh or resumed Session, so it does not adopt a
prior owner's partially retired head. The worker's head ID is only a lookup
key; the actual native head is checked separately. Capacity is checked before
the mutation, and a completed retirement removes its entry.

No persisted head format is changed. An already-partial legacy head without
the operation join refuses continuation. An unretired legacy head with multiple
stages refuses the first cleanup, because that cleanup could leave a partial
head without a join; a single-stage legacy cleanup can finish atomically. This
is a conservative availability limit, not a recovery path. Unknown prior effects
are not repeated or inferred to have succeeded.

## Observations and limits

An isolated source candidate based on `4f4c1255` passed a fresh forced build with
warnings as errors. The separately run schema file passed 11 tests. A native
capacity file passed three synthetic, trusted-seeded controls: a legacy multi-stage
first cleanup refused with the root unchanged, and single active-only and
prepared-only stages each completed atomically. The retirement Session group
passed 11 tests, with 75 excluded; it includes same-live-owner retry, a full
registry refusal, and fresh same-ID resumed-owner refusals through the controller
and public Corpus. After the native groups, the checked fixture-root processes,
operator input lock and known test port were clear.

The isolated evidence directory is
`_build/verification/retirement-owner-fence-4f4c1255-20261107-01/evidence`.
Its `legacy-rebuild-02.log`, `legacy-schema.log`, `legacy-single-native.log`
and `retirement-legacy-tag.log` record the respective observations. The first
candidate build overlapped an edit and is invalid as a build proof. Another
rebuild failed warnings-as-errors because same-name function clauses were
separated; the corrected rebuild passed. A later candidate public fixture also
initially used the oversized source and stopped before an extension invocation
or action intent; its fresh corrected retry passed. These do not change the
earlier counterexample.

A separate checkout of `4f4c1255` combining this candidate with the Research
worker timing change passed a clean PDF-free build and the same focused schema,
native-capacity and retirement Session groups: 11, 3 and 11 tests passed,
respectively, with 75 excluded from the selected Session group. The Research
focused regression and credential-free demo also passed. Fixture-root processes,
the operator input lock and the known test port were clear after these checks.
This combined candidate is not a full-source baseline.

The registry does not itself hold a native Session-owner lease at the final root
switch. Owner or helper loss during an admitted effect, post-publication unknown
outcomes, injected journal-append failure, installed compatibility and the full
combined source baseline remain separately unqualified. The tested live-owner
refusals do not establish safe recovery by a later owner, full document lifecycle
or populated capacity.
