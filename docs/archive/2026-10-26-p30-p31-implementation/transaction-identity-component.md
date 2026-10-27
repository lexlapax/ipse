# Native transaction and project identity component

Dated **2026-10-26**. This is an incremental engineering receipt for P31's
internal host primitives. It is not a whole-milestone audit, an operator procedure,
or evidence of model quality, annual capacity, macOS execution or independent
human use. The [plan](../../plan.md) owns acceptance; the
[native contract](../../../native/README.md#publish-protected-state-through-its-lock-owner)
owns the current wire/API description.

## Why the native owner performs effects

A separate lock helper plus an Elixir `File.rename/2` leaves a publication gap:
the helper can die and release its OS lock before the Elixir caller renames.
Before/after `Port.info/1` checks observe loss but cannot fence that effect.
Independently owned staging and reclamation also allow late allocation or
deletion after the logical lock is released.

`Runner.Transaction` therefore uses one native process for up to three retained
logical locks and for every staging write, immutable installation, reclamation
and final durable file switch. The controller registers with Session.Resources,
monitors the capability caller and original file-effect owner and uses the
existing anchored stdio supervisor for cancellation and confirmed cleanup.
Capabilities bind caller/controller/Port,
depth and generation, with reverse-order release. They grant no policy authority
to model data or workspace files. Supported API calls from another worker refuse;
this does not authenticate arbitrary raw messages from hostile code in the same
BEAM VM. Core callers/controllers are trusted, and cap/Port terms must not cross
that boundary.

The host owns ProjectIdentity → Consent → Collection lock order, schemas, hashes,
CAS, eligibility, orphan selection and divided storage ceilings. Native code owns
bounded private paths, retained descriptors, nonblocking control frames, actual
OS locks, writes, no-replace installation, unlink and rename/directory sync. No
JSON, inference, workflow framework or additional package dependency was added.

ProjectIdentity explicitly admits canonical primary repositories or folder-only
roots. Linked worktrees can join only a previously admitted repository after
reciprocal bounded `.git`/`commondir`/`gitdir` validation and private saved binding.
Clones, moves and replaced metadata do not inherit old permission identities.
Preview grants no recall. The protected global index is at most 1 MiB and uses
the same native transaction owner for its staged/final bytes. One unconfirmed
4096-byte metadata snapshot leaves a retained `.metadata-active` quarantine;
subsequent admission refuses rather than accumulating copies or treating timeout
as cleanup. No Git command, hook or network operation is executed.

## Findings and repairs retained from development

- Initial transaction tests timed out at acquisition. Rust's buffered stdin read
  had consumed bytes beyond the OS poll boundary. Direct bounded descriptor reads
  replaced it; partial and idle deadline controls remain in the suite.
- Independent review required compile-bound helper selection. Protecting only
  the selected child was insufficient: an actual any-invocation poison control
  found that the outer stdio supervisor still followed `IPSE_RUNNER_PATH`.
  `open_protected_stdio/6` now protects that supervisor too. Protected UID and
  initial directory-sync selectors close the earlier bootstrap routes.
- All retained logical parents are checked before commands and before typed
  success/refusal acknowledgements, including acquisition, batch readiness and
  child release. A parent-loss observation invalidates the whole stack.
- Reclamation syncs each retained orphan before the first unlink, then syncs the
  directory and drops all unlisted file FDs before acknowledging. A failed or
  partial effect stays unknown; the host must read a fresh durable root before
  explicitly choosing a later operation.
- Same-process entry guards run before Resources.file_effect starts a worker.
  These detect reentry/reverse acquisition; they do not claim general
  cross-process deadlock prevention or inherited authority.
- Independent review reproduced late publication after the original file-effect
  owner died: its synchronous effect worker had no inherited resource scope and
  the transaction monitored only that surviving worker. Resources now propagates
  the scope and original owner, preserving it through inline nested effects.
  The controller monitors both owners and refuses commands after either death;
  scope cancellation reaches its registered native cleanup. Legacy file-effect
  peers still wait for real IO completion instead of being killed wholesale.

The failed-first logs remain temporary development evidence. No raw transcripts,
credentials, generated private candidate text or host environment dumps are
included in this repository receipt.

## Checks actually run

The author ran strict combined native compilation with `rustc --edition=2021 -D
warnings native/ipse-runner.rs` into an isolated temporary output, strict Elixir
compilation under an isolated MIX_BUILD_PATH, formatting and scoped diff checks.
The focused transaction/identity run passed **35 tests**, seed **721315**, in
**13.5 seconds**. Its local log is
`/tmp/ipse-transaction-identity-protected-supervisor.log`.

After the independent owner-lifecycle finding, the expanded transaction, identity,
Session file-effect/resources and Journal-writer selection passed **60 tests**,
seed **757052**, in **27.5 seconds**, recorded at
`/tmp/ipse-transaction-effect-owner-final.log`. This includes exact `0600` identity
control checks; scoped and unscoped original-owner death during a paused effect;
scope cancellation while the owner and effect worker remain alive; and preserved
legacy FIFO-write/session-lock and budget-lock retention. Both stage and switch
refuse after the controller has confirmed cleanup. The first expanded run passed
59/60: its earlier identity test expected immediate lock-busy refusal after owner
loss, while the repaired controller had already released the lock and the retained
metadata-copy quarantine correctly returned `project_metadata_unconfirmed`.
The corrected test waits for that exact quarantine refusal and retains the
unchanged durable-binding checks.

Formatting and scoped diff checks passed. A subsequent strict compile encountered
two unused aliases in concurrently edited `Session.SourceWindow`; that unrelated
source checkpoint requires its owner's separate repair and strict receipt.

Those controls include:

- Two independent VMs refused while both parent and child locks were retained;
  abrupt VM/owner loss released the same retained inode rather than replacing it.
- Actual native SIGKILL before switch left the candidate uncommitted; SIGKILL
  after rename but before acknowledgement returned unknown with inspectable data.
- Resource cancellation, caller death, absolute lifetime, partial frames,
  oversized frames, malformed UTF-8 and stale sequence refusal.
- Capability caller/generation/top/depth validation, stale parent/child refusal,
  an exact 8-MiB/128-file staged batch and 64-name reclamation pages.
- Actual native quota preflight refusing before pending creation, budget
  narrowing/no widening, flat namespace refusal and full global identity-root
  accounting against its 4-MiB allowance.
- Production any-invocation poison controls for bootstrap and transaction child/
  supervisor selection. Private source-derived test modules override only child
  helper selection; the supervisor remains protected. Those fixtures do not
  establish an operator-selectable production override.

The host's observed kernel was `7.2.10-arch1-1`; native profile admission executed
against the actual test filesystem. This is component evidence, not a substitute
for the independently measured first-year workload or source/installed parity.
The final independent audit and combined-production checks must retain their own
source-bound receipts before completion is claimed.

## Allocation and platform limits

The divided project envelope remains 64 MiB: 42 MiB for collection state and
22 MiB conservatively reserved for controls, comprising an 18-MiB consent root
and the complete shared 4-MiB global identity root charged to each project.
Native quota admission rounds each planned dense file to its supported runtime
unit and reserves twice that amount before payload, while holding all writer
leases for the scope. Per-stage admission repeats the check. Current observations
alone are not used as a prediction for unknown filesystems.

The finite profile admits trusted upstream-compatible Linux 64-bit kernel
`7.2.10`/`7.2.10-*` with the reviewed Btrfs or explicitly configured tmpfs rules.
Unknown kernel/filesystem/huge-page metadata and observed directory-block
allocation refuse. macOS has no admitted quota profile. A same-version kernel
string is not cryptographic kernel attestation. Independent qualification must
retain the actual release, mount/backend and supporting source argument.

The metric is **managed allocated-file bytes**: live, pending, directory and
control `stat.blocks * 512`. It excludes unrelated volume journals/deferred
allocator accounting. Dirty-page/delalloc charges for an interrupted partial file
must remain represented until reclaimed; the kernel-specific proof is an
essential review obligation, not something established merely by killing the
userspace writer. These host primitives assume a protected trusted installation,
not containment of arbitrary same-user code able to replace operator state.

Native path/protocol support includes Linux/macOS implementations, but ABI review
is not runtime verification. Apple's primary
[stdio header](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/stdio.h)
establishes `renameatx_np`/`RENAME_EXCL` and its macOS 10.12 floor; its
[poll header](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/poll.h)
requires the distinct unsigned-int `nfds_t` ABI. Native runtime, complete workload,
all-engine qualification and prepared fresh-user/macOS journeys remain separate
acceptance gates. The component author cannot independently audit their own fix;
the final independent fault audit and whole-document manual reconciliation are
still required.
