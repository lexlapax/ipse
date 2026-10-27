# Serenity no-device boundary preflight, 2026-10-27

This historical diagnostic used the existing approved image
`sha256:757718cecb34fbe2c56e22b5f6299a45f149c7ce1c9b85def543a340bacdf7af`,
with no block devices, network, host project mount, image pull or kernel fault.
It does not qualify Linux 7.2.11, prove cgroup quiescence or validate the live
Btrfs controller. Root-owned staging and its exact cleanup were independently
reviewed by the coordinating agent before execution.

The coordinating agent reviewed and ran
[the exact harness](boundary_preflight_harness.sh), SHA-256
`fea27227d840d1091464832a4d348b1e0ea8da858d1453110df89306f7ede33b`.
The private probe was built from [this frozen source graph](boundary-preflight-build/SOURCE-SHA256SUMS)
with `rustc --edition=2021 boundary_preflight.rs -o /tmp/ipse-boundary-preflight`.
An independent rebuild matched binary SHA-256
`9f308bb56cec28eaef1e1c1db5de6df4fa68db7074718e7347d231c6b4915528`.
The graph's source-hash manifest SHA-256 is
`a01cdd6e1a2e7a1618cdf1b25a487047c6e8c4edf1dd447fce226bbf688c42b0`.
The sources are frozen historical research, not a current operator procedure.

The following is transcribed from the coordinating agent's tool output; no
separate raw log was captured:

- Stage `/tmp/ipse-boundary-check.38OsGytc`, device:inode `53:210877`, original
  UID `1000`; probe `53:210880:0:700` with the binary hash above.
- Host mount namespace inode `4026531832`. Container ID and observed cgroup ID
  both `291a8e93d5651c6325c9091d419bf52f51ee0260e57969b923d67ea8678e0a1c`.
- The probe printed `PREFLIGHT_OK`; exact-ID `docker rm` printed the same ID;
  the harness printed `STAGE_REMOVED` and exited 0.

Two previous attempts stopped before the probe: the first could not traverse a
user-owned 0700 staging directory with only CAP_CHOWN; the second staged the
root-owned files but the host user could no longer stat the probe. The
coordinating agent inspected both exact stages, checked their expected contents
and identities, and removed only the recorded files and directories; neither
attempt touched a block device. The revisions made the temporary stage
non-writable but traversable before chown, then captured the probe identity and
hash before ownership transfer. No unrecorded raw log is implied.

This observation checks the scoped paths and cgroup name at that moment under
the trusted-host assumption. It does not prove absence of mount replacement,
process migration, inherited descriptors or later privileged activity. The
live device effects, guardian integration and complete cleanup remain open.
