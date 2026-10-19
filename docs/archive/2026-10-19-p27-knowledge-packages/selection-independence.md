# Memory and knowledge selection independence, 2026-10-19

Historical verification record after `8297096`. The containing commit owns the
proof and CI additions. Follow the current
[selection exercise](../../developer/knowledge-extensions.md#verify-independent-memory-and-knowledge-selections)
for commands and expected behavior. This record does not reopen P26 or complete
P27's held-out quality and engine-selection gates.

## Exercise actual selections and storage

The proof builds separate Corpus `state-lexical`, Graph `state-explicit` and
Research `offline` artifacts against the public SDK. Each pairs with working
session memory, persistent project memory and persistent operator memory: nine
combinations. Every combination uses a private operator home, separate knowledge
and memory bindings, real public Sessions and a provider that rejects inference.
Graph facts are explicitly authored fixture assertions. Research receives its
source text directly and has no retained knowledge store.

For disabled selections and enabled idle Sessions, the proof requires zero
extension-worker starts, State operations, MCP operations, embedding operations
and text-model operations. It also checks empty disabled catalogs, the exact two
enabled instances, no action intents and zero canonical model requests. There
are no State files before the first explicit data operation.

Actual operations then retain knowledge, remember a different note using the
same source ID, and query both. Knowledge never becomes a memory note; the note
never becomes retrieved corpus evidence or a graph fact. Positive worker and
State counts confirm that the counters observe real execution. Before forget,
the exact closed Session resumes idle with unchanged journal and State bytes and
zero new counted operations. Forgetting the note preserves knowledge. Forgetting
Corpus or Graph knowledge preserves another explicit note. Research is checked
again with fresh provided evidence. Cleanup must be confirmed.

The instrumentation uses isolated OTP trace-session call counters. Every target
must be installed successfully; no arguments, return values or transcript
payloads are traced. These counters observe host entrypoints, not OS confinement.
Existing private journals retain earlier recalled text, and the proof performs
no conversational inference after forget. It does not claim history erasure.

The tenth check selects all three knowledge artifacts plus working memory. Their
combined catalog exceeds the existing 16 KiB bound. Both catalog admission and
Session creation refuse before workers, State or model operations. The proof
does not widen the catalog or SDK limits to make that selection fit.

## Direct local evidence

The first focused run failed because the fixture compared sorted actual instance
names with an unsorted expected pair: one test failed in 4.2 seconds, seed 747064.
Sorting both sides corrected the expectation without changing product behavior.
The initial six-pair version passed; the final nine-pair version passed one test
in 27.8 seconds, seed 978142.

Whole-proof review then found that the State snapshot glob matched namespace
directories rather than their nested `state.json` files. It could therefore
compare two empty maps on resume. An added nonempty-count assertion reproduced
the gap: one test failed in 5.2 seconds, seed 63398. The corrected snapshot binds
each namespace-relative State filename and content hash. Research must capture
one memory file; Corpus and Graph must each capture two independent files.
The report, maintained test and installed wrapper all require those exact counts.
The earlier passes do not prove unchanged State bytes.
The corrected maintained test passed in 27.6 seconds, seed 348553.

Both source and extracted-runtime independence commands passed ten checks across
all nine combinations, with zero model requests and domain modules absent from
the host VM. After the snapshot correction, both commands were repeated: three
cases captured one State file and six captured two, with unchanged bytes on
resume. The original sixteen-check base proof also passed in both modes before
that correction; its implementation is unchanged.
The installed wrapper hid development tools and required unchanged extracted
host and archive bytes. It used the existing local archive with SHA256
`d5d2517e87cf358cfe6b6d82060719e6be52ce0e5fcf7920fc4729df7d5c8a4f`.
That archive was neither rebuilt nor published for this proof-only increment.

All four changed Elixir files matched local Elixir 1.20.3 and Elixir 1.18.5
formatting. The latter formatter ran on local OTP 29; it is not hosted OTP 27
runtime evidence. The complete contributor chapter and package instructions
were reviewed, with their examples exercised against actual source and installed
commands.

Before the State snapshot correction, the complete local suite passed 1150 tests
with 17 Linux-only exclusions in 629.6 seconds, seed 893382. Strict stdio tracing
and both actual macOS enforcement tags were enabled. Build, local formatting and
warnings-as-errors compilation also passed. That baseline is distinct from the
later focused snapshot regression and corrected-proof checks.
Final formatting, warnings-as-errors compilation, CI policy and the isolated
credential-free demo passed. Documentation checks covered 233 files and 2583
local links without errors.

## Previous exact-source hosted checks

The [8297096 matrix](https://github.com/lexlapax/ipse/actions/runs/39263652984)
completed successfully on Linux and macOS. All 24 steps in each job were
inspected; only the two macOS-only checks were skipped on Linux. Source,
macOS native enforcement, packaging and every installed proof passed. This is
evidence for the preceding commit, not the new selection proof. Earlier hosted
failures remain preserved in their own records.

No held-out member, manifest contents or evaluator was read. No model weights,
model inference, model downloads, paid providers or new dependencies were used.
