# Session inference-dispatch admission follow-up

2026-10-27. This local consistency repair is not a current-knowledge freshness
barrier, protected send-time authorization, native-platform qualification, or
completion of P30/P31.

Replay validates that a recorded inference-dispatch intent has the same session,
turn and attempt identity as its admission and that its phase agrees with the
admitted operation. The live `Session.InferenceDispatch.commit/6` previously
constructed and recorded the event without applying that exact validator. It
now refuses before journaling if the constructed event would fail replay's
`valid_intent?/2` contract.

A synthetic owner-process control gives the Session a compaction view with a
model admission. That mismatch refuses without an intent. A matching compaction
admission under the same route and owner records one intent and passes replay
validation. The mismatch is deliberately injected; this test does not establish
that ordinary execution can reach such a state. The first attempt at a positive
control called the owner-only journal writer from the test process and failed
with `:journal_unavailable`; the final test executes both cases in the Session
owner and passed.

The Session dispatch, inference dispatch and usage suites passed 30 tests with
seed 20270413 in the dirty working tree. Their output explicitly says multiple
positive registered-service journeys were not run on the unsupported native
filesystem; those refusals are not positive-path evidence. No live model request
was made. The earlier corrected full regression is still running against its
frozen source tree and does not contain this change.

Uncommitted source hashes:

- `lib/ipse/session/inference_dispatch.ex`:
  `2605ce41259e7ef1ed4e7c656ec5118ad423b2c58e55abe1bdb34c758bcc6aa0`
- `test/ipse/session/inference_dispatch_test.exs`:
  `4911fdf67cb7340743664c7b036254d530c057df32cadab84abb518d7f94ee7c`

The current policy/source-root check, authority held through actual request send,
registered and unregistered positive journeys, cancellation/cleanup, full
source baseline and adversarial review remain open. Do not treat consistency of
a recorded intent as proof that request bytes were sent under current authority.

A subsequent direct-contract review found that `valid_intent?/2` relied on its
replay caller to select the admission by request ID and to call it only for the
intent event type. The validator now explicitly checks both fields, so a direct
caller cannot accept an event bound to another request or another type. The
owner-process fixture tests those mutations. The same three suites passed 30
tests with seed 20270414, with the same unsupported-native positive-path limits.
The updated source hashes are
`643da407347560e62f63eb19cef26e3fe8d4b332a54858c7c006dbbd820efe80` for the
Session dispatch module and
`3640245d7d5b1a04d6ae55584cac17a2df5b9ee88d64182740ffff7819ebec47` for its
test. Earlier hashes identify the preceding version.

The same three suites were then run in a fresh graph reconstructed from commit
`668e6a3` with only the two dispatch files overlaid. The private Git index tree
was `6912db7f1e242a7193a6f7c0dcdeaeeecf1e0d4c`; its tracked bytes matched the
index after testing. The copied production helper SHA-256 was
`891758d90dd875a9e890b25c2eade1955a20bd59aa47fe05b5682e09bad991f5`.
The focused run passed 30 tests, seed 20270415, using the external temporary
directory. Formatting and test-environment strict compilation passed. Its log is
`_build/dispatch-validation-20261027.log`. Native positive cases again reported
not run; the graph did not include the unrelated uncommitted experiments. This
is not a full regression, protected-platform qualification or independent review.
A subsequent forced strict compile rebuilt 141 project files and exited 0.

The decision admission includes a selected service ID, and route resolution
requires the decision profile's ID to equal that service. The intent validator
now also requires that recorded decision service ID to equal the admission's ID.
A synthetic positive and changed-service negative control passed. The isolated
graph with this additional change has tree
`5ee7d4c0843188bf6d73e655693d7ba55bf1f843`; its three focused suites passed
30 tests, seed 20270417, with protected positive cases again not run. The log is
`_build/dispatch-validation-20261027-r2.log`. Updated module and test hashes are
`9347fa4814ba9fdbd7a2f034ef1a884b66eda9c6a4cb47479af20568ed309e25` and
`c89b24013324031a28b89d28e98119f9ef9180c3d068f3cfafb594968775bb92`.
The change still needs the full baseline, protected-platform checks and review.
A later test-only addition also exercised the matching and changed decision
service IDs through the ordered replay validator. The focused owner test passed
with seed 20270418; its current source hash is
`c47a90046ddb49d13ff6edc98ab0149826e48ba699e469069acd6102a94143a5`.

A subsequent static check considered rejecting repeated intent records for one
request. The service-slot path can call the pre-admission gate, lose the race at
the subsequent slot transaction, and return to waiting before a later gate call.
Those are content-free intent records, not evidence of multiple provider sends.
Accordingly, no blanket one-intent-per-request rule was added. Any stronger
replay rule must model those pre-admission retries and reservation lifecycle
rather than treating each intent as a completed or started effect.
