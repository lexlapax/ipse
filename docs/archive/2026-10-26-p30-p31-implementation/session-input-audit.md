# Session input witness incremental audit

Dated **2026-10-26**, after `37f5b9d`; see the [implementation record](index.md),
[contracts](contracts.md) and [developer ownership guide](../../developer/persistence.md#bind-an-actual-operator-observation-before-recording-origin).
This increment binds native observations to Session. Ordinary CLI/question
adoption, knowledge-card acceptance and semantic/headless admission remain open.
Automated PTYs establish no independent human evidence. No model calls occurred.

The independent read-only reviewer found these integration defects. Author repairs
and tests are recorded below. Its final source recheck found no remaining
actionable product defect in this increment; it also caught a test sender-exit
race, repaired with a monitor/exit acknowledgment. It reviewed source and supplied
logs rather than rerunning builds or suites. This is not the final milestone audit.

| Finding | Repair and regression |
| --- | --- |
| Different Sessions compete for one terminal | Serialize active reads globally; actual concurrent different-Session request refuses |
| Old helper can flush after replacement starts | Native retained protected regular-file lock spans all flushes across VMs; stopped old helper refuses a replacement until cleanup completes |
| Binding fetch and read start have an invalidation gap | Session starts the lease within its own serialized handler; client awaits outside it |
| Empty Enter leaves a busy witness slot | Reject empty observations without minting; next actual PTY input succeeds |
| Worker DOWN retains a dead active slot | Clear its task before removal; test unexpected worker death and subsequent admission |
| Service absence can crash Session calls | Refuse witnessed input on service loss; ordinary input and cancellation remain available; service-absent and in-flight restart tests |
| Replayable receipt IDs and unlinked effective hash | Validate unique source/turn/native-event IDs and ordered effective-message hash; corrupted/replayed receipts refuse, legacy origin remains unverified |
| Large unprojectable origin receipt stops unrelated feeds | Durable private append for origin receipts; unchanged lifecycle user-message bytes and near-source-limit live feed regression |
| PTY child exit can hide queued test output | Bound and drain remaining terminal output before inspecting child status |
| Scope loss during reader attachment restarts the global service | Handle attachment failure locally, stop the new worker/scope, and preserve unrelated witnesses; a deterministic suspended-scope startup barrier verifies it |

The author additionally attached readers to existing Session resource scopes and
the retained Session lock. A service monitor stops the scope after registry loss;
known cancellation cooperatively closes the helper before clearing the active
entry. Native fencing covers unknown/abrupt cleanup. Scope loss never mints proof.
Origin service status formatting redacts input and pending messages.

The fence uses the regular-file, open-description lifetime described by the
[Linux flock interface](https://man7.org/linux/man-pages/man2/flock.2.html).
A terminal-device-lock prototype passed the Linux controls, but
[Apple's special-file operation table](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/miscfs/specfs/spec_vnops.c)
maps advisory locking to its error handler. That source check led to the shared
regular-file implementation; it is not evidence of macOS execution.

The actual PTY driver exercises 64 completed witnesses, capacity refusal,
cross-Session/wrong-caller/changed-text/replay/expiry refusal, cancellation before
await, closed/killed Session, killed client/reader/service, actual resume, empty
input, service absence and original versus skill-expanded bytes. Logical expiry
is advanced only through private isolated test-state inspection; this is not a
five-minute wall-clock endurance claim. It uses the existing Rust toolchain and
OS C library, without a terminal utility dependency.

First failures are retained. The initial focused run failed its synthetic header
setup and an unused Rust import. Adding resource ownership later exposed an
unwanted global restart from linked task death; owned scopes plus monitored,
unlinked tasks repaired it. The native fence's first sandbox run refused the
virtualized non-root `/tmp`, correctly; the host run retained that root check.
The first stopped-helper assertion counted Rust's subprocess test-runner preamble
as helper output; its replacement validates that exact preamble and then zero
helper terminal bytes. Safety assertions and resource bounds remain in place.

The prior full fixed-revision baseline separately found a missing release-workflow
mirror of the new CI step. Its repair adds the same terminal checks to the draft
matrix and leaves release publication unchanged. Test/source/platform receipts
belong in [verification](verification.md), not portable milestone-completion claims.
