# Default PDF-enabled package document controls

2026-11-03. This is a synthetic Linux verification checkpoint, not P31D1,
P31F or milestone acceptance. The [plan](../../plan.md) owns current status; the
[Corpus manual](../../operator/corpus.md) describes operator procedures.

An isolated source export of commit `b6d667a1761793007b3e03b926a71089ac080550`
built the default PDF-enabled package offline. The archive's SHA-256 was
`bcf594d80232fc1fd611088db5be18d692e965bd76ceccfa1857a7e1eee5764d`.
The build retained the reviewed PDF dependency notices and reported 52 bundled
documents with no missing local targets. The export omitted the historical
documentation archive and linked its source archive for build-time local-target
checks; it was not a wholly self-contained frozen documentation checkout.

The [installed document verifier](default-pdf-package-20261103/documents.log)
passed nine synthetic checks against the extracted package, including disabled by
default PDF extraction, explicitly selected PDF extraction with an available
resource backend, and all 60 inventoried dependency notice directories. The
other checks cover Word revision policy, matching style effects, packed blocks,
annotation links, Unicode text and artifact loading. Its input was the same
`corpus-state-documents` artifact built into the package. The verifier recorded
unchanged inventories and no system toolchain on the runtime path. No model
inference was used.

The same archive passed all six [installed setup cases](default-pdf-package-20261103/setup.log):
State, Collection, cancelled review, stale code, changed configuration during
review and piped input. Both positive cases exercised native setup, approved
workspace Word acquisition, citation and source-file replacement refusal, then
restoration and Session resume. Their 40-block fixture checks packed citation
coordinates, UTF-8 bytes and the direct single-level numbering labels in both
stores. The [report](default-pdf-package-20261103/setup-report.json) identifies
the archive, fixture, runtime and individual log hashes. It records unchanged
extracted release files and zero model calls. Runtime uses the package's Ipse
code, a precompiled ExUnit overlay and a synthetic PTY compiled before launch;
it is not independent human use.

The fixture SHA-256 was
`8bcd53725549ad62398b9ad798731d5c82dc58f323176aa6100918ea8e5ad2c2`,
and the setup verifier SHA-256 was
`a5eafcfdd8ca5ed4d35456ef642471dc1a252ad6699aba7658c3f046236947bd`.
The source, exact archive, full build logs and fixture output were retained in
private test directories during this run; temporary paths are not durable
project artifacts.

The first package attempt built the PDF parser but the sandbox denied Mix's
[local TCP lock](default-pdf-package-20261103/mix-lock-failure.log). The same
isolated build then completed with local socket access. The first installed
document verification stopped extracting into `/tmp` due to its
[disk quota](default-pdf-package-20261103/tmp-quota-failure.log); it passed using
a private project-filesystem temporary directory. The six setup cases ran on a
private tmpfs filesystem admitted by the existing Collection profile. Offline
Hex and Cargo caches and locked dependency sources were copied into the isolated
build; no dependency or model was downloaded.

These checks do not establish real-Word rendering or PDF semantic quality,
general document capacity, complete lifecycle, model-assisted retrieval,
cross-platform behavior, independent human usability or the final integrated
source suite. PDF remains experimental and requires its own quality disposition.
