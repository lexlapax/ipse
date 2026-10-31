# Original-source admission for managed reads

Dated **2026-10-28**, branch `codex/p30-p31`, following `704bd1d` and the
uncommitted [journal-origin](sol-source-origin.md) and
[native statement](native-assertion.md) sections. This is scoped engineering
evidence; [the plan](../../plan.md) owns milestone status and
[the collection manual](../../developer/collection-sdk.md) owns current behavior.

`CollectionCall` now retains the reviewed read recipes and routes `get`/`scan`
through `ManagedRead`. A provisional view discovers literal records; outside
Identity/Consent, `Session.StoredSources` acquires their original Session locks.
Current-Session proofs use a new owner-only, active-action Writer query. Inactive
Sessions require existing private retained locks, the original descriptor and
directory, a complete Saved prefix and the same protected project/namespace.
The final protected read must match the provisional root/result and authenticate
signed format/live/anchor metadata before current recipe extraction, deadline
and source-selection checks. Sources are rechecked before callback completion.
No tail repair, source relocation, policy refresh or clock renewal is performed.

The source changes are `extension/collection_call.ex`, new
`extension/managed_read.ex`, `extension/semantic_consent.ex`, new
`session/stored_sources.ex`, Session's stored-source callback and collection
execution context. Tests extend the existing native assertion fixture and source
selection controls; no new dependency or production native profile is introduced.

The isolated graph remains `_build/operator-assertion-sol`, with the private
test-only Linux 7.2.11 diagnostic helper override described in the preceding
records. Production profile admission remains unchanged. Changed modules compile
with warnings as errors, and matching inert bundles were rebuilt. A first compile
was refused by the sandbox's Mix loopback lock; the supported escalation allowed
the existing test graph to compile. An incidental default-environment build was
interrupted and supplies no validation evidence.

Focused checks:

- **46706:** one native CLI save fixture passed, four excluded, 6.0 seconds.
  Its nested controls cover live local source reuse, inactive original source
  resolution, retained ownership, busy locks, altered proofs, different project,
  copied sessions, torn tails and source mutation during use.
- **46707:** the same focused fixture passed, four excluded, 6.5 seconds,
  adding actual protected read refusal for an unsigned edit of a signed note.
- **46708:** the fixture passed, four excluded, 7.9 seconds, adding a real signed
  note read using inactive original-source ownership, refusal for a collection
  change between discovery/admission, and a new successful read at the new root.
- **46709:** [collection call contracts, collection Session integration, source
  policy and native assertion scenarios](current-source-read/section-46709.log)
  passed **42 tests**, 22.6 seconds,
  max-cases 1, exit 0. Log SHA-256:
  `8ec01e380354f4bf099ffd32d8975a3f36d2c4db3cb0fbf417f646a10736040c`.
- **46710:** [the save-only fixture](current-source-read/cleanup-46710.log) passed,
  four excluded, 8.2 seconds, exit 0, after adding callback-failure cleanup and
  a subsequent successful acquisition. Log SHA-256:
  `f5c02eda52304b6b4c12e20e1d59f4c48cef6332589ce99413805be8db1efdf0`.

This implements read admission, not per-dispatch withdrawal or end-to-end current
recall. The normalized dependency is checked but not yet attached to Session
producers. Worker/assistant/summary lineage, replay and final egress/delivery
barriers remain open, as do proposal management, retention/suppression workflows,
capacity, installed qualification and final adversarial acceptance. No aggregate
suite was rerun for this section and no release was published.

At the section boundary, `elixir dev/check-docs.exs` checked 670 Markdown files
and 5,383 local links with zero errors and the pre-existing inaccessible receipt
warnings. The retained-log links above were added afterward and their local
targets exist. Whole-manual final acceptance remains open.
