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
Additional image, library and tool execution scope still needs explicit review
and any required approval before a live fixture is run. Approval is not a
claim that the proposed container, host-global device controls, fault procedure
or cleanup is safe or qualified. The live fixture remains under development
and independent review.

The [kernel recovery record](kernel-profile-recovery.md) and
[open audit](2026-10-27-open-audit.md) describe the current evidence and limits;
the [plan](../../plan.md) owns milestone status.
