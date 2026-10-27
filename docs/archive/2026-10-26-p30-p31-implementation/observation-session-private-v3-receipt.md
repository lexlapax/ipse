# Private Session observation prototype v3

This is an incomplete, unreviewed experiment, not an implemented protected
Session lineage path. The [patch](observation-session-private-v3.patch) has
SHA-256 `6e7f7ca13124669f0c7f45e95e88e35576bf0351dbd2769196eb9bfdf99c3367`.
It dry-ran against the working source when preserved but was not applied.
The private graph was copied from a working tree with other uncommitted work;
the hashes below identify the affected files, not a clean revision.

| Patched private file | SHA-256 |
| --- | --- |
| `lib/ipse/session.ex` | `0904d85e70939a58ddde8aabc7ec968030e159c57d963779e4cd7ea1fe12629b` |
| `lib/ipse/session/invocation.ex` | `626923f93005ebe409ff371efc1e9cf916e22a95428a2cbb0b0b6848d7cef855` |
| `lib/ipse/session/saved.ex` | `5861c7238a1231d056c305f8e1d336f424f7609ed04163037f7fff835f22b11f` |
| `lib/ipse/session/observation_receipt.ex` | `f411b4d51f7a143ff26ca919ac3bb0eae06ba84ed3b0747c5055757226a54e04` |
| `lib/ipse/session/observation_admission.ex` | `8bcce46e24d62e87977b0fc6e999ae6eba8b33f9cdd4168859e65bb25347a5ba` |
| `lib/ipse/session/observation_async.ex` | `290f45508ee3fa28a88653659519ffb1c865e67df31aab9f183a2501110dc1e5` |
| `lib/ipse/session/observation_replay.ex` | `f45abafa6d637ee2b690c102e0456078f192b0eb106fdf08fb3758504ab7b579` |
| `test/ipse/extension/collection_call_session_test.exs` | `3cbff097807198657d4ce6fb7d7fc2565297c89026dde8dfcd12a600b9976b68` |
| `test/ownership_diagnostic/observation_receipt_test.exs` | `03fb983bf011fa2bcaaef74e22ffd2ca4d0df063b90ecb69f119434cca6cf960` |
| `test/ownership_diagnostic/observation_owner_test.exs` | `a2e51d88cbc44ed83edf729f559e871fd8cd93a0da3dd301f0ea00c6004e8b0c` |
| `test/ownership_diagnostic/observation_async_test.exs` | `64a4d01c954aaded8316506d173030f1b7b6ef230a23ae178229010f9eb0dbdd` |

The test-only Session flag records a versioned header, refuses the selected
collection reads before they reach a worker, and refuses an unguarded resume.
A test constructs structural replay cases from a real **legacy** synthetic
Session journal and a later observation; it does not prove the original action
had that same-view witness. A syntactically valid envelope still refuses
restoration because the live barrier is unavailable. The optional header has no
independently authenticated activation anchor: removing it and its envelope can
resemble legacy. The saved policy, current external policy and legacy upgrade
rules need a reviewed versioned contract before any use.

The asynchronous prototype asks the existing owner-only `Journal.Writer` via
`:gen_server.send_request`; the owner can answer other calls while that writer
is stalled. A queued append can persist after timeout, so the result remains
unknown and is never disclosed. A synthetic owner-death control produced no
usable worker result. The actual Session does not call this asynchronous path.
Full replay must derive mandatory intents from authenticated Session state,
handle cancellation and late writes, and propagate lineage across every
continuation, result and subsequent effect. Exact reviewed bundled-worker
selection, same-view caller authentication, current root/consent/source locks,
and egress linearization remain open. Neither a separate VM nor these tests prove
OS confinement.

The private graph strictly compiled and the command below passed 24 tests
(seed 20270326); the [log](observation-session-private-v3.log) SHA-256 is
`45f41d6d89430c65e9e3a637d674a5c681471b958b4cd0e8c4ead0dbaa3768c6`.

```sh
MIX_ENV=test MIX_BUILD_PATH=../build TMPDIR=../tmp mix test --no-compile test/ipse/extension/collection_call_session_test.exs test/ownership_diagnostic/observation_async_test.exs test/ownership_diagnostic/observation_owner_test.exs test/ownership_diagnostic/observation_receipt_test.exs test/ipse/session/resources_authority_test.exs --seed 20270326 --max-cases 1
```

The private helper was a **test-only kernel override**, SHA-256
`05d5aa7f9f5c6453254b885b91a6a9dcd602e9077842ae4d05ed7e7bdd591d1a`.
Native-sandbox, macOS-sandbox, macOS-filesystem and memory-scope tags were
excluded. The tests do not qualify the production 7.2.11 kernel or installed
runtime. Independent review of this v3 patch has not occurred.
