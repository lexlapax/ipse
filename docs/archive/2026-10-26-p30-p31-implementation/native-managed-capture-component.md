# Native artifact through managed publication

Dated **2026-10-26**. Historical engineering receipt after `22b41d6`.
The [developer chapter](../../developer/knowledge-extensions.md) owns the current
capture procedure; the [plan](../../plan.md) owns delivery status. This increment
integrates the native artifact with the separately implemented managed SDK. It
does not complete standalone setup, current recall or P30/P31 acceptance.

The inert operator sidecar now declares literal-note and pending-proposal recipes
bound to its exact constraint digests. The worker uses the public SDK's checked
canonical digest helper, requests the separate `collection.managed` operation and
explicitly selects `advance_floor: true`. Its compiled preset declares managed
publication rather than raw collection writing. Source read/quote proofs still
come from the public SDK and are independently authenticated by the host.

The public helper reuses the existing JSON value validator and canonical encoder;
it adds no dependency or alternate hashing scheme. It bounds the ordered digest
inputs at 16 KiB, 128 members, 8-KiB strings and twelve levels per member. These
are digest inputs, not a larger wire object. The independent builder adds the
existing SDK dependency code paths before evaluating its inert sidecar data.

## Exact execution and verification

The private graph `/tmp/ipse-native-managed-session-20261026-01/project` and
sibling `build` copied the committed managed SDK graph, then overlaid this
increment's source and tests. It strictly compiled **125** application sources.
The [inventory](native-managed-capture-sources.json) binds **134** source/test/helper
inputs, **159** application BEAMs and both retained artifact builds. Its private
helper remains `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29`.
The concurrent activation and read-view drafts are outside this graph.

- Final focused controls: **8 passed**, **3.5 seconds**, seed **63301**, at
  `/tmp/ipse-native-managed-session-01-native-repaired-tests.log`. The worker
  continuation test additionally runs six cases in a separate VM. The PTY wrapper
  runs one positive native-input case in another VM.
- Actual headless unattended input publishes only a pending proposal with
  `never_current` host metadata. Actual synthetic PTY input passes through
  `Session.observe_input`, a one-use witness, SourceIndex and the independently
  built/imported worker, then publishes a literal ordinary note without an
  ordinary approval prompt. Both paths verify action format 3, managed effect
  binding 2, normalization 2, one accounting operation and three stored records
  at generation/floor 1. Saved context validates. PTY automation is not independent
  human evidence or model-quality evidence; no live inference runs.
- JSON, bundle, profile and build-spec regressions: **30 passed**, **3.7 seconds**,
  seed **570707**, `/tmp/ipse-native-managed-session-01-regressions.log`.
- Actual Elixir **1.18.5** formatting: ten changed code/test files, zero differences;
  strict compile: seven host/domain files, zero diagnostics. Host OTP is **29**,
  so no OTP 27 or macOS claim follows. Receipt
  `/tmp/ipse-native-managed-session-01-118-repaired.log`.
- Retained independent artifact builds passed under Elixir 1.20.4 and 1.18.5;
  `/tmp/ipse-native-managed-session-01-build.log` and
  `/tmp/ipse-native-managed-session-01-build118.log`. This is source artifact
  verification, not an installed bundled-runtime check.

## Preserve the failures and limits

The initial digest wrapper added two nesting levels around a valid publication
constraint and refused it. Reusing the existing validator with each digest member
at root depth repairs that implementation error without changing wire bounds.
Initial `/tmp/ipse-native-managed-recipes-01-tests.log` records **4/5**, followed
by **5/5** in its repaired receipt; the first artifact build failed for the same
reason. A later isolated Session snapshot lacked LICENSE; copying that unchanged
required file repaired the harness. A strengthened status assertion initially
queried `snapshot` instead of `status`; its **6/7** failure remains retained.

The first PTY extension also broke the scripted model: it selected the first
unlabelled header-reference user message instead of the latest genuine input.
Both native and unattended cases refused before commit (**6/8**). The synthetic
input diagnostic isolates that fixture mistake; selecting the latest nonreference
user restores both controls. A diagnostic line selector initially excluded all
tests and supplies no pass evidence. The first 1.18 compile omitted the unchanged
Notes/Records dependency sources; the repaired complete seven-file selection has
zero diagnostics. No production authority gate, test deadline or assertion was
weakened to obtain a pass.

Typed override creation/adoption, proposal acceptance, correction, forgetting,
expiry collection, managed recall/withdrawal, guided enablement, domain capacity,
live model qualification and final independent whole-implementation review remain
open. Earlier capture and Normalizer audits do not automatically certify this new
integration.
