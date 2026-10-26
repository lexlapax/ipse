# Optional experimental PDF parser

This narrow Rust parser reads already acquired bytes over stdin. Elixir owns
acquisition, consent, source identity, citations, storage and retrieval. Ordinary
`IpseKnowledge.Documents.extract/3` leaves PDF disabled, including when the
executable ships in a package. Explicit experimental selection calls
`extract_pdf/3` with a host-made `Ipse.DocumentParser.descriptor/2` descriptor.
Document text and model arguments never select executable paths or digests.

## Build and installed use

The existing dependency-free OS helper requires Rust 1.85. The optional parser
requires Rust 1.88 and the existing Elixir toolchain:

```sh
IPSE_BUILD_PDF=1 ./dev/build.sh
cargo test --locked --manifest-path native/ipse-pdf/Cargo.toml
mix test test/ipse/document_parser_test.exs test/extensions/knowledge/documents_pdf_test.exs test/extensions/knowledge/documents_parser_stage_test.exs
```

Source `./dev/build.sh` defaults to `IPSE_BUILD_PDF=0` and removes stale generated
parser artifacts. Text/DOCX and the credential-free demo need no PDF toolchain.
`./dev/package.sh` defaults to `IPSE_BUILD_PDF=1`; `IPSE_BUILD_PDF=0` deliberately
produces a parser-free bundle. Parser-enabled bundles contain the executable
and all 60 locked third-party crate notice directories, both in application
`priv/ipse-pdf-notices` and the release license collection. Installed operators
need no Rust, Cargo, Elixir compiler, model service or download to parse a PDF.

The builder uses the checked lockfile, verifies the reviewed
[dependency inventory](DEPENDENCIES.md), and retains upstream notices. It accepts
`CARGO_HOME` and `CARGO_TARGET_DIR` for isolated caches. No transitive non-Rust
library or external PDF rendering tool is introduced.

## Host identity and bounded execution snapshots

`Ipse.DocumentParser.descriptor/0` reports the compiled bundle identity without
reading parser bytes. `/2` accepts the host-selected private operator home and
canonical target workspace. It returns `path`, `sha256`, `uid`, `workspace`,
`staging_root` and `copy_helper: %{path: ..., sha256: ...}`; discovery creates no
directories. `/2` creates one exclusive zero-byte UID probe in the already 0700
home, verifies its retained descriptor owner, immediately changes its mode to 0600
and unlinks only that same inode. No content is written; private ancestor access
protects the empty inode before chmod. UID authority comes from retained-FD
metadata, not chmod or environment variables. Both helper locations come from the loaded host module's bundle,
independent of environment overrides and extension code-path application naming.
The host validates protected ancestors before the first bootstrap read or native
UID query. The kernel UID must match the private home owner. Helpers and staging
must lie outside the target workspace.

The bootstrap invariant is a protected host installation and cooperative code
running as its user. Ancestors must belong to that user or trusted system root,
with no group/world write; a trusted root-owned sticky temporary ancestor may
contain an owner-only home. The home and staging directories must be owner-only.
This boundary does not resist arbitrary unsandboxed hostile code already running
as the same UID, which can replace that user's executable code or kill processes.

`Documents.ParserStage` claims one of four persistent slots before source IO.
The existing OS helper copies at most 32 MiB from a non-following, nonblocking
retained regular-file descriptor into an exclusive private 0600 snapshot. It
verifies source and destination identity before and after the copy. Elixir hashes
those exact copied bytes against the compiled identity and changes the private
snapshot to 0500. Only that verified snapshot is executed: replacing the original
source pathname afterwards cannot change executed bytes. Symlinks, hardlinks,
writable images and unsafe ancestors refuse. Each slot retains its directory
and lock inode. At most four 32-MiB snapshots (128 MiB) are admitted, separately
from the knowledge collection's 64-MiB allocation budget.

A monitored guardian owns copy/parser Ports through caller death. The parser
acquires the retained lease and flushes readiness before receiving a job or
forking. The guardian requires actual supervisor exit and, after possible fork,
a confirmed quiescent lease probe before removing its verified snapshot. A
stopped startup, unknown copy/probe termination or interrupted cleanup quarantines
the finite slot; a later request never reuses unchecked bytes. Retained lock
files are never unlinked. VM-crash leftovers require operator reconciliation
after proving native children quiescent; automatic stale-slot deletion is unsafe.

## Native resource and process boundaries

The single-threaded native supervisor forks directly into its admitted image;
it does not reopen `current_exe`. The child retains the lease, clears its
environment, installs CPU four-second/address-space 384-MiB/core-zero limits,
and verifies that an allocation larger than the address-space ceiling fails.
The parser also watches its supervisor PID. The supervisor kills and reaps its
child on owner loss, unexpected input or the five-second job deadline. It drains
the child's final pipe bytes after reaping. Final stdout is nonblocking and has
a six-second total envelope, so a nonreading owner cannot retain a helper forever.
The Elixir caller's default extraction timeout is five seconds; its guardian
continues cleanup after returning a timeout.

Failure to establish or demonstrate resource limits returns the explicit
resource-backend-unavailable outcome. The adapter never relaxes a limit or falls
back to an in-process parser. This is resource containment, not a filesystem or
network sandbox. No document-supplied path, command, password or endpoint is
accepted; the parser never invokes rendering, OCR, document actions, URL fetching
or external relationship APIs.

Protocol ceilings are 16 MiB original bytes, 256 pages, 32 MiB decoded retained
non-image streams and 1 MiB returned text. Callers may reduce them. Load-time
xref/object streams also have a per-stream expansion cap, while CPU and address
space bound aggregate object construction. This is not a 32-MiB peak-memory
claim. After loading, the parser caps objects at 100,000, validates page-tree
identity/count/order before extraction, and scans bounded nested dictionaries
for attachments. Images are not decoded. Encrypted inputs, even with an empty
password, and embedded files refuse explicitly. Malformed page content can
produce partial output with page warnings; malformed page trees refuse the whole
file. Empty/image-only files have an explicit per-file error. Resource/text
limits never report a truncated file as complete.

Linux subprocess tests cover limits, cancellation, forced supervisor death,
startup readiness, retained leases and blocked output. macOS implementation and
CI checks are present; local Linux verification is not evidence of macOS
execution. A macOS host unable to enforce the 384-MiB address-space ceiling must
refuse explicitly. Other platforms refuse. Synthetic fixtures do not qualify
multi-column reading order, tables, complex fonts or real-document quality.
PDF remains experimental and off by default.

## Exact binary protocol

All integers are unsigned big-endian. A request starts with `IPDF0001` (eight
bytes), then four 32-bit fields: maximum pages, expanded bytes, text bytes and
input length; exactly that many original bytes follow. Keep stdin open until
the result arrives. EOF cancels the job; extra bytes are a protocol failure.

A response starts with `IPDO0001` (eight bytes), one status byte and a 32-bit page
count. Success rows contain a 32-bit one-based page, page status byte, 32-bit UTF-8
length and exact text. Page status is 0 (text), 1 (empty) or 2 (extraction failed);
empty/failed pages have zero bytes. Global status is 0 (complete) or 1 (partial).
Errors have page count zero and status 2 (empty/image-only), 3 (encrypted),
4 (malformed), 5 (resource), 6 (protocol), 7 (page limit), 8 (text limit),
9 (embedded file), or 10 (resource backend unavailable). Error messages never
echo document bytes or parser exceptions.

The host-only `--lease PATH` mode first writes and flushes `IPLEASE1`, then uses
the same request/response framing. `--lease-check PATH` creates no lock and exits
0 with `QUIESCENT` only when the existing retained lease is available; exit 1 is
busy. These paths come exclusively from protected host staging authority.
