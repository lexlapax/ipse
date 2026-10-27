# Independent inference-dispatch audit

Dated **2026-10-26**. Historical-only incremental audit, preserved verbatim below from the independent report. The [component record](inference-dispatch-component.md) owns its checkpoint provenance; the [plan](../../plan.md) owns current milestone status. No final whole-implementation acceptance is implied.

Original report SHA-256: `c0bfd63bfdfc7c9d506ab1e9bda1c3f340f47fd7576e8d8d60b9733daaac4b03`. Durable private evidence manifest SHA-256: `05c1581ce57b9b0782d9a899a717cd2a1c06ef8da0993b618580dda609a06003`.

INDEPENDENT INCREMENTAL INFERENCE-DISPATCH AUDIT
Dated: 2026-10-26
Disposition: zero confirmed actionable findings in this incremental component audit.
This is not final P30/P31 acceptance, model qualification, platform certification,
or a final whole-implementation security review.

BOUND CHECKPOINT AND AUTHORIZATION
The parent requested an independent adversarial audit of the registered inference
foundation checkpoint identified as 5510ddbc8fad373428d6a16d27628534d07f03d9.
The review used the frozen /tmp/ipse-inference-dispatch-26 source/runtime, never
current uncommitted Managed SDK changes. All sources and dependencies were copied
to the auditor-owned private /tmp/ipse-independent-dispatch-8nPPiO directory.
Only owned synthetic local HTTP fixtures were used. No live model, paid provider,
private qualification corpus, gold input, credentials, operator auth/config file,
or private transcript was accessed. No repository source, index, stage, commit,
or shared native helper was changed or rebuilt.

EXACT SCOPE
Reviewed deferred before_admit relay and post-gate admission, current native lease
checks, known-unstarted classification, CompletionWitness transport/parser/cleanup
conjunction, shared Budget ordering, private text buffering and release, Session
final-gate/effect-caller checks and dispatch-intent replay boundaries. Read the
main/compaction and SDK named inference integration and relevant author tests to
understand their contracts. Tests below are fresh independent drivers, not a
rerun of the author's 120-test receipt.

The final gate is an admission linearization point, not an atomic HTTP-start
receipt. A journal inference_dispatch_intent records intent only. A free native
lock or closed socket does not establish remote quiescence.

PRIVATE BUILD
The first private compile harness left copied Inspect protocol BEAMs in the app
output and used a deprecated warnings_as_errors compiler option. Its warning log
and harness are preserved; that run is not clean-build evidence.
The corrected harness removed every private Ipse-app BEAM, set Mix.env(:test),
and used structured parallel-compiler diagnostics. It compiled all 124 frozen
host/bundled source files into 158 modules with zero compile/runtime warnings.
Host toolchain: Elixir 1.20.4, compiled with Erlang/OTP 29; ERTS 17.1, x86_64 host.
No native compilation was performed. Existing native helper bytes were copied.
Receipt: compile-clean.log. Replay of probes uses these independently built BEAMs.

FRESH ADVERSARIAL CONTROLS
A. adversarial.exs; seed 41877; 4/4 passed; 0.6 seconds test time.
1. A valid native terminal marker followed by malformed native bytes could not
   clear the unknown marker or publish earlier text. A changed model on the same
   service could not enter its final gate or issue another provider request.
2. The real HTTP cleanup guardian was killed after upstream text was observed.
   The result remained unknown, the service stayed quarantined, and no text was
   published. The expected Finch supervisor killed-process diagnostic is in the
   log; it is fault-injection evidence, not an unhandled test failure.
3. Successful EOF/parse/cleanup released the service before any visible text.
   A subsequent request for a different project and model used the same service
   and completed; server-observed payloads identified the second model.
4. Final-gate refusal consumed zero shared budget. A zero-budget request never
   entered provider execution, recorded not_started, and left the fixture's first
   TCP request untouched until a later normal request actually used it.
Successful receipt: adversarial-local-http.log.

B. queued-adversarial.exs; seed 77019; 2/2 passed; 1.2 seconds test time.
5. A background request paused in its final gate. A foreground request then
   enqueued while the durable active marker was still nil and budget count zero.
   After gate release, actual server-observed order was foreground then
   background. The background gate ran twice, but only two total HTTP requests
   and two budget admissions occurred: validation repetition did not replay IO.
6. A final gate returned after the original 100 ms wait deadline. It could not
   dispatch or reserve budget. A fresh request then consumed the fixture's first
   real HTTP connection normally.
Successful receipt: queued-adversarial-retry-read.log.

C. session-adversarial.exs; seed 98813; 1/1 passed; 0.6 seconds test time.
7. A real Session used registered main inference. At POST receipt the server
   independently read the synthetic Session journal and verified an existing
   dispatch intent. The server then sent a valid native terminal response and
   usage but withheld the final HTTP byte/EOF. Canonical usage was durably
   observed live; no visible text escaped and the service marker stayed active.
   Session.cancel closed the actual socket. No text or assistant journal message
   appeared, measured usage survived, and the service retained unknown state.
   Another Session/model using that service produced no new dispatch intent or
   HTTP connection. Appending the old intent to historical events was rejected.
Successful receipt: session-adversarial-correct-counts.log.

PRESERVED FIRST FAILURES
adversarial-first.log: all four fixtures failed before IO because sandboxed
loopback listen returned :eperm. The subsequent run was explicitly escalated for
owned local loopback fixtures only; it made no external provider calls.
queued-adversarial.log: first driver version assumed read-only status could never
return transient service_busy during enqueue. The driver now retries that
read-only result; no effect/mutation is retried and production code is unchanged.
session-adversarial.log: the driver expected input_tokens directly under usage;
the canonical key is usage.counts.input_tokens. Correcting that expectation
produced the successful run. No production code was changed for these failures.

INTEGRITY AND PROVENANCE
The repository's complete 133-item frozen source/test/helper manifest was checked
successfully against the private source copy before dynamic probes and after all
seven probes. Its exact original contents are preserved in manifests/frozen-
source-manifest.sha256. SHA-256 of that manifest:
9bf1d47e44e6de8ab16b3685dd3fffe9c2150b42784fb47cb66f5b441c8e4942

The native helper was hashed before probes and after probes in both the frozen
and auditor copies. Every observation matched:
108c762ec23085df6aeaba58c8bdfb34d0a8cb4fa80a410584889a81a556ea29

Five principal BEAMs were hashed after the first four probes and again after the
queue and Session probes. They were unchanged:
Ipse.InferenceSlots:
d35c2cc4d20da6448bbc9e4601fc31a2ad45ff8918725f68ae32f390ffb75925
Ipse.InferenceDispatch:
2f7ca5269a78d81e09b316a418a7c29ac1ee83a0478b93f94ed56e8b5528b393
Ipse.HTTP:
0dae1b787840829cc927c54be7aa63f8dafba19518868eee6de04bf9969f9ff2
Ipse.Provider.CompletionWitness:
60e4667fa7366e53e27d8d9dc1f7352149ef773dba668f17c6846bec573d2f6a
Ipse.Session.InferenceDispatch:
f4deafac43867658e2a9c2b38fb965d8d97a96489dc81f14fc7954c6e6b0372e
These repeated BEAM checks do not pretend to be an unrecorded full-BEAM
measurement before the first four probes. The final complete audit-bindings file
records all 124 private source files, all independently compiled app BEAMs, both
private helper copies, final drivers and successful logs. Original file SHA-256:
76408018dffffa388688c57858b01ec6b981c8f773403050a7ec0753c4be391c

The durable bundle preserves exact original drivers/logs and selected critical
sources, all compiled app/dependency runtime BEAMs and app descriptors, and the
exact helper. Original driver paths deliberately remain unchanged for provenance.
Derived replay copies only relocate the synthetic ProviderFixture require_file
path; those copies have their own hashes. The frozen manifest and original
absolute-path audit bindings remain original evidence, not rewritten into a
claim that every original source file was copied into this smaller bundle.
The durable relative manifest hashes every preserved payload, including this
report and derived replay copies. It excludes itself and its detached hash file.

REPRODUCTION
Original private invocation was:
  elixir -pa '/tmp/ipse-independent-dispatch-8nPPiO/dependencies/*/ebin' DRIVER.exs
Successful local HTTP runs required permission to create owned loopback sockets.
The durable replay/run.sh runs the three derived drivers against the preserved
compiled runtime. It requires a compatible installed Elixir/OTP and permission
for local loopback sockets. It is an audit runner, not installed Ipse qualification
or a bundled release. The compile harnesses refer to the original complete frozen
source copy; only selected critical source files are included durably here.

LIMITS AND OUTSTANDING WORK
No independent reproduction of every SDK text/embedding/decision journey, named
child path, compaction path, active-policy revocation fixture, origin-alias
combination, or platform/backend failure was performed. Some of these paths were
read statically and covered by author receipts, which are not substituted for
independent execution. No Btrfs/kernel allocation requalification, syscall-timing
exhaustion, remote daemon concurrency, paid inference, latency/annual workload,
CI/macOS/installed-release parity, or full-suite certification was performed.
Managed record freshness, withdrawal and later uncommitted Managed SDK predicates
are outside this frozen checkpoint and were not assessed as new defects.

The earlier protected-storage/Consent findings belong to separate component
reviews; their repair status is not adjudicated by this dispatch audit.
This report establishes seven observed synthetic controls and zero confirmed
new actionable dispatch findings in the reviewed scope. It does not declare the
milestone or whole implementation complete.
