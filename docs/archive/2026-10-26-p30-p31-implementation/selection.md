# Storage and parser selection checkpoint

Historical evaluation record, **2026-10-26**, source `fbb207d`; see the
[implementation record](index.md), [baseline](baseline.md) and [current plan](../../plan.md).
No dependency is adopted by this evaluation alone.

## Native operator observation boundary

Ordinary BEAM IO uses abstract devices and can be redirected to a capture server;
it cannot prove matching actual display/input descriptors. OTP's public
`nouse_stdio` Port mode preserves those terminal descriptors while moving control
to 3/4. The existing Rust helper therefore owns the narrow descriptor, poll,
nonblocking IO and terminal-device checks. Elixir retains origin, proposal,
permission and publication policy. Existing bounded native framing and host
terminal escaping are reused; no terminal framework or new package is required.

PTY controls use the already-inventoried standard C library's POSIX functions,
without a separate libutil dependency or external terminal executable. A fresh
terminal open uses the documented platform nonblock/nofollow/noctty flags;
[Apple's public header](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/fcntl.h)
and [POSIX PTY manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_openpt.3.html)
support the macOS declarations. Tested platform evidence remains separate.

## Sustainable local notes

| Candidate | Evidence and fit | Disposition |
| --- | --- | --- |
| Existing `Ipse.Extension.State` | Already protects bounded JSON with retained native locks, CAS and atomic replace; 1 MiB/256 identities and permanent deletion revisions cannot meet 2,000 active notes/annual turnover | Reuse protection/CAS patterns; C0 internal prototype only; unchanged legacy format |
| Bounded versioned State evolution | Existing OTP files/JSON/crypto/native lock can provide reclaimed immutable generations, manifest publication and suppression floors without a second database/runtime | Selected implementation direction for C1a; qualify capacity, cross-VM publication and recovery before release; domain lineage stays in extension |
| OTP DETS | Standard library, disk-backed keyed terms and reclamation; 2-GB limit, repair after unclean VM shutdown, fragmentation memory; in-VM table sharing does not establish independent-VM transactions | Not selected: would still need external serialization, safe opening/repair and a publication protocol; it does not remove the reviewed host gaps. [Official DETS contract](https://www.erlang.org/doc/apps/stdlib/dets.html) |
| OTP Mnesia | Maintained OTP transaction/database facility, but application-wide schema/table lifecycle would add shared-node ownership and recovery to per-project independently launched VMs | Not selected for this local bounded-store scope; no distribution required. [Official Mnesia overview](https://www.erlang.org/doc/apps/mnesia/mnesia_overview.html) |
| Exqlite/SQLite | Maintained Elixir SQLite driver offers transactions/querying; its Mix source compiles a C NIF and carries SQLite/build tools | Not adopted: transitive non-Elixir/Rust implementation needs explicit approval; no need established before bounded State evaluation. [Driver docs](https://exqlite.hexdocs.pm/Exqlite.html), [build/dependency declaration](https://github.com/elixir-sqlite/exqlite/blob/main/mix.exs) |

The selected direction is conditional on measurements, not a license to implement
an unbounded bespoke database. C1a must compare actual read/write/reclamation
costs and ensure old active generations plus staging fit the complete 64-MiB
envelope. If JSON rewrite/publication cannot meet the frozen workload, retain that
failure and revisit a maintained adapter with the required dependency approval.
Do not raise legacy State limits globally or reinterpret old journals.

## Word extraction

Use OTP's ZIP/XML facilities behind a small extension parser adapter if bounded
hostile-input probes pass. [OTP ZIP](https://www.erlang.org/doc/apps/stdlib/zip.html)
supports stored/deflated entries, directory inspection and per-entry reads;
[xmerl SAX](https://www.erlang.org/doc/apps/xmerl/xmerl_sax_parser.html) supports
event-based XML parsing. These facilities avoid a new service or executable.
Neither API alone proves bounded expansion/entity processing.

F must validate ZIP directory sizes/counts/duplicates/paths before reading, limit
actual decompression (not just advertised length), disable/refuse DTD/external
entities and relationships, bound depth/attributes/text, and run in owned bounded
work. Never extract workspace files or execute macros. If OTP ZIP's whole-entry
allocation defeats the memory bound, reuse OTP zlib incrementally behind an
admitted bounded ZIP reader or select a maintained package after concrete tests;
do not call a metadata precheck sufficient against a forged ZIP entry.

Select final visible revision text: include insertions, exclude deletions;
represent headings, paragraphs and table cells in document order, with original
hash and versioned paragraph/cell locators. Footnotes/comments are separately
labelled evidence or explicitly unsupported, never silently merged into prose.
Legacy `.doc`, encrypted archives and embedded objects refuse explicitly.

## PDF evaluation

The maintained Elixir [PDF package](https://pdf.hexdocs.pm/Pdf.html), v0.8.2 in
the inspected documentation, provides PDF generation/drawing; its documented
API does not supply the needed text extraction. That is a concrete mismatch,
not evidence that all BEAM options are unsuitable. Shelling to Poppler/MuPDF
would add non-Elixir/Rust dependencies and is not adopted under the exception.

The narrow Rust exception permits evaluation of pure-Rust parser candidates:

| Candidate | Inspected contract | Remaining qualification |
| --- | --- | --- |
| lopdf 0.46.0 | MIT; PDF objects/pages/text; default chrono-clock/rayon features can be disabled. Its [tagged Cargo manifest](https://raw.githubusercontent.com/J-F-Liu/lopdf/v0.46.0/Cargo.toml) declares **Rust 1.88**, despite the rendered [crate documentation](https://docs.rs/lopdf/0.46.0/lopdf/) saying 1.85 | Cannot adopt at current floor unchanged. Evaluate a maintained compatible version, exact transitive closure/licenses and extraction fidelity; do not silently raise toolchain requirement |
| pdf-extract 0.12.1 | [Crate API](https://docs.rs/pdf-extract/0.12.1/pdf_extract/) exposes extraction by page and plain-text output | Inspect exact tagged manifest/closure, floor, fonts, reading order and resource controls before selecting; no adoption established |

F's parser gate remains open. A simple hand-written PDF text matcher is not a
replacement for evaluating a real parser. Whichever crate is selected must be
locked, inventoried with every transitive license and built into an installed
owned parser artifact. Elixir retains source/consent/citation/knowledge policy.
Binary bytes, decompressed streams, object/page/text count, CPU/wall-time and
memory must be bounded even if semantic quality remains experimental/off.

## Local model identity and preprocessing

Primary model choices remain the frozen Qwen embedding/4B answer pair. Use owned
immutable model closure for qualification where available, following the existing
evaluation model-service inventory. Shared-daemon use is explicitly cooperative:
canonical protected service identity, full digest checks around jobs and refused
changed results; no immutable per-request weight attestation is claimed.
Do not alter/stop another client's daemon or delete its cache during cleanup.

Freeze Qwen query template v1 as
`Instruct: Given a question, retrieve passages that answer it.\nQuery: QUERY`;
documents are unchanged citation-preserving chunk text. The exact line break
is one LF. Do not prefix already wrapped input twice. EmbeddingGemma challenger
uses its own documented task prefixes and cannot reuse Qwen vectors/templates.
Inputs retain the existing 4,096 bytes/eight items/12-KiB aggregate limits,
`truncate:false`, native 1,024 dimensions and finite nonzero vectors. Normalize
in the adapter to L2 unit norm with absolute norm tolerance 0.0001, versioned in
the index recipe; preserve original spans outside model wrappers. Actual digest,
quantization/backend, context and endpoint identity are still qualification inputs.

The serving runtime/model license and safety checks in
[dependency training](../../developer/dependencies.md#keep-optional-services-optional)
remain applicable; this record does not invent a new runtime dependency.
