# Completed document backup source binding — 2026-11-06

Historical development evidence. The [plan](../../plan.md) owns P31 status;
the [operator manual](../../operator/corpus.md) describes current procedures.
This is a bounded follow-up to the
[completed Collection restore](document-result-restore-public-20261106.md).

The completed-backup validator formerly selected a source-head record using the
catalog entry's source key, then validated the head against its own embedded key.
Those checks did not establish that the two keys matched. A synthetic source set
with a different catalog key and storage key, consistent catalog/page/envelope
hashes and an unchanged valid head and source was accepted before the repair.
The retained reproduction log SHA-256 is
`01e12fc2fbe6cf27429663c4072cce1dae2681651a8bedad7b324dc7d0736b6c`.

The validator now requires the catalog entry and head source keys to match.
The existing selected-page test retains a valid control and checks that the
rehashed mismatch refuses both the direct completed-backup predicate and the
selected-page validation. Its protocol driver permits reads only; the tested
rejection occurs before a restore mutation.

One source/helper run used one scheduler, no native Input or TCP, and passed all
26 selected existing and new controls with exit 0 and no warnings. Its log at
`/tmp/ipse-collection-backup-source-binding-20261106/controls-02.log` has SHA-256
`b54b2687bface82ca0fd6fe3438a814f67ded930aa8efb0b88e1c10007962bf9`.
The tested Projection and backup-case files have SHA-256 values respectively
`fec71ad57c08dcc430ba62acdd908e9250688c403fe940fa39aa6aed11c4be2d` and
`27c7398432e25577477c465ba0a87897e12d5081f4b4f1785c078f877bb523e4`.
The earlier source run also passed all 26 but emitted a preloaded-module warning;
its log remains alongside the clean run.

An independent source review found no blocker in the key comparison or the
synthetic selected-page control. It does not establish a native Session or an
actual restore. No restore was attempted with the inconsistent set. Real native
or installed restore, larger migrations, general cleanup and full P31C1b
qualification remain open. A later [installed direct-domain probe](document-backup-installed-binding-20261106.md)
passes the valid and mismatched synthetic cases without claiming a restore.

After the earlier full suite ended, a separate checkout of `d4b15aa6` with only
the Projection and backup-case changes ran the isolated backup wrapper: one
outer test passed, requiring all 26 inner cases. Its log SHA-256 is
`8d7a4a67b20d5400378067e353b6dec4d57bf3ebf4298b0d8f639fd24839e0b5`.
The one-scheduler launcher used a 2.25-GiB available-memory preflight after the
concurrent suite ended; it did not change product limits or test assertions.
The checkout used the separately documented test-helper retention overlay.
