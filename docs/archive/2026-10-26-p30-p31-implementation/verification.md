# Fixed-revision verification receipts

Dated **2026-10-26**; historical evidence for the [implementation record](index.md).
Each result belongs to its exact source revision and tested scope. None closes
P30/P31 or establishes model, human or installed-platform qualification by itself.

## Foundation `f9149f5`

An isolated clean local clone, with its own dependency/build directories, passed
`./dev/build.sh`, `mix format --check-formatted`, strict compilation and the full
source suite: **1,805 passed, 36 excluded**, seed recorded in the retained raw
test log. Elapsed suite time was 1,057.9 seconds. Exclusions are the declared native
sandbox, macOS filesystem/sandbox and memory-scope groups, not silently skipped
failures. Expected process-loss/TLS refusal logs are not test failures. The
combined command exited zero. The pre-repair 1,794-test result remains historical
and is not substituted for this final foundation receipt.

Raw local receipts are `/tmp/ipse-foundation-fixed-build.log` and
`/tmp/ipse-foundation-fixed-tests.log`; they are diagnostic temporary files, not
portable permanent artifacts or a source of credentials to publish.

The same clone then passed the credential-free demo under an isolated operator
home, `./dev/package.sh`, and the installed `package` verification scenario using
`examples/memory-corpus.json`. The Linux x86_64/glibc-2.44 archive contains 48
manual documents with zero missing local targets. Installed CLI, standalone checks
and explicit-memory verification passed under a utility-only PATH without a
system development toolchain. This is foundation packaging evidence; it does not
qualify new knowledge, terminal or control workflows that are absent from that
revision. Raw package/installed logs use the same `/tmp/ipse-foundation-fixed-`
prefix.

## Control `241841a`

The combined focused suite passed 62 tests. Native helper tests passed 39 with
one deliberately ignored subprocess entry. The [incremental audit](control-audit.md)
records findings and independent closure. A full local source run in a separate
fixed clone passed **1,819 tests, 36 excluded**, in 1,061.3 seconds. Build, local
formatting, strict compilation, documentation and CI-policy checks also passed.
This receipt covers the control revision; new operator-channel work is not included.

The branch was pushed to origin. Both configured CI platforms built this revision,
then failed formatting under Elixir 1.18: one long `if` in consent eligibility was
formatted differently by local Elixir 1.20. The
[first CI run](https://github.com/lexlapax/ipse/actions/runs/40411106583)
is retained as a failure. Tests/package/installed checks were skipped after that
failure and supply no pass. Commit `512ddf3` rewrites the expression as a multiline
`do` block, preserving semantics; its fourteen focused consent tests pass. Later
CI evidence must name its repaired revision rather than relabeling this run.
The repaired [Linux/macOS run](https://github.com/lexlapax/ipse/actions/runs/40411704160)
subsequently completed successfully at `512ddf3`.

## Operator primitive `37f5b9d`

A separate fixed clone passed build, local formatting, strict compilation,
documentation and CI-policy checks. Its full suite finished in 1,058.7 seconds
with **1,822/1,823 passed, 36 excluded**. The single failure was the release-policy
guard: ordinary CI gained the terminal test step, but the draft release matrix
had not mirrored it. The next implementation increment adds the identical step;
the focused release-policy suite passes. The original failed run is preserved.
Its chained demo/package/installed steps did not run after failure, so supply no
pass. This is distinct from the earlier foundation package evidence.
The [hosted run](https://github.com/lexlapax/ipse/actions/runs/40413815567)
also failed that guard on both platforms. macOS additionally exhausted the default
60-second aggregate ExUnit allowance in a multi-VM evaluation CLI fixture:
fixture freezing took 39.2 seconds before the refusal command started. The refusal
assertions and subprocess limits are retained; the fixture now uses the same
120-second aggregate allowance as adjacent multi-VM cases. Its focused local
rerun passed in 27.2 seconds (one test, 26 excluded). This does not turn the failed
macOS run into a pass; repaired hosted evidence remains separate.

## Session input increment after `37f5b9d`

The combined changed-feature suite passed **274 tests** in 69.1 seconds, covering
decisions, pilot/interaction, consent, Runner, Session/reconstruction, subscriptions,
feeds and release policy. A subsequent startup-race repair passed the dedicated
two-test origin suite, including its actual PTY resource-attachment barrier and
unrelated-witness preservation. Complete native tests pass **49**, with two
deliberately ignored subprocess entry points. Formatting, strict compilation,
CI-policy and documentation checks pass; the documentation check counted 471
Markdown files and 4,293 local links at that checkpoint.

The documented single-reader `mix run` observation command was exercised with
synthetic terminal input and returned its expected hash-checked success text.
It submitted no task and made no inference request. This machine-driven terminal
exercise is not independent human evidence. Full source/package/installed and
hosted platform evidence was pending at that checkpoint.
The [incremental audit](session-input-audit.md) records the repairs and scopes.

## Fixed Session input `a91dedb`

An independent fixed clone at `a91dedbf385daa08498e4760e026f046f66cc38b`
passed build, local formatting, strict compilation, CI policy, and documentation
checks, then **1,826 tests, 36 excluded** in 1,067.3 seconds. Its isolated demo,
package and installed-package checks also passed. The Linux x86_64/glibc-2.44
archive contains 48 manual documents with zero missing local targets. Installed
CLI and standalone checks used a utility-only PATH; the explicit-memory harness
used only the bundled Erlang runtime. The synthetic 100-record/100-query lexical
memory fixture made zero inference calls. This verifies the input foundation,
not unimplemented knowledge workflows or later reference/decision/parser changes.
Raw receipts use the `/tmp/ipse-input-fixed-` prefix. Hosted CI for this exact
revision was still running when this local receipt was recorded.

Raw logs, including first failures, are retained owner-only outside Git under
`/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/`,
with a SHA-256 manifest. Their names bind the described checkpoints; they are not
evidence for future source changes or milestone completion.

## Admitted sources, decisions and parser `ad67ea6`

A clean isolated clone at `ad67ea6269bc9ee3e7bfa8e003fda9df5d56855d`
passed the PDF-enabled build, local formatting, strict compilation, CI-policy
and documentation checks. The full suite ran with seed **564097** and finished
in **1098.4 seconds**: **1935/1938 passed, 36 excluded**. All three failures were
sealed child-VM boot checks: two measured model-service fixtures and the exact
ERTS path/argument fixture. This is a failed full run. Its chained demo/package
steps did not execute and supply no pass.

The new parser registry fixtures compiled a temporary `ebin`, then removed its
directory without removing the VM code path that compilation installed. A later
child boot correctly refused the missing entry in its exact captured path list.
Cleanup now removes only that fixture path before deleting its directory and
asserts the path is absent. The strict sealed-path boot rules remain unchanged.

A separate same-VM regression first ran all **four parser registry tests**, then
all **17 measured-launch/model-service tests**, retaining the original seed.
All **21 passed** after cleanup. The first regression script itself exited with
an incorrect expected count of 16 although all 17 second-stage tests had passed;
its corrected count rerun exited zero. The raw failed harness is preserved along
with the final run. This targeted result closes the reproduced path-pollution
failure; it does not relabel the failed full run or qualify unimplemented P31
workflows. Logs use the `/tmp/ipse-admitted-fixed-` and
`/tmp/ipse-parser-path-cleanup-regression` prefixes.

Separate commands subsequently passed the isolated demo, default PDF-enabled
package build and installed `package` scenario at the same `ad67ea6` revision.
The Linux x86_64/glibc-2.44 archive contains 48 manual documents with zero missing
local targets. Installed checks used a utility-only PATH; the explicit lexical
memory fixture used bundled Erlang and made zero model/encoder calls. A freshly
built corpus artifact then passed all six independent document checks in both
source and installed modes: Unicode, canonical DOCX revision authority, PDF
default-off/explicit extraction, module closure and all dependency notices. The
Linux PDF resource backend was actually available. These are synthetic format
and packaging results, not real-document extraction quality or P31 integration.

### Hosted formatter failures and equivalent source repair

The [admitted-feature run](https://github.com/lexlapax/ipse/actions/runs/40424973555)
and [parser-cleanup run](https://github.com/lexlapax/ipse/actions/runs/40427665470)
built on Linux/macOS, then failed the Elixir 1.18 formatting gate. Both identified
the same three files: `DocumentParser`, `Session.Reference` and
`Extension.DecisionCall`. Tests and later hosted package/installed steps were
skipped; neither run supplies platform behavior evidence.

The repair separates two long boolean guards into equivalent successive checks
and uses explicit multiline function/conditional bodies, retaining all guards
and refusal behavior. All **18 focused tests** passed. Direct `elixirc
--warnings-as-errors` compilation of the three changed modules passed with no
warnings. The first focused harness used deprecated compiler-option APIs and
printed harness deprecations; the separate direct compiler run is the strict
receipt. Local formatting passes. Elixir 1.18/hosted confirmation remains a
separate result until its repaired run completes. Raw receipts retain both
completed CI failures and the local repair commands/results.

## Protected-owner checkpoint `3654025`

A detached clean checkout at `3654025ae5ccfa66193f7a0a2e8eab5e999261f8`
passed the ordinary parser-free build, local formatting and strict compilation.
The full suite completed with seed **820167** in **1224.8 seconds**:
**2008/2009 passed, 3 skipped, 36 excluded**. This is a failed full run. Its only
failure was the parser-stage Linux test: a test-level `skip: false` overrode the
module's missing-optional-parser skip, then attempted to read an absent parser.
The separate expected journal-exhaustion/process-loss logs were not failures.
Raw receipts use the `/tmp/ipse-protected-365-` prefix. Demo, package and installed
checks were not chained after this failed test command and supply no receipt for
this revision.

The fixture repair combines the parser-presence and Linux predicates in the
test-level tag. With an explicitly absent path, all **three tests skip**. With a
valid owner-safe single-link copy of the already-built parser, all **three pass**
in **3.1 seconds**, seed **366395**. An earlier attempted available-parser run
selected Cargo's executable directly; that image has two hardlinks and correctly
fails the parser identity check. That run passed two tests and failed one; it is
retained as an invalid fixture selection, not a parser pass. The valid run copies
the binary to match the installed parser's single-link identity contract. No
identity rule was weakened. Logs are `/tmp/ipse-parser-stage-optional-absent.log`,
`/tmp/ipse-parser-stage-optional-explicit-present.log`,
`/tmp/ipse-parser-stage-explicit-present-diagnostic.log` and
`/tmp/ipse-parser-stage-single-link-present.log`.

### Hosted compatibility follow-up

The [earlier formatter-repair run](https://github.com/lexlapax/ipse/actions/runs/40428360527)
at `2a3ccb1` passed formatting and reached runtime tests. macOS failed the actual
terminal input fixture. Ubuntu reported **1987 tests, 2 failures, 36 excluded**:
the same terminal fixture and the 128-file protected staging case. This is failed
platform evidence. The terminal cleanup receipt and staging failure require
separate investigation; a subsequent formatting change does not close them.

The [protected-owner run](https://github.com/lexlapax/ipse/actions/runs/40432630453)
at `3654025` failed only the earlier formatting step on both platforms, identifying
six files whose long expressions differ under Elixir 1.18. Runtime and packaging
steps were skipped. Equivalent guards are now split into successive checks or
explicit multiline blocks, and one long test frame is named before constructing
its tuple. Two Session guard changes were included in `1c0531e`; the remaining
mechanical source changes preserve the same validation and refusal behavior.
Neither hosted failure supplies a Linux/macOS acceptance result for the new
protected filesystem profile, which still has its explicitly limited platform
scope.

The five remaining mechanical formatter repairs pass **41 focused behavior
tests** in **13.2 seconds**, seed **296224**. The initial harness, seed **183058**, lacked the override
runtime's private native helper and failed 36 tests with admission unavailable;
installing a copy of the unchanged pinned helper repaired the harness. This
does not weaken helper identity. Direct compilation passes with warnings treated
as errors; the clean command suppresses only expected module-name conflicts when
compiling replacement modules against the complete frozen dependency runtime.
Raw receipts are `/tmp/ipse-ci-compat-focused.log`,
`/tmp/ipse-ci-compat-focused-repaired.log` and
`/tmp/ipse-ci-compat-strict-clean.log`.

The already available packaged Elixir **1.18.5** formatter was also exercised
locally over all `.formatter.exs` inputs. The repaired five files and parser
fixture match both Elixir 1.18.5 and the local 1.20 formatter. Six separately
in-progress files still differ at that snapshot; this is not a whole-tree
formatting pass. The first checker incorrectly appended a second newline to
`Code.format_file!/1` output and reported every file; the corrected checker
compares the complete returned bytes. Its logs preserve that harness failure.
