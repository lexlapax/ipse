# Independent activation writer repair closure

Dated **2026-10-26**. Historical independent component evidence, copied verbatim
from `p31-verification/independent-activation-writer/activation-writer-audit-2026-10-26.txt`.
Original report SHA256: `22d97babff196dda0f090df8a90c4c82adfe5621c3fa5e35d3cb1f623661ceb1`.
The code fence preserves the report text and its exact frozen-runtime references.

This is incremental closure of the two earlier findings at checkpoint `8d493127`. It is not a CLI audit or final milestone acceptance. The [configuration training](../../developer/configuration.md#apply-a-protected-selection-without-changing-base-configuration) describes current behavior; the [plan](../../plan.md) owns remaining acceptance.

```text
Independent activation ancillary-writer repair closure — 2026-10-26

Disposition
No actionable new findings in this incremental component audit. The accepted P2
missing ancillary .writer.lock creation is closed for the tested nonracing case
at checkpoint 8d493127eda7c0f1b0bf794b5aa372a571f7405b. Both exact read APIs refuse
and leave the writer absent. The earlier pending-reclamation repair remains intact.
This is not final whole-implementation or milestone approval, nor a CLI audit.

Freeze and exact runtime provenance
Supplied final graph /tmp/ipse-activation-writer-20261026-01/{project,build} was
copied before probes to /tmp/ipse-independent-activation-writer-yz1mudHH. All 701 author final source/runtime/helper bindings
and 294 earlier component bindings were independently checked in that copy before
execution. The before/after 701-path lists are byte-identical, SHA256:
2ebf96feba4c77dad4e7920d5e06c14304314c73772dfa9d26a84c80626d271d
Both helper copies retain SHA256:
108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29
Critical sources:
Identity ecc2e3750d04cd2cb288ac5bdbc74c3361136c41e82ae89d40a91bf9df5da6de
Consent 3803b34c9d0c61dbb40057da5b25f0a5f47cbe8837028697e52ea6edbfc5ac9f
Activation e5e6bbd9ce1bd7608bbf6101d45b09d8656e2e56421f4d143af743fa8a3d38ca
Full source, compiled app/dependency BEAM and exact helper bindings are retained in
manifests. No current shared working-tree or build content was used for execution.
Copy dereferenced build runtime links; the already broken telemetry/src development
link was unavailable. Only the unused shared project/deps link was removed from the
private copy. All runtime ebin/helper files used by probes match the supplied graph.
No Ipse or native helper compilation, fixture extension compilation or runtime
packaged inventory mutation was needed in this audit. Runtime: Linux, Elixir1.20.4,
Erlang/OTP29. Execution uses elixir -pa 'build/lib/*/ebin' DRIVER.exs.

Reviewed repair and source boundary
Read AGENTS.md, the previous repair/audit evidence, actual Identity/Consent source
diff and matching existing-reader tests. Activation source is unchanged.
ProjectIdentity existing_locked now requires safe empty retained .writer.lock at
lib/ipse/extension/project_identity.ex:143-144 before native acquire/quota and any
linked metadata capture. It rechecks exact writer identity before and after quota
at lines152-154, and after callbacks/actions at179-188. Consent requires the safe
empty writer at lib/ipse/extension/consent.ex:457, guards it before/after quota at
465-467 and again after callbacks at473. Native protocol and quota sizes remain
unchanged. Ordinary explicit mutation paths keep their writer-creation contracts.

Unchanged original exploit and preservation probes
Original writer probe SHA256:
964d6847904d9b76dda18d29f2fbdaeb79cd6b87ea3c225e25e96caddb585cb3
It is unchanged from the prior independent finding. Observed output:
missing_writer_lock: {:identity, {:error, :project_identity_unavailable}, false}
missing_writer_lock: {:consent, :error, false}
This is the positive closure of the prior successful read / true creation output.

Unchanged original pending exploit SHA256:
629682114d634943e3625b4bd667de344ead6edb1f1729e56fbf9b42224c15b3
It exits1 at its original deletion assertion because pending_after remains true.
The assertion-only preservation variant (SHA256 ca2bd1023b0c2a82b68c20c72949b2c92d8be1ea18f0eba6aa5cc81e209143a5)
passes the original Identity, valid Control and malformed Control cases. Pending
and selected JSON remain unchanged; malformed Control refuses, valid state reads.
These drivers and prior before-graphs remain preserved unchanged.

Fresh independent focused controls actually run
writer-closure-controls.exs: 4/4 PASS, seed51209, serialized max_cases1.
1. Remove only the writer from otherwise valid Identity and Consent state. Exact
   callbacks, Activation.current/readiness and Identity.existing/join_existing refuse;
   recursive home inventory remains byte/inode/mode/link/size/time identical and no
   writer appears. The exact callback sends a sentinel if entered; none is observed.
   Explicit Identity.resolve recreates the writer; explicit Consent.replace recreates
   it, advances the epoch and retains the selected policy. Exact reads then succeed.
2. Directory,0640 mode,symlink,hardlink and nonempty writer variants for BOTH owners
   refuse exact reads and current inspection. Sentinel callback never executes and
   recursive full fixture inventory is unchanged by the attempted reads.
3. During both exact callbacks, rename the retained writer and create a safe empty
   replacement with a different inode. The callback sentinel result never escapes:
   response is error or unknown, and selected index/control JSON is unchanged.
   Restore the original writer; subsequent exact read succeeds.
4. A reciprocal synthetic Git primary/linked worktree with a missing Identity writer
   refuses first linked lookup and join before authorization. No .metadata-active,
   new writer, membership publication or other recursive fixture change occurs.

Retained controls run against the new graph
retained-read-controls.exs: 3/3 PASS, seed601727, max_cases1. This unchanged prior
independent driver checks safe invalid-JSON pending preservation, hardlinked pending
refusal, required logical .lock missing without creation, dense4MiB Identity staged
quota refusal without deletion, ordinary reclaim/recovery, and actual native flock
holder death inside BOTH new read callbacks. It finds the actual native PID using
/proc child and FD observations and SIGKILLs that holder. Both results are unknown,
callback sentinel values do not escape, JSON/pending survive and later existing read
succeeds. These are regression controls, not claimed as newly designed proof.

Driver corrections and limits of failed attempts
Preserved initial driver and logs include a syntax error from an unspaced != token,
and two setup assumptions corrected before the passing run: ordinary Consent.snapshot
need not create an absent writer; explicit replace is the relevant writer-creating
mutation. Revocation also changes policy/epoch, so a stale exact-policy callback
correctly refuses; the corrected explicit replace rechecks epoch2. File.chmod with
01600 yielded0600 in this environment, making the attempted sticky-bit setup valid
instead of unsafe. A standalone mode-probe confirms that setup limitation. The
passing unsafe mode uses0640. These failures are harness/setup errors, not product
findings. A shell attempt to assign reserved zsh status was also corrected to a
task-specific probe_exit variable; expected original exploit exit1 was then recorded.
All completed initial/final scripts and logs are retained rather than discarded.

Durable evidence, replay and residual scope
Owner-only durable tree independent-activation-writer contains this report, full
public frozen project and runtime files, original/final drivers, logs, both author
manifests and independently verified before/after manifest plus integrity receipt.
replay/run.sh copies the graph into a new private temporary directory, validates
before bytes, runs the unchanged writer/pending/preservation probes and focused
4+3 controls, and validates after bytes. It never executes against durable evidence.
The complete payload is bound by relative MANIFEST.sha256.

No production/repository/index/shared build/helper edits, models, live network,
provider requests, credentials, qualification material or private transcripts were
accessed. No author full suite was rerun or counted as independent evidence. No
operator PTY/CLI audit, platform portability claim, exhaustive race schedule, or
new helper/framing repair is covered. In particular, raw same-UID concurrent unlink
between precheck and native quota is not claimed atomic no-create protection; this
retains the documented logical-lock precheck limitation. The confirmed P2 was the
uncontended already-missing writer and is closed at these exact bytes. The final
whole-milestone audit and separate future CLI freeze audit remain outstanding.
```
