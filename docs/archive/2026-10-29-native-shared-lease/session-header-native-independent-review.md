# Independent review of the Linux native Session header

2026-10-29. This scoped review covers the frozen
[Linux native Session header cohort](session-header-native.md), not final P31
acceptance. The source manifest and both full runtime inventories verified
locally; the archived implementation files matched the inspected working tree.
The controls support the narrow result that the native lock owner creates,
writes, synchronizes and publishes the header while retaining exclusion at
the tested owner-loss boundaries. The hooks bracket filesystem calls; they do
not suspend the kernel inside a syscall.

The reviewer found a concrete close-semantics defect: an ordinary Linux fresh
Session acquires a `:header_v1` guard but retains `:legacy` as its Session lock
mode. Its close can therefore report confirmed cleanup before the framed lock
release result is known. Failed, malformed or unconfirmed release must be
reflected in the actual Session close outcome.

The transfer also has per-frame timeouts but no single overall deadline. A
slow helper can extend a multi-chunk header transfer far beyond a normal
startup bound. A shared monotonic deadline and slow/stalled controls are needed.
The new Linux fresh path depends on the pinned helper, protected parent paths,
no-replace rename and directory sync. A genuine older-helper and unsupported
filesystem refusal were not covered by the recorded cohort. Resume and
non-Linux startup still use the older ordering and are not qualified here.

The source archive and evidence remain untracked until the eventual commit.
These findings are being repaired before accepting the Linux implementation.
