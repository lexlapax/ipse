# V4 source-bound group geometry — 2026-10-29

Historical development evidence; the [plan](../../plan.md) owns acceptance.
This follows the [selected-root repair](shared-producer-v4-selected-reuse.md).
The 256-chunk case below is a closed protocol model, not a native capacity or
complete producer qualification.

Eight synthetic DOCX sources with 32 near-2,040-byte paragraphs each expose
256 distinct chunks. The original v4 reader produced all 32 pages but refused
hydration at the 512-read cap. An initial reverse traversal brought hydration to
512 reads and left no append budget. A revision-bound read and selected-page
cache lowered the cost, but a modeled late append still exhausted its reads
after two metadata stages. Its synthetic stages and failed log are retained;
there is no actual native effect in that run. A provisional preflight now
reserves space for two immutable-prerequisite passes and control reads before
calling the append controller. Wider stage/fact geometries still need a proof
of that reservation; do not treat it as a general capacity guarantee.

The current internal source-bundle path accepts exact source-head hashes from
the validated catalog page, reads those heads at the pinned native generation,
returns their physical stamps, and verifies every block against the retained
head reference. The selected reader reuses a validated catalog page only inside
the same generation-pinned invocation. Immutable referenced pages/blocks can
start with a hash-bound read rather than a redundant stat. V4 hydration walks
ready slots backward; each descriptor's revision, hash and byte count must
match its fixed-generation read. No changed source, revision or missing page
is interpreted as empty.

The final model run produced all 32 pages and completed the private Job append
using one explicitly supplied synthetic fact per source. Hydration used 417
reads; the highest of 37 append invocations used 509 reads. This is only three
reads below the unchanged per-invocation ceiling. It does not cover 32 facts
per source, other escaping/metadata geometries, all stage interruptions,
public fact production, Session journal handoffs, root selection or physical
peak. In particular, 37 repeated source-hydrating invocations are not a claim
that one real Session can accommodate the journal. Separate controls refused
changed head/block bytes and wrong physical revision, retained the original
object-read behavior without a revision argument, and passed selected-root,
same-Job, unknown, public-continuation and guard1 model cases.

A fresh strict artifact built against the reviewed Host graph, then a separate
actual Session passed the public two-page synthetic-loopback fixture. That
Session used six sources, an initially empty selected root, six embedding
requests, Saved reconstruction and confirmed close; its journal contains 1,540
events and 4,671,581 bytes. The imported artifact digest is
`fd1be1c6d6f4354a1f90b7fe42322c83782f6992f251054d7fab3ced852c70a9`.
It does not execute the private 256-chunk append in a native Session.

The [manifest](shared-producer-v4-bound-geometry/manifest.json), SHA-256
`f502b320daae96acfc42d6f640eb987fd7e7efcca4218d8e54b325159d1f97cc`,
pins 90 source, artifact, synthetic evidence and log files. It retains the
failed runs, including two test-model uppercase identifier issues, a timeout,
the incorrect initial corruption fixture, and the late staged budget failure.
Independent implementation review, source/clock race controls, full native
geometry, fact semantics/egress, GC and migration remain open.
