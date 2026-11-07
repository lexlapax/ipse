# Installed synthetic backup attempt — 2026-11-06

Historical verification evidence. The [plan](../../plan.md) owns current
acceptance; this attempt does not qualify installed backup or restore.

The reviewed, separate synthetic installed-archive public journey was launched
once after its memory and isolation gates passed. It exited 1 with an unknown
outcome, retained under
`_build/verification/installed-backup-public-20261106-01/run-01/`. Its log
reports `project_identity_filesystem_unsupported` during project identity
admission, before any of the 72 planned public command receipts were recorded.
This was not the declined retained-notebook recall check.

The actor placed its synthetic home and project under the receipt root on the
workspace Btrfs filesystem, rather than under the separate temporary tmpfs
prepared by the launcher. The host was `Linux 7.2.11-arch1-1`; the workspace
mount was Btrfs and `/run/user/1000` was a writable tmpfs. This is consistent
with the protected filesystem refusal; the exact native admission predicate was
not independently traced in this attempt. The installed-file and input hash
inventories matched before and after. A host-side check found no remaining
process in the launched process group and no holder of the terminal input lock
or the test port. The claimed attempt and unknown outcome remain preserved;
they must not be automatically replayed.

Any future separately reviewed synthetic attempt needs a suitable admitted
filesystem for the actor's actual home and project, not only its temporary
directory. Passing such a test would still qualify only that exact package and
bounded journey, not the full document lifecycle or current candidate.
