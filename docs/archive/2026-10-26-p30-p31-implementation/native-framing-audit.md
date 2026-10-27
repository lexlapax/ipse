# Independent native framing closure

Dated **2026-10-26**. Historical independent evidence, copied verbatim from
`p31-verification/independent-native-optional-read-closure/REPORT.md`.
Original report SHA256: `6bcb7c343653b7dc19d0265e7c03c089e5b3ef47c9452bf121862a141fc10727`.

This independent closure follows the [framing repair](native-framing-repair.md). It qualifies only the exact facility graph, not empty-view consumers or a milestone. Current protected IO guidance belongs to [persistence training](../../developer/persistence.md).

```text
# Independent native optional-read framing repair closure

The accepted P2 buffered-reply finding is closed for the exact AFTER source/runtime below. No additional actionable defect was found in this incremental review. This is facility-only verification; it is not acceptance of ReadView empty-root integration, current recall, CLI qualification or the P30/P31 milestones.

The auditor did not author or repair production code. Foundation supplied a frozen final graph; the auditor copied it independently before executing tests. Neither repository/index/shared build/helper nor prior durable evidence was edited. All controls use synthetic local fixtures, with no credentials, private transcripts, qualification gold, model calls or network calls. No global operator/PTY Rust suite was run during this closure.

## Exact provenance

Working AFTER graph: `/tmp/ipse-independent-optional-framing-after-20261026`, copied from `/tmp/ipse-optional-framing-after-02`. All executed tests run with this private graph's `project` as CWD and its complete dependency code paths, so child `Application.app_dir` resolves the private helper. Ancillary copied sources do not claim that every retained dependency BEAM was rebuilt from them.

| Input | SHA256 |
| --- | --- |
| BEFORE Transaction source | `87e9f1bc65bcb128fb58b104ac72bb22ac7647d564a0f77169ad95d02d208794` |
| BEFORE Transaction BEAM | `687a8fc6c216fd2a072193cd30f7a2caf2f131911ee8077615676ec1d8242c5d` |
| AFTER Transaction source | `8c769af647054df7d5cf3d468ed3dfd4666d3130d84d9855e6b77195272ea3ef` |
| AFTER Transaction BEAM | `5761cf6cd02829528686b07d20719437d2b96e0aa0b7fdd004454e818dc1fc9f` |
| AFTER Controller BEAM | `41a271a7e3d5a3c79f5e67111af7a6d9a3e9f3108efc690a46ff49eef3dfef35` |
| New framing test source | `a70474f8749f9b5c27a0269f2a1c0b6fac47cb3b79b4e08c216580fac7851d4e` |
| Original optional-read tests, unchanged | `206f0c7963a23ad1496aa03f5c8741de016bc0596e25efd9c428ea579eeb29d8` |
| Native transaction source, unchanged | `4a4d0a52a590e37c7e899f200e2e4ecf24392e768df0035ae0b072f36d54eef2` |
| Private H helper, unchanged | `6f431b5aedde35ecb6f8737e7714dbd197df83c7e8d52e909243e0a39152a55d` |
| Shared old helper, unchanged | `108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29` |
| Own AFTER frozen manifest, 1102 files | `d8b03b52add71cf3aae09c455a4dcca2ea0d4e4b5ed4e5d984540b78af005de6` |
| Author final runtime manifest, 595 files | `657dda51879eaf2d59d3c6746c3b28b1692467fe1a33a2798387826e6397dd4d` |
| Author final source manifest, 450 files | `1d090fe86d176ae0791633d4b88a210f8cbfc37bd5b5b4e1bd09e1adf2d6a84a` |

The original independent BEFORE evidence remains at `/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-native-optional-read`. Its REPORT hash is `daffd06ae8a3d433a44628d8216a23f8ab8919cd4c4f394ff5e60cdda5b3d7bf`; all1147 files in its manifest `103ae9bb77f2d801582f45e7870570b22cba4bacc9bcabc58416eaf828202c2a` were reverified without modifying the evidence. It retains original native/source/runtime/baseline/fault artifacts, full raw failed drivers and the exact accepted P2 reproduction. This separate AFTER directory does not rewrite the BEFORE report.

## Before and after behavior

BEFORE, the independently authored unchanged driver returned `:absent` and `{:ok,"selected data"}` when the same native write appended an already-buffered partial next frame (`inner:"H"`). A subsequent final check returned unknown; callers correctly applying final check/release still withheld publication. The closed read API nevertheless exposed a known malformed transport reply. Original independent BEFORE result:6/7, with the accepted P2 as the only failure.

AFTER, the exact unchanged driver SHA `9a01106fc3316dbe4d8d87adc7aa573e7252f6a0edc920804064457b96f2d1da` still reports6/7, but its sole failure is now a diagnostic `:sys.get_state` on the controller already closed by the repair. Its original failure log is preserved. The companion changes ONLY that diagnostic to catch `{:noproc,...}` and record `:controller_closed`; neither production code nor the rejection assertions change. Companion SHA `dfac8c633dbfe1bff4ffed9c8ce71a6d283c2b455c57b273671dce24f75788cb`, diff `independent-companion.diff`:7/7. Both absent and present variants return `{:unknown,:transaction_lost}`, close the controller and invalidate the capability.

The original independent actual H-then-supervisor-exit diagnostic observed10/10 returns before `finished` was parsed, so it did not reproduce the terminal variant. Foundation's separate unchanged BEFORE rerun reproduced1/10 `finished:true` positive returns and5/7 overall; that owner observation is distinguished from the independent original evidence. This closure's unchanged and companion AFTER runs each observed10/10 positive returns with `finished:false`, with none releasing a read after observed termination. The fresh deterministic parser controls below cover already-parsed real X framing without relying on process scheduling. No claim is made that future supervisor death is predictable at a previously clean read return.

## Independent AFTER verification

| Check | Result and raw log |
| --- | --- |
| Final owner regression sources on own frozen graph |43/43; seed804219;9.2s; `independent-baseline-43.log`; compile diagnostics empty |
| Exact original independent driver |6/7; diagnostic-only noproc; `independent-unchanged-after.log` |
| Diagnostic-only companion |7/7; seed902141;0.7s; `independent-companion-after.log` |
| Fresh independently authored closure controls |6/6; seed329107;2.4s; `independent-fresh-closure-corrected.log` |
| Own full graph and author's declared final manifests |1102+595+450 unchanged entries; `independent-integrity-after.log` |
| Original durable BEFORE integrity |1147 unchanged manifest entries; same integrity log |

Fresh controls, authored after freezing and separately from the owner's tests:

- Valid parsed optional-present/optional-absent/required-read/error replies followed by coalesced supervisor X cannot return known facts after `finished:true`.
- Every partial X prefix split after nonterminal H/G/E replies refuses immediately; partial inner header and duplicate inner replies refuse. A full duplicate may be rejected in the parser before reply dispatch, which is valid refusal.
- Exact root R sequence/depth-zero replies accept coalesced X and every valid buffered X fragment boundary when its remainder arrives; wrong R sequence/depth/tag, malformed/oversized/duplicate X and bytes after terminal state refuse.
- Clean already-parsed replies do not consume or wait for future transport bytes. Dead observed upstream refuses even an otherwise clean queued reply.
- Actual pinned native operations reject each dirty inner/outer/extra-reply/finished state before issuing the next read, terminate the controller, and allow fresh acquisition/read/check/release.
- Actual caller death terminates its native owner/controller. Actual supervisor SIGKILL produces an unknown outcome and allows fresh native acquisition;20 additional native acquire/absent/check/root-release cycles pass.

The first fresh harness run was4/6 because two test assumptions were too narrow: duplicate frames were refused earlier than expected and asynchronous supervisor loss returned `:transaction_unavailable` rather than `:transaction_lost`. The original driver and raw log are retained as `independent-closure-original.exs` and `independent-fresh-closure-harness-diagnostic.log`. `independent-closure-harness.diff` explicitly allows earlier refusal and either unknown transport-loss reason. No successful/known result is admitted by those corrections. A first integrity diagnostic included an in-progress self-hash; it is retained separately as `integrity-first-with-inprogress-selfhash.log`; the final verifier excludes its active log from self-hashing. The durable file manifest binds the completed bytes.

## Scope and reproduction

Static review checked command preflight idle framing, exact root-release exception, both nested framing queues and their partial prefixes, already-observed finished state, deadline/owner checks, known-error correlation and terminal cleanup. The valid root R/X exception preserves legitimate release while nonterminal G/H/E replies reject observed terminal state. Native H implementation/helper bytes are unchanged by this repair.

This is a host framing repair closure using real Linux native transactions plus renamed parser/diagnostic fixtures derived from the frozen production source. Exposing private parser functions is fixture-only. Synthetic trusted-host state corruption exercises rejection/cleanup and is not a claim that hostile arbitrary same-VM Core code is contained. No assertion covers unobserved future bytes, hostile same-UID filesystem writers, unsupported platforms, consumer absence schemas, ReadView empty integration, storage capacity redesign, paid inference or whole-system acceptance. Caller final check and release remain required before exposing read data.

Durable AFTER evidence: `/home/lexlapax/.codex/visualizations/2026/10/26/01a17a12-c7bb-76e2-af9e-95f589cc6f94/p31-verification/independent-native-optional-read-closure`. All directories0700 and regular single-link files0600; executable images are data. Reproduce by copying to a new private working directory, chmod only working helper/executable copies0700, and run `IPSE_OPTIONAL_AUDIT_ROOT=<working-copy> elixir <working-copy>/independent-companion.exs` or `elixir <working-copy>/independent-closure-corrected.exs` from that working copy. Never execute or change preserved evidence in place. Preserved inherited manifests/logs referring to earlier checkpoints are historical; the `independent-*` files and `author-final-*` manifests are the explicit final closure binding. `files.sha256`, `closure-diagnostics.sha256`, and `PRESERVATION-RECEIPT.txt` bind every completed diagnostic, source, BEAM, helper and raw artifact retained here.
```
