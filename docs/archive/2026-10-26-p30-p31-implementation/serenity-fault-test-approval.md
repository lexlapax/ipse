# Serenity fault-test dependency approval

Recorded 2026-10-27. The developer requested qualification on Serenity and
explicitly approved Docker and the already-installed btrfs-progs, util-linux
(including `losetup` and `mount`), and device-mapper tools for a disposable
Btrfs fault test. No package installation or image download was authorized by
this approval. The test fixture must use a fresh disposable backing file and
must not operate on the project filesystem or preexisting host devices.

At read-only inspection Serenity reported Arch packages Docker
`1:29.9.2-1` (Apache-2.0), btrfs-progs `7.3-1` (GPL-2.0-only), util-linux
`2.42.4-1` (package-declared BSD, GPL, ISC, LGPL and public-domain licenses),
and device-mapper `2.03.43-2` (GPL-2.0-only and LGPL-2.1-only). These are
qualification tools, not shipped Ipse runtime dependencies. A pinned existing
local Arch image has digest
`sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af`.
Read-only inspection retained its [137 package versions](serenity-tools/image-packages.txt)
and [package-declared licenses](serenity-tools/image-licenses.txt), the
[host tool binaries and shared libraries](serenity-tools/host-tool-closure.txt),
and a conservative [101-package host dependency closure](serenity-tools/host-package-closure.txt).
The [inventory script](serenity-tools/package_closure.exs) includes all installed
providers of ambiguous virtual dependencies; `pacman -T` found no unmet collected
requirements. Its output is a conservative package-level set, not proof of
dynamic loading, execution, or complete license compliance. The
[direct dependency data](serenity-tools/host-package-depends.txt) is also retained.
The pinned image lacks Elixir/OTP. A separate read-only host BEAM startup sample
loaded 21 mapped files and 369 BEAM files during application startup, crypto and
Transaction-module loading; its [file hashes](serenity-tools/beam-runtime-inventory.txt),
[package ownership](serenity-tools/beam-runtime-packages.txt), and
[package-declared licenses](serenity-tools/beam-runtime-licenses.txt) are retained.
It observed `libsctp.so` from the existing `lksctp-tools` package. Including
Elixir and OTP package roots expands the conservative
[host closure](serenity-tools/host-with-beam-closure.txt) to 110 packages.
This sample did not launch the helper or exercise a device, and it does not prove
the complete runtime or dynamic-loading closure for the later test.
The developer subsequently explicitly approved using the inventoried existing
image and system-library closure for this isolated test. A live run still needs
its exact executed closure checked, including dynamic loading and licenses.
Approval is not a
claim that the proposed container, host-global device controls, fault procedure
or cleanup is safe or qualified. The live fixture remains under development
and independent review.

The [kernel recovery record](kernel-profile-recovery.md) and
[open audit](2026-10-27-open-audit.md) describe the current evidence and limits;
the [plan](../../plan.md) owns milestone status.

A [fixture review snapshot](serenity-tools/fixture-review-snapshot.tar.gz)
preserves an unfinished, disabled controller, probes, proposed container
harness and inventories in case temporary work is lost. Its SHA-256 is
`aefde07b315405449ad2cb578c4c0dfd81516de31f6272cab717ca89d1692706`.
It is historical review material, not an approved or runnable qualification:
device identity races, tool immutability, process and mount cleanup, actual
native-owner fault attribution and the live harness require further work and
independent review. No block device, mapper, mount or injected fault has been
created by this fixture.

A later [text-source snapshot](serenity-fixture/SNAPSHOT.md) preserves the
evolved private barrier, mock controller, scoped cancellation and recovery
experiments with their hashes. It is likewise disabled and incomplete; its
temporary-file controls do not constitute the requested Serenity Btrfs fault run.
