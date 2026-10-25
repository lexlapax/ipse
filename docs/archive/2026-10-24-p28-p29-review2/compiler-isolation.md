# Installed verifier compiler isolation

Dated 2026-10-24. Historical follow-up to the author adversarial review of
`5d9650e`. The [plan](../../plan.md) owns acceptance and
[verification training](../../developer/testing.md#follow-compilation-and-runtime-ownership)
owns current procedures. The [receipt](compiler-isolation.json) records actual
archives, code hashes, failed iterations and passing controls.

## S4: cross-toolchain verification failure

The complete hosted rehearsal at `5d9650e` passes on both floor platforms. Its
Linux archive also launches on the local Linux host and reports that exact
commit, Elixir 1.18.5 and OTP 27. However, running its developer package verifier
from Elixir 1.20.4 / OTP 29 fails before the harness runs: the system compiler
starts with some newer modules already loaded, then archive `-pa` paths introduce
older compiler modules. `:elixir_utils.get_line/2` is undefined in that mixed VM.
This is a P3 developer-tool portability defect, not an operator archive-launch
failure. The first failed check is retained and is not relabelled as passing.

Installed harness compilation now invokes the selected release's own launcher
in a separate private environment. Compilation and subsequent verification use
the same bundled compiler/runtime family. The source-SDK branch keeps its existing
development compiler. No product runtime, native source, dependency version,
workflow or timeout changes are involved. No archive or recorded host BEAM is
recompiled or repaired by the verifier.

## Controls and verification

A synthetic release supplies its own launcher. A poisoned higher-priority host
`elixir` writes a marker and refuses execution. A module captures compiler-time
HOME and a synthetic host-only variable. The repaired path compiles through the
selected launcher, captures the private HOME, captures no host-only variable,
and never invokes the poisoned compiler. The same test against the old verifier
fails at that poisoned compiler. This observes real compilation rather than
checking the command text.

The first full run passes 32/33; the new synthetic archive omitted its outer
launcher. Two focused iterations then expose incorrect assumptions about OTP
JSON's nil/null representation. The fixture now uses Elixir's standard JSON
encoder and decoder, retaining the strict expected nil/private-HOME and absent
marker assertions. The final complete verifier suite passes **33/33**, seed
713790, 77.3 seconds. All failed iterations remain in the receipt.

The repaired verifier passes all twelve installed checks against both actual
`5d9650e` archives: hosted Elixir 1.18.5 / OTP 27.3.4.19 and locally packaged
Elixir 1.20.4 / OTP 29.1.1. Both preserve input/runtime inventories, private homes,
utility-only runtime PATH and zero inference. The runtime's native-inclusive
baseline and complete hosted rehearsal remain scoped to `5d9650e`; later hosted
verification of this developer-tool change is recorded separately.
