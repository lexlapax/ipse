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
local image and the exact executed tools, libraries, source, licenses and hashes
still need to be inventoried before a live fixture is run. Approval is not a
claim that the proposed container, host-global device controls, fault procedure
or cleanup is safe or qualified. The live fixture remains under development
and independent review.

The [kernel recovery record](kernel-profile-recovery.md) and
[open audit](2026-10-27-open-audit.md) describe the current evidence and limits;
the [plan](../../plan.md) owns milestone status.
