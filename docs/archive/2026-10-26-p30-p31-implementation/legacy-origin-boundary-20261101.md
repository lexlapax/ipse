# Separate original-source authority from protected delivery

Dated **2026-11-01**, author-run synthetic Linux source controls based on
`345a91d`, with the tracked test changes described below. The [plan](../../plan.md)
owns delivery status; [testing](../../developer/testing.md) teaches the fixture
boundary and [recovery](../../operator/recovery.md#resume-compatible-work) owns
operator procedures. This is not full-module or milestone acceptance.

## Original failure and fixture correction

The frozen module's two legacy-origin tests constructed a genuine legacy journal
by removing original-file, native-journal, release and lock metadata plus release
events. Their worker then requested a managed snapshot before proposing capture.
The current protected-input adapter requires the consuming Session's actual
share-capable owners. That legacy consumer cannot supply them; it stops during
delivery before publication. Calling confirmed close afterward reports an
unconfirmed already-stopped Session. This was not evidence of a new close bug.

The fixture now has an explicit `capture_unobserved` mode. It still performs the
real source list/read/quote and builds its candidate normally, but submits claimed
generation zero without obtaining a managed snapshot. That integer is untrusted
CAS data; the host still independently checks source origin, saved policy and
the actual native store. No fake observation, injected grant, state replacement,
runtime change or authority bypass was introduced.

Legacy V2 retains its pre-intent unsupported-shape refusal. V3 now reaches a real
saved-consent publication action and receives exactly `collection_consent_denied`.
Its ordinary model may finish the conversation after that known failed action;
conversation success is not publication success. Both variants require unchanged
Consent state, zero generation/floor, valid reconstruction, absent managed-read
observations and idle resume with unchanged journal prefix and worker trace. Their
release claim stays unknown; they acquire no modern release/source provenance.

A new current-source positive uses the same generation-zero/no-snapshot request
and the registered synthetic native Ollama adapter. It requires successful V3
normalization, one settled operation, generation/floor one, two real local HTTP
requests, strict Saved state, confirmed close, exact idle ownership suffix,
unchanged ledger/worker trace on recovery and a signed release claim. Thus the
negative is not satisfied by a fixture that cannot publish anywhere.

## Retained terminal results

| Seed | Selection | Result | Seconds | Exit |
| --- | --- | --- | --- | --- |
| 791711 | Original legacy path with temporary selected-state diagnostic | 0 passed, 2 failed, 183 excluded | 11.1 | 2 |
| 791712 | No-snapshot legacy requests; old turn-error expectation retained | 1 passed, 1 failed, 183 excluded | 25.5 | 2 |
| 791713 | Paired current-source positive and both legacy negatives | 3 passed, 183 excluded | 12.0 | 0 |
| 791714 | Final origin/recovery controls plus existing registered-capture and read-only cases | 7 passed, 179 excluded | 19.5 | 0 |

The temporary diagnostic could not query the already-stopped Session; it is
removed. The second run's V3 mailbox retained the exact refused publication and
subsequent completed conversation, correcting the obsolete turn-error expectation.
Neither failure is hidden or counted as a pass.

```sh
mix test test/ipse/extension/managed_collection_call_session_test.exs --only legacy_origin --only registered_capture --only read_only_export --max-cases 1 --seed 791714
```

Logs are retained under `/tmp/ipse-legacy-origin-{diagnostic,direct,paired,regression}-20261101.log`.
Selected post-run source/log hashes are recorded below; they are not a prelaunch
or complete loaded-runtime inventory. Source and built fixture inputs were not
edited while each cohort ran. The final seven cases also exercise the unchanged
ordinary capture path, paging, revoked/ambiguous mappings and read-only denial.

The Collection SDK chapter was reviewed end to end in the preceding focused
increment, and the recovery manual was reviewed end to end for this change. Its
legacy-history/source distinction, unknown release guidance and no-replay
procedures agree with implementation and the executed source controls. Operator
behavior is unchanged. The testing chapter integrates the paired source-origin
exercise into its existing capture verification flow; no second status ledger
was added to a manual. Final link/format checks are recorded below.

The complete module remains **130 passed, 22 failed, 15 skipped** at `098559f`;
the complete suite remains **3,653 passed, 54 failed, 116 skipped, 112 excluded**
at `f44b63c`. Focused controls do not subtract from either historical aggregate.
These source/fixture results establish no installed, independent human,
external-model quality, non-Linux or confinement acceptance. No runtime,
dependency or native-helper change and no external model call was made. Full
P30/P31 implementation, integrated qualification and final adversarial audit
remain open.

## Selected verification hashes

| File | SHA256 |
| --- | --- |
| Diagnostic log | `df69f086f9c3c93c1c05e4ff687f954e5024c7f600cf731dfd7699880328eda4` |
| Direct legacy log | `a988c7dd3d0f70f20e8b73d8392786700f1267f870691cf3d664118101c649de` |
| Paired log | `b3af02b548d93aeaa6f83b7d45c665cb27fb170f16419463ccb626a46c32e414` |
| Final regression log | `be50f4903c76a58f35db7bd6d9c8294b57292f24076e4dde50a8c1dbd9709a39` |
| Final test module | `d9afb5373ce152b329f0e44da8f2a7b4e4838ffdd713a7af93045354bf2c780b` |

Final formatting and diff-whitespace checks exit zero. Documentation checking
reports 1,029 Markdown files, 8,524 local links and zero errors; existing private
directory discovery warnings remain separate. No runtime/build check was
repeated for this test/documentation-only change.
