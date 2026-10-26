# Optional experimental PDF parser

This narrow Rust parser reads already acquired bytes over stdin. Elixir owns
acquisition, consent, source identity, citations, storage and retrieval. Ordinary
document extraction leaves PDF disabled. Explicit experimental selection calls
`IpseKnowledge.Documents.extract_pdf/3` with a host-admitted absolute executable
path and SHA-256 from protected configuration, outside target workspaces.
Never accept executable paths or digests from document text or model arguments.

Build with Rust 1.88 or newer and the existing Elixir toolchain:

```sh
elixir native/ipse-pdf/build.exs --output priv/ipse-pdf --notices priv/ipse-pdf-notices
cargo test --locked --manifest-path native/ipse-pdf/Cargo.toml
IPSE_TEST_PDF_PARSER="$PWD/priv/ipse-pdf" mix test test/extensions/knowledge/documents_pdf_test.exs
```

The build uses the checked lockfile, verifies the reviewed
[dependency inventory](DEPENDENCIES.md), compiles the helper, and retains notices.
Copy both the executable and notice directory into the installed artifact.
Installed operators do not compile or install a parser toolchain. Source-only
demo builds may omit this helper; text/DOCX and the credential-free demo do not
need it. The existing OS helper keeps its Rust 1.85 floor.

## Ownership and resource boundaries

The Elixir adapter runs in the document worker, bounds retained output and closes
the Port on timeout or caller death. The native supervisor reads one framed job
and launches one separate parser process with an empty environment. It kills and
reaps that worker on its five-second deadline, unexpected input or stdin closure.
The worker also watches the supervisor PID and exits when the supervisor dies,
including forced termination. Document input cannot request other sub-processes.

Before exec and again in worker mode, Unix resource limits cap CPU at four
seconds, address space at 384 MiB and core dumps at zero. Failing to install a
limit refuses parsing. This is resource containment, not a filesystem/network
sandbox. The parser is not given paths and never invokes rendering, OCR, active
document actions, URL resolution or external relationship APIs.

Protocol ceilings are 16 MiB original bytes, 256 pages, 32 MiB decoded retained
non-image stream bytes and 1 MiB returned text. Limits may be reduced. Loading
also caps each eagerly decoded xref/object stream at the expanded-byte ceiling;
the OS memory/CPU limits contain aggregate load-time object construction. This
does not claim a 32-MiB peak-memory limit. Objects are capped at 100,000 after
load. Images are not decoded. Encrypted inputs, even empty-password ones, and
embedded files refuse explicitly. Malformed pages within an otherwise readable
file produce a partial result with per-page warnings. Empty/image-only files
produce an explicit per-file error. Resource and text limits refuse the whole
result, never report a truncated file as complete.

Linux process cancellation and deadlines are covered by real subprocess tests.
The macOS implementation is present but remains unverified until its own checks
run. Other platforms refuse rather than fall back to an unbounded parser.
Neither these synthetic controls nor successful simple-page extraction qualify
multi-column reading order, tables, complex fonts or a live document corpus.
PDF quality remains experimental and off by default.

## Exact binary protocol

All integers are unsigned big-endian. A request is eight bytes `IPDF0001`, then
four 32-bit fields: maximum pages, maximum expanded bytes, maximum text bytes,
input length; exactly that many original bytes follow. Keep stdin open until
the result arrives: EOF cancels the job. Extra input is a protocol failure.
No command, path, password or endpoint is accepted in a request.

A response is eight bytes `IPDO0001`, one status byte, and a 32-bit page count.
For success, each page is its 32-bit one-based number, one page status byte,
32-bit UTF-8 byte length and exact text. Page status is 0 (text), 1 (empty) or
2 (extraction failed); empty/failed pages have zero bytes. Global status is
0 (all pages read) or 1 (partial). Error responses have page count zero and
status 2 (empty/image-only), 3 (encrypted), 4 (malformed), 5 (resource),
6 (protocol), 7 (page limit), 8 (text limit), or 9 (embedded file).
Error messages never echo document bytes or parser exception text.
