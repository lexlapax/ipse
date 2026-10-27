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
