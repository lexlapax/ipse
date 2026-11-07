# Synthetic document replacement model: focused check, 2026-11-06

Historical implementation evidence; current milestone scope and status are in
[the plan](../../plan.md). The worktree under test contained the pending
replacement-model changes. This is a model check, not an operator procedure.

The focused command selected the replacement and stop-condition cases:

```sh
mix test test/dev/knowledge/collection_recipe_public_test.exs --only public_recipe_replacement --only public_recipe_replacement_stop --max-cases 1
```

The first run failed both selected cases: the checkpoint identity comparison
mixed `File.lstat` UTC timestamps with local timestamps from the Erlang file
descriptor. An isolated synthetic file probe confirmed that mismatch and that
explicit POSIX timestamps agree. The correction requests `time: :posix` for the
named and descriptor snapshots before and after the bounded read. The successful
replacement case sets `TZ=UTC-8` only in its verification child and checks that
the two default timestamp representations differ. The parent observed the
focused rerun complete with **2 passed and 10 excluded**. This record does not
represent an additional run.

The synthetic model pins the exact checkpoint bytes with a caller-supplied
SHA-256 digest; that identifies bytes but does not authenticate their origin.
It bounds and checks the regular single-link checkpoint read, validates its
modeled operation history, and refuses malformed input. The selected controls
cover an incorrect pin, missing history, oversized declared term, trailing bytes,
symlinks and unsafe continuation outcomes. Unknown, refused, malformed,
foreign or repeated continuations stop the modeled sequence rather than being
treated as permission to continue. These controls establish only the behavior
exercised by the synthetic tests.

The check did not execute native Collection operations or a Session journal,
establish citation correctness or capacity fit, or complete the full recipe.
The decline of the retained notebook recall remains in effect.
