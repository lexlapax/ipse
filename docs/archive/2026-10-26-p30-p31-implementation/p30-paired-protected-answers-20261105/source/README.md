# Historical public fixture sources

These byte-exact public source snapshots support the
[2026-11-05 synthetic paired record](../../p30-paired-protected-answers-20261105.md).
They contain no runtime, journal, transcript, response blob, private log, compiled
object or PTY binary. [source.sha256](source.sha256) pins every copied source.
Files are non-executable archive material, not an installation or authorization
to run an actor.

`03/` comes from the historical scratch directory
`_build/verification/p30-paired-protected-workflow-20261105-03/`.
It contains the strictly compiled owner, actual phase entry and guard, subordinate
phase script, OFF inner/outer actor launchers, metadata serializer and one-owner
compile checker/OFF wrapper. The actual launch used separately reviewed
derivatives that changed only the descriptor's reviewed flag and removed the two
OFF lines from each actor launcher. Those activation hashes are in the public
evidence; this archive preserves the OFF launcher preimages. No reviewed actor
descriptor, live approval, helper BEAM or executable runtime is supplied here.
The phase script and entry are subordinate historical sources, not standalone
commands. Do not execute them against their embedded scratch paths.

`reused-02/` comes from
`_build/verification/p30-paired-protected-workflow-20261105-02/`.
The answer extension and builder produced the same qualified artifact reused by
03; `qualification-02-check.exs` revalidated the already compiled outputs after
the earlier build check's code-path API error. That failed build is not relabelled
as passing. The 03 compile checker reuses six byte-exact helper objects, compiles
only the repaired owner and rechecks the existing artifact. No SDK or artifact
rebuild occurred for that repair.

Absolute paths are historical provenance, not portable defaults. The public
development helper owners remain under `dev/evaluation/`; ordinary support
owners remain under `test/support/`. The source snapshots preserve their exact
normal-runtime and helper-origin checks. Reproduction requires a separately
reviewed complete runtime, input closure, fresh isolated storage and explicit
actor scheduling. This record grants none of those permissions and cannot renew
the expired disposable grant or authorize retained-cohort access.
