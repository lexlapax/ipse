# Serenity temporary-file stage in Docker, 2026-10-27

This historical experiment used the already approved local Arch image,
network disabled, a read-only container root, all capabilities dropped, no
block devices and UID/GID 1000. It mounted the existing host Erlang and Elixir
trees and the previously inventoried `libsctp.so.1` read-only, plus a private
compiled Ipse graph read-only. Its only writable bind was an owner-only,
temporary synthetic fixture. It neither injected a fault nor exercised the
production helper or a Session journey.

The [captured output](stage-container-evidence/stage-channel-5.stdout) from the
Rust adapter, peer listener, source-derived native helper and a bound Resources
scope was `RUST_STAGE_ADAPTER_OK REPORT W=0 S=0`; its separately captured
[stderr](stage-container-evidence/stage-channel-5.stderr) was empty. The exact
private source used for that run is retained under `stage-container-evidence`.
The test helper's post-run SHA-256 was
`2c022bc2e1627ecdbf6fa48a6f0c9141a251838ff8ebc849da5d319c7899e57a`; the
recompiled `Ipse.Runner` BEAM module's post-run SHA-256 was
`9de5beb9a10a88a02581cc42965b517e6f059624429156ebb234447754c0e8fe`.
These are observations, not immutable-at-exec proofs.

A later no-device run added a pre-acquisition BEAM executable/pidfd/pipe gate:
the transcript reported the same adapter success; a deliberately wrong
executable was refused and its fresh stage directory stayed empty. Separate
logs were not captured for those two runs. The first attempted container run
failed because invoking Elixir through `/usr/bin/elixir` changed its installation
root; the successful runs used `/usr/lib/elixir/bin/elixir`. An earlier local
attempt also revealed that the gate must notify the `Resources.file_effect`
worker rather than its scope owner; the private script was corrected.

A separate captured [sample](stage-container-evidence/container-run-3.stdout)
of `/proc` mappings while a stage was paused included the BEAM executable,
crypto NIFs, loader, libc, libcrypto, SCTP, ncurses, Brotli, zlib, zstd and
OpenSSL paths; the native helper mapped itself, loader, libc and libgcc. It is
a single observed point, not a complete closure for later code or error paths.
A first runtime-only probe also revealed the image lacked SCTP; the existing,
previously inventoried host library was then mounted read-only.
