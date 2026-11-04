# Source port close and confirmed native exit — 2026-11-04

This component observes shutdown ordering only. It is not a Session, publication,
source-transfer, permission or guard qualification. It used the unchanged private
Runner and helper `ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b`,
fresh task-owned 0700 directories and empty 0600 source lock files. No application,
native operator input, TTY, consent, provider or model was started. The existing
`Ipse.Test.NativePipeScope.await_native_exit/1` supplied the confirmed exit test;
no new Rust helper or process-state parser was introduced.

For every acquired helper the code captured its OS PID, required its `/proc/PID/exe`
link to name the exact private helper, and matched the executable's device/inode
to that helper before closing the Erlang port. It recorded the immediate
post-return executable observation before waiting for confirmed native exit.

Of 55 retained observations, **50 still exposed the same helper executable after
`Port.close/1` returned true**. Five had a missing executable at that immediate
point; missing executable alone was not classified as confirmed death. There
were zero unknown observations. The existing exit wait subsequently confirmed
all 55 exits. Input and complete private runtime hashes were unchanged afterward.
All immediate and confirmed per-sample records are durable and owner-only.

The original fixed batch had 64 indices. Attempt 01 stopped before acquisition
because its constructor used a generic `.lock` name instead of the required
32-lowercase-hex source name. Attempt 02 completed indices 1–9, then refused
index 10 because Elixir's base-16 conversion produced uppercase `A`. Its
final-only aggregation meant those nine immediate observation values were not
retained. They are explicitly unavailable, not passes, and were not repeated.
Both failures and all fixture roots remain preserved. Attempt 03 validates every
lowercase name before acquisition, executes only still-unobserved indices 10–64,
and syncs each immediate record before awaiting exit and writing confirmation.

This establishes that a successful Erlang port close need not be a confirmed
native helper exit. It does not reconstruct the original regression case's
commit/loss timeline or demonstrate any publication failure or safety. A fresh
causal publication control still needs the confirmed native exit boundary and
all original source, snapshot, liability, replay and lifecycle assertions.

Inputs SHA-256:
`bc51c82c631fa14f9ce819e7479d39462ff4cbb98a8b28c54f8084cfac0d9f57`.
Status SHA-256:
`29bb12480893047b6977cca07015607c11ebccafd1340e32dbdbd916f18e7d0a`.
Aggregate observations SHA-256:
`2f7b614368f29125abdd24ff8a74a9700570d878f7e0ee40755399e85ab96950`.
The 110 per-sample-file inventory SHA-256:
`107cc426b8e5008b8c103f520ad15353668c0e1e44847a15fe8d4dd35e6535a2`.
