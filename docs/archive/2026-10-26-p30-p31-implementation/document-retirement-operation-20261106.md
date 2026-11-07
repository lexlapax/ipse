# Document retirement operation binding — 2026-11-06

Historical implementation and synthetic verification evidence. The
[plan](../../plan.md) owns current acceptance and the
[Collection SDK chapter](../../developer/collection-sdk.md#stage-ordinary-documents-under-their-own-grant)
describes the current protocol. This increment does not authorize interrupted
retirement recovery.

New native document progress heads reserve room for a retirement operation and
start with its marker set to null. A partial retirement publishes its operation
and current invocation IDs with the resulting head in the same native update.
Validation requires a local operation ledger entry at that head revision; an
imported entry at the same generation is insufficient. Legacy heads retain their
old encoding and reservation during cleanup. Earlier binaries cannot read newly
marked heads, even before retirement; installed upgrade and downgrade journeys
remain unqualified.

Focused schema and capacity controls passed 13 tests. Three native draft tests
passed on fresh synthetic stores. An earlier native attempt used an incorrect
assertion about where to inspect the operation ledger; the corrected control
uses the native inspection API. The separately run mixed-format native capacity
control passed one test: its trusted-seeded fixture had 3,815 public records,
eight heads, 16 active or prepared stages and 104 synthetic stage records. An
adjacent write refused with `collection_capacity` and left the root unchanged;
sequential partial cleanup of one legacy and one marked head succeeded. The
legacy head retained its old encoding, and the marked head's IDs matched the
native operation. The legacy cleanup ran first and freed space, so this run does
not establish marked-head cleanup at the original limit. The test ran on the
available host's private tmpfs; cleanup
checks found its test processes, input lock and test port idle. Its retained log
is `_build/verification/native-retirement-mixed-capacity-20261106-01/output.log`
(SHA-256 `221350d1c034fc5ef1b3e4e088883e93b974ffee8a2dc1eb1fddb5d19844dde3`).
After independent review identified that ordering limitation, a fresh run with
the marked head first also passed. In that run the adjacent write refused with
the root unchanged, and marked-head partial retirement succeeded before legacy
cleanup freed space. Its retained log is
`_build/verification/native-retirement-mixed-capacity-20261106-02/output.log`
(SHA-256 `b7169c52347dd309c7161fa725408e24642c07860ba6ab7b256c331d1fc719ef`).
Both runs seed metadata directly and share a backing object among public records;
they test this metadata reservation boundary, not normal population or a disk
quota maximum.

The join records potential evidence, not the complete authorization. It does not
compare the prior Session journal's exact action and request digest or establish
that the original owner and its dependent processes have stopped. The existing
release inspection drops its Session lock and returns only a classification; a
safe later design must retain the necessary owner-bound evidence and join it to
the native operation under the relevant locks. Missing or unconfirmed cleanup
continues to refuse. The capacity test uses trusted seeded metadata at one limit;
it does not establish full physical allocation limits, real migration, crash
recovery, installed compatibility or the populated document workload.
